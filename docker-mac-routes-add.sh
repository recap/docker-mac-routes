#!/bin/bash

echoerr() { echo "ERROR: $@" 1>&2; }

# Check if the script is running on macOS
if [[ "$(uname)" != "Darwin" ]]; then
  echoerr "This script is intended to run on macOS only."
  exit 1
fi

# Check if Docker Desktop is running
docker ps > /dev/null
if [ $? -ne 0 ]; then
  echoerr "Error with finding local Docker. Make sure Docker cli and Docker Desktop are installed."
  exit 1
fi

if [ "$1" == "test" ]; then
  echo "Testing Docker host to container network..."
  docker run --rm --name test_nginx -d nginx > /dev/null
  sleep 1
  NGINX_IP=$(docker inspect test_nginx --format '{{.NetworkSettings.IPAddress}}')
  curl -m 2 --silent --output /dev/null -I $NGINX_IP:80
  if [ $? -eq 0 ]; then
    docker stop test_nginx > /dev/null
    echo "Host to container networking works! ✅"
    exit 0
  else
    docker stop test_nginx > /dev/null
    echo "Host to container networking does NOT work! ❌"
    exit 1
  fi
fi

MIN_REQUIRED_VERSION="4.26.0"
BREAKING_VERSION="4.39.0"

# Extract Docker Desktop version
DOCKER_VERSION=$(docker version | grep 'Server: Docker Desktop' | awk '{print $4}')

# Function to compare versions
docker_version_gte() {
    printf '%s\n%s' "$1" "$2" | sort -V | head -n1 | grep -q "$2"
}

if docker_version_gte "$DOCKER_VERSION" "$MIN_REQUIRED_VERSION"; then
    echo "Docker version $DOCKER_VERSION is >= $MIN_REQUIRED_VERSION ✅"
else
    echo "Docker version $DOCKER_VERSION is < $MIN_REQUIRED_VERSION ❌"
    exit 1
fi

# Get IP of eth1 from BusyBox container with NET_ADMIN privileges
# Define the Docker command to get the IP address of eth1
DOCKER_COMMAND="ip addr show eth1 | grep 'inet ' | awk '{print \$2}' | cut -d/ -f1"

if docker_version_gte "$DOCKER_VERSION" "$BREAKING_VERSION"; then
  echo "Building Alpine Docker image..."
  # Build a custom Alpine Docker image with required tools
  DOCKERFILE='
  FROM alpine:latest
  RUN apk add --no-cache iptables iproute2 net-tools iputils dnsmasq tcpdump socat curl wget nmap bind-tools && rm -rf /var/cache/apk/*
  CMD ["sh"]' 

  echo "$DOCKERFILE" | docker build -t alpine-net-tools -f - .
  DOCKER_IMAGE="alpine-net-tools"
else
  # Pull the BusyBox image if not already pulled
  echo "Pulling BusyBox Docker image..."
  docker pull busybox:latest
  DOCKER_IMAGE="busybox:latest"
fi

# Run the BusyBox container with network privileges (NET_ADMIN) and execute the command
echo "Running BusyBox container with network privileges (NET_ADMIN) to get IP address of eth1..."
IP_ADDRESS=$(docker run --rm --network host --cap-add NET_ADMIN $DOCKER_IMAGE sh -c "$DOCKER_COMMAND")

# Check if the IP address was successfully retrieved
if [ -n "$IP_ADDRESS" ]; then
  echo "IP address of eth1: $IP_ADDRESS"
else
  echoerr "Failed to retrieve IP address of eth1."
  echoerr "Make sure kernelForUDP is set, it is needed for this to work."
  echoerr "You can enable it manually from Docker Desktop GUI."
  echoerr "This is done from Settings(top right)->Resources->Network."
  echoerr "Enable 'Use kernel networking for UDP' in Docker Desktop."
  exit 1
fi

# List Docker networks with 'bridge' driver and display their subnets
echo "Listing Docker networks with 'bridge' driver and their subnets..."

# Get a list of all Docker networks with the 'bridge' driver
NETWORKS=$(docker network ls --filter driver=bridge --format "{{.ID}}")

# Iterate over each network and get its subnet
for NETWORK_ID in $NETWORKS; do
  # Inspect the network and extract the subnet information
  SUBNETS=$(docker network inspect --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}' "$NETWORK_ID")

  # Get the network name for display purposes
  NETWORK_NAME=$(docker network inspect --format '{{.Name}}' "$NETWORK_ID")

  # Display the network name and its subnets
  if [ -n "$SUBNETS" ]; then
    echo "Network: $NETWORK_NAME (ID: $NETWORK_ID)"
    echo "  Subnet(s): $SUBNETS"

    # Check and Add/Remove Routes on macOS
    for SUBNET in $SUBNETS; do
      # Checking if iptables is dropping packets for the subnet. If so, remove the rule.
      # This is required for Docker Desktop versions >= 4.39.0
      if docker_version_gte "$DOCKER_VERSION" "$BREAKING_VERSION"; then
        echo "Checking for iptables blocking rule for subnet $SUBNET..."
        # Get the interface in the Docker VM associated with the subnet
        NETWORK="${SUBNET%%/*}"
        DOCKER_CMD="route -n | grep "$NETWORK" | awk '{print \$8}'"
        INTERFACE=$(docker run --rm --network host --cap-add NET_ADMIN $DOCKER_IMAGE sh -c "$DOCKER_CMD")
        # echo "Interface for subnet $SUBNET: $INTERFACE"
        IPTABLES_RULE="DOCKER ! -i $INTERFACE -o $INTERFACE -j DROP"
        # echo "IPTABLES rule for subnet $SUBNET: $IPTABLES_RULE"
        RULE_EXISTS_CMD="iptables -C $IPTABLES_RULE 2>/dev/null"
        if docker run --rm --network host --cap-add NET_ADMIN $DOCKER_IMAGE sh -c "$RULE_EXISTS_CMD"; then
          echo "Iptables DROP rule found in Docker VM for subnet $SUBNET"
          echo "Removing iptables DROP rule from Docker VM..."
          DROP_RULE_CMD="iptables -D $IPTABLES_RULE"
          docker run --rm --network host --cap-add NET_ADMIN $DOCKER_IMAGE sh -c "$DROP_RULE_CMD"
        else
          echo "Iptables DROP rule NOT found in Docker VM for subnet $SUBNET"
        fi
      fi
      # Check if the route already exists
      echo "Checking for local routes already setup for subnet $SUBNET..."
      EXISTING_ROUTE=$(route -n get "$SUBNET" | grep destination: | grep -v default)

      if [ -n "$EXISTING_ROUTE" ]; then
        ROUTE_INFO=$(route -n get "$SUBNET")
        ROUTE_GATEWAY=$(echo "$ROUTE_INFO" | grep gateway: | awk '{print $2}')
        ROUTE_INTERFACE=$(echo "$ROUTE_INFO" | grep interface: | awk '{print $2}')
        echo "Route for subnet $SUBNET already exists:"
        echo "  subnet: $SUBNET gateway: $ROUTE_GATEWAY interface: $ROUTE_INTERFACE"
        # Check if the route to Docker VM already exists
        if [ "$ROUTE_GATEWAY" == "$IP_ADDRESS" ]; then
          echo "Skipping."
          continue
        fi

        # Ask to delete route to subnet before adding route to Docker VM
        read -p "Do you want to remove this existing route? (y/n): " CHOICE

        if [[ "$CHOICE" == "y" || "$CHOICE" == "Y" ]]; then
          # Remove the existing route
          echo "[NEED SUDO RIGHTS] Removing existing route for subnet $SUBNET..."
          sudo route -n delete -net $SUBNET
        else
          echo "Skipping route addition for subnet $SUBNET."
          continue
        fi
      fi

      # Add the new route for the subnet to the IP_ADDRESS
      echo "[NEED SUDO RIGHTS] Adding route to subnet $SUBNET via $IP_ADDRESS..."
      sudo route -n add -net $SUBNET $IP_ADDRESS
    done
  else
    echo "Network: $NETWORK_NAME (ID: $NETWORK_ID) has no defined subnets."
  fi
  echo "Done."
done

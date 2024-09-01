#!/bin/bash

# Check if the script is running on macOS
if [[ "$(uname)" != "Darwin" ]]; then
  echo "This script is intended to run on macOS only."
  exit 1
fi

# Check if Docker Desktop is running
docker ps > /dev/null
if [ $? -ne 0 ]; then
  echo "Error with finding local Docker. Make sure Docker cli and Docker desktop are installed."
  exit 1
fi

# Check if kernelForUDP is set in settings.json. 
SETTINGS_FILE=$(echo ~/Library/Group\ Containers/group.com.docker/settings.json)
IS_SET=$(cat "$SETTINGS_FILE" | grep kernelForUDP | awk '{print $2}')
if [[ $IS_SET == "false," ]]; then
  echo "kernelForUDP is not set, it is needed for this to work."
  echo "You can enable it manually from Docker Desktop GUI."
  echo "This is done from Settings(top right)->Resources->Network."
  echo "Enable 'Use kernel networking for UDP' in Docker Desktop."
  echo "Or we do it here."
  read -p "Do you want to set kernelForUDP to true and restart Docker Desktop? (y/n): " CHOICE

  if [[ "$CHOICE" == "y" || "$CHOICE" == "Y" ]]; then
    echo Updating settings file: "$SETTINGS_FILE".
    sed -i '' 's/"kernelForUDP": false/"kernelForUDP": true/' "$SETTINGS_FILE"
    echo "Restarting Docker Desktop..."
    ps aux | grep -i docker | grep -v grep | grep -v docker-mac- | awk '{print $2}' | xargs kill -9
    sleep 1
    open -a Docker
    sleep 2
  else
    echo "Exiting..."
    continue
  fi

fi

# Get IP of eth1 from BusyBox container with NET_ADMIN privileges
# Define the Docker command to get the IP address of eth1
DOCKER_COMMAND="ip addr show eth1 | grep 'inet ' | awk '{print \$2}' | cut -d/ -f1"

# Pull the BusyBox image if not already pulled
echo "Pulling BusyBox Docker image..."
docker pull busybox:latest

# Run the BusyBox container with network privileges (NET_ADMIN) and execute the command
echo "Running BusyBox container with network privileges (NET_ADMIN) to get IP address of eth1..."
IP_ADDRESS=$(docker run --rm --network host --cap-add NET_ADMIN busybox:latest sh -c "$DOCKER_COMMAND")

# Check if the IP address was successfully retrieved
if [ -n "$IP_ADDRESS" ]; then
  echo "IP address of eth1: $IP_ADDRESS"
else
  echo "Failed to retrieve IP address of eth1."
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
      # Check if the route already exists
      echo "Checking for local routes already setup..."
      EXISTING_ROUTE=$(route -n get "$SUBNET" | grep destination: | grep -v default)

      if [ -n "$EXISTING_ROUTE" ]; then
        ROUTE_INFO=$(route -n get "$SUBNET")
        ROUTE_GATEWAY=$(echo "$ROUTE_INFO" | grep gateway: | awk '{print $2}')
        ROUTE_INTERFACE=$(echo "$ROUTE_INFO" | grep interface: | awk '{print $2}')
        echo "Route for subnet $SUBNET already exists:"
        echo "  subnet: $SUBNET gateway: $ROUTE_GATEWAY interface: $ROUTE_INTERFACE"
        # Check if the route to Docker VM already esists
        if [ "$ROUTE_GATEWAY" == "$IP_ADDRESS" ]; then
          echo "Skipping."
          continue
        fi

        # Ask to delete route to subnet before adding route to Docker VM
        read -p "Do you want to remove this existing route? (y/n): " CHOICE

        if [[ "$CHOICE" == "y" || "$CHOICE" == "Y" ]]; then
          # Remove the existing route
          echo "Removing existing route for subnet $SUBNET..."
          sudo route -n delete -net $SUBNET
        else
          echo "Skipping route addition for subnet $SUBNET."
          continue
        fi
      fi

      # Add the new route for the subnet to the IP_ADDRESS
      echo "Adding route to subnet $SUBNET via $IP_ADDRESS..."
      sudo route -n add -net $SUBNET $IP_ADDRESS
    done
  else
    echo "Network: $NETWORK_NAME (ID: $NETWORK_ID) has no defined subnets."
  fi
  echo "Done."
done


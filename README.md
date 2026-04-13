# docker-mac-routes

Routes IP traffic from MacOS host to docker containers in Docker Desktop. This script uses a feature `kernelForUDP` in Docker Desktop versions >= 4.26. When enabled, Docker Desktop creates a bridge interface on the MacOS `bridge101` and an interface `eth1` on the Desktop VM. This script piggybacks on this feature by adding local MacOS routes to route container network e.g. subnet `172.17.0.0/16` through interface `eth1` on the VM.

The purpose of this script is to be as simple as possible and to have no extra dependencies; being pure Bash and relying on standard cli tools only. Sudo rights are only asked for specific `route` commands and not the whole script.

## Latest Docker desktop version tested

- 4.53.0
- 4.63.0
- 4.69.0

## Script steps

- Initial checks that Docker and Docker Desktop is installed.
- Run a `busybox` container with `NET_ADMIN` privileges to query the IP of `eth1`.
- Query Docker networks.
- Add a route for every Docker network.

### Note for Docker Desktop versions >= 4.39.0

Since version 4.39.0, Docker Desktop introduces `iptable` rules that block traffic from MacOS to containers. To fix this I introduce a few more steps in the script:

- Check for Docker Desktop version.
- Build an Alpine docker image with `iptables` installed.
- For every Docker network, check for `iptables` rules and remove the `DROP` rule that blocks traffic from MacOS to containers.

## How to run

Enable "kernel networking for UDP" in Docker Desktop from Settings->Resources->Network.

![docker](./docker-desktop.png)
Run instantly with `curl` or `wget`:

```bash
curl -o- https://raw.githubusercontent.com/recap/docker-mac-routes/refs/heads/main/docker-mac-routes-add.sh | bash
```

```bash
wget -qO- https://raw.githubusercontent.com/recap/docker-mac-routes/refs/heads/main/docker-mac-routes-add.sh | bash

```

Or clone repo with `git`:

```bash
git clone https://github.com/recap/docker-mac-routes.git
cd docker-mac-routes
bash docker-mac-routes-add.sh

```

## Test connectivity automatically

To test if host to container connectivity is working, run:

```bash
bash docker-mac-routes-test.sh test
```

This `test` script will automate the below steps.

## Test connectivity manually

To check routes to a particular subnet on MacOS use `netstat` and grep for your subnets e.g.

```bash
netstat -nr | grep 172
```

Run a NGINX container and grab its container IP

```bash
docker run --rm --name test_nginx -d nginx
docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' test_nginx
```

Check if NGINX is reachable.

```bash
curl -I [container_ip]
```

Stop container

```bash
docker stop test_nginx
```

The script must be run every time Docker Desktop restarts or any changes are made to Docker networks e.g. Adding a new network.

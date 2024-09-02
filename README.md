# docker-mac-routes

Routes IP traffic from MacOS host to docker containers in Docker Desktop. This script uses a feature `kernelForUDP` in Docker Desktop versions >= 4.26. When enabled, Docker Desktop creates a bridge interface on the MacOS `bridge101` and an interface `eth1` on the Desktop VM. This script piggybacks on this feature by adding local MacOS routes to route container network e.g. subnet `172.17.0.0/16` through interface `eth1` on the VM.

There are other approaches to achieve this e.g. [docker-mac-net-connect](https://github.com/chipmk/docker-mac-net-connect).
The purpose of this script is to be simple as possible and have no extra dependencies; being pure Bash and relying on standard cli tools only. Sudo rights are only asked for specific `route` commands and not the whole script.

## Script steps

- Initial checks that Docker and Docker Desktop is installed.
- Check that `kernelForUDP` is `true` in `~//Library/Group Containers/group.com.docker/settings.json`
- Run a `busybox` container with `NET_ADMIN` privileges to query the IP of `eth1`.
- Query Docker networks.
- Add a route for every Docker network.

## How to run

```bash
git clone https://github.com/recap/docker-mac-routes.git
cd docker-mac-routes
./docker-mac-routes-add.sh
```

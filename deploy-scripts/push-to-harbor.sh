#!/bin/bash
# This script assumes a lot of things. To use it you would need to set up a build server with credentials to your upstream container registry.
# After Artifact Download...
set -e
containerName=name:release
docker load -i docker-container.tar
docker push ${containerName}
docker rmi -f ${containerName}

#!/bin/bash
# This script, like push to Harbor assumes many things. Namely, that you have a unique value (like Bamboo.BuildNumber) set as the env var for BUILDNUM.
# 
set -e
kubectl patch -f pod.yaml -n ${namespace} -p "{\"metadata\":{\"labels\":{\"build\":\""$BUILDNUM"\"}},\"spec\":{\"template\":{\"metadata\":{\"labels\":{\"build\":\""$BUILDNUM"\"}}}}}" --local=true -o yaml > newpod.yaml
mv newpod.yaml pod.yaml
kubectl apply -f . -n ${namespace} --context=${clustername}
# The above change to the labels will make kubernetes re-pull the image from our container registry and deploy it to our running pods.

# K8s Up And Running

### Starting Components:
* Command Line: 
  * aws cli
  * kubectl
  * eksctl
* Create EKS cluster:
  * `eks create cluster --name xyz -t t3.small`
  * Above creates a cluster with the following components by default:
    * 2 EC2 instances (t3.small).
    * 2 20GiB EBS volumes associated with those EC2's - this is the standard EC2 storage.
    * 1 Elastic IP (publice IPv4).
    * 4 Security Groups
      * `eksctl-k8sUp-cluster/ClusterSharedNodeSecurityGroup`
        * 'Communication between all nodes in the cluster'
      * `eksctl-k8sUp-cluster/ControlPlaneSecurityGroup`
        * 'Communication between the control plane and worker nodegroups'
      * `eksctl-k8sUp-nodegroup-ng-73166dbe/SQ`
        * 'Communication between the control plane and worker nodes in group ng-73166dbe	'
      * `eksctl-cluster-sg-k8sUp-100598305`
        * 'EKS created security group applied to ENI that is attached to EKS Control Plane master nodes, as well as any managed workloads.'
  
### Test Image:
* Kuard: gcr.io/kuar-demo/kuard-amd64:blue
  * `docker pull gcr.io/kuar-demo/kuard-amd64:blue`
  * From above, we now have a docker image, tagged `blue`, locally.
  * We can run it locally with `docker run --rm -p 8080:8080 <image-id>`
    * Navigate to localhost:8080 to view the running application.
  * To stop it, run `docker ps` will give you the container-id, then `docker stop <container-id>` will do the trick.
  
## THE POD MANIFEST FILE
* A pod manifest file is (usually) a manifest file that includes key information about a pod, including:
  * metadata: for describing the pod and its labels
  * spec: for describing volumes and the containers that we want running within the pod.
    * This also lets us describe where we want the pod manifest to pull the images from.

```yml Starting Point
apiVersion: v1
kind: Pod
metadata:
  name: kuard
spec:
  containers:
    - image: gcr.io/kuar-demo/kuard-amd64:blue
      name: kuard
      ports:
        - containerPort: 8080
          name: http
          protocol: TCP
```
  
### Now, let's start and interact with our first pod.
* Run the pod in your cluster with: `kubectl apply -f kuard-pod.yml`
* View it with `kubectl get pods`/`kubectl get pods -o wide`/`kubectl describe pods`
* Connect to it with Port Forwarding: `kubectl port-forward kuard 8080:8080`
* Get logs from it: `kubectl logs kuard`
  * Good for one-off debugging, but for general logging we would want to use a log aggregation service. Something like `fluentd` or `elasticsearch`.
* Execute commands in the container with `kubectl exec kuard <command>`, ex: `date`.
* Open an interactive shell with `kubectl exec -it kuard ...`
* Delete it with `kubectl delete pods/kuard`
  
## Health Checks
* Add a liveness probe to our existing pod manifest:
  * Liveness probes are container/application specific, thus we have to define them in the pod manifest individually.
  * After applying this pod manifest (and after deleting the old pod), you can actually view these liveness probes by running the port-forward command from above and navigating to `Liveness Probe`.
    * You can force failures here too!
```yml
apiVersion: v1
kind: Pod
metadata:
  name: kuard
spec:
  containers:
    - image: gcr.io/kuar-demo/kuard-amd64:blue
      name: kuard
      livenessProbe:
        httpGet:
          path: /healthy
          port: 8080
        initialDelaySeconds: 5
        timeoutSeconds: 1
        periodSeconds: 10
        failureThreshold: 3 
      ports:
        - containerPort: 8080
          name: http
          protocol: TCP
```
  
## Resource Allocation
* **Resource Request**: The minimum amount of resources the Pod requests to run its containers. Kubernetes will schedule the Pod onto a Node with at least this minimum of resources available.
  * i.e. the Pod _requests_ to be scheduled on a Node with at least the resources available.
```yml
apiVersion: v1
kind: Pod
metadata:
  name: kuard
spec:
  containers:
    - image: gcr.io/kuar-demo/kuard-amd64:blue
      name: kuard
      resources:
        requests:
          cpu: "500m"
          memory: "128Mi"
      ports:
        - containerPort: 8080
          name: http
          protocol: TCP
```
* **Resource Limits**: Similarly, we can set the maximum amount of resources a Pod/container can use.
```yml
# ...
      resources:
        requests:
          cpu: "500m"
          memory: "128Mi"
        limits:
          cpu: "1000m"
          memory: "256Mi"
# ...
```
  
## Persistent Volumes:
* Pods are, by default, stateless. Meaning if a pod is restarted, any data that was stored within the pod will not be persisted. It will be lost.
* We fix this by defining persistent volumes for each Pod, and defining for each container what volumes and mounting paths to mount to.
  * `spec.volumes` is an array that defines all the volumes that may be accessed by continers in the Pod manifest.
    * Not all containers are required to mount all volumes defined within the Pod.
  * `spec.containers.volumeMounts` is the second stanza we need to define for persistent pod storage. 
    * This array defines the volumes that are mounted into a particular container, and the path where each volume should be mounted.
    * Different containers can mount to the same volume, but they must use **different mount paths**.
* What if we want data to persist even when a Pod is restarted on a different Node?
  * You want **Remote Network Storage** rather than using the on-node hostPath (the Node's filesystem) as the persistent volume, like we did in `kuard-pod-vol.yml`.
    * A brief example of what this would look like is describe below, and will be covered more in depth later on.
```yml
# ...
volumes:
  - name: "kuard-data"
    nfs:
      server: my.nfs.server.local
      path: "/exports"
# ...
```

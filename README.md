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
  
## Labels & Annotations
* **Labels** are key/value pairs used to group kubernetes objects. They are simply identifying metadata for objects like Pods and ReplicaSets.
  * Ex Keys: `acme.com/app-version`, `appVersion`, `app.version`, `kubernetes.io/cluster-service`
  * Ex Values: `1.0.0`, `true`
* Search/filter Pods by labels with `kubectl get pods --show-labels` & `kubectl get pods --selector="<Key=Value,...>"`
  * Return pods with an OR conditional with `kubectl get pods --selector="<KEY in (value1,value2,...)>"`
  * There are many `--selector` operators that can be used here, like `=`, `!=`, `in`, etc...
* **Annotations** are also k/v pairs, and are used to provide extra information about the object.
  * ex: where it came from, how to use it, or some policy around it.
  * When in doubt, use Annotations to add info about an object, and promote it to a label if we want to use a selector query to group it.
  * **Primarily used in rolling deployments.** In this case, annotations are used to track rollout status and provide necessary data to rollback to the previous state if need be.
  * If you want to get crafty, you can store a json object (encoded to a string) as an annotation. However, if the object is invalid in some way, we would not know.
  
## Service Discovery in K8s
* Service discovery helops solve the problem of finding which processes are listening, at which addresses, and for which services. 
  * Basically, it is advanced DNS to serve the highly dynamic environment that is K8s.
* This chapter reviews some imperative `kubectl` commands for creating and exposing services via Service Objects. We are not as interested in the imperative bits, so the notes here will focus on the concepts; how DNS/service discovery is working in kubernetes.
* **The ClusterIP**: When a service is exposed in Kubernetes, it is assigned a ClusterIP. This is a virtual IP that K8s uses to identify a service, and uses to load balance across all the Pods identified by the selectors in the Service Object.
* **Service DNS**: A DNS name assigned to a cluster IP. The DNS name provides further identification for a service, and is generally structured by `<nameOfService>.<namespace>.svc.<baseDomainForCluster>`.
* **Readiness Checks**: We've already covered these, the main thing to know is that, if a container is failing readiness checks, K8s will not send traffic to it. This also helps with graceful shutdowns. If a container fails its readiness checks, it is no longer assigned traffic, so if we wait until all of its existing connections are closed, shutting down will be much more safe.
* **NodePorts**: Are the ports to/from which we want Node traffic to flow. These are set in the Service Object as `spec.type: NodePort`.
* **LoadBalancer**: Builds on top of the NodePort type and is used in cloud K8s environments. Basically, setting a Service Object to a LoadBalancer type will create a load balancer in your cloud environment and direct it towards the nodes in your cluster.

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
* **Endpoints**: An object great for applications from which you are designing for K8s from the start. This is an alternative to using ClusterIP's. Basically, for every service object there would be a 'buddy' Endpoints object created by K8s that contains the IP's for that service.
* **kube-proxy**: Watches for new services in the cluster via the API server, then redirects packet destinations to one of the endpoints for that service. It is dynamic, so any scaling events will cause the service to re-write itself to reflect the new state of the system.
* **Connecting to On-Prem Services**: We have 3 main options here.
  * Use a selector-less kubernetes service to declare a manually input IP address. The IP address here is outside the cluster (what we use to hit the external service).
    * This works for k8s => on-prem, but not vice-versa.
  * Create an internal Load Balancer in your cloud environment, living in your VPC. This delivers traffic from a fixed IP (outside the cluster) into the kubernetes cluster.
    * Likely your best option if your provider allows it.
  * Run kube-proxy on the external service itself. This is generally the most complex option.
  * Use something like Consul.
  
## Ingress!
* Install Contour on our cluster:
```
$ kubectl apply -f https://j.hept.io/contour-deployment-rbac
...
namespace/projectcontour created
serviceaccount/contour created
serviceaccount/envoy created
configmap/contour created
customresourcedefinition.apiextensions.k8s.io/ingressroutes.contour.heptio.com created
customresourcedefinition.apiextensions.k8s.io/tlscertificatedelegations.contour.heptio.com created
customresourcedefinition.apiextensions.k8s.io/httpproxies.projectcontour.io created
customresourcedefinition.apiextensions.k8s.io/tlscertificatedelegations.projectcontour.io created
serviceaccount/contour-certgen created
rolebinding.rbac.authorization.k8s.io/contour created
role.rbac.authorization.k8s.io/contour-certgen created
job.batch/contour-certgen-v1.5.0 created
clusterrolebinding.rbac.authorization.k8s.io/contour created
clusterrole.rbac.authorization.k8s.io/contour created
role.rbac.authorization.k8s.io/contour-leaderelection created
rolebinding.rbac.authorization.k8s.io/contour-leaderelection created
service/contour created
service/envoy created
deployment.apps/contour created
daemonset.apps/envoy created
...
$ kubectl get -n projectcontour service contour -o wide
```
* Then, once we have contour installed, let's deploy some sample applications to configure our new ingress controller to use.
```
// After creating a deployment manifest...
$ kubectl apply -f deployment.yml // creates the deployment via an empedded pod manifest in the deployment yaml.
$ kubectl get deployments // view your deployments.
$ kubectl get pods // view the pods you created from the deployments specifications.
$ kubectl expose deployment alpaca // Creates a Service Object with a ClusterIP to allow Load Balancing to our deployment.
$ kubectl get services // View our new alpaca service (and external clusterIP)
```
* **Host Ingress**: Depicted in the host-ingress file, though it is depicted badly (because we haven't hooked a real host to our cluster yet), host ingress directs traffic from your ingress controller to a service based on the host name in the HTTP headers of the request. So, if we had two hosts (abc.brainbard.io and xyz.brainbard.io for example), we could use host ingress to direct http to the relevant services running in our cluster based on those two host names.
* **Path Ingress**: Very similar to host ingress with the extra feature of directing traffic based on both the host and the `/path` following the hostname. This is particularly useful for microservice applications where we have different pod deployments running the services for different parts of a website/app. Ex: one deployment serves payments at `/cart`, another deployment serves store inventory at `/browse`, etc...

## Deployments!
* Deployment objects are generally used as an additional abstraction on top of ReplicaSets, and are well-suited for managing container images that developers are changing regularly.
* The main features on top of ReplicaSets are the `spec.strategy` stanza, `spec.template.metadata.annotations.kubernetes.io/change-cause`, `spec.revisionHistoryLimit`, and `spec.template.containers.imagePullPolicy`.
  * `spec.strategy`: Dictates different ways in which a rollout of new software can proceed. There are two primary ways 'Recreate' and 'RollingUpdate'.
    * **Recreate:** Simple, fast, but bad. It will cause site downtime. Only really useful for test deployments, but even then it makes more sense to keep your environment consistent if you are using RollingUpdate in your other environments.
    * **RollingUpdate:** Slower, but more sophisticated and robust than the above. With this, you can rollout a new version of your service while it is still receiving user traffic, without any customer downtime.
      * Updates a few pods at a time, moving through them incrementally until all your pods are running the new update.
      * `maxUnavailable: 1`: This can also be set to a percentage, i.e. 20%. Setting via a percentage is generally a better practice as it scales as your service grows in replica size. Also note that, 20% will ensure that 80% of your service is still able to serve requests at any given time throughout the rollout. If your traffic is cyclical (maybe you have fewer users at night) you could speed up your deployments by setting maxunavailable to something like 50%.
        * If you do not want your service falling below 100% capacity ever, you can set this to 0% and instead control your rolling update by configuring `maxSurge`...
      * `maxSurge: 1`: Percents are also a best practice here. This specifes the number of replicas a service can scale above the replicaset stipulations. Ex: if we have a service with 10 replicas, maxUnavailable is 0, and maxSurge is 20%, the Deployment will scale up 2 new replicas with the update (to a total of 12), scale down the old replicas by 2, and repeat. This way, we always have 10 active replicas to service user requests.
        * maxSurge: 100% and maxUnavailable: 0 is the equivalent of a **blue/green** deployment.
    * For the deployment controller (and your specified strategy to work reliably) you **HAVE TO SPECIFY READINESS CHECKS** in your containers. Otherwise, the deployment controller has no idea when a new replica is ready to handle traffic.
  * `change-cause`: Is basically a commit message. You can view previous change causes by running `kubectl rollout history deployment alpaca`.
  * `revisionHistoryLimit`: Aptly named. Sets the maximum number of revisions to a deployment that are stored. Ex: if you rollout daily, setting this to 14 will ensure your deployment revisions are visible/accessible for the last two weeks in K8s. AKA the limit at which you expect it is reasonable to have to roll back.
  * `imagePullPolicy`: Defines what changes to the Deployment YAML dictate a pull of the new image.
* Common deployment kubectl commands:
  * `kubectl rollout status deployments {deployment-name}` - to view and watch the rollout.
  * `kubectl rollout pause deployments {deployment-name}`
  * `kubectl rollout resume deployments {deployment-name}`
  * `kubectl rollout history deployment {deployment-name}` - will output a list of your revision numbers and their associated change cause.
  * `kubectl rollout history deployment {deployment-name} --revision=2` - more details on a specific rollout based on revision 2.
  * `kubectl rollout undo deployments {deployment-name}` - to undo a rollout. Can be used while a rollout is in progress or complete. It's literally just the rollout you tried but in reverse. 
    * NOTE IT IS BETTER TO REVERT YOUR DEPLOYMENT MANIFEST BACK AND APPLY IT DECLARATIVELY.
  * `kubectl delete deployments {deployment-name}` for imperative deletion, or declaratively: `kubectl delete -f {deployment-manifest}.yml`.
* More deployment stanza's to help with deployment reliability and monitoring:
  * `minReadySeconds: 60`: Additional wait time to ensure Pods are healthy. This is best used as a safeguard against bugs or memory leaks that take some time after a pod is running/handling traffic to cause problems. 60s is mostly arbitrary, but in this context we assume that most serious bugs would show up and cause a failed health check within that time period. **NOTE** that this should be configured to align with the timing and failure criteria for your health and liveness probes. In this case, 60s is the minimum time in which a health probe could fail.
  * `progressDeadlineSeconds: 600`: If a given stage of the deployment takes longer than 10mins, mark the deployment as failed. It's best to add some sort of monitoring for failed deployments. Maybe a deployment with failed status triggers an automatic rollback and creates a ticket that requires human intervention, for example.
    * To get the status, look in the `status.conditions` array where there will be a Condition whose type is Progressing and the Status is False.
  
## DaemonSets
* Where deployments and replicasets are about creating a service (like a webserver) with replicas for redundancy, we may want to replicate a Pod on every Node to run some sort of agent or daemon on each node. To do this, we will use DaemonSets!
* DaemonSets ensure there is a copy of a Pod running across a set of nodes in a Kubernetes cluster.
  * Some examples: 
    * Log Collectors, 
    * Monitoring Agents, 
    * You can also run specialized intrusion detection software on Nodes that are exposed to the edge network/internet (you would only run the DaemonSet on specific nodes in this case).
    * Or you can use them to install software on your Nodes.
* **ReplicaSets should be used when your service is completely decoupled from the Node.** Meaning, we could run multiple copies of a ReplicaSet on a single Node without an issue. DaemonSets **must have one copy on each Node to function properly.**
* By default, DaemonSets will schedule one per Node, unless a node selector is used to specify.
  * Use the `nodeName` field in the Pod spec to do this.
  * This can be done declaratively upon provisioning your resources using terraform's `default_node_pool: node_labels`: https://www.terraform.io/docs/providers/azurerm/r/kubernetes_cluster.html
    * Similarly, if you want to set `tags` that are visible to your Cloud Provider, there is a stanza for this as well!
  * Alternatively, you can imperatively label the nodes in your cluster via: `kubectl label nodes ${node-name} ssd=true`.
  * To get the labels for a particular node: `kubectl get nodes ip-192-168-17-43.ec2.internal -o json | jq .metadata.labels`
  
## Jobs
* Best for one-off and/or short-lived tasks.
* **A Job creates Pods that run until successful termination (exit 0).** Contrastingly, normal pods will continually restart regardless of exit code.
  * Best for Database Migrations or Batch Jobs.
* By default, a Job runs a single Pod once until successful termination.
  * But Jobs can be configured by 2 primary attributes:
    * The number of job completions we want,
    * And the number of Pods to run in parallel.
  * Job Patterns:
```
Type                        | Use Case                                      | Behavior                                            | completions | parallelism |
One Shot                    | DB Migrations                                 | Single pod runs once until successful termination.  | 1           | 1           |
Parallel Fixed Completions  | Mult Pods processing set of work in parallel  | 1+ Pods running 1+ times until a fixed completion.  | 1+          | 1+          |
Work Queue: Parallel Jobs   | Mult Pods processing from central work queue  | 1+ Pods running once until successful termination.  | 1           | 1+          |          
```
* One Shot:
  * First a pod must be created and submitted to the k8s api.
  * Then the pod must be monitored for successful termination.
  * If it fails, the pod will be re-created until successful termination is reached.
  * Imperatively: `-i` means this command is interactive. It will show log output from the Pod(s). `restart=OnFailure` is what actually tells K8s to create a Job object. Everything after `--` are command-line args to the container image.
```!#/bin/bash
kubectl run -i oneshot \
--image=gcr.io/kuar-demo/kuard-amd64:blue \
--restart=OnFailure \
-- --keygen-enable \
--keygen-exit-on-complete \
--keygen-num-to-gen 10
```
* Get logs from the Pod Job: `kubectl logs ${job-pod}`
* Use liveness probes in your jobs to improve their reliability and transparency.
* Parallelism:
  * Job goal: Generate 100 keys by having 10 runs of kuard with each run generation 10 keys. Limit to 5 running pods at a time to minimize cluster load.
    * `completions: 10, parallelism: 5`
* Work Queues":
  * A common use case for jobs is to process work from a work queue.
    * `Producer => Work Queue => Consumer Replicas`
    * To do this we will need to create a centralized work queue service (`rs-queue.yaml`). Kuard (demo-app) has one built in. We will need to start an instance of kuard to act as a coordinator for all the work needed to be done.
      * Then run `QUEUE_POD=$(kubectl get pods -l app=work-queue,component=queue -o jsonpath='{.items[0].metadata.name}')` and `kubectl port-forward $QUEUE_POD 8080:8080` to port forward to your new ReplicaSet. Nav to localhost:8080.
      * Expose the replicaset with `service-queue.yaml` so we can start loading items into it.
    * Then, create a ReplicaSet to manage a singleton work queue daemon.
  * Delete this junk: `kubectl delete rs,svc,job -l chapter=jobs`

## Config Maps and Secrets
  * There are examples for declarative configmaps here. Secrets, however, are done more imperatively. Lets create a TLS secret as an example for the kuard container.
    * Once you have a `.crt` and `.key`, run...
      * `kubectl create secret generic kuard-tls --from-file=kuard.crt --from-file=kuard.key`
    * Once we have created the cert and key for tls on our demo app, we can use a pod like the kuard-secret.yaml pod to actually mount the secrets such that the Pod can use them.
  * Secrets are accessed by Pods via the secrets volume type. These volumes are managed by the kubelet and are created at Pod creation. They are stored in RAM, and thus not stored on disk on the Node itself.
  * **Private Docker Registries** - Accessed via Image Pull Secrets!
    * These are stored just like normal secrets but are consumed through the `spec.imagePullSecrets` Pod spec field.
    * Create and Image Pull Secret with a command like:
      * `kubectl create secret docker-registry my-image-pull-secret --docker-username=<un> --docker-password=<pw> --docker-email=<email>`
    * Also note if you have to set IPS frequently, you can instead add the IPS secrets to the default service account associated with each pod. This will prevent you having to specify the secrets in every manifest.
* Normal kubectl commands work for configmaps and secrets, i.e. `create`, `delete`, `get`,`describe`.
* When creating configmaps and secrets, there are a few ways you can specify how to load the required data in (if doing so imperatively)...
  * `--from-file=<filename>` - Load from file where secret data key is the same as the filename.
  * `--from-file=<key>=<filename>` - ^ But instead we explicitly define the key name.
  * `--from-file=<directory>` - Load all the files from a directory, filenames will be key names.
  * `--from-literal=<key>=<value>` - Explicitly define the K/V directly.
* You can update ConfigMaps and secrets without having to restart/rollout any changes to the Pods/objects using them.
  * Update from a file:
    * You'd want an in-use manifest file, and then update the file directly. You would have to add the required data directly in the manifest, however. So this is generally a bad practice with secrets.
  * Recreate and Update:
    * If your inputs are stored in separate files...
      * `kubectl create secret generic kuard-tls --from-file=kuard.crt --from-file=kuard.key --dry-run -o yaml | kubectl replace -f -`
  * Edit current version
    * Works best with configmaps since they are not base64 encoded like secrets.
    * `kubectl edit configmap my-config`

## RBAC
* Every request to kubernetes is authenticated! Even though managed clusters like AKS and EKS setup authentication/rbac to work in conjunction with cloud IAM, they still integrate with K8s' system for roles, role-bindings, and the cluster variety of each.
* **Roles**: The set of rules/capabilities. There are restricted by namespace, and specify objects and the verbs that a user with this role may use.
* **Role Bindings**: The assignment of given role(s) to a user's identity.
* **ClusterRole and ClusterRoleBinding**: The same as above but are global to the cluster rather than being restricted by namespace.
* To see the clusterroles present on your cluster (many are built in by default) `kubectl get clusterroles`
  * `cluster-admin` provides complete access to the entire cluster.
  * `admin` provides complete access to a namespace.
  * `edit` allows an end user to modify things in a namespace.
  * `view` allows read-only access to a namespace.
* Note: If you edit any of the built in roles, your changes will be wiped if your cluster is updated/restarted for any reason. To prevent this, add `rbac.authorization.k8s.io/autoupdate` to false in the built in ClusterRole resource.
* To remove unauthorized access, set `--anonymous-auth=false` on your API Server.
* Managing RBAC:
  * Testing capabilities with `can-i` - ex: `kubectl auth can-i create pods` or `kubectl auth can-i get pods --subresource=logs` 
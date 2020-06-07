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

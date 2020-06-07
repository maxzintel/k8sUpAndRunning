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
  * We can run it with `docker run --rm -p 8080:8080 <image-id>`
    * Navigate to localhost:8080 to view the running application.
  * To stop it, run `docker ps` will give you the container-id, then `docker stop <container-id>` will do the trick.

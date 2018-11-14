# RFC 1918 EKS Worker Nodes Communication Example
EKS Worker Nodes Private IP space communication use-case.

For those in a hurry, Jump to [deployment](#deployment)

## The use-case
EKS is awesome! However the default [worker nodes example](https://docs.aws.amazon.com/eks/latest/userguide/launch-workers.html)
routes traffic to the public load balancer IPs of the EKS CLuster Masters,
requiring plumbing for public IP traffic, by default with public IPs.
Even when non-public IPs are used this still means that traffic will either flow
through a [NATGW or IGW](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-nat-gateway.html),
to the public IP of the EKS Cluster Masters load balancer.  
This scenario is not always desirable, especially if one wants to prevent any public
traffic, or have a security policy where that doesn't allow control, and management
traffic to take place over public IP space (non RFC-1918).  
AWS has a lot of robust features around using many of their services privately,
and securely locked down from the outside world, if desirable, which enhances
the validity of this use-case.

A simplified view of the default networking in the standard EKS Worker Nodes example:  
![Simplified Default EKS Worker Nodes network picture][default]

### EKS Networking Continued
A [VPC Endpoint Services](https://docs.aws.amazon.com/vpc/latest/userguide/endpoint-service.html)
like solution would be nice for traffic to the EKS Cluster Masters, where the endpoint is
represented in the desired subnets, and allows for comprehensive fine grained
policies to be applied to the VPC Endpoint.  
This is however not required, as some of this is provisioned by default when
creating an EKS Master Cluster. When setting up the EKS Master Cluster a
requirement is having [at least two, max five, Subnets for Worker Nodes](https://docs.aws.amazon.com/eks/latest/userguide/network_reqs.html). All the Subnets
get security group permissions to support communication between the EKS
Masters and the EKS Worker Nodes. On top of that [two, the "at least",
of the subnets](https://docs.aws.amazon.com/eks/latest/userguide/network_reqs.html)
get a [Requester Managed ENI](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/requester-managed-eni.html).
ENIs that end up on the EKS Master's Load Balancer, and are present in the Certificate
that is used to communicate with the EKS Master Cluster. Leveraging these two ENIs
fulfills a requirement of not having traffic to any public IP Space.

### Desired result
The default AMI, as provided by AWS, does the plumbing for communication with the EKS Cluster Masters when setting up the EKS Worker Nodes.
This plumbing, by means of a [bootstrap.sh](https://github.com/awslabs/amazon-eks-ami/blob/master/files/bootstrap.sh)
shell script, is an example on how to deploy nodes, or build images to use with EKS.  
In this specific case the ideal outcome is to have the ['--apiserver-endpoint'](https://github.com/awslabs/amazon-eks-ami/blob/master/files/bootstrap.sh), from the bootstrap script,
be something else then the default hostname of the EKS Master Cluster's Load Balancer.
As a matter of fact the local ENI in the Availability Zone, and Subnet that the Worker Node is deployed in, would be most excellent. Fortunately AWS has tooling that can be used to introspect what the surrounding environment looks like upon bootstrapping a node, which sets the stage to reconfigure, or manipulate the
node into the networking behavior that is desired.

### PoC Example
As an example this deployment uses a modified version of the [amazon-eks-nodegroup.yml](https://amazon-eks.s3-us-west-2.amazonaws.com/cloudformation/2018-11-07/amazon-eks-nodegroup.yaml), and instead of just the EKS Worker Nodes, deploys an EKS Master Cluster,
EKS Worker Nodes, and an EKS Control Node. Besides deploying these artifacts the [UserData](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/user-data.html)
for the EKS Worker Nodes, and the EKS Control Node has been modified to adapt the [hosts](https://en.wikipedia.org/wiki/Hosts_(file))
file to point to the AZ's local ENI for the Public URL of the EKS Master Cluster,
after which restarting the services involved with cluster communication afterwards. Forcing
the EKS Worker Nodes to communicate with the EKS Cluster over the ENIs.

A simplified view of the desired networking:  
![Simplified Altered EKS Worker Nodes network picture][altered]

## Other Notes
This setup also takes care of potential misconception around privileges with regard to
setting up the EKS Master Cluster, and the EKS Worker Nodes. As the EKS Cluster's owner, and the
owner of the EKS Worker Nodes need to be the same for the Worker Nodes to have the initial
permissions to join the cluster. This is especially cumbersome when people work
with STS tokens, and assumed roles. This "one" package deal, and the creation
of the EKS Control Node, should make this more simple. Where the EKS Control
Node's root user can be used to control K8s

## Limitations
There are just two ENIs, not more, not less. With more subnets, and AZs it will
remain just two. The example will only work with the EKS Worker Nodes in those
two AZs, a sane fallback can be provided, by editing the UserData to do so,
if there are more subnets. If EKS in the future creates more than just two
ENIs, in the respective AZs, these will automatically be picked up by the
UserData in this example.

# deployment
This example sets up an EKS Master Cluster, EKS Worker Nodes, and a EKS Control Node
inside an existing VPC. Using the ENIs with internal IPs, that are created in
two subnets when the EKS Master Cluster is created, for the EKS Worker Nodes,
and the EKS Control Node to communicate with the EKS Master Cluster.  
The EKS Control Node's root user can be used as an admin user for the EKS
Master Cluster, and to configure the EKS Cluster further if all external
communication is non-desirable.

## requirements
To use this example there are several requirements:  

* A VPC
* Preferably, and At least two subnets, in the VPC to deploy Worker Nodes
* A Default Security Group, or a specific Security Group for the EKS Worker Nodes
* An SSH Key
* Permissions to create EC2 instances, Network Interfaces, EKS Clusters etc
* [jq](https://stedolan.github.io/jq/), a command-line JSON ([TODO](#TODO))

## options
The properties file contains the options for the CloudFormation template, adapt
these to reflect your environment.

* VpcId - The ID of the VPC to be used
* KeyName - Name of the SSH Key for Control Node access
* ClusterName - Name of the EKS cluster
* Subnets - Subnets EKS Worker Nodes will deploy in
* ClusterControlPlaneSecurityGroup - The default Cluster
* ControlNodeSubnet - Subnet the EKS Control Node should be deployed in
* NodeGroupName - Group name of the EKS Worker Nodes
* NodeAutoScalingGroupMaxSize - Minimum size of the EKS Worker Node group
* NodeAutoScalingGroupMinSize - Maximum size of the EKS Worker Node group
* NodeImageId - An AWS AMI EKS Worker Node Image to use, or a custom AMI Image
* BootstrapArguments - Optional bootstrap arguments for the worker nodes
* NodeInstanceType - Instance Type to use for the EKS Worker Nodes, the Control
Node defaults to micro
* NodeVolumeSize - Size of the volume added to the EKS Worker Nodes

## things to take into account.
By default there is NO host with an external IP in this scenario, so a bastion
with a public IP, VPN Setup to the VPC, or other connected VPC is required to
access the EKS Control Node, or EKS Worker Nodes inside the VPC.

## running

* eks-up.sh - A simple script calling CloudFormation and a one liner for K8s
Configuration Mapping, besides some window dressing.
* eks-destroy.sh - destroys the CloudFormation.

# TODO
Fix the K8s config mapping from the EKS Control Node, so the eks-up.sh script can be
reduced to just the CloudFormation creat-stack, also dropping the jq requirement for the scripts.

## Options that were explored and annotations.
An overview of options that were explored and alterations that were done:  

![The Test Map Picture][testmap]

[default]: images/default.png "Default EKS Workers example networking"
[altered]: images/altered.png "Altered hosts file to point at AZs local ENI"
[testmap]: images/testmap.png "Test map"

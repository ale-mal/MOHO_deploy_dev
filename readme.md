## Terraform deployment script for MOHO

### Prerequisites

- Install and configure AWS CLI
- Download kubectl binary ver 1.27 as in https://docs.aws.amazon.com/eks/latest/userguide/install-kubectl.html

### Deploy

```
cd ./terraform
terraform init

terraform plan
terraform apply
```

### Confirm deploy

Go to AWS console:
- EKS Clusters, check that cluster was created.
- EC2 Auto Scaling groups, new group was created.
- EC2 Instances, there should be instance with loaded kubernetes.
- EC2 Load Balancer, new load balancer was deployed.

Or check in command line:

```
# grab our EKS config
aws eks update-kubeconfig --name moho-eks --region eu-central-1

kubectl get nodes --namespace=moho
kubectl get deploy --namespace=moho
kubectl get pods --namespace=moho
kubectl get svc --namespace=moho
```

From the `kubectl get svc` get list of services, find LoadBalancer and copy external-ip. Go to it, your service should be deployed now.

### Clean up

```
terraform destroy
```

### Useful links

- https://www.youtube.com/watch?v=Qy2A_yJH5-o Little bit outdated but still good as starting point.
- https://github.com/marcel-dempers/docker-development-youtube-series/tree/master/kubernetes/cloud/amazon/terraform Sources from the previous video link
- https://docs.aws.amazon.com/eks/latest/userguide/getting-started-console.html eks cli setup
- https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/guides/getting-started.html kubernetes config how-to
- https://alexlogy.io/creating-eks-cluster-in-aws-with-terraform/ just good article

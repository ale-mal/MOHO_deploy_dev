provider "aws" {
    region = var.region
}

# data sources
data "aws_eks_cluster" "cluster" {
    name = var.cluster_name
    depends_on = [ module.eks.cluster_name ]
}

data "aws_eks_cluster_auth" "cluster" {
    name = var.cluster_name
    depends_on = [ module.eks.cluster_name ]
}

data "aws_availability_zones" "available" {
}

# security groups
resource "aws_security_group" "worker_group_mgmt_one" {
    name_prefix = "worker_group_mgmt_one"
    vpc_id      = module.vpc.vpc_id

    ingress {
        from_port   = 22
        to_port     = 22
        protocol    = "tcp"
        cidr_blocks = [
            "10.0.0.0/8",
        ]
    }
}

resource "aws_security_group" "all_worker_mgmt" {
    name_prefix = "all_worker_management"
    vpc_id      = module.vpc.vpc_id

    ingress {
        from_port   = 22
        to_port     = 22
        protocol    = "tcp"
        cidr_blocks = [
            "10.0.0.0/8",
            "172.16.0.0/12",
            "192.168.0.0/16",
        ]
    }
}

# vpc
module "vpc" {
    source = "terraform-aws-modules/vpc/aws"
    version = "5.9.0"

    name                 = "moho-vpc"
    cidr                 = "10.0.0.0/16"
    azs                  = data.aws_availability_zones.available.names
    private_subnets      = ["10.0.1.0/24","10.0.2.0/24","10.0.3.0/24"]
    public_subnets       = ["10.0.4.0/24","10.0.5.0/24","10.0.6.0/24"]
    enable_nat_gateway   = true
    single_nat_gateway   = true
    enable_dns_hostnames = true

    public_subnet_tags = {
        "kubernetes.io/cluster/${var.cluster_name}" = "shared"
        "kubernetes.io/role/elb" = "1"
    }

    private_subnet_tags = {
        "kubernetes.io/cluster/${var.cluster_name}" = "shared"
        "kubernetes.io/role/internal-elb" = "1"
    }
}

# eks
module "eks" {
    source = "terraform-aws-modules/eks/aws"
    version = "~> 18.0"

    cluster_name = var.cluster_name
    cluster_version = "1.27"

    vpc_id = module.vpc.vpc_id
    subnet_ids = module.vpc.private_subnets

    cluster_endpoint_private_access = true
    cluster_endpoint_public_access  = true

    cluster_endpoint_public_access_cidrs = ["0.0.0.0/0"]

    enable_irsa = true

    eks_managed_node_groups = {
        node_group_1 = {
            instance_type = "t2.micro"
            desired_capacity = 1
            max_capacity = 1
            min_capacity = 1
            node_additional_security_group_ids = [aws_security_group.worker_group_mgmt_one.id]
        }
    }

    manage_aws_auth_configmap = true

    cluster_additional_security_group_ids = [aws_security_group.all_worker_mgmt.id]
}

provider "kubernetes" {
    host                   = data.aws_eks_cluster.cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.cluster.token
}

resource "kubernetes_namespace" "moho" {
  metadata {
    name = "moho"
  }
}

resource "kubernetes_deployment" "moho" {
  metadata {
    name = "moho"
    namespace = kubernetes_namespace.moho.metadata.0.name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        test = "MOHOApp"
      }
    }

    template {
      metadata {
        labels = {
          test = "MOHOApp"
        }
      }

      spec {
        container {
          image = "alexwhen/docker-2048"
          name  = "moho-container"
          port {
            container_port = 80
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "moho" {
  metadata {
    name = "moho"
    namespace = kubernetes_namespace.moho.metadata.0.name
  }
  spec {
    selector = {
      test = "MOHOApp"
    }
    port {
      port        = 80
      target_port = 80
    }

    type = "LoadBalancer"
  }
}

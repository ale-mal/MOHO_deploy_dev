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
            instance_types = ["t2.small"]
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

resource "kubernetes_deployment" "moho-backend" {
  metadata {
    name = "moho-backend-deployment"
    namespace = kubernetes_namespace.moho.metadata.0.name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        test = "backend"
      }
    }

    template {
      metadata {
        labels = {
          test = "backend"
        }
      }

      spec {
        container {
          name  = "moho-backend-container"
          image = "680324637652.dkr.ecr.eu-central-1.amazonaws.com/moho-be:latest"
          port {
            container_port = 8080
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "moho-backend" {
  metadata {
    name = "moho-backend-service"
    namespace = kubernetes_namespace.moho.metadata.0.name
  }
  spec {
    selector = {
      test = "backend"
    }
    port {
      port        = 8080
      target_port = 8080
    }

    type = "LoadBalancer"
  }
}

resource "kubernetes_deployment" "moho-frontend" {
  metadata {
    name = "moho-frontend-deployment"
    namespace = kubernetes_namespace.moho.metadata.0.name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        test = "frontend"
      }
    }

    template {
      metadata {
        labels = {
          test = "frontend"
        }
      }

      spec {
        container {
          name  = "moho-frontend-container"
          image = "680324637652.dkr.ecr.eu-central-1.amazonaws.com/moho-fe:latest"
          port {
            container_port = 3000
          }

          env {
            name  = "VITE_WEBSOCKET_URL"
            value = "ws://moho-backend-service.${kubernetes_namespace.moho.metadata.0.name}.svc.cluster.local:8080/ws"
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "moho-frontend" {
  metadata {
    name = "moho-frontend-service"
    namespace = kubernetes_namespace.moho.metadata.0.name
  }
  spec {
    selector = {
      test = "frontend"
    }
    port {
      port        = 80
      target_port = 3000
    }

    type = "LoadBalancer"
  }
}

resource "null_resource" "update_frontend_env" {
  provisioner "local-exec" {
    command = <<EOT
      #!/bin/bash
      timeout 30m bash -c '
      while true; do
        FRONTEND_URL=$(kubectl get svc moho-frontend-service -n moho -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
        if [ -z "$FRONTEND_URL" ]; then
          echo "Waiting for frontend service to be provisioned..."
          sleep 10
          continue
        fi
        BACKEND_URL=$(kubectl get svc moho-backend-service -n moho -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
        if [ -z "$BACKEND_URL" ]; then
          echo "Waiting for backend service to be provisioned..."
          sleep 10
          continue
        fi
        echo "Updating VITE_WEBSOCKET_URL with backend service URL: $BACKEND_URL"
        kubectl set env deployment/moho-frontend-deployment -n moho VITE_WEBSOCKET_URL="ws://$BACKEND_URL:8080/ws"
        break
      done
      '
    EOT
  }

  depends_on = [
    kubernetes_service.moho-backend,
    kubernetes_service.moho-frontend
  ]
}

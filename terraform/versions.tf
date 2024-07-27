terraform {
    required_version = ">= 0.13"
    required_providers {
      kubernetes = {
        source = "hashicorp/kubernetes"
        version = "~> 2.31"
      }
      aws = {
        source = "hashicorp/aws"
        version = "~> 5.60"
      }
    }
}

provider "aws" {
  region = "us-east-1"
  default_tags {
    tags = {
      Project = "zero-to-hero-eks"
    }
  }
}

terraform {
  backend "s3" {
    bucket       = "zero-to-hero-terraform-be2164899d3745a399f93b30fc4a0433"
    key          = "infra/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.96.0"
    }

    helm = {
      source  = "hashicorp/helm"
      version = "3.0.0-pre2"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.36.0"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "1.19.0"
    }
  }
  required_version = "~> 1.0"
}

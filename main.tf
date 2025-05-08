locals {
  karpenter = {
    namespace = "karpenter"
    version   = "1.0.2"
  }
  cluster_name    = "bunny-cluster"
  cluster_version = "1.32"

  vpc_name = "bunny-vpc"

  tags = {
    Project     = "zero-to-hero-eks"
    Environment = "dev"
    ManagedBy   = "terraform"
  }

  region = "us-east-1"

}

variable "vpc_cird" {
  type    = string
  default = "10.0.0.0/16"
}

module "vpc" {
  source               = "terraform-aws-modules/vpc/aws"
  name                 = local.vpc_name
  cidr                 = var.vpc_cird
  azs                  = ["us-east-1a", "us-east-1b", "us-east-1c"]
  private_subnets      = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets       = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
  enable_dns_support   = true
  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }
}

module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  version         = "~> 20.24"
  cluster_name    = local.cluster_name
  cluster_version = local.cluster_version

  enable_cluster_creator_admin_permissions = true
  cluster_endpoint_public_access           = true

  cluster_addons = {
    eks-pod-identity-agent = {}
    kube-proxy             = {}
    vpc-cni                = {}
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets


  fargate_profiles = {
    karpenter = {
      selectors = [
        { namespace = local.karpenter.namespace }
      ]
    }
    argocd = {
      selectors = [
        { namespace = "argocd" }
      ]
    }
  }

  tags = merge(local.tags, {
    "karpenter.sh/discovery" = local.cluster_name
  })

  depends_on = [module.vpc]
}

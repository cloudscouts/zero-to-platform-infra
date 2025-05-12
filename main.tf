locals {
  karpenter = {
    namespace = "karpenter"
    version   = "1.4.0"
  }
  cluster_name       = "bunny-cluster"
  cluster_version    = "1.32"
  node_iam_role_name = module.karpenter.node_iam_role_name
  vpc_name           = "bunny-vpc"

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
    "karpenter.sh/discovery"          = local.cluster_name
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


module "aws-auth" {
  source  = "terraform-aws-modules/eks/aws//modules/aws-auth"
  version = "~> 20.36"

  manage_aws_auth_configmap = true

  aws_auth_roles = [
    {
      rolearn  = module.karpenter.node_iam_role_arn
      username = "system:node:{{EC2PrivateDNSName}}"
      groups   = ["system:bootstrappers", "system:nodes"]
    }
  ]

}


module "ebs_csi_driver_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.55.0"

  role_name_prefix = "${module.eks.cluster_name}-ebs-csi-driver-"

  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = local.tags
}


resource "null_resource" "update_kubeconfig" {
  triggers = {
    cluster_name = module.eks.cluster_name
    region       = local.region
  }

  provisioner "local-exec" {
    command = "aws eks --region ${self.triggers.region} update-kubeconfig --name ${self.triggers.cluster_name} --kubeconfig ~/.kube/${self.triggers.cluster_name}"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "rm -f ~/.kube/${self.triggers.cluster_name}"
  }

  depends_on = [module.eks]
}

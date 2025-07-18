locals {
  karpenter = {
    namespace = "karpenter"
    version   = "1.5.0"
  }
  cluster_name       = "bunny-cluster"
  cluster_version    = "1.33"
  node_iam_role_name = module.karpenter.node_iam_role_name
  vpc_name           = "bunny-vpc"

  tags = {
    Project     = "zero-to-hero-eks"
    Environment = "dev"
    ManagedBy   = "terraform"
  }

  region = "us-east-1"


  argocd_version = "v2.9.3"

  istio_chart_url     = "https://istio-release.storage.googleapis.com/charts"
  istio_chart_version = "1.21.6"

}

variable "vpc_cird" {
  type    = string
  default = "10.0.0.0/16"
}



module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  version         = "~> 20.24"
  cluster_name    = local.cluster_name
  cluster_version = local.cluster_version

  enable_cluster_creator_admin_permissions = true
  cluster_endpoint_public_access           = true
  create_cluster_security_group            = false
  create_node_security_group               = false

  cluster_addons = {
    eks-pod-identity-agent = {}
    kube-proxy             = {}
    vpc-cni                = {}
    coredns = {
      configuration_values = jsonencode({
        tolerations = [
          # Allow CoreDNS to run on the same nodes as the Karpenter controller
          # for use during cluster creation when Karpenter nodes do not yet exist
          {
            key    = "karpenter.sh/controller"
            value  = "true"
            effect = "NoSchedule"
          }
        ]
      })
    }
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets


  eks_managed_node_groups = {
    karpenter = {
      ami_type       = "BOTTLEROCKET_x86_64"
      instance_types = ["m5.large"]

      min_size     = 1
      max_size     = 3
      desired_size = 1

      labels = {
        "karpenter.sh/controller" = "true"
      }

      taints = {
        karpenter = {
          key    = "karpenter.sh/controller"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      }
    }
  }



  node_security_group_additional_rules = {
    ingress_15017 = {
      description                   = "Cluster API - Istio Webhook namespace.sidecar-injector.istio.io"
      protocol                      = "TCP"
      from_port                     = 15017
      to_port                       = 15017
      type                          = "ingress"
      source_cluster_security_group = true
    }
    ingress_15012 = {
      description                   = "Cluster API to nodes ports/protocols"
      protocol                      = "TCP"
      from_port                     = 15012
      to_port                       = 15012
      type                          = "ingress"
      source_cluster_security_group = true
    }
  }

  node_security_group_tags = merge(local.tags, {
    "karpenter.sh/discovery" = local.cluster_name
  })


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


# resource "null_resource" "update_kubeconfig" {
#   triggers = {
#     cluster_name = module.eks.cluster_name
#     region       = local.region
#   }

#   provisioner "local-exec" {
#     command = "aws eks --region ${self.triggers.region} update-kubeconfig --name ${self.triggers.cluster_name} --kubeconfig ~/.kube/${self.triggers.cluster_name}"
#   }

#   # This provisioner executes a local command when the resource is destroyed.
#   # It removes the kubeconfig file associated with the EKS cluster to clean up
#   # local configuration and prevent stale kubeconfig files from persisting.
#   provisioner "local-exec" {
#     when    = destroy
#     command = "rm -f ~/.kube/${self.triggers.cluster_name}"
#   }

#   depends_on = [module.eks]
# }


# module "nlb-security" {
#   source  = "terraform-aws-modules/security-group/aws"
#   version = "5.3.0"


#   name = "nlb-security"

#   vpc_id = module.vpc.vpc_id

#   ingress_with_cidr_blocks = [
#     {
#       from_port   = 80
#       to_port     = 80
#       protocol    = "tcp"
#       description = "HTTP"
#       cidr_blocks = "0.0.0.0/0"
#     },
#     {
#       from_port   = 443
#       to_port     = 443
#       protocol    = "tcp"
#       description = "HTTPS"
#       cidr_blocks = "0.0.0.0/0"
#     }
#   ]
#   egress_with_cidr_blocks = [
#     {
#       from_port   = 0
#       to_port     = 0
#       protocol    = "-1"
#       description = "All traffic"
#       cidr_blocks = "0.0.0.0/0"
#     }
#   ]
#   tags = local.tags

# }

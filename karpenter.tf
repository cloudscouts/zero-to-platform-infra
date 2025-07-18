module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 20.24"

  cluster_name                  = local.cluster_name
  enable_v1_permissions         = true
  namespace                     = local.karpenter.namespace
  node_iam_role_use_name_prefix = false
  node_iam_role_name            = local.cluster_name

  create_pod_identity_association = true
  enable_irsa                     = true
  irsa_oidc_provider_arn          = module.eks.oidc_provider_arn
  tags                            = local.tags


  # Disable access entry creation in the module
  create_access_entry = false


  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  depends_on = [
    module.eks,
  ]
}


resource "aws_iam_role_policy" "karpenter_pass_role" {
  name = "karpenter-pass-role"
  role = module.karpenter.iam_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iam:PassRole",
          "iam:RemoveRoleFromInstanceProfile"
        ]
        Resource = [
          module.karpenter.iam_role_arn
        ]
      }
    ]
  })

  depends_on = [module.karpenter]
}

# Create access entry separately
resource "aws_eks_access_entry" "karpenter" {
  cluster_name  = module.eks.cluster_name
  principal_arn = module.karpenter.iam_role_arn
  type          = "STANDARD"

  depends_on = [
    module.eks,
    module.karpenter,
  ]
}

resource "aws_eks_access_policy_association" "karpenter" {
  cluster_name  = module.eks.cluster_name
  principal_arn = module.karpenter.iam_role_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }

  depends_on = [
    aws_eks_access_entry.karpenter
  ]
}

resource "helm_release" "karpenter" {
  name                = "karpenter"
  namespace           = local.karpenter.namespace
  create_namespace    = true
  repository          = "oci://public.ecr.aws/karpenter"
  chart               = "karpenter"
  version             = local.karpenter.version
  repository_username = data.aws_ecrpublic_authorization_token.token.user_name
  repository_password = data.aws_ecrpublic_authorization_token.token.password
  wait                = false

  values = [
    <<-EOT
    replicas: 1
    nodeSelector:
      karpenter.sh/controller: 'true'
    settings:
      clusterName: ${module.eks.cluster_name}
      clusterEndpoint: ${module.eks.cluster_endpoint}
      interruptionQueue: ${module.karpenter.queue_name}
    tolerations:
      - key: CriticalAddonsOnly
        operator: Exists
      - key: karpenter.sh/controller
        operator: Exists
        effect: NoSchedule
    webhook:
      enabled: false
    EOT
  ]

  lifecycle {
    ignore_changes = [
      repository_password
    ]
  }

}

resource "kubectl_manifest" "karpenter_default_ec2_node_class" {
  yaml_body = <<YAML
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: default
spec:
  role: "${local.node_iam_role_name}"
  amiSelectorTerms: 
  - alias: bottlerocket@latest
  securityGroupSelectorTerms:
  - tags:
      karpenter.sh/discovery: ${local.cluster_name}
  subnetSelectorTerms:
  - tags:
      karpenter.sh/discovery: ${local.cluster_name}
  tags:
    KarpenterNodePoolName: default
    intent: apps
    karpenter.sh/discovery: ${local.cluster_name}
    project: zero-to-platform
YAML
}

resource "kubectl_manifest" "karpenter_default_node_pool" {
  yaml_body = <<YAML
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default 
spec:  
  template:
    metadata:
      labels:
        intent: apps
    spec:
      requirements:
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64", "arm64"]
        - key: "karpenter.k8s.aws/instance-cpu"
          operator: In
          values: ["2","4", "8"]
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot"]
        - key: karpenter.k8s.aws/instance-category
          operator: In
          values: ["m", "t"]
      nodeClassRef:
        name: default
        group: karpenter.k8s.aws
        kind: EC2NodeClass
      kubelet:
        containerRuntime: containerd
        systemReserved:
          cpu: 100m
          memory: 100Mi
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 1m

YAML
}

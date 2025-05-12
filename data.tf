data "aws_ecrpublic_authorization_token" "token" {
}

data "aws_ssm_parameter" "eks_ami" {
  name = "/aws/service/eks/optimized-ami/${local.cluster_version}/amazon-linux-2023/x86_64/standard/recommended/image_id"
}

data "aws_ami" "eks_ami" {
  most_recent = true
  owners      = ["602401143452"]

  filter {
    name   = "image-id"
    values = [data.aws_ssm_parameter.eks_ami.value]
  }
}


data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

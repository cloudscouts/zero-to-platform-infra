data "http" "argocd_core" {
  url = "https://raw.githubusercontent.com/argoproj/argo-cd/${local.argocd_version}/manifests/core-install.yaml"
}

resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }
}

locals {
  argocd_manifests = split("---", data.http.argocd_core.response_body)
}

resource "kubectl_manifest" "argocd_core" {
  for_each  = toset(local.argocd_manifests)
  yaml_body = each.value

  depends_on         = [kubernetes_namespace.argocd, module.eks]
  override_namespace = "argocd"
}

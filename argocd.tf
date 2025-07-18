resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }
}

# Use Helm chart instead of raw manifests for better reliability
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "7.7.8"  # Compatible with ArgoCD v2.9.3
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  values = [
    yamlencode({
      global = {
        domain = "argocd.local"
      }
      
      configs = {
        params = {
          "server.insecure" = true
        }
      }
      
      server = {
        service = {
          type = "LoadBalancer"
        }
        
        # Add proper RBAC permissions
        rbacConfig = {
          "policy.default" = "role:readonly"
          "policy.csv" = <<-EOT
            p, role:admin, applications, *, */*, allow
            p, role:admin, clusters, *, *, allow
            p, role:admin, repositories, *, *, allow
            g, argocd-admins, role:admin
          EOT
        }
      }
      
      # Ensure proper service account permissions
      serviceAccount = {
        create = true
        name = "argocd-server"
      }
      
      controller = {
        serviceAccount = {
          create = true
          name = "argocd-application-controller"
        }
      }
      
      repoServer = {
        serviceAccount = {
          create = true
          name = "argocd-repo-server"
        }
      }
    })
  ]

  depends_on = [kubernetes_namespace.argocd, module.eks]
}

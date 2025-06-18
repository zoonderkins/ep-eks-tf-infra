resource "helm_release" "argocd" {
  depends_on = [module.eks.eks_managed_node_groups]
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "8.0.17"

  namespace = "argocd"

  create_namespace = true

  set {
    name  = "server.service.type"
    value = "LoadBalancer"
  }

  # set {
  #   name  = "server.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-type"
  #   value = "nlb"
  # }

  values = [
    file("${path.module}/values/argocd.yaml")
  ]
}


data "kubernetes_service" "argocd_server" {
  metadata {
    name      = "argocd-server"
    namespace = helm_release.argocd.namespace
  }
}
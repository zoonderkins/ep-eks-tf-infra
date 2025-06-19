## Reveal the ArgoCD password

kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

## Get the kubeconfig
aws eks update-kubeconfig --name ep-k8s-101-eks-demo-edward --profile xxx
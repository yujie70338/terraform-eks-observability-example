# Fetch available AZs in the region
data "aws_availability_zones" "available" {
  state = "available"
}

# NOTE: kubernetes/helm providers now use exec plugin (aws eks get-token)
# so aws_eks_cluster_auth is no longer needed.

# TLS certificate for EKS OIDC provider is also handled automatically
# by the EKS module (enable_irsa = true), so tls_certificate is not needed.

locals {
  cluster_name = "${var.project_name}-${var.environment}"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  # Subnet CIDR calculation: split /16 into /20 blocks
  # Public:  10.0.0.0/20, 10.0.16.0/20, 10.0.32.0/20
  # Private: 10.0.48.0/20, 10.0.64.0/20, 10.0.80.0/20
  public_subnets  = [for i in range(3) : cidrsubnet(var.vpc_cidr, 4, i)]
  private_subnets = [for i in range(3) : cidrsubnet(var.vpc_cidr, 4, i + 3)]
}

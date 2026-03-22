# Fetch available AZs in the region
data "aws_availability_zones" "available" {
  state = "available"
}

# Fetch current AWS account ID and caller identity
data "aws_caller_identity" "current" {}

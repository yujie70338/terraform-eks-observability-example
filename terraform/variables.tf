variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "ap-northeast-1"
}

variable "project_name" {
  description = "Project name used as prefix for all resources"
  type        = string
  default     = "eks-obs"
}

variable "environment" {
  description = "Environment name (e.g. dev, staging, prod)"
  type        = string
  default     = "dev"
}

# ─── VPC ────────────────────────────────────────────────────────────────────────

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

# ─── EKS ────────────────────────────────────────────────────────────────────────

variable "eks_cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.35"
}

variable "infra_node_instance_type" {
  description = "EC2 instance type for Infra node group"
  type        = string
  default     = "t3.medium"
}

variable "infra_node_desired" {
  description = "Desired number of nodes in Infra node group"
  type        = number
  default     = 2
}

variable "infra_node_min" {
  description = "Minimum number of nodes in Infra node group"
  type        = number
  default     = 1
}

variable "infra_node_max" {
  description = "Maximum number of nodes in Infra node group"
  type        = number
  default     = 3
}

variable "app_node_instance_type" {
  description = "EC2 instance type for App node group"
  type        = string
  default     = "t3.small"
}

variable "app_node_desired" {
  description = "Desired number of nodes in App node group"
  type        = number
  default     = 2
}

variable "app_node_min" {
  description = "Minimum number of nodes in App node group"
  type        = number
  default     = 1
}

variable "app_node_max" {
  description = "Maximum number of nodes in App node group"
  type        = number
  default     = 3
}

# ─── Security ───────────────────────────────────────────────────────────────────

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access the EKS API server publicly. Restrict to my IP."
  type        = list(string)
  default     = ["0.0.0.0/0"] # TODO: replace with your own IP e.g. ["1.2.3.4/32"]
}

# ─── GitHub Actions OIDC ────────────────────────────────────────────────────────

variable "github_repo" {
  description = "GitHub repository in format 'owner/repo' for OIDC trust"
  type        = string
}

# ─── EKS Cluster ────────────────────────────────────────────────────────────────
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.8"

  cluster_name    = local.cluster_name
  cluster_version = var.eks_cluster_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Allow public access to the API server (for kubectl from local)
  # Restrict to your own IP for security; use 0.0.0.0/0 only temporarily
  cluster_endpoint_public_access       = true
  cluster_endpoint_private_access      = true
  cluster_endpoint_public_access_cidrs = var.allowed_cidr_blocks

  # Enable OIDC provider for IRSA
  enable_irsa = true

  # Cluster add-ons
  cluster_addons = {
    coredns = {
      most_recent = true
      configuration_values = jsonencode({
        tolerations = [
          {
            key      = "dedicated"
            value    = "infra"
            effect   = "NoSchedule"
            operator = "Equal"
          }
        ]
        nodeSelector = {
          role = "infra"
        }
      })
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
  }

  # ─── Managed Node Groups ──────────────────────────────────────────────────────
  eks_managed_node_groups = {
    # Infra Node Group: monitoring & cluster components
    infra = {
      instance_types = [var.infra_node_instance_type]
      capacity_type  = "ON_DEMAND"

      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = 20
            volume_type           = "gp3"
            encrypted             = true
            delete_on_termination = true
          }
        }
      }

      min_size     = var.infra_node_min
      max_size     = var.infra_node_max
      desired_size = var.infra_node_desired

      labels = {
        role = "infra"
      }

      taints = [
        {
          key    = "dedicated"
          value  = "infra"
          effect = "NO_SCHEDULE"
        }
      ]

      tags = merge(local.common_tags, {
        NodeGroup = "infra"
      })
    }

    # App Node Group: business application workloads
    app = {
      instance_types = [var.app_node_instance_type]
      capacity_type  = "ON_DEMAND"

      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = 20
            volume_type           = "gp3"
            encrypted             = true
            delete_on_termination = true
          }
        }
      }

      min_size     = var.app_node_min
      max_size     = var.app_node_max
      desired_size = var.app_node_desired

      labels = {
        role = "app"
      }

      taints = [
        {
          key    = "dedicated"
          value  = "app"
          effect = "NO_SCHEDULE"
        }
      ]

      tags = merge(local.common_tags, {
        NodeGroup = "app"
      })
    }
  }

  # Grant current caller admin access to the cluster
  enable_cluster_creator_admin_permissions = true

  # Grant IAM admin user permanent kubectl access via EKS Access Entries API
  access_entries = {
    admin_user = {
      principal_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/admin"

      policy_associations = {
        cluster_admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  tags = local.common_tags
}

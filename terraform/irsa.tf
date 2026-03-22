# ─── AWS Load Balancer Controller IRSA ──────────────────────────────────────────
# IAM policy document: allow ALB Controller to assume role via OIDC
data "aws_iam_policy_document" "alb_controller_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }
  }
}

resource "aws_iam_role" "alb_controller" {
  name               = "${local.cluster_name}-alb-controller"
  assume_role_policy = data.aws_iam_policy_document.alb_controller_assume.json
  tags               = local.common_tags
}

# AWS-managed policy for ALB Controller
# Reference: https://github.com/kubernetes-sigs/aws-load-balancer-controller/blob/main/docs/install/iam_policy.json
resource "aws_iam_role_policy_attachment" "alb_controller" {
  role       = aws_iam_role.alb_controller.name
  policy_arn = aws_iam_policy.alb_controller.arn
}

resource "aws_iam_policy" "alb_controller" {
  name   = "${local.cluster_name}-alb-controller-policy"
  policy = file("${path.module}/policies/alb-controller-policy.json")
  tags   = local.common_tags
}

# ─── Prometheus (AMP) IRSA ──────────────────────────────────────────────────────
# IAM role for Prometheus to write metrics (optional: for future AMP integration)
data "aws_iam_policy_document" "prometheus_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:sub"
      # kube-prometheus-stack default: namespace=monitoring, SA=<release>-kube-prometheus-stack-prometheus
      # Adjust <release-name> to match your Helm release name
      values = ["system:serviceaccount:monitoring:kube-prometheus-stack-prometheus"]
    }
  }
}

resource "aws_iam_role" "prometheus" {
  name               = "${local.cluster_name}-prometheus"
  assume_role_policy = data.aws_iam_policy_document.prometheus_assume.json
  tags               = local.common_tags
}

# Attach AmazonPrometheusRemoteWriteAccess for future AMP usage
resource "aws_iam_role_policy_attachment" "prometheus" {
  role       = aws_iam_role.prometheus.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonPrometheusRemoteWriteAccess"
}

# ─── GitHub Actions OIDC Verification ───────────────────────────────────────────
# Temporary test resource to verify GitHub Actions OIDC authentication works.
# Delete this file after verification is complete.

resource "aws_ssm_parameter" "github_actions_test" {
  name  = "/eks-obs-dev/github-actions-test"
  type  = "String"
  value = "hello-from-github-actions"

  tags = local.common_tags
}

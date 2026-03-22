# ─── S3 Remote State Backend with Native Locking ─────────────────────────────
# Requires Terraform >= 1.11.0. No DynamoDB needed.
#
# Prerequisites:
#   1. Create S3 bucket: aws s3api create-bucket --bucket eks-obs-tfstate-760033296418 \
#        --region ap-northeast-1 --create-bucket-configuration LocationConstraint=ap-northeast-1
#   2. Enable versioning: aws s3api put-bucket-versioning \
#        --bucket eks-obs-tfstate-760033296418 --versioning-configuration Status=Enabled
#   3. Run: terraform init -migrate-state

terraform {
  backend "s3" {
    bucket       = "eks-obs-tfstate-760033296418"
    key          = "eks-obs/terraform.tfstate"
    region       = "ap-northeast-1"
    use_lockfile = true
    encrypt      = true
  }
}

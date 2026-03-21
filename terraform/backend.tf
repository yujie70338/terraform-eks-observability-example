# ─── S3 Remote State Backend (uncomment when S3 bucket is ready) ─────────────
#
# terraform {
#   backend "s3" {
#     bucket         = "<BUCKET_NAME>"
#     key            = "eks-obs/terraform.tfstate"
#     region         = "ap-northeast-1"
#     dynamodb_table = "<LOCK_TABLE>"
#     encrypt        = true
#   }
# }
#
# Prerequisites:
#   1. Create an S3 bucket with versioning enabled
#   2. Create a DynamoDB table with partition key "LockID" (String)
#   3. Replace the placeholder values above and uncomment the block

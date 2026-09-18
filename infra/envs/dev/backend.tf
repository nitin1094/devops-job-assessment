# State lives in a bucket that only the dev account/role can reach. Prod uses a
# different bucket, not just a different key, so a mistyped -backend-config can
# never point a dev apply at prod state.
#
# use_lockfile replaces the old DynamoDB lock table: S3 conditional writes give
# the same mutual exclusion with one less resource to provision (Terraform 1.10+).
#
# No AWS access? See README "Reviewing the Terraform without an AWS account" --
# scripts/tf-local-backend.sh swaps this for local state in one command.
terraform {
  backend "s3" {
    bucket       = "bookings-tfstate-dev-ap-south-1"
    key          = "platform/terraform.tfstate"
    region       = "ap-south-1"
    encrypt      = true
    use_lockfile = true
  }
}

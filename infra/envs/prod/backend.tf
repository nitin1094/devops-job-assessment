# Separate bucket from dev, in a separate account in any setup worth the name.
# The blast radius of a wrong -backend-config or a stale AWS_PROFILE should be
# "permission denied", not "destroyed the wrong environment".
terraform {
  backend "s3" {
    bucket       = "bookings-tfstate-prod-ap-south-1"
    key          = "platform/terraform.tfstate"
    region       = "ap-south-1"
    encrypt      = true
    use_lockfile = true
  }
}

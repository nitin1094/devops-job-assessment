provider "aws" {
  region = var.aws_region

  # Applied to everything that supports tagging, so individual resources only
  # carry a Name. This is what makes cost allocation by environment possible.
  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Repository  = "devops-assessment"
    }
  }
}

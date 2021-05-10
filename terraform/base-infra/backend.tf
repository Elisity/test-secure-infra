terraform {
  backend "s3" {
    workspace_key_prefix = "infra:"
    region               = "us-west-2" # bucket region
    key                  = "base-infra"
    encrypt              = true
  }
}

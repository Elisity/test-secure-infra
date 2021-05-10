terraform {
  backend "s3" {
    region               = "us-west-2" # bucket region
    key                  = "account"
    encrypt              = true
  }
}

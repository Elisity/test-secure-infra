module "master-amis-us-west-2" {
  source = "../modules/master-amis"
  to_region = "us-west-2"
}

module "master-amis-us-east-2" {
  source = "../modules/master-amis"
  to_region = "us-east-2"
}

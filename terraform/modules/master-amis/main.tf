// Master account credentials.
data "aws_secretsmanager_secret" "master-awscreds" {
  name = "elisity-master-awscreds"
}
data "aws_secretsmanager_secret_version" "master-awscreds" {
  secret_id = data.aws_secretsmanager_secret.master-awscreds.id
}

provider "aws" {
  alias = "master"

  region = var.to_region
  access_key = jsondecode(data.aws_secretsmanager_secret_version.master-awscreds.secret_string)["accessKeyId"]
  secret_key = jsondecode(data.aws_secretsmanager_secret_version.master-awscreds.secret_string)["secretAccessKey"]
}

data "aws_caller_identity" "master" {
  provider = aws.master
}

locals {
  master_account_id = data.aws_caller_identity.master.account_id
}

// Master account AMI list.
data "aws_ami" "master" {
  provider = aws.master

  for_each = toset(var.master_amis)

  owners = [ local.master_account_id ]

  filter {
    name = "name"
    values = [ each.value ]
  }
}

// Master account AMI launch permissions for subordinate account.
resource "aws_ami_launch_permission" "master" {
  provider = aws.master

  for_each = data.aws_ami.master
  image_id   = each.value.image_id
  account_id = data.aws_caller_identity.current.account_id
}

// Target account ID
data "aws_caller_identity" "current" {}

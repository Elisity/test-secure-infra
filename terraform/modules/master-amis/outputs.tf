output "ami_ids" {
  description = "A map of AMI IDs, keyed by name"
  value = { for name in var.master_amis : name => data.aws_ami.master[name].image_id }
}

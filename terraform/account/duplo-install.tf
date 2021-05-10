resource "aws_cloudformation_stack" "duplo-root-stack" {
  provider = aws.us-west-2
  count = var.manage_duplo_install ? 1 : 0

  lifecycle {
    ignore_changes = all
  }

  name = "duplo-root-stack"

  template_body = file(coalesce(var.duplo_root_stack_path, "${path.module}/files/duplo-root-stack.json"))

  parameters = {
    DefaultAdmin       = "joe@duplocloud.net"
    MasterAmiId        = "ami-0c6a0557943dd76f9"
    BastionAmiId       = "ami-0d4efc14256385b61"
    SetupUrl           = local.duplo_url
    DUPLOEXTDNSPRFX    = ".${local.external_fqdn}"
    DUPLOINTDNSPRFX    = ".${local.internal_fqdn}"
    AWSROUTE53DOMAINID = aws_route53_zone.internal.id
  }

  capabilities = [ "CAPABILITY_NAMED_IAM", "CAPABILITY_AUTO_EXPAND" ]

  // Sleep for 20 minutes after completion.
  provisioner "local-exec" {
    command = "sleep 1200"
  }
}

data "aws_elb" "duplo-authelb" {
  provider = aws.us-west-2

  name = "AuthELBDuplo"
}

resource "null_resource" "master-ecr-policy" {
  provisioner "local-exec" {
    when = create
    command = "${path.module}/files/ecr-policy.sh create"
  }
  provisioner "local-exec" {
    when = destroy
    command = "${path.module}/files/ecr-policy.sh destroy"
  }
}

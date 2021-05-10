resource "random_password" "postgres-master-user" {
  length  = var.postgres_master_user_length
  number  = true
  special = false
}

resource "random_password" "postgres-master-password" {
  length  = var.postgres_master_password_length
  number  = true
  special = false
}

resource "duplocloud_rds_instance" "postgres" {
  tenant_id = duplocloud_tenant.this.tenant_id
  name = local.tenant_name
  engine = 1  // PostgreSQL
  engine_version = var.postgres_version
  size = var.postgres_instance_size

  master_username = lower(random_password.postgres-master-user.result)
  master_password = random_password.postgres-master-password.result

  encrypt_storage = true
}

################################################################################
# Auto-generated AUTH Token (Redis/Valkey only)
################################################################################

resource "random_password" "auth_token" {
  count = local.generate_auth_token ? 1 : 0

  length  = var.auth_token_length
  special = false
}

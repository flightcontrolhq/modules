provider "aws" {
  region = var.region
}

# Ravion API provider. Authenticates with RAVION_API_KEY (the runner JWT injected
# by tower-go for the stack run) against RAVION_BASE_URL — both from the env.
provider "ravion" {}

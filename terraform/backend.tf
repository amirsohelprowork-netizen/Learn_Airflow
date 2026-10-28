terraform {
  # Local state removes the circular dependency on the MinIO stack it provisions.
  backend "local" {
    path = "local.tfstate"
  }
}

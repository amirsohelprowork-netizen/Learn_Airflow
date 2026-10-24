terraform {
  backend "s3" {
    bucket                      = "airflow-tfstate"
    key                         = "airflow/local/terraform.tfstate"
    region                      = "us-east-1"
    endpoint                    = "http://localhost:9000"
    access_key                  = "minioadmin"
    secret_key                  = "minioadmin"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    force_path_style            = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
  }
}

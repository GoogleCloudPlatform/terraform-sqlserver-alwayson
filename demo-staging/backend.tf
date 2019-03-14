terraform {
 backend "gcs" {
   bucket  = "{common-backend-bucket}"
   prefix    = "/states/terraform.tfstate"
   project = "{cloud-project-id}"
 }
}

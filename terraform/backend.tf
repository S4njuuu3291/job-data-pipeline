terraform {
  backend "s3" {
    bucket  = "jobscraper-terraform-state-730335315755"
    key     = "terraform.tfstate"
    region  = "ap-southeast-1"
    encrypt = true
  }
}

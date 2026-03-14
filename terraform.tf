terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "7.20.0"
    }
  }
}

#configure the provider with the provider block

provider "google" {
  project = "norse-bond-323008"
  region  = "asia-south1"
}
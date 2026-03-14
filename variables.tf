#define your project variables in this file
variable "project_id" {
  description = "GCP project ID where the resources will be created"
  type        = string
  default     = "norse-bond-323008"
}

variable "region" {
  description = "GCP region where the resources will be created"
  type        = string
  default     = "asia-south1"
}
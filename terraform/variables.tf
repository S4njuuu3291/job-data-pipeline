variable "aws_region" {
  type        = string
  default     = "ap-southeast-1"
  description = "AWS region untuk deploy resources. Default: ap-southeast-1 (Singapore)"
}

variable "aws_access_key" {
  type        = string
  description = "AWS Access Key ID untuk authentication"
  sensitive   = true
}

variable "aws_secret_key" {
  type        = string
  description = "AWS Secret Access Key untuk authentication. JANGAN hardcode, gunakan env var atau .tfvars"
  sensitive   = true
}
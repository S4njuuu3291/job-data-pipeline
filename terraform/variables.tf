variable "aws_region" {
  type        = string
  default     = "ap-southeast-1"
  description = "AWS region untuk deploy resources. Default: ap-southeast-1 (Singapore)"
}

variable "slack_webhook_url" {
  type        = string
  default     = "template_webhook_url"
  description = "Slack webhook URL for sending alerts"
  sensitive   = true
}

variable "aws_region" {
  type        = string
  default     = "ap-southeast-1"
  description = "AWS region untuk deploy resources. Default: ap-southeast-1 (Singapore)"
}

variable "slack_webhook_url" {
  type        = string
  default     = ""
  description = "Slack webhook URL for sending alerts. Leave empty and set manually in AWS Console SSM Parameter Store"
  sensitive   = true
}

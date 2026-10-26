variable "name" {
  type = string
}

variable "alert_email" {
  type = string
}

variable "monthly_budget" {
  type = number
}

variable "existing_monitor_arn" {
  type    = string
  default = ""
}

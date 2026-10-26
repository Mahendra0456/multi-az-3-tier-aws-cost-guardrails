variable "name" { type = string }
variable "project" { type = string }
variable "env" { type = string }
variable "app_subnet_ids" { type = list(string) }
variable "app_sg_id" { type = string }
variable "target_group_arn" { type = string }
variable "instance_type" { type = string }

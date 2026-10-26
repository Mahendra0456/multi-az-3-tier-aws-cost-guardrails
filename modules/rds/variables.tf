variable "name" { type = string }
variable "env" { type = string }
variable "db_subnet_ids" { type = list(string) }
variable "db_sg_id" { type = string }
variable "db_instance_class" { type = string }
variable "multi_az" { type = bool }

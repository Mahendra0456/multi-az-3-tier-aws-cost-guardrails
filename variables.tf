variable "region" { default = "ap-south-1" }
variable "project" { default = "three-tier" }
variable "env" { default = "dev" }
variable "vpc_cidr" { default = "10.0.0.0/16" }
variable "single_nat" { default = true }
variable "instance_type" { default = "t3.micro" }
variable "db_instance_class" { default = "db.t3.micro" }
variable "multi_az" { default = true }
variable "monthly_budget" { default = 50 }
variable "alert_email" { type = string }

# Optional HTTPS: leave both empty to run HTTP only
variable "domain_name" { default = "" } # e.g. app.example.com
variable "zone_name" { default = "" }   # e.g. example.com (must be a Route 53 public hosted zone)

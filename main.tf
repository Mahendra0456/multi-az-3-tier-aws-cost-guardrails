data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name = "${var.project}-${var.env}"
  azs  = slice(data.aws_availability_zones.available.names, 0, 2)
}

module "vpc" {
  source     = "./modules/vpc"
  name       = local.name
  vpc_cidr   = var.vpc_cidr
  azs        = local.azs
  single_nat = var.single_nat
}

module "security" {
  source = "./modules/security"
  name   = local.name
  vpc_id = module.vpc.vpc_id
}

module "alb" {
  source            = "./modules/alb"
  name              = local.name
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
  alb_sg_id         = module.security.alb_sg_id
  domain_name       = var.domain_name
  zone_name         = var.zone_name
}

module "compute" {
  source           = "./modules/compute"
  name             = local.name
  project          = var.project
  env              = var.env
  app_subnet_ids   = module.vpc.app_subnet_ids
  app_sg_id        = module.security.app_sg_id
  target_group_arn = module.alb.target_group_arn
  instance_type    = var.instance_type

  # wait for NAT gateways and routes so user-data can download packages
  depends_on = [module.vpc]
}

module "rds" {
  source            = "./modules/rds"
  name              = local.name
  env               = var.env
  db_subnet_ids     = module.vpc.db_subnet_ids
  db_sg_id          = module.security.db_sg_id
  db_instance_class = var.db_instance_class
  multi_az          = var.multi_az
}

module "guardrails" {
  source         = "./modules/guardrails"
  name           = local.name
  alert_email    = var.alert_email
  monthly_budget = var.monthly_budget

  existing_monitor_arn = "arn:aws:ce::977133951325:anomalymonitor/11e6cba6-44f2-4d6a-b51f-2c2942fd54fb"
}

module "monitoring" {
  source         = "./modules/monitoring"
  name           = local.name
  sns_topic_arn  = module.guardrails.topic_arn
  alb_arn_suffix = module.alb.alb_arn_suffix
  tg_arn_suffix  = module.alb.tg_arn_suffix
  db_identifier  = module.rds.identifier
}

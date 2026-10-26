output "app_url" {
  value = var.domain_name != "" ? "https://${var.domain_name}" : "http://${module.alb.dns_name}"
}

output "alb_dns_name" {
  value = module.alb.dns_name
}

output "rds_endpoint" {
  value = module.rds.endpoint
}

output "db_secret_arn" {
  value = module.rds.secret_arn
}

output "alerts_topic_arn" {
  value = module.guardrails.topic_arn
}

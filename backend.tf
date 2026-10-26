terraform {
  backend "s3" {
    bucket       = "3-tire-cost-guardrails-bkt"
    key          = "three-tier/dev/terraform.tfstate"
    region       = "ap-south-1"
    encrypt      = true
    use_lockfile = true
  }
}

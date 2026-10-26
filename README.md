<div align="center">

# Multi-AZ 3-Tier Infrastructure on AWS with Cost Guardrails

**A highly available, secure, cost-governed web platform on AWS, provisioned entirely with modular Terraform.**

![Terraform](https://img.shields.io/badge/IaC-Terraform-7B42BC?logo=terraform&logoColor=white)
![AWS](https://img.shields.io/badge/Cloud-AWS-FF9900?logo=amazonaws&logoColor=white)
![Region](https://img.shields.io/badge/Region-ap--south--1%20(Mumbai)-blue)
![CI](https://img.shields.io/badge/CI-GitHub%20Actions-2088FF?logo=githubactions&logoColor=white)
![Modules](https://img.shields.io/badge/Terraform%20modules-7-success)
![Resources](https://img.shields.io/badge/Resources%20deployed-48-brightgreen)
![License](https://img.shields.io/badge/License-MIT-yellow)

</div>

## Project Overview

Designed and deployed a Multi-AZ 3-tier AWS infrastructure using Terraform, featuring an Application Load Balancer, self-healing EC2 Auto Scaling, and an encrypted Multi-AZ RDS database.

Integrated AWS Budgets, Cost Anomaly Detection, CloudWatch, SNS email alerts, resource tagging, and scheduled development scale-down for cost governance. Implemented secure networking, S3 remote state, and GitHub Actions for automated Terraform validation.

**Scope:** The application serves a static page displaying the EC2 instance ID and Availability Zone; database application integration is not implemented.
<div align="center">

[Architecture]
<img width="3400" height="2000" alt="image" src="https://github.com/user-attachments/assets/a7dbd5e6-85c7-4c4c-acc9-503fd43957b9" />


</div>

---

## Highlights

| | |
|---|---|
| **High availability** | 2 AZs, ALB, Auto Scaling Group (2 to 4), RDS MySQL Multi-AZ with automatic failover |
| **Security** | 3 isolated tiers, security-group chaining, no SSH or key pairs, IMDSv2, encrypted RDS, secrets in Secrets Manager |
| **Cost governance** | Budgets, anomaly detection, cost-allocation tags, dev schedule, single-NAT dev mode |
| **Operations** | CloudWatch alarms into SNS, optional HTTPS with ACM, CI with `fmt` and `validate` |
| **Infrastructure as code** | 7 Terraform modules, S3 remote state with native locking, 48 resources |

---

## Table of contents

- [Key features](#key-features)
- [Tech stack](#tech-stack)
- [Repository structure](#repository-structure)
- [Design decisions](#design-decisions)
- [Cost guardrails](#cost-guardrails)
- [Prerequisites](#prerequisites)
- [Deployment](#deployment)
- [Validation and evidence](#validation-and-evidence)
- [Estimated cost](#estimated-cost)
- [Cleanup](#cleanup)
- [Known limitations](#known-limitations)
- [Possible improvements](#possible-improvements)

---

## Key features

**High availability**
- Resources spread across two Availability Zones: public, private-app and isolated DB subnets
- Application Load Balancer with health checks
- Auto Scaling Group (min 2, max 4) with ELB health checks, self-healing and CPU target tracking at 50%
- RDS MySQL Multi-AZ with automatic failover

**Security**
- Three isolated network tiers; only the ALB is internet-facing
- Security groups reference each other instead of CIDR ranges (ALB → app → DB)
- No SSH and no key pairs on app servers; access via AWS Systems Manager Session Manager
- IMDSv2 enforced on instances
- RDS encrypted at rest, not publicly accessible, master password generated and held in AWS Secrets Manager (never in code or `tfvars`)
- Remote Terraform state in a versioned, encrypted, private S3 bucket

**Cost guardrails**
- Budget alerts, anomaly detection, tagging and dev scheduling (details [below](#cost-guardrails))

**Operations**
- CloudWatch alarms for ALB 5xx, unhealthy targets, RDS CPU and RDS free storage
- Optional HTTPS with ACM and an HTTP-to-HTTPS redirect (enabled only when a domain is provided)
- GitHub Actions workflow running `terraform fmt` and `validate`

---

## Tech stack

| Area | Services and tools |
|---|---|
| Infrastructure as code | Terraform (modular), S3 remote state with native locking |
| Network | VPC, public/private subnets, Internet Gateway, NAT Gateway, route tables |
| Compute | EC2 Launch Template, Auto Scaling Group, Amazon Linux 2023 |
| Load balancing | Application Load Balancer, target group, optional ACM + Route 53 |
| Database | RDS MySQL 8.0 Multi-AZ, Secrets Manager |
| Observability and alerting | CloudWatch alarms, SNS |
| FinOps | AWS Budgets, Cost Anomaly Detection, cost-allocation tags |
| CI | GitHub Actions |

---

## Repository structure

```text
three-tier-aws/
├── provider.tf          # AWS provider, default_tags
├── backend.tf           # S3 backend (bucket supplied via backend.hcl)
├── variables.tf
├── main.tf              # wires the modules together
├── outputs.tf
├── modules/
│   ├── vpc/             # VPC, subnets, IGW, NAT, route tables
│   ├── security/        # ALB, app and DB security groups
│   ├── alb/             # ALB, listeners, optional ACM/Route 53
│   ├── compute/         # launch template, ASG, scaling, dev schedules
│   ├── rds/             # Multi-AZ MySQL, subnet group, Secrets Manager
│   ├── guardrails/      # SNS topic, Budgets, Cost Anomaly Detection
│   └── monitoring/      # CloudWatch alarms
├── docs/images/         # architecture diagram and screenshots
└── .github/workflows/
    └── terraform-ci.yml # fmt + validate
```

---

## Design decisions

| Decision | Reason and trade-off |
|---|---|
| **Single NAT gateway in dev, one per AZ in prod** (`single_nat` variable) | Saves about $40/month per extra NAT. Trade-off: dev loses outbound access if that AZ fails. |
| **Session Manager instead of SSH** | No inbound port 22, no key management, access is logged and controlled by IAM. |
| **`manage_master_user_password`** | The database password is generated by AWS and stored in Secrets Manager, so it never appears in code or `tfvars`. |
| **Explicit tags on the launch template** | Provider `default_tags` do not propagate to instances launched by an Auto Scaling Group. Without explicit tags, the most expensive resources would be untagged in Cost Explorer. |
| **Reuse the account's existing Cost Anomaly monitor** | AWS allows one service-level monitor per account and creates it automatically. The Terraform accepts an `existing_monitor_arn` and only creates a monitor when none is supplied. Creating a second one failed with `Limit exceeded on dimensional spend monitor creation`. |
| **One SNS topic for all alerts** | Budgets, anomaly detection and CloudWatch share one destination, so email can later be extended to Slack or Lambda without changing the alert sources. |
| **Optional HTTPS behind a variable** | Certificate validation needs a domain in Route 53. Leaving `domain_name` empty keeps the project deployable without one. |
| **Dev vs prod behaviour from variables** | `multi_az`, `single_nat`, backup retention, final snapshot and scheduled scale-down switch on `env` and variables. |

---

## Cost guardrails

| Control | What it does |
|---|---|
| **AWS Budgets** | Monthly budget with alerts at 50%, 80% and 100% of actual spend and 100% of forecasted spend |
| **Cost Anomaly Detection** | Subscription (individual alerts) on the service-level monitor, alerting through SNS when an anomaly's impact is at least $5 |
| **Cost-allocation tags** | `Project`, `Env`, `ManagedBy` on every resource, including ASG-launched instances and volumes |
| **Dev scheduling** | Auto Scaling Group scales to 0 at 22:00 IST and back to 2 at 08:00 IST in the dev environment |
| **Right-sized resources** | `t3.micro` instances, `db.t3.micro`, minimal backups and no final snapshot in dev |
| **CloudWatch alarms** | Early warning for load and capacity problems, sent to the same SNS topic |

> **Important:** Budgets and anomaly detection **notify**; they do not stop spending. The scheduled scale-down only affects the app instances. The ALB, NAT gateway and RDS keep running and billing overnight.

---

## Prerequisites

- An AWS account and a control machine (an EC2 instance with an IAM role works well)
- Terraform **1.10 or newer** (required for S3 native state locking)
- AWS CLI v2
- An S3 bucket for Terraform state (created once, see below)
- Optional: a domain in a Route 53 public hosted zone, for HTTPS

---

## Deployment

**1. Create the state bucket (one time)**
```bash
export ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export BUCKET=three-tier-tfstate-$ACCOUNT

aws s3api create-bucket --bucket $BUCKET --region ap-south-1 \
  --create-bucket-configuration LocationConstraint=ap-south-1
aws s3api put-bucket-versioning --bucket $BUCKET \
  --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --bucket $BUCKET \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
aws s3api put-public-access-block --bucket $BUCKET \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```

**2. Configure variables**

`backend.hcl`
```hcl
bucket = "three-tier-tfstate-<ACCOUNT_ID>"
```

`terraform.tfvars`
```hcl
alert_email    = "you@example.com"
monthly_budget = 50
# domain_name  = "app.example.com"   # optional HTTPS
# zone_name    = "example.com"
```

**3. Reuse the existing anomaly monitor**

Find your account's monitor and set `existing_monitor_arn` in the `guardrails` module block in `main.tf`:
```bash
aws ce get-anomaly-monitors --query 'AnomalyMonitors[].[MonitorName,MonitorArn]' --output table
```
In an account with no existing monitor, leave it empty and Terraform creates one.

**4. Deploy**
```bash
terraform fmt -recursive
terraform init -backend-config=backend.hcl
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
```
RDS Multi-AZ takes roughly 10 to 15 minutes.

**5. Confirm the alert subscription**

Click **Confirm subscription** in the "AWS Notification - Subscription Confirmation" email. Alerts are not delivered until this is done.

**6. Get the URL**
```bash
terraform output app_url
```

---

## Validation and evidence

Results from the deployment in `ap-south-1`. Anything not yet run is marked *Pending* and has no evidence claimed.

| Check | Result | Status |
|---|---|---|
| Deployment from code | 48 resources in Terraform state, outputs returned | ✅ Passed |
| Network layout | 6 subnets across 2 AZs, 5 route tables, 1 internet gateway, 1 NAT gateway | ✅ Passed |
| Target health | Both ALB targets `healthy` | ✅ Passed |
| Load balancing across AZs | Repeated requests to the ALB URL were served by two different instances in `ap-south-1a` and `ap-south-1b` | ✅ Passed |
| RDS configuration | MySQL, Multi-AZ = True, encrypted = True, publicly accessible = False, primary in `ap-south-1a`, standby in `ap-south-1b` | ✅ Passed |
| SNS to email delivery | Test message received by email | ✅ Passed |
| Budget alert | Forecasted-spend alert received (budget temporarily set to $0.10, forecast $0.28) | ✅ Passed |
| CI pipeline | GitHub Actions run: `fmt -check`, `init -backend=false`, `validate` all green | ✅ Passed |
| Cost Anomaly Detection | Subscription `three-tier-dev-anomaly-sns` created, individual alerts, $5 threshold, attached to the account's service monitor. No anomaly has fired. | ⚙️ Configured |
| Self-healing | Terminate one instance, ASG replaces it | ✅ Passed |
| RDS failover | Forced failover promotes the standby | ✅ Passed |
| CloudWatch alarm email | `set-alarm-state` to `ALARM` | ✅ Passed |
| Tags on EC2, volumes, RDS | `Project`, `Env`, `ManagedBy` present | ✅ Passed |
| Dev schedule | ASG activity after 22:00 IST | ✅ Passed |

### Deployment outputs
`terraform output` and the number of resources in state (48).
<div align="center">
Terraform output<img width="1917" height="466" alt="Screenshot 2026-10-26 170759" src="https://github.com/user-attachments/assets/a1a2c3a0-1b6b-425d-a2fb-42307ea4bcd1" />
</div>

### Network: VPC resource map
Six subnets across two AZs, five route tables, an internet gateway and a NAT gateway.
<div align="center">
VPC resource map<img width="1917" height="858" alt="Screenshot 2026-10-26 171015" src="https://github.com/user-attachments/assets/bf734fac-ec16-41b7-a415-26e81a25763e" />
</div>

### Application tier: target health
Both instances registered with the load balancer and reporting healthy.
<div align="center">
Target health<img width="1917" height="436" alt="Screenshot 2026-10-26 171143" src="https://github.com/user-attachments/assets/991e035f-eef6-4786-959b-876427e94375" />
</div>

### Database tier: RDS Multi-AZ
Multi-AZ enabled, storage encrypted, not publicly accessible, standby in a second AZ.
<div align="center">
RDS Multi-AZ<img width="1917" height="395" alt="Screenshot 2026-10-26 171307" src="https://github.com/user-attachments/assets/09994d07-22f5-4c3b-9bc1-501e530745d1" />
</div>

### Cost guardrails: anomaly detection subscription
Subscription attached to the account's default service monitor with a $5 threshold.
<div align="center">
Anomaly subscription<img width="1917" height="867" alt="Screenshot 2026-10-26 171601" src="https://github.com/user-attachments/assets/91eb2b80-16fb-4e0e-896a-3000b6fe08cc" />
</div>

### Alerting: SNS email delivery
A test message published to the SNS topic, delivered by email.
<div align="center">
SNS test email<img width="1602" height="782" alt="Screenshot 2026-10-26 171856" src="https://github.com/user-attachments/assets/a7c3b5c6-2451-40d6-8b30-e68aa4966fc1" />
</div>

### Alerting: budget alert
A forecasted-spend alert from AWS Budgets, delivered through the SNS topic. The budget was temporarily lowered to $0.10 to trigger it, then restored.
<div align="center">
Budget alert email<img width="1606" height="797" alt="Screenshot 2026-10-26 171705" src="https://github.com/user-attachments/assets/8ec64190-49a7-4bcd-a830-4714919ea2c9" />
</div>

### CI: GitHub Actions
`terraform fmt -check`, `terraform init -backend=false` and `terraform validate` run on every push.
<div align="center">
GitHub Actions CI<img width="1917" height="907" alt="Screenshot 2026-10-26 174057" src="https://github.com/user-attachments/assets/9b403016-0486-4025-a13e-f9f51e687e11" />
</div>

---

## Estimated cost

Approximate while running in `ap-south-1`. Verify with the AWS Pricing Calculator.

| Item | Approx. monthly |
|---|---|
| NAT gateway (1) | about $40 plus data |
| Application Load Balancer | about $18 plus LCU |
| RDS db.t3.micro Multi-AZ | about $25 to $30 |
| 2x t3.micro app instances | about $16 |
| **Total** | **about $100, or about $3 to $4 per day** |

This project is intended to be deployed, tested and destroyed within a day.

---

## Cleanup

```bash
terraform destroy
```

Then verify in the console that these are gone: EC2 instances and the ASG, the ALB and target group, NAT gateways and Elastic IPs, the RDS instance and any snapshots, and the Secrets Manager secret. Finally empty and delete the state bucket, and remove any temporary IAM role used for provisioning.

The account's `Default-Services-Monitor` is not managed by this project and is left untouched.

---

## Known limitations

- The application is a static page. It does not connect to RDS, so the database tier is validated by network and security design, not by application queries.
- Budgets and anomaly detection send notifications only. They do not enforce spending limits or shut anything down.
- The dev schedule scales only the app instances. NAT, ALB and RDS continue to bill.
- A single NAT gateway in dev is a deliberate single point of failure for outbound traffic.
- Cost Anomaly Detection needs time to build a baseline, so a subscription existing is not evidence that an anomaly has been detected.
- Budget alerts can take hours to arrive after a threshold is crossed.

---

## Possible improvements

- Make the app query RDS using credentials read from Secrets Manager at runtime
- Add AWS WAF on the ALB and VPC endpoints for SSM to remove NAT dependency for management traffic
- Run `terraform plan` on pull requests through GitHub OIDC and a scoped AWS role
- Add a Lambda that sends alerts to Slack, and one that stops dev resources when a budget is exceeded
- Split dev and prod into separate state files and accounts
- Add `tflint` and `checkov` to CI

---

## Author

**Mahendra Swain** · Aspiring DevOps and Cloud Engineer
[GitHub](https://github.com/Mahendra0456)

## License

MIT

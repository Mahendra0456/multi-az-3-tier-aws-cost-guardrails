data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# SSM access instead of SSH (no port 22, no key pairs)
resource "aws_iam_role" "app" {
  name = "${var.name}-app-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "app" {
  name = "${var.name}-app-profile"
  role = aws_iam_role.app.name
}

resource "aws_launch_template" "app" {
  name_prefix   = "${var.name}-lt-"
  image_id      = data.aws_ssm_parameter.al2023.value
  instance_type = var.instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.app.name
  }

  vpc_security_group_ids = [var.app_sg_id]

  metadata_options {
    http_tokens = "required" # IMDSv2 only
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    until dnf install -y httpd; do sleep 10; done
    systemctl enable --now httpd
    TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
    ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
    AZ=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/availability-zone)
    echo "<h1>3-Tier App</h1><p>Instance: $ID</p><p>AZ: $AZ</p>" > /var/www/html/index.html
  EOF
  )

  # provider default_tags do NOT reach ASG-launched instances/volumes, so tag them here
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name      = "${var.name}-app"
      Project   = var.project
      Env       = var.env
      ManagedBy = "terraform"
    }
  }

  tag_specifications {
    resource_type = "volume"
    tags = {
      Project   = var.project
      Env       = var.env
      ManagedBy = "terraform"
    }
  }
}

resource "aws_autoscaling_group" "app" {
  name                      = "${var.name}-asg"
  min_size                  = 2
  desired_capacity          = 2
  max_size                  = 4
  vpc_zone_identifier       = var.app_subnet_ids
  target_group_arns         = [var.target_group_arn]
  health_check_type         = "ELB"
  health_check_grace_period = 180

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }
}

resource "aws_autoscaling_policy" "cpu" {
  name                   = "${var.name}-cpu-target"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 50
  }
}

# Cost guardrail: dev scales to 0 at night, back up in the morning (IST)
resource "aws_autoscaling_schedule" "night_down" {
  count                  = var.env == "dev" ? 1 : 0
  scheduled_action_name  = "night-scale-down"
  autoscaling_group_name = aws_autoscaling_group.app.name
  recurrence             = "0 22 * * *"
  time_zone              = "Asia/Kolkata"
  min_size               = 0
  desired_capacity       = 0
  max_size               = 0
}

resource "aws_autoscaling_schedule" "morning_up" {
  count                  = var.env == "dev" ? 1 : 0
  scheduled_action_name  = "morning-scale-up"
  autoscaling_group_name = aws_autoscaling_group.app.name
  recurrence             = "0 8 * * *"
  time_zone              = "Asia/Kolkata"
  min_size               = 2
  desired_capacity       = 2
  max_size               = 4
}

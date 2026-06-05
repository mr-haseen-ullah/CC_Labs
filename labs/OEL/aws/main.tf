terraform {
  backend "s3" {
    bucket         = "tfstate-haseen-22mdswe238"
    key            = "OEL/terraform.tfstate"
    region         = "us-east-1"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "random_id" "suffix" {
  byte_length = 4
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

# ─── VPC & Networking (Part 1) ──────────────────────────────────────────────────

resource "aws_vpc" "oel_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "HaseenUllah-22MDSWE238-OEL-VPC"
  }
}

resource "aws_internet_gateway" "oel_igw" {
  vpc_id = aws_vpc.oel_vpc.id

  tags = {
    Name = "OEL-IGW"
  }
}

# Two Public Subnets (required for multi-AZ ALB)
resource "aws_subnet" "oel_public_1" {
  vpc_id                  = aws_vpc.oel_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "OEL-Public-Subnet-1"
  }
}

resource "aws_subnet" "oel_public_2" {
  vpc_id                  = aws_vpc.oel_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "OEL-Public-Subnet-2"
  }
}

# Two Private Subnets (Part 1.2 requirement)
resource "aws_subnet" "oel_private_1" {
  vpc_id            = aws_vpc.oel_vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "OEL-Private-Subnet-1"
  }
}

resource "aws_subnet" "oel_private_2" {
  vpc_id            = aws_vpc.oel_vpc.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "OEL-Private-Subnet-2"
  }
}

# Route Tables
resource "aws_route_table" "oel_public_rt" {
  vpc_id = aws_vpc.oel_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.oel_igw.id
  }

  tags = {
    Name = "OEL-Public-RT"
  }
}

resource "aws_route_table" "oel_private_rt" {
  vpc_id = aws_vpc.oel_vpc.id

  tags = {
    Name = "OEL-Private-RT"
  }
}

# Route Table Associations
resource "aws_route_table_association" "oel_pub_1" {
  subnet_id      = aws_subnet.oel_public_1.id
  route_table_id = aws_route_table.oel_public_rt.id
}

resource "aws_route_table_association" "oel_pub_2" {
  subnet_id      = aws_subnet.oel_public_2.id
  route_table_id = aws_route_table.oel_public_rt.id
}

resource "aws_route_table_association" "oel_priv_1" {
  subnet_id      = aws_subnet.oel_private_1.id
  route_table_id = aws_route_table.oel_private_rt.id
}

resource "aws_route_table_association" "oel_priv_2" {
  subnet_id      = aws_subnet.oel_private_2.id
  route_table_id = aws_route_table.oel_private_rt.id
}

# ─── Cloud Storage (Part 3) ───────────────────────────────────────────────────

resource "aws_s3_bucket" "portfolio_bucket" {
  bucket        = "oel-portfolio-bucket-${random_id.suffix.hex}"
  force_destroy = true
}

# Unblock public access configurations so we can grant read permissions
resource "aws_s3_bucket_public_access_block" "portfolio_bucket_block" {
  bucket = aws_s3_bucket.portfolio_bucket.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# S3 Policy granting public read access specifically to objects in 'assets/' prefix
resource "aws_s3_bucket_policy" "public_read_policy" {
  bucket = aws_s3_bucket.portfolio_bucket.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.portfolio_bucket.arn}/assets/*"
      }
    ]
  })
  depends_on = [aws_s3_bucket_public_access_block.portfolio_bucket_block]
}

# Ingest dummy portfolio resume and documentation files (Part 3.2 requirement)
resource "aws_s3_object" "resume" {
  bucket       = aws_s3_bucket.portfolio_bucket.id
  key          = "assets/resume.pdf"
  content      = "Haseen Ullah (22MDSWE238) - Professional CV / Resume\nCourse: SE-409L Cloud Computing Lab\nEmail: haseen.ullah@student.example.com\nSkills: AWS Architecture, Terraform, Azure Administrator, DevOps, CI/CD Pipelines."
  content_type = "text/plain"
}

resource "aws_s3_object" "project_doc" {
  bucket       = aws_s3_bucket.portfolio_bucket.id
  key          = "assets/project_doc.txt"
  content      = "Project Documentation Summary:\n1. AI-Driven Threat Detection: Deployed real-time log anomaly detectors via SageMaker.\n2. Cloud-Native E-Commerce: Scaled dynamic catalogs using AWS EC2, ALB, and Auto Scaling.\n3. Serverless Task Orchestrator: Built microservices using Lambda, API Gateway, and DynamoDB."
  content_type = "text/plain"
}

resource "aws_s3_object" "avatar" {
  bucket       = aws_s3_bucket.portfolio_bucket.id
  key          = "assets/avatar.jpg"
  content      = "Haseen Ullah - Profile Image Placeholder"
  content_type = "image/jpeg"
}

# ─── Load Balancer Infrastructure (Part 4 - Option A & B) ───────────────────────

# Security Group for Application Load Balancer
resource "aws_security_group" "alb_sg" {
  name        = "oel-alb-sg-${random_id.suffix.hex}"
  description = "Allow HTTP inbound from Internet"
  vpc_id      = aws_vpc.oel_vpc.id

  ingress {
    description = "HTTP from Internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "OEL-ALB-SG"
  }
}

# Application Load Balancer
resource "aws_lb" "portfolio_alb" {
  name               = "oel-portfolio-alb-${random_id.suffix.hex}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.oel_public_1.id, aws_subnet.oel_public_2.id]

  tags = {
    Name = "OEL-Portfolio-ALB"
  }
}

# Target Group
resource "aws_lb_target_group" "portfolio_tg" {
  name     = "oel-portfolio-tg-${random_id.suffix.hex}"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.oel_vpc.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }
}

# ALB Listener
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.portfolio_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.portfolio_tg.arn
  }
}

# ─── EC2 Auto Scaling Resources (Part 2 & 4) ───────────────────────────────────

# Security Group for EC2 instances (Least Privilege - Inbound HTTP ONLY from ALB)
resource "aws_security_group" "ec2_sg" {
  name        = "oel-ec2-sg-${random_id.suffix.hex}"
  description = "Least Privilege Security Group: HTTP from ALB only"
  vpc_id      = aws_vpc.oel_vpc.id

  ingress {
    description     = "HTTP inbound from ALB only"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  ingress {
    description = "SSH from Internet (Optional/Manual)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "OEL-EC2-SG"
  }
}

# Generate Key Pair
resource "tls_private_key" "oel_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "oel_keypair" {
  key_name   = "oel-keypair-${random_id.suffix.hex}"
  public_key = tls_private_key.oel_key.public_key_openssh
}

# Launch Template for Auto Scaling Group
resource "aws_launch_template" "portfolio_lt" {
  name_prefix   = "oel-portfolio-lt-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.ec2_sg.id]
  }

  key_name = aws_key_pair.oel_keypair.key_name

  user_data = base64encode(<<-EOF
    #!/bin/bash
    # Install Apache Web Server
    dnf update -y
    dnf install httpd -y
    systemctl start httpd
    systemctl enable httpd

    # Create the beautiful static portfolio HTML page (Part 2.2 requirement)
    cat << 'HTML_EOF' > /var/www/html/index.html
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Haseen Ullah - Cloud Portfolio</title>
        <link href="https://fonts.googleapis.com/css2?family=Outfit:wght@300;400;600;700&display=swap" rel="stylesheet">
        <style>
            :root {
                --primary: #4f46e5;
                --secondary: #06b6d4;
                --background: #0f172a;
                --card-bg: #1e293b;
                --text: #f8fafc;
                --text-muted: #94a3b8;
            }
            * {
                box-sizing: border-box;
                margin: 0;
                padding: 0;
                font-family: 'Outfit', sans-serif;
            }
            body {
                background-color: var(--background);
                color: var(--text);
                line-height: 1.6;
            }
            header {
                background: linear-gradient(135deg, var(--primary) 0%, var(--secondary) 100%);
                padding: 4rem 2rem;
                text-align: center;
                border-bottom: 4px solid var(--secondary);
            }
            header h1 {
                font-size: 3rem;
                font-weight: 700;
                margin-bottom: 0.5rem;
            }
            header p.student-info {
                font-size: 1.25rem;
                color: #e2e8f0;
                margin-bottom: 0.25rem;
            }
            .container {
                max-width: 1000px;
                margin: 3rem auto;
                padding: 0 2rem;
            }
            section {
                margin-bottom: 4rem;
            }
            h2 {
                font-size: 2rem;
                border-bottom: 2px solid var(--primary);
                padding-bottom: 0.5rem;
                margin-bottom: 1.5rem;
            }
            .grid {
                display: grid;
                grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
                gap: 2rem;
            }
            .card {
                background-color: var(--card-bg);
                border: 1px solid #334155;
                border-radius: 12px;
                padding: 2rem;
                transition: transform 0.3s ease, border-color 0.3s ease;
            }
            .card:hover {
                transform: translateY(-5s);
                border-color: var(--secondary);
            }
            .card h3 {
                color: var(--secondary);
                margin-bottom: 1rem;
                font-size: 1.4rem;
            }
            .card p {
                color: var(--text-muted);
                font-size: 0.95rem;
            }
            .btn-group {
                display: flex;
                gap: 1.5rem;
                margin-top: 2rem;
                justify-content: center;
                flex-wrap: wrap;
            }
            .btn {
                display: inline-block;
                padding: 0.75rem 1.5rem;
                border-radius: 8px;
                background-color: var(--primary);
                color: var(--text);
                text-decoration: none;
                font-weight: 600;
                transition: background-color 0.3s ease;
            }
            .btn-secondary {
                background-color: transparent;
                border: 2px solid var(--secondary);
                color: var(--secondary);
            }
            .btn:hover {
                background-color: #3b82f6;
            }
            .btn-secondary:hover {
                background-color: var(--secondary);
                color: var(--background);
            }
            footer {
                text-align: center;
                padding: 2rem;
                color: var(--text-muted);
                border-top: 1px solid #334155;
                margin-top: 4rem;
            }
        </style>
    </head>
    <body>
        <header>
            <h1>Haseen Ullah</h1>
            <p class="student-info">Reg No: <strong>22MDSWE238</strong></p>
            <p class="student-info">Course: <strong>SE-409L Cloud Computing Lab (Spring 2026)</strong></p>
        </header>
        
        <div class="container">
            <section id="projects">
                <h2>Featured Projects</h2>
                <div class="grid">
                    <div class="card">
                        <h3>AI-Driven Threat Detection</h3>
                        <p>Implemented an automated ML monitoring workflow that pipes real-time application and network traffic logs into AWS SageMaker, triggering CloudWatch anomaly alerts when potential threat patterns are identified.</p>
                    </div>
                    <div class="card">
                        <h3>Cloud-Native E-Commerce</h3>
                        <p>Architected a highly available multi-tier e-commerce catalog application backed by an AWS Application Load Balancer and Auto Scaling Groups, ensuring seamless scaling during high traffic loads.</p>
                    </div>
                    <div class="card">
                        <h3>Serverless Task Orchestrator</h3>
                        <p>Built a microservice system that schedules and runs recurring administrative cron tasks using AWS Lambda, API Gateway, and Amazon DynamoDB, resulting in a zero-management, 100% serverless infrastructure.</p>
                    </div>
                </div>
            </section>

            <section id="assets">
                <h2>Verified Cloud Storage Assets</h2>
                <p style="color: var(--text-muted); margin-bottom: 1.5rem;">The following links dynamically fetch verified curriculum artifacts hosted securely on our public S3 storage bucket:</p>
                <div class="btn-group">
                    <a href="https://${aws_s3_bucket.portfolio_bucket.bucket_regional_domain_name}/${aws_s3_object.resume.key}" class="btn" target="_blank">Download Resume (S3 URL)</a>
                    <a href="https://${aws_s3_bucket.portfolio_bucket.bucket_regional_domain_name}/${aws_s3_object.project_doc.key}" class="btn btn-secondary" target="_blank">View Project Documentation</a>
                </div>
            </section>
        </div>

        <footer>
            <p>&copy; 2026 Haseen Ullah (22MDSWE238). Powered by AWS Auto Scaling & S3.</p>
        </footer>
    </body>
    </html>
    HTML_EOF
  EOF
  )

  lifecycle {
    create_before_destroy = true
  }
}

# Auto Scaling Group (Part 4 - Option B requirement: Min 1, Max 2)
resource "aws_autoscaling_group" "portfolio_asg" {
  name_prefix         = "oel-portfolio-asg-"
  vpc_zone_identifier = [aws_subnet.oel_public_1.id, aws_subnet.oel_public_2.id]
  target_group_arns   = [aws_lb_target_group.portfolio_tg.arn]

  min_size         = 1
  max_size         = 2
  desired_capacity = 2

  launch_template {
    id      = aws_launch_template.portfolio_lt.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "OEL-Portfolio-ASG-Instance"
    propagate_at_launch = true
  }
}

# ─── CloudWatch Monitoring (Part 5) ───────────────────────────────────────────

# CPU Alarm exceeding 80% (Part 5.2 requirement)
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "oel-asg-cpu-high-alarm"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "60"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This alarm monitors EC2 average CPU utilization and triggers when average CPU exceeds 80%"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.portfolio_asg.name
  }
}

# CloudWatch Dashboard with at least one widget (Part 5.2 requirement)
resource "aws_cloudwatch_dashboard" "oel_dashboard" {
  dashboard_name = "OEL-Dashboard-${random_id.suffix.hex}"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", aws_autoscaling_group.portfolio_asg.name]
          ]
          period = 60
          stat   = "Average"
          region = "us-east-1"
          title  = "Auto Scaling Group - CPU Utilization (%)"
        }
      }
    ]
  })
}

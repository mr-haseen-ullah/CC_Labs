terraform {
  backend "s3" {
    bucket = "tfstate-haseen-22mdswe238"
    key    = "lab_paper/terraform.tfstate"
    region = "us-east-1"
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
  region = var.aws_region
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

# ─── VPC & Networking ──────────────────────────────────────────────────────────

resource "aws_vpc" "finalterm_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "FinalTerm-VPC-${var.student_reg_number}"
  }
}

resource "aws_subnet" "public_subnet_1" {
  vpc_id                  = aws_vpc.finalterm_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "Public-Subnet-1"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.finalterm_vpc.id

  tags = {
    Name = "FinalTerm-IGW"
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.finalterm_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "Public-Route-Table"
  }
}

resource "aws_route_table_association" "public_rta" {
  subnet_id      = aws_subnet.public_subnet_1.id
  route_table_id = aws_route_table.public_rt.id
}

# ─── Security Groups ───────────────────────────────────────────────────────────

resource "aws_security_group" "web_sg" {
  name        = "web-server-sg-${random_id.suffix.hex}"
  description = "Allow HTTP and SSH inbound traffic"
  vpc_id      = aws_vpc.finalterm_vpc.id

  ingress {
    description = "HTTP from Internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH from Internet"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "WebServer-SG"
  }
}

# ─── Key Pair ─────────────────────────────────────────────────────────────────

resource "tls_private_key" "web_server_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "web_server_keypair" {
  key_name   = "webserver-keypair-${random_id.suffix.hex}"
  public_key = tls_private_key.web_server_key.public_key_openssh

  tags = {
    Name = "WebServer-KeyPair"
  }
}

# ─── IAM Service Roles for CloudWatch Agent ───────────────────────────────────

resource "aws_iam_role" "ec2_role" {
  name = "webserver-ec2-role-${random_id.suffix.hex}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# Attachment of AWS-managed policy for CloudWatch Server Agent
resource "aws_iam_role_policy_attachment" "ec2_cw_agent" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Attachment of AWS-managed policy for Systems Manager (SSM) access
resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "webserver-ec2-profile-${random_id.suffix.hex}"
  role = aws_iam_role.ec2_role.name
}

# ─── EC2 Instance ─────────────────────────────────────────────────────────────

resource "aws_instance" "web_server" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public_subnet_1.id
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  key_name               = aws_key_pair.web_server_keypair.key_name
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  user_data = base64encode(<<-EOF
    #!/bin/bash
    # Update packages and install Apache + CloudWatch Agent
    dnf update -y
    dnf install amazon-cloudwatch-agent httpd -y

    # Enable and start Apache HTTP server
    systemctl start httpd
    systemctl enable httpd

    # Create beautifully styled landing index file with Student Information
    cat << 'HTML_EOF' > /var/www/html/index.html
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>SE-409L: Final Term Web Server</title>
        <link href="https://fonts.googleapis.com/css2?family=Outfit:wght@300;400;600;700&display=swap" rel="stylesheet">
        <style>
            :root {
                --primary: #6366f1;
                --success: #10b981;
                --background: #090d16;
                --card-bg: #111827;
                --border: #1f2937;
                --text: #f9fafb;
                --text-muted: #9ca3af;
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
                display: flex;
                justify-content: center;
                align-items: center;
                min-height: 100vh;
                padding: 2rem;
                background-image: radial-gradient(circle at 10% 20%, rgba(99, 102, 241, 0.15) 0%, transparent 40%),
                                  radial-gradient(circle at 90% 80%, rgba(16, 185, 129, 0.1) 0%, transparent 45%);
            }
            .card {
                background-color: var(--card-bg);
                border: 1px solid var(--border);
                border-radius: 20px;
                padding: 3rem;
                max-width: 600px;
                width: 100%;
                text-align: center;
                box-shadow: 0 20px 40px -15px rgba(0, 0, 0, 0.7);
                backdrop-filter: blur(10px);
            }
            .badge {
                display: inline-block;
                background-color: rgba(16, 185, 129, 0.15);
                color: var(--success);
                padding: 0.5rem 1.25rem;
                border-radius: 9999px;
                font-weight: 600;
                font-size: 0.85rem;
                margin-bottom: 1.5rem;
                border: 1px solid rgba(16, 185, 129, 0.3);
                letter-spacing: 0.05em;
                text-transform: uppercase;
            }
            h1 {
                font-size: 2.25rem;
                font-weight: 700;
                margin-bottom: 1rem;
                background: linear-gradient(to right, #818cf8, #34d399);
                -webkit-background-clip: text;
                -webkit-text-fill-color: transparent;
            }
            p {
                color: var(--text-muted);
                margin-bottom: 2rem;
                font-size: 1.05rem;
                line-height: 1.6;
            }
            .details {
                border-top: 1px solid var(--border);
                padding-top: 1.5rem;
                text-align: left;
            }
            .detail-item {
                display: flex;
                justify-content: space-between;
                margin-bottom: 0.85rem;
                font-size: 0.95rem;
                padding: 0.5rem 0;
                border-bottom: 1px solid rgba(31, 41, 55, 0.5);
            }
            .detail-item:last-child {
                border-bottom: none;
            }
            .detail-label {
                color: var(--text-muted);
                font-weight: 400;
            }
            .detail-value {
                font-weight: 600;
                color: var(--text);
            }
            .footer {
                margin-top: 2rem;
                font-size: 0.8rem;
                color: var(--text-muted);
            }
        </style>
    </head>
    <body>
        <div class="card">
            <div class="badge">● Server Active & Secure</div>
            <h1>Final Term Exam Server</h1>
            <p>Static product information web server isolated inside a custom VPC with CloudWatch performance monitoring telemetry enabled.</p>
            
            <div class="details">
                <div class="detail-item">
                    <span class="detail-label">Student Name:</span>
                    <span class="detail-value">${var.student_name}</span>
                </div>
                <div class="detail-item">
                    <span class="detail-label">Registration No:</span>
                    <span class="detail-value">${var.student_reg_number}</span>
                </div>
                <div class="detail-item">
                    <span class="detail-label">Course Code:</span>
                    <span class="detail-value">${var.course_code}</span>
                </div>
                <div class="detail-item">
                    <span class="detail-label">Virtual VPC:</span>
                    <span class="detail-value">FinalTerm-VPC-${var.student_reg_number}</span>
                </div>
                <div class="detail-item">
                    <span class="detail-label">Subnet Name:</span>
                    <span class="detail-value">Public-Subnet-1</span>
                </div>
            </div>
            <div class="footer">
                SE-409L Cloud Computing Lab &copy; 2026
            </div>
        </div>
    </body>
    </html>
    HTML_EOF

    # Generate the CloudWatch Agent config JSON file
    cat << 'OUTER_EOF' > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
    {
      "agent": {
        "metrics_collection_interval": 60,
        "run_as_user": "cwagent"
      },
      "metrics": {
        "append_dimensions": {
          "InstanceId": "$${aws:InstanceId}",
          "InstanceType": "$${aws:InstanceType}"
        },
        "metrics_collected": {
          "cpu": {
            "measurement": [
              "usage_active",
              "usage_user",
              "usage_system",
              "usage_idle"
            ],
            "metrics_collection_interval": 60,
            "totalcpu": true
          },
          "mem": {
            "measurement": [
              "mem_active",
              "mem_available",
              "mem_used",
              "mem_used_percent"
            ],
            "metrics_collection_interval": 60
          }
        }
      }
    }
    OUTER_EOF

    # Start the CloudWatch agent using the configuration file
    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s
  EOF
  )

  tags = {
    Name = "WebServer-${var.student_reg_number}"
  }
}

# ─── Object Storage Integration ───────────────────────────────────────────────

resource "aws_s3_bucket" "finalterm_bucket" {
  bucket        = "finalterm-bucket-${lower(var.student_reg_number)}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "finalterm_bucket_block" {
  bucket = aws_s3_bucket.finalterm_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Upload the confirmation text file to S3
resource "aws_s3_object" "exam_confirmation" {
  bucket  = aws_s3_bucket.finalterm_bucket.id
  key     = "exam_confirmation.txt"
  content = "Final Term Exam Upload Completed Successfully."
}

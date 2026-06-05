# **Open-Ended Lab (OEL): AWS CLI Deployment Walkthrough**

**Course**: SE-409L Cloud Computing Lab (Spring 2026)  
**Student Name**: Haseen Ullah  
**Registration Number**: 22MDSWE238  

---

This guide details the step-by-step commands to deploy the entire Open-Ended Lab (OEL) infrastructure on AWS using the **AWS CLI**. 

These commands are fully optimized to run inside **AWS CloudShell** (the browser-based terminal in the AWS Management Console) or any environment configured with credentials.

---

## **0. Environment Setup & Variables**

To make this deployment copy-pasteable and clean, we will define environment variables first. This ensures all resource configurations, VPC attachments, and naming suffixes align seamlessly.

> [!NOTE]
> Run these lines in your terminal before executing subsequent commands.

```bash
# Set your student identifier
export STUDENT_NAME="HaseenUllah"
export REG_NO="22MDSWE238"

# Unique 4-digit hexadecimal suffix to avoid bucket naming conflicts (analogous to Terraform's random_id)
export SUFFIX="e238" 

# Target Region
export AWS_DEFAULT_REGION="us-east-1"
```

---

## **1. Networking & VPC Infrastructure**

We will create a custom VPC, subnets spanning two availability zones (for ALB high-availability requirements), an Internet Gateway, and associate them with Route Tables.

### **1.1. Create the VPC**
Create a VPC with block `10.0.0.0/16` and tag it:
```bash
VPC_ID=$(aws ec2 create-vpc \
  --cidr-block 10.0.0.0/16 \
  --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=$STUDENT_NAME-$REG_NO-OEL-VPC}]" \
  --query "Vpc.VpcId" \
  --output text)

echo "VPC Created successfully: $VPC_ID"
```

Enable DNS support and DNS hostnames inside the VPC:
```bash
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-support '{"Value":true}'
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames '{"Value":true}'
```

### **1.2. Create and Attach the Internet Gateway**
```bash
IGW_ID=$(aws ec2 create-internet-gateway \
  --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=OEL-IGW}]" \
  --query "InternetGateway.InternetGatewayId" \
  --output text)

echo "Internet Gateway Created: $IGW_ID"

aws ec2 attach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID
```

### **1.3. Create Subnets**

Create two **Public Subnets** (Multi-AZ for Load Balancer distribution):
```bash
# Public Subnet 1 (AZ: us-east-1a)
SUBNET_PUB1_ID=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.1.0/24 \
  --availability-zone us-east-1a \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=OEL-Public-Subnet-1}]" \
  --query "Subnet.SubnetId" \
  --output text)

# Enable auto-assign public IPv4 on launch for this subnet
aws ec2 modify-subnet-attribute --subnet-id $SUBNET_PUB1_ID --map-public-ip-on-launch

# Public Subnet 2 (AZ: us-east-1b)
SUBNET_PUB2_ID=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.2.0/24 \
  --availability-zone us-east-1b \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=OEL-Public-Subnet-2}]" \
  --query "Subnet.SubnetId" \
  --output text)

# Enable auto-assign public IPv4 on launch for this subnet
aws ec2 modify-subnet-attribute --subnet-id $SUBNET_PUB2_ID --map-public-ip-on-launch

echo "Public Subnets created: $SUBNET_PUB1_ID, $SUBNET_PUB2_ID"
```

Create two **Private Subnets** (Multi-AZ for internal database or server architecture):
```bash
# Private Subnet 1 (AZ: us-east-1a)
SUBNET_PRIV1_ID=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.3.0/24 \
  --availability-zone us-east-1a \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=OEL-Private-Subnet-1}]" \
  --query "Subnet.SubnetId" \
  --output text)

# Private Subnet 2 (AZ: us-east-1b)
SUBNET_PRIV2_ID=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.4.0/24 \
  --availability-zone us-east-1b \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=OEL-Private-Subnet-2}]" \
  --query "Subnet.SubnetId" \
  --output text)

echo "Private Subnets created: $SUBNET_PRIV1_ID, $SUBNET_PRIV2_ID"
```

### **1.4. Configure Route Tables**

Create and configure the **Public Route Table**:
```bash
RT_PUB_ID=$(aws ec2 create-route-table \
  --vpc-id $VPC_ID \
  --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=OEL-Public-RT}]" \
  --query "RouteTable.RouteTableId" \
  --output text)

# Add default route sending traffic out of IGW
aws ec2 create-route \
  --route-table-id $RT_PUB_ID \
  --destination-cidr-block 0.0.0.0/0 \
  --gateway-id $IGW_ID

# Associate Public Subnets with the Public Route Table
aws ec2 associate-route-table --subnet-id $SUBNET_PUB1_ID --route-table-id $RT_PUB_ID
aws ec2 associate-route-table --subnet-id $SUBNET_PUB2_ID --route-table-id $RT_PUB_ID

echo "Public Route Table $RT_PUB_ID associated with public subnets."
```

Create and configure the **Private Route Table**:
```bash
RT_PRIV_ID=$(aws ec2 create-route-table \
  --vpc-id $VPC_ID \
  --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=OEL-Private-RT}]" \
  --query "RouteTable.RouteTableId" \
  --output text)

# Associate Private Subnets with the Private Route Table
aws ec2 associate-route-table --subnet-id $SUBNET_PRIV1_ID --route-table-id $RT_PRIV_ID
aws ec2 associate-route-table --subnet-id $SUBNET_PRIV2_ID --route-table-id $RT_PRIV_ID

echo "Private Route Table $RT_PRIV_ID associated with private subnets."
```

---

## **2. Least-Privilege Security Boundaries**

Create independent security groups for the Load Balancer and the backend compute EC2 instances to isolate the compute layer from direct public access.

### **2.1. Create Load Balancer Security Group**
Create the ALB Security Group:
```bash
ALB_SG_ID=$(aws ec2 create-security-group \
  --group-name "oel-alb-sg-$SUFFIX" \
  --description "Allow HTTP inbound from Internet" \
  --vpc-id $VPC_ID \
  --query "GroupId" \
  --output text)

aws ec2 create-tags --resources $ALB_SG_ID --tags Key=Name,Value=OEL-ALB-SG

# Allow Inbound HTTP on Port 80 from anywhere
aws ec2 authorize-security-group-ingress \
  --group-id $ALB_SG_ID \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0

echo "ALB Security Group created: $ALB_SG_ID"
```

### **2.2. Create EC2 Instaces Security Group (Least-Privilege)**
```bash
EC2_SG_ID=$(aws ec2 create-security-group \
  --group-name "oel-ec2-sg-$SUFFIX" \
  --description "Least Privilege Security Group: HTTP from ALB only" \
  --vpc-id $VPC_ID \
  --query "GroupId" \
  --output text)

aws ec2 create-tags --resources $EC2_SG_ID --tags Key=Name,Value=OEL-EC2-SG

# Rule 1: Allow inbound HTTP strictly from the ALB Security Group ID only
aws ec2 authorize-security-group-ingress \
  --group-id $EC2_SG_ID \
  --protocol tcp \
  --port 80 \
  --source-group $ALB_SG_ID

# Rule 2: Allow inbound SSH from internet for administrative tasks
aws ec2 authorize-security-group-ingress \
  --group-id $EC2_SG_ID \
  --protocol tcp \
  --port 22 \
  --cidr 0.0.0.0/0

echo "EC2 instances Security Group created: $EC2_SG_ID"
```

---

## **3. Cloud Object Storage (Amazon S3)**

Decouple static assets (documents, images, and resumes) by creating a public read-accessible Amazon S3 bucket.

### **3.1. Create Bucket**
```bash
BUCKET_NAME="oel-portfolio-bucket-$SUFFIX"

aws s3api create-bucket \
  --bucket $BUCKET_NAME \
  --region us-east-1

echo "Bucket $BUCKET_NAME created successfully."
```

### **3.2. Unblock Public Access Policies**
Configure the S3 public access block so that policies can grant read-only requests:
```bash
aws s3api put-public-access-block \
  --bucket $BUCKET_NAME \
  --public-access-block-configuration "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false"
```

### **3.3. Apply Bucket Policy**
Apply a read-only policy strictly to the `assets/` prefix, leaving everything else secure.

Write the policy definition JSON dynamically:
```bash
cat << EOF > policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicReadGetObject",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::$BUCKET_NAME/assets/*"
    }
  ]
}
EOF

# Apply the policy
aws s3api put-bucket-policy --bucket $BUCKET_NAME --policy file://policy.json
rm -f policy.json
```

### **3.4. Upload Assets**
Generate placeholder portfolio assets and upload them with accurate MIME metadata:
```bash
# Create dummy files
echo -e "Haseen Ullah (22MDSWE238) - Professional CV / Resume\nCourse: SE-409L Cloud Computing Lab\nEmail: haseen.ullah@student.example.com\nSkills: AWS Architecture, Terraform, Azure Administrator, DevOps, CI/CD Pipelines." > resume.pdf
echo -e "Project Documentation Summary:\n1. AI-Driven Threat Detection: Deployed real-time log anomaly detectors via SageMaker.\n2. Cloud-Native E-Commerce: Scaled dynamic catalogs using AWS EC2, ALB, and Auto Scaling.\n3. Serverless Task Orchestrator: Built microservices using Lambda, API Gateway, and DynamoDB." > project_doc.txt
echo "Haseen Ullah - Profile Image Placeholder" > avatar.jpg

# Upload to bucket
aws s3 cp resume.pdf s3://$BUCKET_NAME/assets/resume.pdf --content-type "text/plain"
aws s3 cp project_doc.txt s3://$BUCKET_NAME/assets/project_doc.txt --content-type "text/plain"
aws s3 cp avatar.jpg s3://$BUCKET_NAME/assets/avatar.jpg --content-type "image/jpeg"

# Remove local temp files
rm -f resume.pdf project_doc.txt avatar.jpg
```

---

## **4. Compute Launch Template & Core Scripting**

Prepare the EC2 Launch Template configuration that specifies the machine architecture and script execution on boot.

### **4.1. Generate Key Pair**
Generate an administrative key pair:
```bash
aws ec2 create-key-pair \
  --key-name "oel-keypair-$SUFFIX" \
  --query 'KeyMaterial' \
  --output text > oel-keypair.pem

chmod 400 oel-keypair.pem
echo "Keypair saved locally to: oel-keypair.pem"
```

### **4.2. Dynamically Select Latest Amazon Linux 2023 AMI**
```bash
AMI_ID=$(aws ec2 describe-images \
  --owners amazon \
  --filters "Name=name,Values=al2023-ami-*-x86_64" "Name=state,Values=available" \
  --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
  --output text)

echo "Selected latest AL2023 AMI ID: $AMI_ID"
```

### **4.3. Write Launch User Data (Portfolio Web Server)**
Write the script that launches on instance deployment, installs Apache, and maps the static HTML interface dynamically utilizing S3 assets:
```bash
cat << EOF > user_data.txt
#!/bin/bash
dnf update -y
dnf install httpd -y
systemctl start httpd
systemctl enable httpd

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
            transform: translateY(-5px);
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
                <a href="https://$BUCKET_NAME.s3.amazonaws.com/assets/resume.pdf" class="btn" target="_blank">Download Resume (S3 URL)</a>
                <a href="https://$BUCKET_NAME.s3.amazonaws.com/assets/project_doc.txt" class="btn btn-secondary" target="_blank">View Project Documentation</a>
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
```

### **4.4. Create Launch Template**
Base64-encode the user data script and formulate the template description JSON structure to launch:
```bash
# Base64 encode user data
USER_DATA_B64=$(base64 -w 0 user_data.txt)

# Construct JSON payload file
cat << EOF > launch_template_data.json
{
  "ImageId": "$AMI_ID",
  "InstanceType": "t3.micro",
  "KeyName": "oel-keypair-$SUFFIX",
  "NetworkInterfaces": [
    {
      "DeviceIndex": 0,
      "AssociatePublicIpAddress": true,
      "Groups": ["$EC2_SG_ID"]
    }
  ],
  "UserData": "$USER_DATA_B64"
}
EOF

# Execute launch template creation
aws ec2 create-launch-template \
  --launch-template-name "oel-portfolio-lt-$SUFFIX" \
  --launch-template-data file://launch_template_data.json

# Clean up configuration scripts
rm -f user_data.txt launch_template_data.json
```

---

## **5. Ingress & Load Balancing (ALB)**

Deploy the ALB and target group configurations to route internet traffic dynamically.

### **5.1. Create Target Group**
Create the HTTP target group targeting VPC subnets:
```bash
TG_ARN=$(aws elbv2 create-target-group \
  --name "oel-portfolio-tg-$SUFFIX" \
  --protocol HTTP \
  --port 80 \
  --vpc-id $VPC_ID \
  --health-check-path "/" \
  --health-check-interval-seconds 30 \
  --health-check-timeout-seconds 5 \
  --healthy-threshold-count 3 \
  --unhealthy-threshold-count 3 \
  --query 'TargetGroups[0].TargetGroupArn' \
  --output text)

echo "Target Group Configured: $TG_ARN"
```

### **5.2. Create Load Balancer**
Create the Application Load Balancer distributed across public subnets:
```bash
ALB_ARN=$(aws elbv2 create-load-balancer \
  --name "oel-portfolio-alb-$SUFFIX" \
  --subnets $SUBNET_PUB1_ID $SUBNET_PUB2_ID \
  --security-groups $ALB_SG_ID \
  --query 'LoadBalancers[0].LoadBalancerArn' \
  --output text)

ALB_DNS=$(aws elbv2 describe-load-balancers \
  --load-balancer-arns $ALB_ARN \
  --query 'LoadBalancers[0].DNSName' \
  --output text)

echo "ALB Created successfully!"
echo "Public Site Endpoint: http://$ALB_DNS"
```

### **5.3. Associate Ingress Listener**
Add listener mapping port 80 to route traffic directly to the target group:
```bash
aws elbv2 create-listener \
  --load-balancer-arn $ALB_ARN \
  --protocol HTTP \
  --port 80 \
  --default-actions Type=forward,TargetGroupArn=$TG_ARN
```

---

## **6. Auto Scaling Configuration (ASG)**

Create the Auto Scaling Group. This maintains instance redundancy (desired capacity = 2, min = 1, max = 2) distributed across Availability Zones.

```bash
aws autoscaling create-auto-scaling-group \
  --auto-scaling-group-name "oel-portfolio-asg-$SUFFIX" \
  --launch-template LaunchTemplateName="oel-portfolio-lt-$SUFFIX",Version='$Latest' \
  --min-size 1 \
  --max-size 2 \
  --desired-capacity 2 \
  --vpc-zone-identifier "$SUBNET_PUB1_ID,$SUBNET_PUB2_ID" \
  --target-group-arns "$TG_ARN" \
  --tags Key=Name,Value=OEL-Portfolio-ASG-Instance,PropagateAtLaunch=true

echo "Auto Scaling Group configured and booting instances."
```

---

## **7. Observability & Monitoring (CloudWatch)**

Build threshold alerts and a centralized instrumentation dashboard.

### **7.1. Create CPU Performance Metric Alarm**
Define an alarm that transitions to `ALARM` when average CPU Utilization is equal to or greater than 80% for two consecutive 60-second evaluations:
```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "oel-asg-cpu-high-alarm-$SUFFIX" \
  --comparison-operator GreaterThanOrEqualToThreshold \
  --evaluation-periods 2 \
  --metric-name CPUUtilization \
  --namespace AWS/EC2 \
  --period 60 \
  --statistic Average \
  --threshold 80 \
  --alarm-description "Monitor ASG CPU and trigger when average exceeds 80%" \
  --dimensions Name=AutoScalingGroupName,Value="oel-portfolio-asg-$SUFFIX"

echo "CloudWatch Performance Alarm registered."
```

### **7.2. Deploy Custom Operations Dashboard**
Deploy a metric widget displaying target instances CPU Utilization:
```bash
# Formulate dashboard representation structure
cat << EOF > dashboard.json
{
  "widgets": [
    {
      "type": "metric",
      "x": 0,
      "y": 0,
      "width": 12,
      "height": 6,
      "properties": {
        "metrics": [
          ["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", "oel-portfolio-asg-$SUFFIX"]
        ],
        "period": 60,
        "stat": "Average",
        "region": "us-east-1",
        "title": "Auto Scaling Group - CPU Utilization (%)"
      }
    }
  ]
}
EOF

# Create Dashboard
aws cloudwatch put-dashboard \
  --dashboard-name "OEL-Dashboard-$SUFFIX" \
  --dashboard-body file://dashboard.json

rm -f dashboard.json
echo "Custom Instrumentation Dashboard created successfully."
```

---

## **8. Verification Steps**

After deploying, verify health status and operation:

1. **Verify ALB Target Group Registration**:
   Ensure EC2 instances are marked `healthy`:
   ```bash
   aws elbv2 describe-target-health --target-group-arn $TG_ARN --query 'TargetHealthDescriptions[*].{InstanceID:Target.Id,State:TargetHealth.State}'
   ```
2. **Access Web Application**:
   Print the Load Balancer DNS name:
   ```bash
   echo "Go to: http://$ALB_DNS"
   ```
   Open this URL in a web browser.
3. **Verify S3 Decoupled Assets**:
   Verify you can download the uploaded assets via the browser or verify with `curl`:
   ```bash
   curl -I "https://$BUCKET_NAME.s3.amazonaws.com/assets/resume.pdf"
   ```

---

## **9. Cleanup & Teardown Guide**

> [!WARNING]
> Resources left running in AWS can incur costs. Clean up the entire configuration by running the commands below in the exact order specified.

```bash
# 9.1. Delete CloudWatch Alarm & Dashboard
aws cloudwatch delete-alarms --alarm-names "oel-asg-cpu-high-alarm-$SUFFIX"
aws cloudwatch delete-dashboards --dashboard-names "OEL-Dashboard-$SUFFIX"

# 9.2. Delete Auto Scaling Group (Force termination of active instances)
aws autoscaling delete-auto-scaling-group --auto-scaling-group-name "oel-portfolio-asg-$SUFFIX" --force-delete

# 9.3. Wait for ASG EC2 instances to terminate completely before continuing
echo "Waiting for ASG instances to terminate..."
aws ec2 wait instance-terminated --filters "Name=tag:Name,Values=OEL-Portfolio-ASG-Instance"

# 9.4. Delete Launch Template
aws ec2 delete-launch-template --launch-template-name "oel-portfolio-lt-$SUFFIX"

# 9.5. Delete Key Pair
aws ec2 delete-key-pair --key-name "oel-keypair-$SUFFIX"
rm -f oel-keypair.pem

# 9.6. Delete Load Balancer
aws elbv2 delete-load-balancer --load-balancer-arn $ALB_ARN
echo "Waiting for Load Balancer to delete..."
aws elbv2 wait load-balancers-deleted --load-balancer-arns $ALB_ARN

# 9.7. Delete Target Group
aws elbv2 delete-target-group --target-group-arn $TG_ARN

# 9.8. Delete S3 Bucket and uploaded contents
aws s3 rm s3://$BUCKET_NAME --recursive
aws s3api delete-bucket --bucket $BUCKET_NAME

# 9.9. Delete Security Groups
aws ec2 delete-security-group --group-id $EC2_SG_ID
aws ec2 delete-security-group --group-id $ALB_SG_ID

# 9.10. Delete Route Tables & Associations
# Disassociate Route Tables
PUB_ASSOCS=$(aws ec2 describe-route-tables --route-table-ids $RT_PUB_ID --query 'RouteTables[0].Associations[*].RouteTableAssociationId' --output text)
for assoc in $PUB_ASSOCS; do aws ec2 disassociate-route-table --association-id $assoc; done

PRIV_ASSOCS=$(aws ec2 describe-route-tables --route-table-ids $RT_PRIV_ID --query 'RouteTables[0].Associations[*].RouteTableAssociationId' --output text)
for assoc in $PRIV_ASSOCS; do aws ec2 disassociate-route-table --association-id $assoc; done

# Delete Route Tables
aws ec2 delete-route-table --route-table-id $RT_PUB_ID
aws ec2 delete-route-table --route-table-id $RT_PRIV_ID

# 9.11. Delete Subnets
aws ec2 delete-subnet --subnet-id $SUBNET_PUB1_ID
aws ec2 delete-subnet --subnet-id $SUBNET_PUB2_ID
aws ec2 delete-subnet --subnet-id $SUBNET_PRIV1_ID
aws ec2 delete-subnet --subnet-id $SUBNET_PRIV2_ID

# 9.12. Detach and delete Internet Gateway
aws ec2 detach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID
aws ec2 delete-internet-gateway --internet-gateway-id $IGW_ID

# 9.13. Delete VPC
aws ec2 delete-vpc --vpc-id $VPC_ID

echo "All OEL resources have been successfully torn down!"
```

**SE-409L: Cloud Computing Lab**

**Final Term Practical Examination (Spring 2026)** **Total Marks:** 25

**Duration:** 45 Minutes

**Environment:** AWS Free Tier

\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_

**[Problem Scenario]{.underline}**

A small startup wants to deploy a highly secure, static product
information web server on AWS. The application must be isolated inside a
custom network environment, store product documentation assets reliably,
and be monitored for anomalies. You are required to implement a minimal,
cost-efficient proof-of-concept architecture within the AWS Free Tier
limitations.

**[Task Breakdown]{.underline}**

**Part 1: Network & Security Infrastructure (8 Marks)**

CLO-1 (P-3, PLO-5), CLO-4 (C-3, PLO-1)

> **Instructions:**

1.  Create a Custom VPC named FinalTerm-VPC-\[YourRollNumber\] with an
    IPv4 CIDR block of 10.0.0.0/16.

2.  Subnet Creation: Create one **Public Subnet** named Public-Subnet-1
    with CIDR 10.0.1.0/24 inside your VPC.

3.  Internet Connectivity: Create an **Internet Gateway (IGW)**, attach
    it to your custom VPC, and modify the Public Route Table to forward
    all outbound traffic (0.0.0.0/0) through the IGW.

4.  Security Firewalls: Define an EC2 Security Group that permits **HTTP
    (Port 80)** traffic from anywhere (0.0.0.0/0) and restricted **SSH
    (Port 22)** traffic exclusively for remote server management.

**Part 2: Compute Deployment & Web Hosting (8 Marks)**

CLO-1 (P-3, PLO-5), CLO-5 (P-3, PLO-5)

> **Instructions:**

1.  Virtual Server Provisioning: Launch a single **t2.micro** EC2 Linux
    instance named WebServer-\[YourRollNumber\] inside the newly created
    Public-Subnet-1. Associate your pre-configured Security Group and
    enable the allocation of an Auto-assign Public IP.

2.  Web Server Configuration: Establish an SSH connection to the virtual
    instance using an appropriate client (e.g., PuTTY or native
    Terminal).

3.  Deploy a lightweight Apache (httpd) web server instance. Configure
    the default application landing index file
    (/var/www/html/index.html) to dynamically output your **Student
    Name**, **Registration/Roll Number**, and the specific **Course Code
    (SE-409L)**. Ensure the service is up and active.

**Part 3: Object Cloud Storage Integration (5 Marks)**

CLO-1 (P-3, PLO-5), CLO-5 (P-3, PLO-5)

> **Instructions:**

1.  Object Vault Creation: Provision an **Amazon S3 Bucket** with a
    globally unique name format structured as
    finalterm-bucket-\[yourrollnumber\] deployed in the same AWS Region.

2.  Asset Ingestion: Create a blank text file on your local machine
    named exam_confirmation.txt containing the phrase: *\"Final Term
    Exam Upload Completed Successfully.\"* Upload this artifact manually
    to the root folder of your S3 Bucket.

**Part 4: Infrastructure CWAgent CloudWatch Monitoring (4 Marks)**

CLO-4 (C-3, PLO-1), CLO-5 (P-3, PLO-5)

> **Instructions:**

1.  Metric Telemetry: Navigate directly to the **Amazon CloudWatch**
    environment dashboard terminal console.

2.  Performance Monitoring Setup: Select your active web application
    host EC2 instance from the primary telemetry view. Locate the native
    basic monitoring graph configurations and render a visual timeline
    showing real-time **CPU Utilization (%)** tracking data.

**[Deliverables (Submission Guidelines)]{.underline}**

Compile a verification document (PDF/Word format) matching the format
followed in your lab tasks reports. The document must include the
following unedited interface evidence captures along with brief
description:

1.  **VPC Architecture Verification:** Screenshot highlighting the
    custom named VPC dashboard view with its corresponding subnet
    allocation and Internet Gateway routing configuration visible.

2.  **Web Content Reachability:** A browser window capture displaying
    the public IP address in the address bar, rendering your **Full Name
    and Roll Number** successfully hosted over HTTP.

3.  **Storage Pipeline Confirmation:** A console capture displaying the
    S3 bucket dashboard containing the explicitly named file object
    exam_confirmation.txt.

4.  **CloudWatch Telemetry:** A final screenshot displaying the active
    CloudWatch graph mapping operational metrics for your EC2 deployment
    instance.

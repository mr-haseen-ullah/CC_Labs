# **Open-Ended Lab (OEL): Azure CLI Deployment Walkthrough**

**Course**: SE-409L Cloud Computing Lab (Spring 2026)  
**Student Name**: Student  
**Registration Number**: STUDENT-ID  

---

This guide details the step-by-step commands to deploy the entire Open-Ended Lab (OEL) infrastructure on Azure using the **Azure CLI**. 

These commands are fully optimized to run inside **Azure CloudShell** (the browser-based terminal in the Azure Portal) or any environment configured with Azure CLI.

---

## **0. Environment Setup & Variables**

To make this deployment copy-pasteable and clean, we will define environment variables first. This ensures all resource configurations, VNet settings, and naming suffixes align seamlessly.

> [!NOTE]
> Run these lines in your terminal before executing subsequent commands.

```bash
# Set your student identifier
export STUDENT_NAME="Student"
export REG_NO="STUDENT-ID"

# Unique 4-digit hexadecimal suffix to avoid naming conflicts (analogous to Terraform's random_id)
export SUFFIX="e238" 

# Target Region
export LOCATION="eastus"

# Target Resource Group
export RG_NAME="OEL-Portfolio-RG-$SUFFIX"
```

---

## **1. Resource Group & Networking Infrastructure**

We will create a Resource Group to isolate all resources, a Virtual Network (VNet) with a single subnet, and a Standard Public IP for our Load Balancer.

### **1.1. Create the Resource Group**
Create the Resource Group to contain all OEL infrastructure:
```bash
az group create \
  --name $RG_NAME \
  --location $LOCATION

echo "Resource Group Created successfully: $RG_NAME"
```

### **1.2. Create the Virtual Network and Subnet**
Create a VNet with address block `10.0.0.0/16` and a subnet with block `10.0.1.0/24`:
```bash
az network vnet create \
  --resource-group $RG_NAME \
  --name "$STUDENT_NAME-$REG_NO-OEL-VNet" \
  --location $LOCATION \
  --address-prefixes 10.0.0.0/16 \
  --subnet-name "OEL-Subnet" \
  --subnet-prefixes 10.0.1.0/24

echo "VNet and Subnet created successfully."
```

### **1.3. Create the Public IP**
Create a standard, static public IP address for the Load Balancer:
```bash
az network public-ip create \
  --resource-group $RG_NAME \
  --name "OEL-PIP" \
  --location $LOCATION \
  --allocation-method Static \
  --sku Standard

echo "Public IP Address OEL-PIP created successfully."
```

---

## **2. Network Security Groups & Rules (Security Boundaries)**

Create a Network Security Group (NSG) and add least-privilege security rules to protect your Virtual Machine instances from unauthorized public access while allowing HTTP traffic on Port 80 and administrative SSH traffic on Port 22.

### **2.1. Create Network Security Group (NSG)**
Create the security group:
```bash
az network nsg create \
  --resource-group $RG_NAME \
  --name "OEL-NSG" \
  --location $LOCATION

echo "Network Security Group OEL-NSG created."
```

### **2.2. Add Rules to the NSG**
Configure the rules for HTTP and SSH:
```bash
# Rule 1: Allow Inbound HTTP on Port 80 from the Internet
az network nsg rule create \
  --resource-group $RG_NAME \
  --nsg-name "OEL-NSG" \
  --name "AllowHTTP" \
  --priority 100 \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --source-port-ranges "*" \
  --destination-port-ranges 80 \
  --source-address-prefixes Internet \
  --destination-address-prefixes "*"

# Rule 2: Allow Inbound SSH on Port 22 from the Internet for administrative tasks
az network nsg rule create \
  --resource-group $RG_NAME \
  --nsg-name "OEL-NSG" \
  --name "AllowSSH" \
  --priority 110 \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --source-port-ranges "*" \
  --destination-port-ranges 22 \
  --source-address-prefixes Internet \
  --destination-address-prefixes "*"

echo "Security rules applied to OEL-NSG successfully."
```

### **2.3. Associate NSG with Subnet**
Apply the security boundaries directly to the VNet Subnet:
```bash
az network vnet subnet update \
  --resource-group $RG_NAME \
  --vnet-name "$STUDENT_NAME-$REG_NO-OEL-VNet" \
  --name "OEL-Subnet" \
  --network-security-group "OEL-NSG"

echo "OEL-NSG associated with OEL-Subnet successfully."
```

---

## **3. Cloud Object Storage (Azure Blob Storage)**

Decouple static assets (documents, images, and resumes) by creating a public-read-accessible Azure Blob Storage Container inside a Storage Account.

### **3.1. Create Storage Account**
Create the storage account (name must be 3-24 characters, lowercase alphanumeric only):
```bash
export STORAGE_ACCOUNT_NAME="oelportfolio$SUFFIX"

az storage account create \
  --resource-group $RG_NAME \
  --name $STORAGE_ACCOUNT_NAME \
  --location $LOCATION \
  --sku Standard_LRS \
  --kind StorageV2 \
  --allow-blob-public-access true

echo "Storage Account $STORAGE_ACCOUNT_NAME created."
```

### **3.2. Retrieve Connection String**
Retrieve the primary connection string to facilitate container creation and blob uploads:
```bash
export AZURE_STORAGE_CONNECTION_STRING=$(az storage account show-connection-string \
  --resource-group $RG_NAME \
  --name $STORAGE_ACCOUNT_NAME \
  --query connectionString \
  --output tsv)
```

### **3.3. Create Container with Public Blob Access**
Create the container `assets` and set its access type to `blob` so that uploaded files are publicly reachable via direct URL:
```bash
az storage container create \
  --name assets \
  --public-access blob \
  --connection-string $AZURE_STORAGE_CONNECTION_STRING

echo "Container 'assets' created with public blob access."
```

### **3.4. Upload Portfolio Assets**
Generate placeholder portfolio assets and upload them to the container:
```bash
# Create dummy files
echo -e "Student (STUDENT-ID) - Professional CV / Resume\nCourse: SE-409L Cloud Computing Lab\nEmail: student@student.example.com\nSkills: Azure Administration, Terraform, AWS DevOps, CI/CD, Linux Systems." > resume.pdf
echo -e "Project Documentation Summary:\n1. AI-Driven Threat Detection: Deployed real-time log anomaly detectors via SageMaker.\n2. Cloud-Native E-Commerce: Scaled dynamic catalogs using AWS EC2, ALB, and Auto Scaling.\n3. Serverless Task Orchestrator: Built microservices using Lambda, API Gateway, and DynamoDB." > project_doc.txt

# Upload to storage account container
az storage blob upload \
  --container-name assets \
  --file resume.pdf \
  --name resume.pdf \
  --content-type "text/plain" \
  --connection-string $AZURE_STORAGE_CONNECTION_STRING

az storage blob upload \
  --container-name assets \
  --file project_doc.txt \
  --name project_doc.txt \
  --content-type "text/plain" \
  --connection-string $AZURE_STORAGE_CONNECTION_STRING

# Remove local temp files
rm -f resume.pdf project_doc.txt
echo "Assets uploaded successfully."
```

---

## **4. SSH Key Generation & Compute Custom Data**

Prepare the Virtual Machine Scale Set (VMSS) configurations, generate keys for SSH access, and define the startup shell script.

### **4.1. Generate Key Pair**
Generate a local SSH key pair:
```bash
ssh-keygen -t rsa -b 4096 -f oel-keypair -N ""
chmod 400 oel-keypair
echo "Keypair oel-keypair and oel-keypair.pub generated."
```

### **4.2. Write Startup Script (Apache Web Server + Styled Portfolio)**
Write the script that launches on instance deployment, installs Apache, and maps the static HTML interface dynamically utilizing Azure Storage blobs:
```bash
cat << EOF > user_data.txt
#!/bin/bash
# Install Apache
apt-get update -y
apt-get install apache2 -y
systemctl start apache2
systemctl enable apache2

# Create portfolio index page
cat << 'HTML_EOF' > /var/www/html/index.html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Student - Cloud Portfolio</title>
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
        <h1>Student</h1>
        <p class="student-info">Reg No: <strong>STUDENT-ID</strong></p>
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
            <p style="color: var(--text-muted); margin-bottom: 1.5rem;">The following links dynamically fetch verified curriculum artifacts hosted securely on our public Azure Blob storage account container:</p>
            <div class="btn-group">
                <a href="https://$STORAGE_ACCOUNT_NAME.blob.core.windows.net/assets/resume.pdf" class="btn" target="_blank">Download Resume (Azure Blob URL)</a>
                <a href="https://$STORAGE_ACCOUNT_NAME.blob.core.windows.net/assets/project_doc.txt" class="btn btn-secondary" target="_blank">View Project Documentation</a>
            </div>
        </section>
    </div>

    <footer>
        <p>&copy; 2026 Student (STUDENT-ID). Powered by Azure VMSS & Blob Storage.</p>
    </footer>
</body>
</html>
HTML_EOF
EOF
```

---

## **5. Azure Load Balancer Configuration**

Deploy a Public Standard Load Balancer with Backend Address Pools, Health Probes, and Load Balancing Rules to distribute port 80 traffic.

### **5.1. Create Load Balancer**
Create the Azure Load Balancer associated with the public IP address:
```bash
az network lb create \
  --resource-group $RG_NAME \
  --name "OEL-LB" \
  --location $LOCATION \
  --sku Standard \
  --frontend-ip-name "PublicIPAddress" \
  --public-ip-address "OEL-PIP" \
  --backend-pool-name "OEL-BackEndAddressPool"

echo "Load Balancer OEL-LB created successfully."
```

### **5.2. Create Health Probe**
Add a health probe configured to monitor the root path `/` on Port 80:
```bash
az network lb probe create \
  --resource-group $RG_NAME \
  --lb-name "OEL-LB" \
  --name "http-running-probe" \
  --protocol Http \
  --port 80 \
  --path "/"

echo "Health probe configured successfully."
```

### **5.3. Create Load Balancing Rule**
Create the Rule distributing inbound HTTP requests on Port 80 to the backend VM instances:
```bash
az network lb rule create \
  --resource-group $RG_NAME \
  --lb-name "OEL-LB" \
  --name "LBRule" \
  --protocol Tcp \
  --frontend-port 80 \
  --backend-port 80 \
  --frontend-ip-name "PublicIPAddress" \
  --backend-pools-name "OEL-BackEndAddressPool" \
  --probe-name "http-running-probe"

echo "Load balancing rule LBRule associated."
```

---

## **6. Virtual Machine Scale Set (VMSS) Configuration**

Deploy the VMSS to automatically manage and dynamically scale 2 VM instances across your VNet Subnet, associating them with the Load Balancer and utilizing your startup custom data.

```bash
az vmss create \
  --resource-group $RG_NAME \
  --name "OEL-VMSS" \
  --image "Canonical:0001-com-ubuntu-server-jammy:22_04-lts:latest" \
  --vm-sku "Standard_D2s_v3" \
  --instance-count 2 \
  --admin-username "azureuser" \
  --ssh-key-value oel-keypair.pub \
  --vnet-name "$STUDENT_NAME-$REG_NO-OEL-VNet" \
  --subnet "OEL-Subnet" \
  --lb "OEL-LB" \
  --backend-pool-name "OEL-BackEndAddressPool" \
  --custom-data user_data.txt \
  --upgrade-policy-mode Automatic

# Clean up local configuration script
rm -f user_data.txt
echo "Virtual Machine Scale Set successfully deployed and configured."
```

---

## **7. Observability & Monitoring (Azure Monitor)**

Configure telemetry, logs collection, and a threshold metric alert to notify when instances exceed performance boundaries.

### **7.1. Create Log Analytics Workspace**
Create the Log Analytics Workspace for storing application logs and system resource telemetry:
```bash
az monitor log-analytics workspace create \
  --resource-group $RG_NAME \
  --workspace-name "oel-workspace-$SUFFIX" \
  --location $LOCATION

echo "Log Analytics Workspace created: oel-workspace-$SUFFIX"
```

### **7.2. Create VMSS CPU Performance Metric Alert**
Get the VMSS resource identifier and create a metric alert that triggers if average CPU usage exceeds 80%:
```bash
# Get the VMSS resource ID
VMSS_ID=$(az vmss show \
  --name "OEL-VMSS" \
  --resource-group $RG_NAME \
  --query id \
  --output tsv)

# Create the metric alert
az monitor metric-alert create \
  --name "oel-vmss-cpu-high-alert" \
  --resource-group $RG_NAME \
  --scopes $VMSS_ID \
  --condition "avg Percentage CPU > 80" \
  --description "This alert monitors VMSS average CPU usage and triggers when average CPU exceeds 80%" \
  --evaluation-frequency 1m \
  --window-size 5m \
  --severity 3

echo "Azure Monitor CPU Performance Alert registered successfully."
```

---

## **8. Verification Steps**

After deploying, verify the health status and operation of the services:

1. **Verify VMSS Instance States**:
   Ensure all scaling nodes are active and provisioning has completed:
   ```bash
   az vmss list-instances \
     --name "OEL-VMSS" \
     --resource-group $RG_NAME \
     --query "[].{InstanceId:instanceId,ProvisioningState:provisioningState,PowerState:powerState}" \
     --output table
   ```
2. **Access Web Application**:
   Retrieve the Public IP address of the Load Balancer:
   ```bash
   LB_IP=$(az network public-ip show \
     --name "OEL-PIP" \
     --resource-group $RG_NAME \
     --query ipAddress \
     --output tsv)
   
   echo "Public Portfolio Website Endpoint: http://$LB_IP"
   ```
   Copy the output IP and open it in a web browser.
3. **Verify Storage Account Decoupled Assets**:
   Confirm that the CV resume file can be accessed publicly via HTTP:
   ```bash
   curl -I "https://$STORAGE_ACCOUNT_NAME.blob.core.windows.net/assets/resume.pdf"
   ```

---

## **9. Cleanup & Teardown Guide**

> [!WARNING]
> Resources left running in Azure will incur costs if they fall outside the free tier. Clean up the configuration by running the commands below.

### **Option A: Delete the Entire Resource Group (Recommended & Easiest)**
Since all OEL resources reside within the same Resource Group, deleting the group will automatically cascade and destroy all nested resources (VMSS, Load Balancer, VNet, Public IP, Storage Account, and Workspace) in a single action:
```bash
az group delete --name $RG_NAME --yes --no-wait
rm -f oel-keypair oel-keypair.pub
echo "Resource Group $RG_NAME deletion initiated."
```

### **Option B: Step-by-Step Granular Teardown**
If you wish to remove resources individually in a specific order:
```bash
# 9.1. Delete Monitor Alert
az monitor metric-alert delete --name "oel-vmss-cpu-high-alert" --resource-group $RG_NAME

# 9.2. Delete Log Analytics Workspace
az monitor log-analytics workspace delete --workspace-name "oel-workspace-$SUFFIX" --resource-group $RG_NAME --yes

# 9.3. Delete Virtual Machine Scale Set
az vmss delete --name "OEL-VMSS" --resource-group $RG_NAME

# 9.4. Clean up Load Balancer Rules & Probes
az network lb rule delete --name "LBRule" --lb-name "OEL-LB" --resource-group $RG_NAME
az network lb probe delete --name "http-running-probe" --lb-name "OEL-LB" --resource-group $RG_NAME
az network lb delete --name "OEL-LB" --resource-group $RG_NAME

# 9.5. Delete Public IP
az network public-ip delete --name "OEL-PIP" --resource-group $RG_NAME

# 9.6. Disassociate and delete NSG and Network VNet
az network vnet subnet update \
  --resource-group $RG_NAME \
  --vnet-name "$STUDENT_NAME-$REG_NO-OEL-VNet" \
  --name "OEL-Subnet" \
  --network-security-group null

az network nsg delete --name "OEL-NSG" --resource-group $RG_NAME
az network vnet delete --name "$STUDENT_NAME-$REG_NO-OEL-VNet" --resource-group $RG_NAME

# 9.7. Delete Storage Account
az storage account delete --name $STORAGE_ACCOUNT_NAME --resource-group $RG_NAME --yes

# 9.8. Delete Local Keypair Files
rm -f oel-keypair oel-keypair.pub

# 9.9. Delete Resource Group
az group delete --name $RG_NAME --yes --no-wait
echo "All Azure OEL resources have been successfully torn down!"
```

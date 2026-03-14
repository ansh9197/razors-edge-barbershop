# 💈 The Razor's Edge — Barbershop Booking System

A complete full-stack barbershop booking app with WhatsApp notifications, OTP login, UPI payments — deployed on **AWS EC2** using **Terraform**, **Docker Compose**, **Jenkins CI/CD**, and monitored with **Prometheus + Grafana**.

---

## 📁 Project Structure

```
razors-edge/
├── app/
│   ├── public/
│   │   ├── login.html        ← OTP Login Page
│   │   └── index.html        ← Booking Form (light theme)
│   ├── server.js             ← Node.js API + Prometheus metrics
│   ├── package.json
│   └── Dockerfile
├── terraform/
│   ├── ec2.tf                ← EC2 instance + Security Group + IAM
│   ├── s3.tf                 ← S3 bucket for booking storage
│   ├── dynamodb.tf           ← DynamoDB appointments table
│   └── variables.tf          ← All configurable variables
├── docker-compose.yml        ← App + Prometheus + Grafana + Node Exporter
├── jenkins/
│   └── Jenkinsfile           ← CI/CD pipeline
├── monitoring/
│   ├── prometheus/
│   │   └── prometheus.yml    ← Scrape config
│   └── grafana/
│       └── provisioning/
│           └── datasources/
│               └── prometheus.yml
├── .env.example              ← Environment variable template
├── .gitignore
└── README.md
```

---

## ✅ PHASE 1 — Test Locally (No Cloud Needed) — 5 Minutes

### Step 1: Change Your WhatsApp Number
Open `app/public/index.html`, find and update:
```js
const BARBER_WHATSAPP = '91XXXXXXXXXX';
// Replace with your number e.g. 919876543210
```

### Step 2: Open in Browser
- Double-click `app/public/login.html` → opens in Chrome
- Enter any 10-digit number → get OTP → enter it → booking form opens
- Book an appointment → WhatsApp opens with full details ✅

---

## ☁️ PHASE 2 — Deploy on AWS EC2

### Prerequisites — Install These Tools

| Tool | Download Link | Verify |
|------|--------------|--------|
| Git | git-scm.com | `git --version` |
| Terraform | terraform.io/downloads | `terraform --version` |
| AWS CLI | aws.amazon.com/cli | `aws --version` |
| Docker Desktop | docker.com | `docker --version` |

---

### STEP 1 — Create AWS Account
1. Go to **aws.amazon.com** → Create Account
2. Enter email, password, credit card (Mumbai region is cheapest for India)
3. Choose **Basic Support** (free)

---

### STEP 2 — Create IAM User
1. Login to AWS Console → Search **IAM** → Click **Users**
2. Click **Create User** → Username: `razors-edge-admin`
3. Click **Attach policies directly** → Select **AdministratorAccess**
4. Click **Create User** → Click the user → **Security credentials**
5. Click **Create access key** → Choose **CLI** → Download CSV
6. **Save the Access Key ID and Secret Access Key from the CSV**

---

### STEP 3 — Configure AWS CLI
Open Terminal / Command Prompt:
```bash
aws configure
```
Enter:
```
AWS Access Key ID: (paste from CSV)
AWS Secret Access Key: (paste from CSV)
Default region name: ap-south-1
Default output format: json
```

---

### STEP 4 — Generate SSH Key (to connect to EC2)
```bash
# Windows (PowerShell) / Mac / Linux:
ssh-keygen -t rsa -b 4096 -f ~/.ssh/razors-edge-key
```
Press Enter twice (no passphrase). This creates:
- `~/.ssh/razors-edge-key` (private — keep secret!)
- `~/.ssh/razors-edge-key.pub` (public — used by Terraform)

Update `terraform/variables.tf`:
```hcl
variable "public_key_path" {
  default = "~/.ssh/razors-edge-key.pub"
}
```

---

### STEP 5 — Push Project to GitHub

#### Create GitHub Repository
1. Go to **github.com** → Sign in (or create account)
2. Click **+** → **New repository**
3. Name: `razors-edge-barbershop`
4. Select **Private** → Click **Create repository**

#### Push Code
Open Terminal in your project folder:
```bash
git init
git add .
git commit -m "Initial commit: Razor's Edge Barbershop"
git branch -M main
git remote add origin https://github.com/YOUR_USERNAME/razors-edge-barbershop.git
git push -u origin main
```

Update `terraform/variables.tf` with your GitHub username:
```hcl
variable "github_username" { default = "YOUR_GITHUB_USERNAME" }
variable "github_repo"     { default = "razors-edge-barbershop" }
```

---

### STEP 6 — Deploy AWS Infrastructure with Terraform

```bash
cd terraform/
```

**First time only — create the state bucket manually:**
```bash
aws s3 mb s3://razors-edge-tf-state --region ap-south-1
```

**Initialize Terraform:**
```bash
terraform init
```

**Preview what will be created:**
```bash
terraform plan
```
You'll see: EC2 instance, Security Group, S3 buckets, DynamoDB tables, IAM roles.

**Deploy everything:**
```bash
terraform apply
```
Type `yes` when asked. Wait ~3 minutes.

When done, you'll see:
```
ec2_public_ip   = "13.xxx.xxx.xxx"
app_url         = "http://13.xxx.xxx.xxx:3000"
grafana_url     = "http://13.xxx.xxx.xxx:3001"
prometheus_url  = "http://13.xxx.xxx.xxx:9090"
s3_bucket_name  = "razors-edge-bookings-prod"
dynamodb_table  = "razors-edge-appointments"
```
**Copy and save the EC2 IP address.**

---

### STEP 7 — Configure Environment Variables on EC2

SSH into your server:
```bash
ssh -i ~/.ssh/razors-edge-key ubuntu@YOUR_EC2_IP
```

Create the .env file:
```bash
cd /home/ubuntu/app
cp .env.example .env
nano .env
```

Fill in your AWS credentials (or leave blank — EC2 IAM role handles it automatically):
```
AWS_REGION=ap-south-1
S3_BUCKET=razors-edge-bookings-prod
DYNAMO_TABLE=razors-edge-appointments
```
Press `Ctrl+X` → `Y` → Enter to save.

---

### STEP 8 — Start the App with Docker Compose

While still SSH'd into EC2:
```bash
cd /home/ubuntu/app
docker-compose up -d --build
```

Check everything is running:
```bash
docker-compose ps
```
You should see all 4 containers: `app`, `prometheus`, `grafana`, `node-exporter` — all `Up`.

---

### STEP 9 — Test Your Live App

Open in browser:
```
http://YOUR_EC2_IP:3000        ← Booking app
http://YOUR_EC2_IP:3001        ← Grafana (admin / razors@123)
http://YOUR_EC2_IP:9090        ← Prometheus
```

---

## 📊 PHASE 3 — Set Up Grafana Monitoring Dashboard

### Step 1: Login to Grafana
- Go to `http://YOUR_EC2_IP:3001`
- Username: `admin` | Password: `razors@123`

### Step 2: Create Dashboard
1. Click **+** → **New Dashboard** → **Add visualization**
2. Select **Prometheus** as data source
3. Add these panels:

| Panel | Query |
|-------|-------|
| Total Bookings | `bookings_total` |
| Request Rate | `rate(http_requests_total[5m])` |
| CPU Usage | `100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)` |
| Memory Usage | `(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100` |

4. Click **Save Dashboard** → Name: "Razor's Edge Overview"

---

## 🔄 PHASE 4 — Set Up Jenkins CI/CD

### Step 1: Install Jenkins on EC2
SSH into your server:
```bash
# Install Java first
sudo apt update
sudo apt install -y openjdk-17-jdk

# Install Jenkins
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | sudo tee \
  /usr/share/keyrings/jenkins-keyring.asc > /dev/null
echo deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] \
  https://pkg.jenkins.io/debian-stable binary/ | sudo tee \
  /etc/apt/sources.list.d/jenkins.list > /dev/null
sudo apt update
sudo apt install -y jenkins
sudo systemctl start jenkins
sudo systemctl enable jenkins
```

### Step 2: Open Jenkins
- Go to `http://YOUR_EC2_IP:8080`
- Get initial password: `sudo cat /var/lib/jenkins/secrets/initialAdminPassword`
- Install suggested plugins
- Create admin user

### Step 3: Add Credentials in Jenkins
Go to **Manage Jenkins** → **Credentials** → **Global** → **Add Credentials**:

| ID | Type | Value |
|----|------|-------|
| `ec2-host-ip` | Secret text | Your EC2 public IP |
| `ec2-ssh-key` | SSH Username with private key | Paste content of `~/.ssh/razors-edge-key` |

### Step 4: Create Pipeline Job
1. Click **New Item** → Name: `razors-edge-pipeline` → **Pipeline**
2. Under **Pipeline** → **Definition**: Pipeline script from SCM
3. SCM: **Git**
4. Repository URL: `https://github.com/YOUR_USERNAME/razors-edge-barbershop.git`
5. Script Path: `jenkins/Jenkinsfile`
6. Click **Save**

### Step 5: Trigger Pipeline
- Click **Build Now**
- Watch the stages run in real time

**From now on:** Every time you push code to GitHub → Jenkins automatically builds and deploys! 🎉

---

## 🔁 How to Update Your App After Deployment

```bash
# On your computer, make changes to any file
# Then:
git add .
git commit -m "Updated barber prices"
git push origin main

# Jenkins auto-detects the push and redeploys in ~3 minutes
```

---

## 💰 AWS Cost Estimate (ap-south-1 Mumbai)

| Service | Spec | Monthly Cost |
|---------|------|-------------|
| EC2 t3.small | 2 vCPU, 2GB | ~₹1,200 |
| S3 | < 1GB bookings | ~₹2 |
| DynamoDB | Pay-per-request | ~₹50 |
| Elastic IP | Static IP | ~₹200 |
| **Total** | | **~₹1,450/month** |

---

## 🛑 How to Stop / Delete Everything

```bash
# Stop app (keeps EC2 running)
ssh ubuntu@YOUR_EC2_IP "cd /home/ubuntu/app && docker-compose down"

# Destroy ALL AWS resources (no more charges)
cd terraform/
terraform destroy
# Type: yes
```

---

## 📱 WhatsApp Message Format You'll Receive

```
✂ NEW BOOKING — The Razor's Edge
━━━━━━━━━━━━━━━━━━━━

👤 CUSTOMER
Name: Rahul Sharma
Phone: +91 98765 43210

📅 APPOINTMENT
Date: Monday, 20 January 2025
Time: 11:00 AM
Barber: PANKU

✂ SERVICES
  • Haircut (₹350)
  • Beard Trim (₹150)

💰 TOTAL: ₹500
💳 Payment: UPI

📝 NOTES
Keep top long, short sides
━━━━━━━━━━━━━━━━━━━━
```

---

## 🆘 Troubleshooting

**App not opening on port 3000:**
```bash
ssh ubuntu@YOUR_IP "docker-compose ps"
ssh ubuntu@YOUR_IP "docker-compose logs app"
```

**Terraform error "bucket already exists":**
Change `s3_bucket_name` in `variables.tf` to a unique name.

**Jenkins can't connect to EC2:**
Make sure port 8080 is added to EC2 security group in AWS Console.

#!/bin/bash

# ============================================================
#   THE RAZOR'S EDGE — FULL AUTO DEPLOYMENT SCRIPT
#   Run this ONE script to deploy everything automatically:
#   → Installs all tools (Git, Docker, Terraform, AWS CLI)
#   → Configures AWS
#   → Pushes code to GitHub
#   → Deploys EC2 + S3 + DynamoDB via Terraform
#   → Deploys App + Prometheus + Grafana via Docker Compose
#   → Sets up Jenkins CI/CD
# ============================================================

set -e  # Stop on any error

# ── Colors for pretty output ────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ── Helper functions ─────────────────────────────────────────
print_banner() {
    echo ""
    echo -e "${CYAN}${BOLD}"
    echo "  ╔══════════════════════════════════════════════════╗"
    echo "  ║       💈 THE RAZOR'S EDGE BARBERSHOP            ║"
    echo "  ║          AUTO DEPLOYMENT SCRIPT                  ║"
    echo "  ╚══════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_step() {
    echo ""
    echo -e "${BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}${BOLD}  $1${NC}"
    echo -e "${BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_ok()   { echo -e "  ${GREEN}✅ $1${NC}"; }
print_warn() { echo -e "  ${YELLOW}⚠️  $1${NC}"; }
print_err()  { echo -e "  ${RED}❌ $1${NC}"; }
print_info() { echo -e "  ${CYAN}ℹ️  $1${NC}"; }

ask() {
    echo -e "\n  ${YELLOW}${BOLD}▶ $1${NC}"
    echo -n "  → "
}

confirm() {
    echo -e "\n  ${YELLOW}${BOLD}$1 (y/n): ${NC}"
    read -r REPLY
    [[ "$REPLY" =~ ^[Yy]$ ]]
}

# ── Detect OS ────────────────────────────────────────────────
detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if command -v apt-get &>/dev/null; then
            OS="ubuntu"
        elif command -v yum &>/dev/null; then
            OS="centos"
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        OS="mac"
    else
        print_err "Unsupported OS. Use Linux (Ubuntu) or Mac."
        exit 1
    fi
    print_ok "Detected OS: $OS"
}

# ── Check if command exists ──────────────────────────────────
cmd_exists() { command -v "$1" &>/dev/null; }

# ============================================================
#   COLLECT USER CONFIG UPFRONT
# ============================================================
collect_config() {
    print_step "📋 STEP 1 — COLLECT YOUR CONFIGURATION"
    echo ""
    echo -e "  ${BOLD}Please enter the following details.${NC}"
    echo -e "  ${CYAN}(These will be used throughout the deployment)${NC}"
    echo ""

    # WhatsApp number
    ask "Your WhatsApp number with country code (e.g. 919876543210 for India):"
    read -r WHATSAPP_NUMBER

    # AWS credentials
    ask "Your AWS Access Key ID:"
    read -r AWS_ACCESS_KEY_ID

    ask "Your AWS Secret Access Key:"
    read -rs AWS_SECRET_ACCESS_KEY
    echo ""

    ask "AWS Region (press Enter for us-east-2, best for Everyone):"
    read -r AWS_REGION
    AWS_REGION=${AWS_REGION:-us-east-2}

    # GitHub
    ask "Your GitHub username:"
    read -r GITHUB_USERNAME

    ask "GitHub repository name (press Enter for 'razors-edge-barbershop'):"
    read -r GITHUB_REPO
    GITHUB_REPO=${GITHUB_REPO:-razors-edge-barbershop}

    ask "Your GitHub Personal Access Token (needed to push code):"
    read -rs GITHUB_TOKEN
    echo ""

    # S3 bucket name must be globally unique
    ask "S3 bucket name (press Enter for 'razors-edge-bookings-${GITHUB_USERNAME}'):"
    read -r S3_BUCKET
    S3_BUCKET=${S3_BUCKET:-razors-edge-bookings-${GITHUB_USERNAME}}

    # Summary
    echo ""
    echo -e "  ${BOLD}${GREEN}Configuration Summary:${NC}"
    echo -e "  WhatsApp : ${CYAN}${WHATSAPP_NUMBER}${NC}"
    echo -e "  AWS Key  : ${CYAN}${AWS_ACCESS_KEY_ID:0:8}...${NC}"
    echo -e "  Region   : ${CYAN}${AWS_REGION}${NC}"
    echo -e "  GitHub   : ${CYAN}${GITHUB_USERNAME}/${GITHUB_REPO}${NC}"
    echo -e "  S3 Bucket: ${CYAN}${S3_BUCKET}${NC}"
    echo ""

    if ! confirm "Everything looks correct? Continue with deployment?"; then
        print_err "Deployment cancelled."
        exit 0
    fi
}

# ============================================================
#   STEP 2 — INSTALL ALL REQUIRED TOOLS
# ============================================================
install_tools() {
    print_step "🛠️  STEP 2 — INSTALLING REQUIRED TOOLS"

    # ── Git ────────────────────────────────────────────────
    if cmd_exists git; then
        print_ok "Git already installed: $(git --version)"
    else
        print_info "Installing Git..."
        if [[ "$OS" == "ubuntu" ]]; then
            sudo apt-get update -y && sudo apt-get install -y git
        elif [[ "$OS" == "mac" ]]; then
            brew install git
        fi
        print_ok "Git installed: $(git --version)"
    fi

    # ── Docker ─────────────────────────────────────────────
    if cmd_exists docker; then
        print_ok "Docker already installed: $(docker --version)"
    else
        print_info "Installing Docker..."
        if [[ "$OS" == "ubuntu" ]]; then
            sudo apt-get update -y
            sudo apt-get install -y ca-certificates curl gnupg lsb-release
            sudo mkdir -p /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
                sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            echo "deb [arch=$(dpkg --print-architecture) \
                signed-by=/etc/apt/keyrings/docker.gpg] \
                https://download.docker.com/linux/ubuntu \
                $(lsb_release -cs) stable" | \
                sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            sudo apt-get update -y
            sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
            sudo systemctl start docker
            sudo systemctl enable docker
            sudo usermod -aG docker "$USER"
        elif [[ "$OS" == "mac" ]]; then
            print_warn "Please install Docker Desktop manually from docker.com, then re-run this script."
            exit 1
        fi
        print_ok "Docker installed: $(docker --version)"
    fi

    # ── Docker Compose ─────────────────────────────────────
    if cmd_exists docker-compose; then
        print_ok "Docker Compose already installed: $(docker-compose --version)"
    else
        print_info "Installing Docker Compose..."
        sudo curl -SL \
            "https://github.com/docker/compose/releases/download/v2.23.0/docker-compose-linux-x86_64" \
            -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
        print_ok "Docker Compose installed: $(docker-compose --version)"
    fi

    # ── AWS CLI ─────────────────────────────────────────────
    if cmd_exists aws; then
        print_ok "AWS CLI already installed: $(aws --version)"
    else
        print_info "Installing AWS CLI..."
        if [[ "$OS" == "ubuntu" ]]; then
            curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
            sudo apt-get install -y unzip
            unzip -q /tmp/awscliv2.zip -d /tmp/
            sudo /tmp/aws/install
            rm -rf /tmp/awscliv2.zip /tmp/aws
        elif [[ "$OS" == "mac" ]]; then
            curl -s "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o /tmp/AWSCLIV2.pkg
            sudo installer -pkg /tmp/AWSCLIV2.pkg -target /
        fi
        print_ok "AWS CLI installed: $(aws --version)"
    fi

    # ── Terraform ──────────────────────────────────────────
    if cmd_exists terraform; then
        print_ok "Terraform already installed: $(terraform --version | head -1)"
    else
        print_info "Installing Terraform..."
        if [[ "$OS" == "ubuntu" ]]; then
            sudo apt-get install -y gnupg software-properties-common
            wget -O- https://apt.releases.hashicorp.com/gpg | \
                sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
            echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
                https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
                sudo tee /etc/apt/sources.list.d/hashicorp.list
            sudo apt-get update -y && sudo apt-get install -y terraform
        elif [[ "$OS" == "mac" ]]; then
            brew tap hashicorp/tap
            brew install hashicorp/tap/terraform
        fi
        print_ok "Terraform installed: $(terraform --version | head -1)"
    fi

    # ── Node.js ─────────────────────────────────────────────
    if cmd_exists node; then
        print_ok "Node.js already installed: $(node --version)"
    else
        print_info "Installing Node.js v20..."
        if [[ "$OS" == "ubuntu" ]]; then
            curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
            sudo apt-get install -y nodejs
        elif [[ "$OS" == "mac" ]]; then
            brew install node@20
        fi
        print_ok "Node.js installed: $(node --version)"
    fi

    print_ok "All tools installed successfully!"
}

# ============================================================
#   STEP 3 — CONFIGURE AWS CLI
# ============================================================
configure_aws() {
    print_step "☁️  STEP 3 — CONFIGURE AWS"

    # Write credentials
    mkdir -p ~/.aws
    cat > ~/.aws/credentials << EOF
[default]
aws_access_key_id = ${AWS_ACCESS_KEY_ID}
aws_secret_access_key = ${AWS_SECRET_ACCESS_KEY}
EOF

    cat > ~/.aws/config << EOF
[default]
region = ${AWS_REGION}
output = json
EOF

    chmod 600 ~/.aws/credentials

    # Verify
    if aws sts get-caller-identity &>/dev/null; then
        ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        print_ok "AWS configured! Account ID: ${ACCOUNT_ID}"
    else
        print_err "AWS credentials are invalid. Please check and re-run."
        exit 1
    fi
}

# ============================================================
#   STEP 4 — GENERATE SSH KEY
# ============================================================
generate_ssh_key() {
    print_step "🔑 STEP 4 — GENERATE SSH KEY"

    SSH_KEY_PATH="$HOME/.ssh/razors-edge-key"

    if [[ -f "$SSH_KEY_PATH" ]]; then
        print_ok "SSH key already exists at $SSH_KEY_PATH"
    else
        print_info "Generating SSH key pair..."
        ssh-keygen -t rsa -b 4096 -f "$SSH_KEY_PATH" -N "" -C "razors-edge-deploy"
        print_ok "SSH key generated at $SSH_KEY_PATH"
    fi

    chmod 600 "$SSH_KEY_PATH"
    print_ok "SSH key ready"
}

# ============================================================
#   STEP 5 — UPDATE CONFIG IN PROJECT FILES
# ============================================================
update_project_config() {
    print_step "⚙️  STEP 5 — UPDATE PROJECT CONFIGURATION"

    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # Update WhatsApp number in index.html
    if [[ -f "$SCRIPT_DIR/app/public/index.html" ]]; then
        sed -i.bak "s/91XXXXXXXXXX/${WHATSAPP_NUMBER}/g" "$SCRIPT_DIR/app/public/index.html"
        rm -f "$SCRIPT_DIR/app/public/index.html.bak"
        print_ok "WhatsApp number updated in index.html"
    fi

    # Update variables.tf with GitHub info and S3 bucket
    if [[ -f "$SCRIPT_DIR/terraform/variables.tf" ]]; then
        sed -i.bak "s/your-github-username/${GITHUB_USERNAME}/g" "$SCRIPT_DIR/terraform/variables.tf"
        sed -i.bak "s/razors-edge-barbershop/${GITHUB_REPO}/g"   "$SCRIPT_DIR/terraform/variables.tf"
        sed -i.bak "s/razors-edge-bookings-prod/${S3_BUCKET}/g"  "$SCRIPT_DIR/terraform/variables.tf"
        sed -i.bak "s/ap-south-1/${AWS_REGION}/g"                "$SCRIPT_DIR/terraform/variables.tf"
        find "$SCRIPT_DIR/terraform" -name "*.bak" -delete
        print_ok "Terraform variables updated"
    fi

    # Update public key path in variables.tf
    sed -i.bak "s|~/.ssh/id_rsa.pub|$HOME/.ssh/razors-edge-key.pub|g" \
        "$SCRIPT_DIR/terraform/variables.tf" 2>/dev/null || true
    find "$SCRIPT_DIR/terraform" -name "*.bak" -delete 2>/dev/null || true

    # Create .env file
    cat > "$SCRIPT_DIR/.env" << EOF
AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
AWS_REGION=${AWS_REGION}
S3_BUCKET=${S3_BUCKET}
DYNAMO_TABLE=razors-edge-appointments
PORT=3000
NODE_ENV=production
EOF
    chmod 600 "$SCRIPT_DIR/.env"
    print_ok ".env file created"

    # Update terraform backend S3 bucket name
    sed -i.bak "s/razors-edge-tf-state/razors-edge-tf-state-${GITHUB_USERNAME}/g" \
        "$SCRIPT_DIR/terraform/ec2.tf" 2>/dev/null || true
    find "$SCRIPT_DIR/terraform" -name "*.bak" -delete 2>/dev/null || true

    TF_STATE_BUCKET="razors-edge-tf-state-${GITHUB_USERNAME}"
    print_ok "All config files updated"
}

# ============================================================
#   STEP 6 — PUSH TO GITHUB
# ============================================================
push_to_github() {
    print_step "🐙 STEP 6 — PUSH CODE TO GITHUB"

    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # Create GitHub repo via API
    print_info "Creating GitHub repository..."
    HTTP_CODE=$(curl -s -o /tmp/github_response.json -w "%{http_code}" \
        -X POST \
        -H "Authorization: token ${GITHUB_TOKEN}" \
        -H "Accept: application/vnd.github.v3+json" \
        https://api.github.com/user/repos \
        -d "{\"name\":\"${GITHUB_REPO}\",\"private\":true,\"description\":\"Razor's Edge Barbershop Booking System\"}")

    if [[ "$HTTP_CODE" == "201" ]]; then
        print_ok "GitHub repository created: ${GITHUB_USERNAME}/${GITHUB_REPO}"
    elif [[ "$HTTP_CODE" == "422" ]]; then
        print_warn "Repository already exists — using existing repo"
    else
        print_warn "GitHub repo creation returned code $HTTP_CODE — continuing anyway"
    fi

    # Git setup
    cd "$SCRIPT_DIR"
    git config --global user.email "${GITHUB_USERNAME}@users.noreply.github.com"
    git config --global user.name "Razor's Edge Deploy"

    if [[ ! -d ".git" ]]; then
        git init
        print_ok "Git repository initialized"
    fi

    git add .
    git commit -m "🚀 Auto-deploy: Razor's Edge Barbershop v2.0" 2>/dev/null || \
        git commit --allow-empty -m "🚀 Auto-deploy: Razor's Edge Barbershop v2.0"

    git branch -M main

    # Set remote with token embedded
    git remote remove origin 2>/dev/null || true
    git remote add origin "https://${GITHUB_TOKEN}@github.com/${GITHUB_USERNAME}/${GITHUB_REPO}.git"

    git push -u origin main --force
    print_ok "Code pushed to GitHub: https://github.com/${GITHUB_USERNAME}/${GITHUB_REPO}"
}

# ============================================================
#   STEP 7 — TERRAFORM — CREATE AWS RESOURCES
# ============================================================
deploy_terraform() {
    print_step "🏗️  STEP 7 — DEPLOY AWS INFRASTRUCTURE WITH TERRAFORM"

    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # Create Terraform state bucket first
    print_info "Creating Terraform state S3 bucket..."
    aws s3 mb "s3://${TF_STATE_BUCKET}" --region "$AWS_REGION" 2>/dev/null || \
        print_warn "State bucket may already exist — continuing"

    # Enable versioning on state bucket
    aws s3api put-bucket-versioning \
        --bucket "$TF_STATE_BUCKET" \
        --versioning-configuration Status=Enabled 2>/dev/null || true

    # Create app bookings bucket
    print_info "Creating app S3 bucket..."
    aws s3 mb "s3://${S3_BUCKET}" --region "$AWS_REGION" 2>/dev/null || \
        print_warn "Bookings bucket may already exist — continuing"

    # Run Terraform
    cd "$SCRIPT_DIR/terraform"

    print_info "Running: terraform init..."
    terraform init \
        -backend-config="bucket=${TF_STATE_BUCKET}" \
        -backend-config="region=${AWS_REGION}" \
        -input=false

    print_info "Running: terraform plan..."
    terraform plan \
        -var="aws_region=${AWS_REGION}" \
        -var="s3_bucket_name=${S3_BUCKET}" \
        -var="github_username=${GITHUB_USERNAME}" \
        -var="github_repo=${GITHUB_REPO}" \
        -out=tfplan \
        -input=false

    print_info "Running: terraform apply..."
    terraform apply -input=false -auto-approve tfplan

    # Capture outputs
    EC2_IP=$(terraform output -raw ec2_public_ip 2>/dev/null)
    APP_URL=$(terraform output -raw app_url 2>/dev/null)
    GRAFANA_URL=$(terraform output -raw grafana_url 2>/dev/null)
    PROMETHEUS_URL=$(terraform output -raw prometheus_url 2>/dev/null)

    print_ok "Terraform deployment complete!"
    print_ok "EC2 IP: ${EC2_IP}"

    cd "$SCRIPT_DIR"
}

# ============================================================
#   STEP 8 — WAIT FOR EC2 TO BE READY
# ============================================================
wait_for_ec2() {
    print_step "⏳ STEP 8 — WAITING FOR EC2 TO BE READY"

    print_info "Waiting for EC2 instance to boot up (~60 seconds)..."
    sleep 20

    SSH_KEY_PATH="$HOME/.ssh/razors-edge-key"
    MAX_TRIES=20
    TRIES=0

    while [[ $TRIES -lt $MAX_TRIES ]]; do
        if ssh -i "$SSH_KEY_PATH" \
               -o StrictHostKeyChecking=no \
               -o ConnectTimeout=10 \
               "ubuntu@${EC2_IP}" "echo ready" &>/dev/null; then
            print_ok "EC2 is ready and accepting SSH connections!"
            break
        fi
        TRIES=$((TRIES + 1))
        echo -e "  ${YELLOW}  Attempt ${TRIES}/${MAX_TRIES} — waiting 15 seconds...${NC}"
        sleep 15
    done

    if [[ $TRIES -eq $MAX_TRIES ]]; then
        print_err "EC2 didn't become ready in time. Check AWS Console."
        exit 1
    fi
}

# ============================================================
#   STEP 9 — DEPLOY APP VIA DOCKER COMPOSE ON EC2
# ============================================================
deploy_app() {
    print_step "🐳 STEP 9 — DEPLOY APP ON EC2 WITH DOCKER COMPOSE"

    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    SSH_KEY_PATH="$HOME/.ssh/razors-edge-key"
    SSH_CMD="ssh -i $SSH_KEY_PATH -o StrictHostKeyChecking=no ubuntu@${EC2_IP}"

    # Copy project files to EC2
    print_info "Copying project files to EC2..."
    scp -i "$SSH_KEY_PATH" \
        -o StrictHostKeyChecking=no \
        -r "$SCRIPT_DIR"/* \
        "ubuntu@${EC2_IP}:/home/ubuntu/app/"

    # Copy .env file
    scp -i "$SSH_KEY_PATH" \
        -o StrictHostKeyChecking=no \
        "$SCRIPT_DIR/.env" \
        "ubuntu@${EC2_IP}:/home/ubuntu/app/.env"

    # Install Docker on EC2 if not present, then launch app
    print_info "Setting up Docker and launching app on EC2..."
    $SSH_CMD << 'ENDSSH'
        set -e

        # Install Docker if not present
        if ! command -v docker &>/dev/null; then
            echo "Installing Docker..."
            sudo apt-get update -y
            sudo apt-get install -y docker.io docker-compose
            sudo systemctl start docker
            sudo systemctl enable docker
            sudo usermod -aG docker ubuntu
        fi

        # Install Docker Compose v2 if not present
        if ! command -v docker-compose &>/dev/null; then
            sudo curl -SL "https://github.com/docker/compose/releases/download/v2.23.0/docker-compose-linux-x86_64" \
                -o /usr/local/bin/docker-compose
            sudo chmod +x /usr/local/bin/docker-compose
        fi

        cd /home/ubuntu/app

        # Start all containers
        sudo docker-compose up -d --build

        echo "✅ App deployed!"
        sudo docker-compose ps
ENDSSH

    print_ok "App deployed on EC2!"
}

# ============================================================
#   STEP 10 — INSTALL JENKINS ON EC2
# ============================================================
install_jenkins() {
    print_step "🔄 STEP 10 — INSTALL JENKINS CI/CD"

    SSH_KEY_PATH="$HOME/.ssh/razors-edge-key"
    SSH_CMD="ssh -i $SSH_KEY_PATH -o StrictHostKeyChecking=no ubuntu@${EC2_IP}"

    print_info "Installing Jenkins on EC2..."
    $SSH_CMD << 'ENDSSH'
        set -e

        # Install Java
        if ! command -v java &>/dev/null; then
            sudo apt-get update -y
            sudo apt-get install -y openjdk-17-jdk
        fi

        # Install Jenkins
        if ! command -v jenkins &>/dev/null; then
            curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | \
                sudo tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null
            echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] \
                https://pkg.jenkins.io/debian-stable binary/" | \
                sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null
            sudo apt-get update -y
            sudo apt-get install -y jenkins
        fi

        sudo systemctl start jenkins
        sudo systemctl enable jenkins

        echo "Jenkins is running!"
        echo "Initial password:"
        sudo cat /var/lib/jenkins/secrets/initialAdminPassword 2>/dev/null || echo "Password file not ready yet"
ENDSSH

    print_ok "Jenkins installed on EC2!"
    print_info "Jenkins URL: http://${EC2_IP}:8080"
}

# ============================================================
#   STEP 11 — HEALTH CHECKS
# ============================================================
run_health_checks() {
    print_step "🏥 STEP 11 — RUNNING HEALTH CHECKS"

    print_info "Waiting 30 seconds for all services to start..."
    sleep 30

    check_url() {
        local NAME=$1
        local URL=$2
        if curl -sf --max-time 10 "$URL" &>/dev/null; then
            print_ok "$NAME is UP → $URL"
        else
            print_warn "$NAME not responding yet at $URL (may need more time)"
        fi
    }

    check_url "App"        "http://${EC2_IP}:3000/health"
    check_url "Prometheus" "http://${EC2_IP}:9090/-/healthy"
    check_url "Grafana"    "http://${EC2_IP}:3001/api/health"
}

# ============================================================
#   FINAL SUMMARY
# ============================================================
print_summary() {
    echo ""
    echo -e "${GREEN}${BOLD}"
    echo "  ╔══════════════════════════════════════════════════════╗"
    echo "  ║         🎉 DEPLOYMENT COMPLETE!                     ║"
    echo "  ╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "  ${BOLD}Your live URLs:${NC}"
    echo ""
    echo -e "  📱 ${CYAN}${BOLD}Booking App:${NC}   http://${EC2_IP}:3000"
    echo -e "  📊 ${CYAN}${BOLD}Grafana:${NC}       http://${EC2_IP}:3001  (admin / razors@123)"
    echo -e "  🔥 ${CYAN}${BOLD}Prometheus:${NC}    http://${EC2_IP}:9090"
    echo -e "  🔄 ${CYAN}${BOLD}Jenkins:${NC}       http://${EC2_IP}:8080"
    echo -e "  🐙 ${CYAN}${BOLD}GitHub Repo:${NC}   https://github.com/${GITHUB_USERNAME}/${GITHUB_REPO}"
    echo ""
    echo -e "  ${BOLD}SSH into your server:${NC}"
    echo -e "  ${YELLOW}  ssh -i ~/.ssh/razors-edge-key ubuntu@${EC2_IP}${NC}"
    echo ""
    echo -e "  ${BOLD}To update the app in future:${NC}"
    echo -e "  ${YELLOW}  git add . && git commit -m 'update' && git push${NC}"
    echo -e "  ${CYAN}  Jenkins will auto-deploy your changes!${NC}"
    echo ""
    echo -e "  ${BOLD}To destroy all AWS resources:${NC}"
    echo -e "  ${YELLOW}  cd terraform && terraform destroy${NC}"
    echo ""
    echo -e "  ${GREEN}${BOLD}Share your booking link with customers: http://${EC2_IP}:3000 💈${NC}"
    echo ""
}

# ============================================================
#   CLEANUP ON ERROR
# ============================================================
cleanup_on_error() {
    print_err "Deployment failed! Check the error above."
    echo ""
    echo -e "  ${YELLOW}To retry, simply run the script again:${NC}"
    echo -e "  ${CYAN}  bash deploy.sh${NC}"
    echo ""
    echo -e "  ${YELLOW}To destroy AWS resources if partially created:${NC}"
    echo -e "  ${CYAN}  cd terraform && terraform destroy${NC}"
}
trap cleanup_on_error ERR

# ============================================================
#   MAIN — RUN ALL STEPS IN ORDER
# ============================================================
main() {
    print_banner
    detect_os
    collect_config
    install_tools
    configure_aws
    generate_ssh_key
    update_project_config
    push_to_github
    deploy_terraform
    wait_for_ec2
    deploy_app
    install_jenkins
    run_health_checks
    print_summary
}

main "$@"

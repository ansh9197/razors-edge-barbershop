#!/bin/bash

# ============================================================
#   THE RAZOR'S EDGE — UPDATE SCRIPT
#   Run this when you make changes to the app
#   It will push to GitHub and redeploy on EC2
# ============================================================

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

print_ok()   { echo -e "  ${GREEN}✅ $1${NC}"; }
print_info() { echo -e "  ${CYAN}ℹ️  $1${NC}"; }

echo ""
echo -e "${CYAN}${BOLD}  💈 RAZOR'S EDGE — REDEPLOY${NC}"
echo ""

echo -n "  Enter your EC2 IP: "
read -r EC2_IP

echo -n "  Commit message (e.g. 'Updated prices'): "
read -r COMMIT_MSG

# Push to GitHub
print_info "Pushing to GitHub..."
git add .
git commit -m "$COMMIT_MSG" || echo "Nothing to commit"
git push origin main
print_ok "Pushed to GitHub"

# Deploy on EC2
print_info "Deploying on EC2..."
ssh -i ~/.ssh/razors-edge-key -o StrictHostKeyChecking=no ubuntu@"$EC2_IP" << 'ENDSSH'
    cd /home/ubuntu/app
    git pull origin main
    docker-compose up -d --build --no-deps app
    echo "✅ Redeployed!"
ENDSSH

print_ok "Update deployed to http://${EC2_IP}:3000"

#!/bin/bash

# ============================================================
#   THE RAZOR'S EDGE — STOP / DESTROY SCRIPT
#   Run this to stop the app or destroy all AWS resources
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

print_step() {
    echo ""
    echo -e "${CYAN}${BOLD}━━━━ $1 ━━━━${NC}"
}

print_ok()   { echo -e "  ${GREEN}✅ $1${NC}"; }
print_warn() { echo -e "  ${YELLOW}⚠️  $1${NC}"; }
print_err()  { echo -e "  ${RED}❌ $1${NC}"; }

echo ""
echo -e "${YELLOW}${BOLD}  💈 THE RAZOR'S EDGE — STOP/DESTROY MENU${NC}"
echo ""
echo "  1) Stop app only       (Docker containers stop, EC2 keeps running)"
echo "  2) Restart app         (Restart all Docker containers)"
echo "  3) Destroy EVERYTHING  (Delete all AWS resources — stops billing)"
echo "  4) Cancel"
echo ""
echo -n "  Choose (1/2/3/4): "
read -r CHOICE

case $CHOICE in

  1)
    print_step "STOPPING APP"
    echo -n "  Enter your EC2 IP: "
    read -r EC2_IP
    ssh -i ~/.ssh/razors-edge-key -o StrictHostKeyChecking=no ubuntu@"$EC2_IP" \
        "cd /home/ubuntu/app && docker-compose down"
    print_ok "App stopped. EC2 is still running (you are still billed for EC2)."
    print_warn "To stop billing completely, choose option 3."
    ;;

  2)
    print_step "RESTARTING APP"
    echo -n "  Enter your EC2 IP: "
    read -r EC2_IP
    ssh -i ~/.ssh/razors-edge-key -o StrictHostKeyChecking=no ubuntu@"$EC2_IP" \
        "cd /home/ubuntu/app && docker-compose restart"
    print_ok "App restarted!"
    ;;

  3)
    print_step "DESTROY ALL AWS RESOURCES"
    echo ""
    echo -e "  ${RED}${BOLD}WARNING: This will permanently delete:${NC}"
    echo -e "  ${RED}  • EC2 Instance${NC}"
    echo -e "  ${RED}  • S3 Bucket (all booking data)${NC}"
    echo -e "  ${RED}  • DynamoDB Table (all appointments)${NC}"
    echo -e "  ${RED}  • All AWS resources created by Terraform${NC}"
    echo ""
    echo -n "  Type 'DESTROY' to confirm: "
    read -r CONFIRM
    if [[ "$CONFIRM" == "DESTROY" ]]; then
        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        cd "$SCRIPT_DIR/terraform"
        terraform destroy -auto-approve
        print_ok "All AWS resources destroyed. No more charges!"
    else
        echo "  Cancelled."
    fi
    ;;

  4)
    echo "  Cancelled."
    ;;

  *)
    print_err "Invalid choice."
    ;;
esac

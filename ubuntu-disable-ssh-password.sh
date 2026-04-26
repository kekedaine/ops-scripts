#!/bin/bash

# Disable SSH password authentication on Ubuntu (20.04 -> 26.04)
# Standalone version of disable_ssh_password_auth() from setup_basic_host.sh
#
# Usage: sudo ./ubuntu-disable-ssh-password.sh
#
# Or run directly via curl:
#   curl -fsSL https://ops.bhtas.co/ubuntu-disable-ssh-password.sh | sudo bash
#
# WARNING: Make sure your SSH public key is already in ~/.ssh/authorized_keys
# before running this script, otherwise you may lock yourself out.

set -e

# Bump on every release. Format: YYYYMMDD-HHmmss (UTC).
SCRIPT_VERSION="20260426-180300"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_success() { echo -e "${GREEN}[ OK ]${NC} $1"; }

# Verify Ubuntu version (20.04 -> 26.04)
check_ubuntu_version() {
    if [ ! -f /etc/os-release ]; then
        log_error "Cannot detect OS: /etc/os-release not found"
        exit 1
    fi

    # shellcheck disable=SC1091
    . /etc/os-release

    if [ "${ID}" != "ubuntu" ]; then
        log_error "Unsupported OS: ${PRETTY_NAME:-$ID}. This script supports Ubuntu only."
        exit 1
    fi

    local major
    major=$(echo "${VERSION_ID}" | cut -d. -f1)
    if [ "${major}" -lt 20 ] || [ "${major}" -gt 26 ]; then
        log_error "Unsupported Ubuntu version: ${VERSION_ID}. Supported: 20.04 -> 26.04"
        exit 1
    fi

    log_info "Detected: ${PRETTY_NAME}"
}

# Safety check: ensure at least one authorized_keys file exists
check_authorized_keys() {
    local found=0
    for keyfile in /root/.ssh/authorized_keys /home/*/.ssh/authorized_keys; do
        if [ -s "${keyfile}" ]; then
            found=1
            break
        fi
    done

    if [ "${found}" -eq 0 ]; then
        log_error "No authorized_keys file found. Disabling password auth would lock you out."
        log_error "Add an SSH public key first, then re-run this script."
        exit 1
    fi
}

# Function to disable SSH password authentication
disable_ssh_password_auth() {
    log_info "Disabling SSH password authentication..."

    # Backup sshd_config
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    sudo cp /etc/ssh/sshd_config "/etc/ssh/sshd_config.backup.${timestamp}"
    log_info "Backup: /etc/ssh/sshd_config.backup.${timestamp}"

    # Disable password authentication in main config
    if grep -q "^PasswordAuthentication" /etc/ssh/sshd_config; then
        sudo sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
    else
        echo "PasswordAuthentication no" | sudo tee -a /etc/ssh/sshd_config > /dev/null
    fi

    # Also disable ChallengeResponseAuthentication
    if grep -q "^ChallengeResponseAuthentication" /etc/ssh/sshd_config; then
        sudo sed -i 's/^ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' /etc/ssh/sshd_config
    else
        echo "ChallengeResponseAuthentication no" | sudo tee -a /etc/ssh/sshd_config > /dev/null
    fi

    # Also disable KbdInteractiveAuthentication (modern OpenSSH uses this name)
    if grep -q "^KbdInteractiveAuthentication" /etc/ssh/sshd_config; then
        sudo sed -i 's/^KbdInteractiveAuthentication.*/KbdInteractiveAuthentication no/' /etc/ssh/sshd_config
    else
        echo "KbdInteractiveAuthentication no" | sudo tee -a /etc/ssh/sshd_config > /dev/null
    fi

    # Also disable in config.d files (they can override main config)
    if [ -d /etc/ssh/sshd_config.d ]; then
        for config_file in /etc/ssh/sshd_config.d/*.conf; do
            if [ -f "${config_file}" ]; then
                # Backup
                sudo cp "${config_file}" "${config_file}.backup.${timestamp}" 2>/dev/null || true

                # Update PasswordAuthentication
                if grep -q "^PasswordAuthentication" "${config_file}"; then
                    sudo sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' "${config_file}"
                fi

                # Update ChallengeResponseAuthentication
                if grep -q "^ChallengeResponseAuthentication" "${config_file}"; then
                    sudo sed -i 's/^ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' "${config_file}"
                fi

                # Update KbdInteractiveAuthentication
                if grep -q "^KbdInteractiveAuthentication" "${config_file}"; then
                    sudo sed -i 's/^KbdInteractiveAuthentication.*/KbdInteractiveAuthentication no/' "${config_file}"
                fi
            fi
        done
    fi

    # Test SSH config first
    log_info "Validating SSH configuration..."
    if sudo sshd -t 2>/dev/null; then
        log_info "Restarting SSH service..."

        # Ubuntu uses 'ssh.service', not 'sshd.service'
        # If ssh.socket is active, we need to restart it too
        if systemctl is-active --quiet ssh.socket 2>/dev/null; then
            sudo systemctl restart ssh.socket 2>/dev/null || true
        fi

        # Restart SSH service
        if systemctl is-active --quiet ssh.service 2>/dev/null; then
            sudo systemctl restart ssh.service 2>/dev/null || true
        elif systemctl is-active --quiet sshd.service 2>/dev/null; then
            sudo systemctl restart sshd.service 2>/dev/null || true
        else
            sudo systemctl restart ssh.service 2>/dev/null || sudo systemctl restart sshd.service 2>/dev/null || true
        fi
    else
        log_error "SSH config test failed. Restoring backup..."
        sudo cp "/etc/ssh/sshd_config.backup.${timestamp}" /etc/ssh/sshd_config
        exit 1
    fi

    log_success "SSH password authentication disabled"
}

# Banners
print_banner_start() {
    echo ""
    echo "========================================================"
    echo "  Ubuntu SSH Password Authentication Disabler"
    echo "  Target:  Ubuntu 20.04 -> 26.04"
    echo "  Version: ${SCRIPT_VERSION}"
    echo "  Started: $(date -u +'%Y-%m-%d %H:%M:%S UTC')"
    echo "========================================================"
    echo ""
}

print_banner_done() {
    local password_status="$1"
    local kbd_status="$2"

    echo ""
    echo "========================================================"
    echo "  ✅ COMPLETED — SSH password authentication disabled"
    echo "========================================================"
    echo "  PasswordAuthentication:        ${password_status:-unknown}"
    echo "  KbdInteractiveAuthentication:  ${kbd_status:-unknown}"
    echo "  Finished: $(date -u +'%Y-%m-%d %H:%M:%S UTC')"
    echo "========================================================"
    echo ""
}

# Print effective settings (returned via globals for the done banner)
read_effective_settings() {
    EFFECTIVE_PASSWORD=$(sudo sshd -T 2>/dev/null | awk '/^passwordauthentication/ {print $2}')
    EFFECTIVE_KBD=$(sudo sshd -T 2>/dev/null | awk '/^kbdinteractiveauthentication/ {print $2}')
}

# Main
main() {
    print_banner_start

    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi

    log_info "Step 1/4: Verifying Ubuntu version..."
    check_ubuntu_version

    log_info "Step 2/4: Checking authorized SSH keys..."
    check_authorized_keys
    log_success "Authorized keys present — safe to proceed"

    log_info "Step 3/4: Checking current SSH settings..."
    read_effective_settings
    if [ "${EFFECTIVE_PASSWORD}" = "no" ] && [ "${EFFECTIVE_KBD}" = "no" ]; then
        log_success "SSH password auth already disabled — no changes made (no backup, no restart)"
        print_banner_done "${EFFECTIVE_PASSWORD}" "${EFFECTIVE_KBD}"
        exit 0
    fi
    log_info "Current state: PasswordAuthentication=${EFFECTIVE_PASSWORD:-unknown}, KbdInteractiveAuthentication=${EFFECTIVE_KBD:-unknown}"

    log_info "Step 4/4: Applying SSH config changes..."
    disable_ssh_password_auth
    read_effective_settings

    print_banner_done "${EFFECTIVE_PASSWORD}" "${EFFECTIVE_KBD}"
}

main "$@"

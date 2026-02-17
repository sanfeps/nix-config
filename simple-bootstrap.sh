#!/usr/bin/env bash
set -euo pipefail

# Default values
target_hostname=""
target_ip=""
ssh_key="$HOME/.ssh/lykill"
ssh_port=22
luks_password=""

# Color output helpers
function green() { echo -e "\x1B[32m[+] $1\x1B[0m"; }
function red() { echo -e "\x1B[31m[!] $1\x1B[0m"; }
function blue() { echo -e "\x1B[34m[*] $1\x1B[0m"; }

# Usage
function show_help() {
    echo "Usage: $0 -n <hostname> -i <target_ip> [OPTIONS]"
    echo ""
    echo "Required:"
    echo "  -n <hostname>     Target hostname (e.g., asgard)"
    echo "  -i <target_ip>    Target IP address (e.g., 192.168.1.42)"
    echo ""
    echo "Optional:"
    echo "  -k <ssh_key>      Path to SSH private key (default: ~/.ssh/lykill)"
    echo "  -p <port>         SSH port (default: 22)"
    echo "  -l <password>     LUKS encryption password (omit for no encryption)"
    echo "  -h                Show this help"
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -n) shift; target_hostname=$1 ;;
        -i) shift; target_ip=$1 ;;
        -k) shift; ssh_key=$1 ;;
        -p) shift; ssh_port=$1 ;;
        -l) shift; luks_password=$1 ;;
        -h) show_help ;;
        *) red "Unknown option: $1"; show_help ;;
    esac
    shift
done

# Validate required arguments
if [[ -z "$target_hostname" ]] || [[ -z "$target_ip" ]]; then
    red "Error: -n and -i are required"
    show_help
fi

# Verify SSH key exists
if [[ ! -f "$ssh_key" ]]; then
    red "Error: SSH key not found at $ssh_key"
    exit 1
fi

if [[ ! -f "${ssh_key}.pub" ]]; then
    red "Error: SSH public key not found at ${ssh_key}.pub"
    exit 1
fi

green "=== Simple NixOS Bootstrap ==="
blue "Target: $target_hostname ($target_ip)"
blue "SSH Key: $ssh_key"
blue "SSH Port: $ssh_port"
if [[ -n "$luks_password" ]]; then
    blue "Disk Encryption: Enabled"
else
    blue "Disk Encryption: Disabled"
fi
echo ""

# Step 1: Copy SSH key to target
green "Step 1: Copying SSH public key to target..."
if ssh-copy-id -i "${ssh_key}.pub" -p "$ssh_port" "root@$target_ip"; then
    green "SSH key copied successfully"
else
    red "Failed to copy SSH key. Did you set a root password on the target?"
    exit 1
fi

# Step 2: Test SSH connection
green "Step 2: Testing SSH connection..."
if ssh -i "$ssh_key" -p "$ssh_port" -o ConnectTimeout=5 "root@$target_ip" "echo 'Connection successful'"; then
    green "SSH connection verified"
else
    red "SSH connection failed"
    exit 1
fi

# Step 3: Clean known_hosts
green "Step 3: Cleaning known_hosts..."
sed -i "/$target_ip/d" ~/.ssh/known_hosts 2>/dev/null || true
ssh-keyscan -p "$ssh_port" "$target_ip" 2>/dev/null | grep -v '^#' >> ~/.ssh/known_hosts

# Step 4: Run nixos-anywhere
green "Step 4: Running nixos-anywhere..."
echo ""
blue "This will wipe the target system and install NixOS"
read -p "Continue? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    red "Aborted by user"
    exit 1
fi

# Build nixos-anywhere command
nix_anywhere_cmd=(
    nix run github:nix-community/nixos-anywhere --
    --flake ".#${target_hostname}"
    --target-host "root@${target_ip}"
    --ssh-port "$ssh_port"
    --post-kexec-ssh-port "$ssh_port"
)

# Add disk encryption keys only if password is provided
if [[ -n "$luks_password" ]]; then
    nix_anywhere_cmd+=(--disk-encryption-keys /tmp/disko-password <(echo "$luks_password"))
fi

# Execute nixos-anywhere
"${nix_anywhere_cmd[@]}"

green "=== Installation Complete ==="
echo ""
blue "Next steps:"
echo "1. Wait for the system to reboot"
echo "2. SSH into your new system: ssh -i $ssh_key root@$target_ip"
if [[ -n "$luks_password" ]]; then
    echo "3. Change the LUKS password if needed"
fi

#!/bin/bash

# VMware Virtual Network Editor - Password-free fix for student user
# Run as root on RedOS (RHEL-based) systems
#
# Two approaches are used:
# 1. Sudoers rules - for running vmware-netcfg via sudo
# 2. Setuid on gksu-run-helper - VMware uses its own gksu library for
#    privilege escalation, not the system's sudo

set -e

echo "=== VMware Network Editor Fix Script ==="

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: Please run as root"
    exit 1
fi

# Step 1: Create sudoers rule
echo "[1/5] Creating sudoers rule..."
cat > /etc/sudoers.d/vmware-netcfg << 'EOF'
student ALL=(root) NOPASSWD: /usr/bin/vmware-netcfg
student ALL=(root) NOPASSWD: /usr/lib/vmware/bin/vmware-netcfg
student ALL=(root) NOPASSWD: /usr/lib/vmware/lib/libvmware-gksu.so/gksu-run-helper
EOF

# Step 2: Set sudoers permissions
echo "[2/5] Setting sudoers permissions..."
chmod 440 /etc/sudoers.d/vmware-netcfg
visudo -c

# Step 3: Update desktop file
echo "[3/5] Updating desktop file..."
sed -i 's|Exec=/usr/bin/vmware-netcfg|Exec=sudo /usr/bin/vmware-netcfg|' \
    /usr/share/applications/vmware-netcfg.desktop

# Step 4: Set setuid on gksu-run-helper (VMware's internal privilege escalation)
echo "[4/5] Setting setuid on gksu-run-helper..."
chmod u+s /usr/lib/vmware/lib/libvmware-gksu.so/gksu-run-helper
ls -la /usr/lib/vmware/lib/libvmware-gksu.so/gksu-run-helper

# Step 5: Create symlink for gksu-run-helper at expected path
# VMware's libvmware-gksu.so looks for helper at /usr/lib/libgksu/gksu-run-helper
echo "[5/5] Creating symlink for gksu-run-helper..."
mkdir -p /usr/lib/libgksu
ln -sf /usr/lib/vmware/lib/libvmware-gksu.so/gksu-run-helper /usr/lib/libgksu/gksu-run-helper

echo ""
echo "=== Done ==="
echo "Student can now open Virtual Network Editor without password."

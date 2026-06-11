#!/bin/bash
#
# Proxmox Backup Server first-boot configuration script.
#
# Mirrors the community post-pbs-install script:
# https://github.com/community-scripts/ProxmoxVE/blob/main/tools/pve/post-pbs-install.sh
#

set -euo pipefail

# 1. Disable the enterprise (subscription-required) repository.
for file in /etc/apt/sources.list.d/*.sources; do
    if grep -q "Components:.*pbs-enterprise" "${file}"; then
        if grep -q "^Enabled:" "${file}"; then
            sed -i 's/^Enabled:.*/Enabled: false/' "${file}"
        else
            echo "Enabled: false" >> "${file}"
        fi
    fi
done

# 2. Enable the no-subscription repository.
if ! grep -q "pbs-no-subscription" /etc/apt/sources.list.d/proxmox.sources 2>/dev/null; then
    cat >> /etc/apt/sources.list.d/proxmox.sources <<EOF

Types: deb
URIs: http://download.proxmox.com/debian/pbs
Suites: trixie
Components: pbs-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF
fi

# 3. Remove the subscription nag from the web UI.
sed -i.bak "s/res === null || res === undefined || \!res || res/false/g" /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
apt-get --reinstall install -y proxmox-widget-toolkit

# 4. Update package lists and upgrade, then reboot.
apt-get update -qq
apt-get -y dist-upgrade
reboot

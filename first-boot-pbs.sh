#!/bin/bash
#
# Proxmox Backup Server first-boot configuration script.
#
# Non-interactive equivalent of the community post-pbs-install script:
# https://github.com/community-scripts/ProxmoxVE/blob/main/tools/pve/post-pbs-install.sh
#

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# 1. Disable the enterprise (pbs-enterprise) repository.
for file in /etc/apt/sources.list.d/*.sources; do
    [ -e "${file}" ] || continue
    if grep -q "Components:.*pbs-enterprise" "${file}"; then
        if grep -q "^Enabled:" "${file}"; then
            sed -i 's/^Enabled:.*/Enabled: false/' "${file}"
        else
            echo "Enabled: false" >> "${file}"
        fi
    fi
done

# 2. Enable the no-subscription repository.
if ! grep -rq "pbs-no-subscription" /etc/apt/sources.list.d/ 2>/dev/null; then
    cat > /etc/apt/sources.list.d/proxmox.sources <<EOF
Types: deb
URIs: http://download.proxmox.com/debian/pbs
Suites: trixie
Components: pbs-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF
fi

# 3. Disable the subscription nag in the web UI via an apt hook, so it
#    re-applies whenever a package update overwrites proxmoxlib.js.
mkdir -p /usr/local/bin
cat > /usr/local/bin/pve-remove-nag.sh <<'EOF'
#!/bin/sh
WEB_JS=/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
if [ -s "$WEB_JS" ] && ! grep -q NoMoreNagging "$WEB_JS"; then
    sed -i -e "/data\.status/ s/!//" -e "/data\.status/ s/active/NoMoreNagging/" "$WEB_JS"
fi
EOF
chmod 755 /usr/local/bin/pve-remove-nag.sh

cat > /etc/apt/apt.conf.d/no-nag-script <<'EOF'
DPkg::Post-Invoke { "/usr/local/bin/pve-remove-nag.sh"; };
EOF
chmod 644 /etc/apt/apt.conf.d/no-nag-script

# Reinstall to trigger the hook immediately on the running install.
apt-get --reinstall install -y proxmox-widget-toolkit

# 4. Update package lists and upgrade, then reboot.
apt-get update
apt-get -y -o Dpkg::Options::="--force-confold" dist-upgrade
reboot

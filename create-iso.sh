# !/bin/bash

# Verify the hostname argument was passed.  
if [ "$#" -ne 2 ]; then
    printf "*** Invalid arguments provided ***\n\n"
    printf "Execute script using: ./create-iso.sh proxmox_type  hostname\n\n"
    exit 1
fi

# Increment the version number for new releases.
PVE_VERSION=8.4-1
PBS_VERSION=3.4-1
PVE_BASE="proxmox-ve"
PBS_BASE="proxmox-backup-server"

# Passed arguments.
proxmox_type=${1}
iso_hostname=${2}

# Verify the proxmox_type argument was passed.
if [ "$proxmox_type" != "pbs" ] && [ "$proxmox_type" != "pve" ]; then
    echo "Invalid proxmox_type: $proxmox_type"
    exit 1
fi

# Final proxmox version and base name.
proxmox_version=${PVE_VERSION}
proxmox_base=${PVE_BASE}
if [ "$proxmox_type" == "pbs" ]; then
    proxmox_version=${PBS_VERSION}
    proxmox_base=${PBS_BASE}
fi

# Verify the hostname answer file exists.
if [ ! -f ./answers/answer-"${iso_hostname}".toml ]; then
    printf "*** Missing answer file ***\n\n"
    printf "Expecting answer file for hostname ${iso_hostname}.\n\n"
    exit 1
fi

# Verify the base proxmox installation iso exists.
if [ ! -f "${proxmox_base}"_"${proxmox_version}".iso ]; then
    printf "*** Missing proxmox .iso ***\n\n"
    printf "Expecting proxmox ${proxmox_type} installation .iso for version ${proxmox_version}.\n\n"
    exit 1
fi

printf "\nCreating automatic installation .iso for ${iso_hostname} and proxmox ${proxmox_type} version ${proxmox_version}.\n\n"

# Create the auto install .iso file.
proxmox-auto-install-assistant prepare-iso ./"${proxmox_base}"_"${proxmox_version}".iso --fetch-from iso --answer-file ./answers/answer-"${iso_hostname}".toml

# Rename the .iso file.
cp ./"${proxmox_base}"_"${proxmox_version}"-auto-from-iso.iso ./"${proxmox_base}"_"${proxmox_version}"-auto-from-iso-"${iso_hostname}".iso
rm -f ./"${proxmox_base}"_"${proxmox_version}"-auto-from-iso.iso 

printf "\nDone...\n"
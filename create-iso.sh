# !/bin/bash

# Verify the hostname arguement was passed.  
if [ "$#" -ne 1 ]; then
    printf "*** Invalid arguements provided ***\n\n"
    printf "Excute script using: ./create-iso.sh hostname\n\n"
    exit 1
fi

iso_hostname=${1}
proxmox_version=8.2-2

# Verify the base proxmox installation iso exists.
if [ ! -f proxmox-ve_"${proxmox_version}".iso ]; then
    printf "*** Missing proxmox .iso ***\n\n"
    printf "Expecting proxmox installation .iso for version ${proxmox_version}.\n\n"
    exit 1
fi

printf "\nCreating automatic installation .iso for ${iso_hostname} and proxmox version ${proxmox_version}.\n\n"

# Create the auto install .iso file.
proxmox-auto-install-assistant prepare-iso ./proxmox-ve_"${proxmox_version}".iso --fetch-from iso --answer-file ./answers/answer-"${iso_hostname}".toml

# Rename the .iso file.
cp ./proxmox-ve_"${proxmox_version}"-auto-from-iso.iso ./proxmox-ve_"${proxmox_version}"-auto-from-iso-"${iso_hostname}".iso
rm -f ./proxmox-ve_"${proxmox_version}"-auto-from-iso.iso 

printf "\nDone...\n"
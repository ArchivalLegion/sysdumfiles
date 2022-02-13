#!/usr/bin/env bash
set -euo pipefail
#set -xv
export DEBIAN_FRONTEND=noninteractive

echo "Update packages and configure system" && {
	apt update
	apt full-upgrade -yq
	dpkg-reconfigure locales tzdata keyboard-configuration console-setup
	apt install -yq nano dosfstools cryptsetup ubuntu-standard linux-image-generic linux-image-lowlatency-hwe-20.04
  }

echo "Adding system groups" && {
	addgroup --system lpadmin
	addgroup --system lxd
	addgroup --system sambashare
	addgroup --system gpio
	addgroup --system i2c
	addgroup --system input
	addgroup --system spi
	addgroup --system wheel
	}

echo "Create user" && {
	useradd -m -s /bin/bash "$USER"
	usermod -aG adm,cdrom,dip,lpadmin,lxd,plugdev,sambashare,sudo,gpio,i2c,input,spi,audio,wheel "$USER"
}

echo "Install GRUB" && {
	apt install -yq grub-efi-amd64 grub-efi-amd64-signed shim shim-signed
	grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=$BOOTID --recheck --removable
	apt-get install --reinstall --yes --quiet grub-efi-amd64-signed
	update-initramfs -c -k all
	update-grub
	}

set +e
echo "Install user packages" && {
	xargs -a ubuntu-gui apt install -yq 
	}

echo "Set passwords" && {
	passwd root
	passwd "$USER"
	}
set -e
echo "Finished! Enjoy the system"

#!/usr/bin/env bash
set -euo pipefail
set -xv

echo "Update packages and configure system" && {
	apt update
	apt full-upgrade -yq
	dpkg-reconfigure locales tzdata keyboard-configuration console-setup nano \
  	dosfstools cryptsetup ubuntu-standard grub-efi-amd64 grub-efi-amd64-signed \
  	shim-signed linux-image-generic linux-image-lowlatency-hwe-20.04
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
	grub-probe /boot || true
	update-grub
	grub-install --target=x86_64-efi --efi-directory=/efi \
	--bootloader-id=$BOOTID --recheck --removable --no-floppy
	grub-install --target=x86_64-efi --efi-directory=/efi \
	--bootloader-id=$BOOTID --recheck --no-floppy
	}

set +e
echo "Install user packages" && {
	xargs -a ubuntu-gui apt install 
  }

echo "Set passwords" && {
	passwd
	passwd "$USER"
  }
set -e

echo "Finished! Enjoy the system"

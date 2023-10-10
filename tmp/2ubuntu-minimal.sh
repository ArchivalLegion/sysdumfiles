#!/usr/bin/env bash
set -euo pipefail
#set -xv
export DEBIAN_FRONTEND=noninteractive

echo "Update packages and configure system" && {
	apt update
	apt full-upgrade -yq
	dpkg-reconfigure locales tzdata keyboard-configuration console-setup
	apt install -yq nano dosfstools cryptsetup ubuntu-standard linux-image-generic
  }

echo "Adding wheel group" && {
	addgroup --system wheel
	}

echo "Create user" && {
	useradd -m -s /bin/bash "$USER"
	usermod -aG cdrom,plugdev,sudo,audio,wheel "$USER"
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

echo "Set $USER password" && {
	passwd "$USER"
	}
set -e
echo "Finished! Enjoy the system"

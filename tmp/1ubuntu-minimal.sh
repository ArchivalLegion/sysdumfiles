#!/usr/bin/env bash
set -euo pipefail
set -xv

DISK=/dev/disk/by-id/
USER=NewPlayer
EFILABEL=ZAMN
RELEASE=focal
ARCH=amd64
HOSTNAME=boom
BOOTID=ZAMN

echo "Disabling automount" && {
	gsettings set org.gnome.desktop.media-handling automount false || true
	}
	
echo "Install tools" && {
	apt update
	apt install -yq debootstrap gdisk
	}

echo "Wiping and partitioning drive" && {
	swapoff --all
	sgdisk --zap-all $DISK
	wipefs -af $DISK
	sgdisk -n1:1M:+64M -t1:EF00 $DISK -c1:$EFILABEL
	sgdisk -a1 -n5:0:+1000K -t5:EF02 $DISK -c5:legacy_boot
	sgdisk -n4:0:0 -t4:BF00 $DISK -c2:ZAMN
	echo "Waiting for partition symlinks to update"
	sleep 7
	}

echo "Creating Filesystems" && {
  	cryptsetup luksFormat --luks1 "$DISK-part2"
  	cryptsetup luksOpen "$DISK" install
  	mkfs.ext4 -e remount-ro -E discard,lazy_journal_init=0,lazy_itable_init=0 -L zamn -m 1 -U time -v /dev/mapper/install
  	mount /dev/mapper/install /mnt
  	mkfs.fat -v -n "$EFILABEL" "$DISK-part1"
  	mkdir /mnt/efi
  	mount "$DISK-part1" /mnt/efi
  }

echo "Populating system" && {
	debootstrap --arch="$ARCH" "$RELEASE" /mnt
	}

echo "Setting hostname" && {
	echo "$HOSTNAME" > /mnt/etc/hostname
	}

echo "Copying system configs into target system" && {
	cp -r ../etc/ /mnt/
	cp -r ../tmp/ /mnt/
	}

echo "Chroot into system" && {
	mount --make-private --rbind /dev  /mnt/dev
	mount --make-private --rbind /proc /mnt/proc
	mount --make-private --rbind /sys  /mnt/sys
	chroot /mnt /usr/bin/env BOOTID=$BOOTID USER=$USER bash --login
	}

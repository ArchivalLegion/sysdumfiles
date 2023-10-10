#!/usr/bin/env bash
set -euo pipefail
#set -xv
export DEBIAN_FRONTEND=noninteractive

#DISK=/dev/disk/by-id/
#USER=user
#EFILABEL=ubuntu
#RELEASE=focal
#HOSTNAME=ubuntu
#BOOTID=ubuntu
#EPASS=password
#RLABEL=ubuntu

echo "Enter the following information" && {
	echo "Target disk id";read DISK
	DISK=/dev/disk/by-id/$DISK
	echo "User name";read USER
	#echo "Encryption password";read EPASS
	echo "Root partition label";read RLABEL
	echo "Computer name"; read HOSTNAME
	echo "Bootloader id";read BOOTID
	EFILABEL=$BOOTID
	echo "Which release should be installed?";read RELEASE
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
	sgdisk -n2:0:0 -t2:8300 $DISK -c2:$RLABEL
	echo "Waiting for partition symlinks to update"
	sleep 7
	}

echo "Creating Filesystems" && {
  	#echo -n "$EPASS" | cryptsetup luksFormat --type luks1 "$DISK-part2"
  	#echo "$EPASS" | cryptsetup luksOpen "$DISK-part2" $RLABEL
  	mkfs.ext4 -E discard,lazy_journal_init=0,lazy_itable_init=0 -L $RLABEL -m 1 -U time -v "$DISK-part2"
  	mount "$DISK-part2" /mnt
  	mkfs.vfat -F 32 -s 1 -v -n "$EFILABEL" "$DISK-part1"
  	mkdir -p /mnt/boot/efi
  	mount "$DISK-part1" /mnt/boot/efi
	}

echo "Populating system" && {
	debootstrap "$RELEASE" /mnt
	}

echo "Setting hostname" && {
	echo "$HOSTNAME" > /mnt/etc/hostname
	}

echo "Copying system configs into target system" && {
	cp -r ../etc/ /mnt/
	cp -r ../tmp/ /mnt/
	}

echo "Chroot into system" && {
	mount --make-private --rbind --make-rslave /dev  /mnt/dev
	mount --make-private --rbind --make-rslave /proc /mnt/proc
	mount --make-private --rbind --make-rslave /sys  /mnt/sys
	chroot /mnt /usr/bin/env BOOTID=$BOOTID USER=$USER bash --login
	}

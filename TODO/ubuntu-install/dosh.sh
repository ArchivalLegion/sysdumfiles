#!/usr/bin/env bash
set -euo pipefail
# set -xv

# Modify variables below, run script as root

# Select the target disk
DISK=/dev/disk/by-id/

# Encryption password
PASS=password

# Ubuntu / Debian release for debootstrap
RELEASE=focal

# System architecture: amd64,armhf,arm64,powerpc,ppc64el,i386,s390x
# amd64 = x86_64/64bit | i386 = x86/32bit
ARCH=amd64

# The dataset name: rpool/peanut_butter
RSET=peanut
UUID=butter
DSET="$RSET"_"$UUID"

# Username
USER=dauser

# Computer hostname
HOSTNAME=NewPlayer

# GRUB bootloader id
BOOTID=ubuntu-zfs

# Name of the EFI/FAT partition
EFILABEL=TUXZFS




set +e
echo "Disabling automount and stopping zed" && {
	gsettings set org.gnome.desktop.media-handling automount false
	systemctl stop zed
	zpool export -a
	}
set -e
echo "Setting mirrors and installing tools" && {
	apt update
	apt install -yq debootstrap gdisk zfsutils-linux
	}

echo "Wiping and partitioning drive" && {
	swapoff --all
	sgdisk --zap-all $DISK
	wipefs -af $DISK
	sgdisk -n1:1M:+64M -t1:EF00 $DISK -c1:$EFILABEL
	sgdisk -a1 -n5:0:+1000K -t5:EF02 $DISK -c5:legacy_boot
	sgdisk -n2:0:+1G -t2:8200 $DISK -c2:swap
	sgdisk -n3:0:+2G -t3:BE00 $DISK -c3:bpool
	sgdisk -n4:0:0 -t4:BF00 $DISK -c4:rpool
	echo "Waiting for partition symlinks to update"
	sleep 7
	}

echo "Creating bpool" && {
zpool create -f \
			 -o cachefile=/etc/zfs/zpool.cache \
			 -o ashift=12 \
			 -o autotrim=on \
			 -d \
			 -o feature@allocation_classes=enabled \
			 -o feature@async_destroy=enabled      \
			 -o feature@bookmarks=enabled          \
			 -o feature@embedded_data=enabled      \
			 -o feature@empty_bpobj=enabled        \
			 -o feature@enabled_txg=enabled        \
			 -o feature@extensible_dataset=enabled \
			 -o feature@filesystem_limits=enabled  \
			 -o feature@hole_birth=enabled         \
			 -o feature@large_blocks=enabled       \
			 -o feature@lz4_compress=enabled       \
			 -o feature@project_quota=enabled      \
			 -o feature@resilver_defer=enabled     \
			 -o feature@spacemap_histogram=enabled \
			 -o feature@spacemap_v2=enabled        \
			 -o feature@userobj_accounting=enabled \
			 -o feature@zpool_checkpoint=enabled   \
			 -O acltype=posixacl \
			 -O canmount=off \
			 -O compression=lz4 \
			 -O devices=off \
			 -O normalization=formD \
			 -O atime=off \
			 -O xattr=sa \
			 -O mountpoint=/boot \
			 -R /mnt \
bpool $DISK-part3
echo "bpool created!"
	}

echo "Creating rpool" && {
echo $PASS | \
zpool create -f \
			 -o cachefile=/etc/zfs/zpool.cache \
			 -o ashift=12 \
			 -o autotrim=on \
			 -O encryption=aes-256-gcm \
			 -O keylocation=prompt \
			 -O keyformat=passphrase \
			 -O acltype=posixacl \
			 -O canmount=off \
			 -O compression=lz4 \
			 -O dnodesize=auto \
			 -O normalization=formD \
			 -O atime=off \
			 -O xattr=sa \
			 -O mountpoint=/ \
			 -R /mnt \
rpool $DISK-part4
echo "rpool created"
	}

echo "Create filesystem datasets to act as containers" && {
	zfs create -o com.ubuntu.zsys:bootfs=yes -o canmount=off -o mountpoint=none rpool/ROOT
	zfs create -o canmount=off -o mountpoint=none bpool/BOOT
	}

echo "Create filesystem datasets for the root and boot filesystems" && {
	zfs create -o mountpoint=/ rpool/ROOT/"$DSET"
	zfs create -o mountpoint=/boot bpool/BOOT/"$DSET"
	}

echo "Create sub datasets" && {
	zfs create -o com.ubuntu.zsys:bootfs=no rpool/ROOT/"$DSET"/srv
	zfs create -o com.ubuntu.zsys:bootfs=no -o canmount=off rpool/ROOT/"$DSET"/usr
	zfs create rpool/ROOT/"$DSET"/usr/local
	zfs create -o com.ubuntu.zsys:bootfs=no -o canmount=off rpool/ROOT/"$DSET"/var
	zfs create rpool/ROOT/"$DSET"/var/games
	zfs create rpool/ROOT/"$DSET"/var/lib
	zfs create rpool/ROOT/"$DSET"/var/lib/AccountsService
	zfs create rpool/ROOT/"$DSET"/var/lib/apt
	zfs create rpool/ROOT/"$DSET"/var/lib/dpkg
	zfs create rpool/ROOT/"$DSET"/var/lib/NetworkManager
	zfs create rpool/ROOT/"$DSET"/var/log
	zfs create rpool/ROOT/"$DSET"/var/mail
	zfs create rpool/ROOT/"$DSET"/var/snap
	zfs create rpool/ROOT/"$DSET"/var/spool
	zfs create rpool/ROOT/"$DSET"/var/www
	mkdir /mnt/run
	mount -t tmpfs tmpfs /mnt/run
	mkdir /mnt/run/lock
	}

echo "Create root's dataset" && {
	zfs create -o canmount=off -o mountpoint=/ rpool/USERDATA
	zfs create -o com.ubuntu.zsys:bootfs-datasets=rpool/ROOT/$DSET -o canmount=on -o mountpoint=/root rpool/USERDATA/root_"$UUID"
	chmod 700 /mnt/root
	}

echo "Populating target system" && {
	debootstrap --arch="$ARCH" "$RELEASE" /mnt
	}

echo "Copying host zfs cache" && {
	mkdir /mnt/etc/zfs || true
	cp /etc/zfs/zpool.cache /mnt/etc/zfs/
	}

echo "Setting target hostname" && {
	echo "$HOSTNAME" > /mnt/etc/hostname
	}

echo "Copying system configs into target system" && {
	cp plzno-part2.sh /mnt/root/
	cp -r ../../etc/ /mnt/
	cp -r ../../tmp/ /mnt/
	}

echo "Chrooting into new system" && {
	mount --make-private --rbind /dev  /mnt/dev
	mount --make-private --rbind /proc /mnt/proc
	mount --make-private --rbind /sys  /mnt/sys
	chroot /mnt /usr/bin/env DSET=$DSET UUID=$UUID DISK=$DISK EFILABEL=$EFILABEL BOOTID=$BOOTID USER=$USER bash --login
	}

echo "Welcome back! unmounting target" && {
	mount | grep -v zfs | tac | awk '/\/mnt/ {print $3}' | xargs -i{} umount -lf {} && zpool export -a
	}

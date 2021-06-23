#!/usr/bin/env bash
set -euo pipefail
#set -xv
# Doing this by hand has crushed my soul.
# Modify variables below,then run script as root

# Select the target disk
export DISK=/dev/disk/by-id/

# Encryption password
PASS=password

# Ubuntu / Debian release for debootstrap
RELEASE=focal

# System architecture: amd64,armhf,arm64,powerpc,ppc64el,i386,s390x
ARCH=amd64

# The dataset naming scheme: rpool/peanut_butter
export RDATASET=peanut
export UUID=butter

# Username, lowercase only
export USER=dauser

# Computer hostname
HOSTNAME=ArchivalLegion

# GRUB bootloader id
export BOOTID=ubuntu

# Name of the EFI/FAT partition
export EFILABEL=FATT


echo "Disabling automount and stopping zed" && {
gsettings set org.gnome.desktop.media-handling automount false
systemctl stop zed
killall zed || true
zpool export -a
}

echo "Setting mirrors and installing tools" && {
rm /etc/apt/sources.list || true
cp -r etc/apt/sources.list.d/* /etc/apt/sources.list.d/
apt update
apt install --yes debootstrap gdisk zfs-initramfs
}

echo "Wiping and partitioning drive" && {
sgdisk --zap-all $DISK
wipefs -af $DISK
sgdisk -n1:1M:+256M -t1:EF00 $DISK -c1:$EFILABEL
sgdisk -a1 -n5:0:+1000K -t5:EF02 $DISK -c5:LEGACY_BOOT
sgdisk -n2:0:+16G -t2:8200 $DISK -c2:SWAP
sgdisk -n3:0:+4G -t3:BE00 $DISK -c3:BPOOL
sgdisk -n4:0:0 -t4:BF00 $DISK -c4:RPOOL
}
echo "Waiting for partition symlinks to update" && {
udevadm settle --timeout 7 || true
ls -l /dev/disk/by-id/ | grep -i "$DISK" -
}

echo "Creating bpool" && {
zpool create -f \
-o cachefile=/etc/zfs/zpool.cache \
-o ashift=12 -o autotrim=on -d \
-o feature@async_destroy=enabled \
-o feature@bookmarks=enabled \
-o feature@embedded_data=enabled \
-o feature@empty_bpobj=enabled \
-o feature@enabled_txg=enabled \
-o feature@extensible_dataset=enabled \
-o feature@filesystem_limits=enabled \
-o feature@hole_birth=enabled \
-o feature@large_blocks=enabled \
-o feature@lz4_compress=enabled \
-o feature@spacemap_histogram=enabled \
-O acltype=posixacl -O canmount=off -O compression=lz4 \
-O devices=off -O normalization=formD -O atime=off -O xattr=sa \
-O mountpoint=/boot -R /mnt \
bpool $DISK-part3
}

echo "Creating rpool" && {
echo $PASS | zpool create -f \
-o ashift=12 -o autotrim=on \
-O encryption=aes-256-gcm -O keylocation=prompt -O keyformat=passphrase \
-O acltype=posixacl -O canmount=off -O compression=lz4 \
-O dnodesize=auto -O normalization=formD -O atime=off -O xattr=sa \
-O mountpoint=/ -R /mnt \
rpool $DISK-part4
}

echo "Create filesystem datasets to act as containers" && {
zfs create -o canmount=off -o mountpoint=none rpool/ROOT
zfs create -o canmount=off -o mountpoint=none bpool/BOOT
}

echo "Create filesystem datasets for the root and boot filesystems" && {
zfs create -o mountpoint=/ -o com.ubuntu.zsys:bootfs=yes -o com.ubuntu.zsys:last-used=$(date +%s) rpool/ROOT/"$RDATASET"_"$UUID"
zfs create -o mountpoint=/boot bpool/BOOT/"$RDATASET"_"$UUID"
}

echo "Create more sub datasets" && {
zfs create -o com.ubuntu.zsys:bootfs=no rpool/ROOT/"$RDATASET"_"$UUID"/srv
zfs create -o com.ubuntu.zsys:bootfs=no -o canmount=off rpool/ROOT/"$RDATASET"_"$UUID"/usr
zfs create rpool/ROOT/"$RDATASET"_"$UUID"/usr/local
zfs create -o com.ubuntu.zsys:bootfs=no -o canmount=off rpool/ROOT/"$RDATASET"_"$UUID"/var
zfs create rpool/ROOT/"$RDATASET"_"$UUID"/var/games
zfs create rpool/ROOT/"$RDATASET"_"$UUID"/var/lib
zfs create rpool/ROOT/"$RDATASET"_"$UUID"/var/lib/AccountsService
zfs create rpool/ROOT/"$RDATASET"_"$UUID"/var/lib/apt
zfs create rpool/ROOT/"$RDATASET"_"$UUID"/var/lib/dpkg
zfs create rpool/ROOT/"$RDATASET"_"$UUID"/var/lib/flatpak
zfs create rpool/ROOT/"$RDATASET"_"$UUID"/var/lib/NetworkManager
zfs create rpool/ROOT/"$RDATASET"_"$UUID"/var/lib/snapd
zfs create rpool/ROOT/"$RDATASET"_"$UUID"/var/log
zfs create rpool/ROOT/"$RDATASET"_"$UUID"/var/mail
zfs create rpool/ROOT/"$RDATASET"_"$UUID"/var/snap
zfs create rpool/ROOT/"$RDATASET"_"$UUID"/var/spool
zfs create rpool/ROOT/"$RDATASET"_"$UUID"/var/www
zfs create -o com.ubuntu.zsys:bootfs=no rpool/ROOT/"$RDATASET"_"$UUID"/tmp
chmod 1777 /mnt/tmp
}

echo "Create root user's dataset" && {
zfs create -o canmount=off -o mountpoint=/ rpool/USERDATA
zfs create -o com.ubuntu.zsys:bootfs-datasets=rpool/ROOT/"$RDATASET"_"$UUID" -o canmount=on -o mountpoint=/root rpool/USERDATA/root
chmod 700 /mnt/root
}

echo "Creating base system" && {
debootstrap --arch=$ARCH "$RELEASE" /mnt
}

echo "Copying zfs cache" && {
mkdir /mnt/etc/zfs
cp /etc/zfs/zpool.cache /mnt/etc/zfs/
}

echo "Setting hostname" && {
echo "$HOSTNAME" > /mnt/etc/hostname
}

echo "Copying system config and scripts into target system" && {
cp plzno* /mnt/root/
cp -r etc/ /mnt/
cp -r tmp/ /mnt/
}

echo "Chrooting into install" && {
mount --rbind /dev  /mnt/dev
mount --rbind /proc /mnt/proc
mount --rbind /sys  /mnt/sys
chroot /mnt /usr/bin/env RDATASET=$RDATASET UUID=$UUID DISK=$DISK EFILABEL=$EFILABEL BOOTID=$BOOTID USER=$USER bash --login
}

echo "Welcome! System chrooted"

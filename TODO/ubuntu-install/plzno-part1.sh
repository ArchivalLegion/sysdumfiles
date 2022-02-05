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
ARCH=amd64
# amd64 = x86_64/64bit | i386 = x86/32bit

# The dataset name: rpool/peanut_butter
RDATASET=peanut
UUID=butter

# Username
USER=dauser

# Computer hostname
HOSTNAME=NewPlayer

# GRUB bootloader id
BOOTID=ubuntu_$RELEASE

# Name of the EFI/FAT partition
EFILABEL=tuxzfs


echo "Disabling automount and stopping zed" && {
gsettings set org.gnome.desktop.media-handling automount false
systemctl stop zed
killall zed || true
zpool export -a
}

echo "Setting mirrors and installing tools" && {
rm /etc/apt/sources.list || true
cp -r ../../etc/apt/sources.list.d/* /etc/apt/sources.list.d/
apt update
apt install -yq debootstrap gdisk zfs-initramfs
}

echo "Wiping and partitioning drive" && {
swapoff --all
sgdisk --zap-all $DISK
wipefs -af $DISK
sgdisk -n1:1M:+256M -t1:EF00 $DISK -c1:$EFILABEL
sgdisk -a1 -n5:0:+1000K -t5:EF02 $DISK -c5:LEGACY_BOOT
sgdisk -n2:0:+1G -t2:8200 $DISK -c2:SWAP
sgdisk -n3:0:+4G -t3:BE00 $DISK -c3:BPOOL
sgdisk -n4:0:0 -t4:BF00 $DISK -c4:RPOOL
echo "Waiting for partition symlinks to update"
sleep 7
}

echo "Creating bpool" && {
zpool create -f \
-d \
-o cachefile=/etc/zfs/zpool.cache \
-o ashift=12 \
-o autotrim=on \
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
echo "bpool done"
}

echo "Creating rpool" && {
echo $PASS | zpool create -f \
-o cachefile=/etc/zfs/zpool.cache \
-o ashift=12 \
-o autotrim=on \
-O encryption=aes-256-gcm -O keylocation=prompt -O keyformat=passphrase \
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
echo "rpool done"
}

echo "Create filesystem datasets to act as containers" && {
zfs create -o canmount=off -o mountpoint=none rpool/ROOT
zfs create -o canmount=off -o mountpoint=none bpool/BOOT
}

echo "Create filesystem datasets for the root and boot filesystems" && {
zfs create -o mountpoint=/ rpool/ROOT/"$RDATASET"_"$UUID"
zfs create -o mountpoint=/boot bpool/BOOT/"$RDATASET"_"$UUID"
}

echo "Create sub datasets" && {
zfs create rpool/ROOT/"$RDATASET"_"$UUID"/srv
zfs create rpool/ROOT/"$RDATASET"_"$UUID"/usr
zfs create rpool/ROOT/"$RDATASET"_"$UUID"/usr/local
zfs create rpool/ROOT/"$RDATASET"_"$UUID"/var
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
zfs create rpool/ROOT/"$RDATASET"_"$UUID"/tmp
chmod 1777 /mnt/tmp
}

echo "Create root's dataset" && {
zfs create -o canmount=off -o mountpoint=/ rpool/USERDATA
zfs create -o canmount=on -o mountpoint=/root rpool/USERDATA/root
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
cp -r /../../etc/ /mnt/
cp -r /../../tmp/ /mnt/
}

echo "Chrooting into new system" && {
mount --make-private --rbind /dev  /mnt/dev
mount --make-private --rbind /proc /mnt/proc
mount --make-private --rbind /sys  /mnt/sys
chroot /mnt /usr/bin/env RDATASET=$RDATASET UUID=$UUID DISK=$DISK EFILABEL=$EFILABEL BOOTID=$BOOTID USER=$USER bash --login
}

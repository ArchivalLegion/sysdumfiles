#!/bin/bash

# Doing this by hand has crushed my soul.
# Start by modifying variables below, then
# run script as root ( sudo -i )

export DISK=/dev/disk/by-id/
export RDATASET=
export UUID=
export USER=
export HOSTNAME=
export BOOTID=
export RELEASE=focal
export PASS=
export USERPASS=
export EFILABEL=

systemctl stop zed &&


apt update &&


zpool export -a &&


gsettings set org.gnome.desktop.media-handling automount false &&


apt install --yes debootstrap gdisk zfs-initramfs &&


sgdisk --zap-all $DISK &&


wipefs -af $DISK &&


sgdisk -n1:1M:+128M -t1:EF00 $DISK &&


sgdisk -a1 -n5:24K:+1000K -t5:EF02 $DISK &&


sgdisk -n2:0:+2G -t2:8200 $DISK &&


sgdisk -n3:0:+2G -t3:BE00 $DISK &&


sgdisk -n4:0:0 -t4:BF00 $DISK &&


sync &&
sleep 7 &&
ls -l /dev/disk/by-id/ &&


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
-O devices=off -O normalization=formD -O relatime=on -O xattr=sa \
-O mountpoint=/boot -R /mnt \
bpool $DISK-part3

echo "Boot pool"

echo $PASS | zpool create -f \
-o ashift=12 -o autotrim=on \
-O encryption=aes-256-gcm \
-O keylocation=prompt -O keyformat=passphrase \
-O acltype=posixacl -O canmount=off -O compression=lz4 \
-O dnodesize=auto -O normalization=formD -O relatime=on \
-O xattr=sa -O mountpoint=/ -R /mnt \
rpool $DISK-part4

echo "Root pool"

zfs create -o canmount=off -o mountpoint=none rpool/ROOT
zfs create -o canmount=off -o mountpoint=none bpool/BOOT
zfs create -o mountpoint=/ \
-o com.ubuntu.zsys:bootfs=yes \
-o com.ubuntu.zsys:last-used=$(date +%s) rpool/ROOT/"$RDATASET"_"$UUID"
zfs create -o mountpoint=/boot bpool/BOOT/"$RDATASET"_"$UUID"



zfs create -o com.ubuntu.zsys:bootfs=no \
rpool/ROOT/"$RDATASET"_"$UUID"/srv
zfs create -o com.ubuntu.zsys:bootfs=no -o canmount=off \
rpool/ROOT/"$RDATASET"_"$UUID"/usr
zfs create rpool/ROOT/"$RDATASET"_"$UUID"/usr/local
zfs create -o com.ubuntu.zsys:bootfs=no -o canmount=off \
rpool/ROOT/"$RDATASET"_"$UUID"/var
zfs create rpool/ROOT/"$RDATASET"_"$UUID"/var/games
zfs create rpool/ROOT/"$RDATASET"_"$UUID"/var/lib
zfs create rpool/ROOT/"$RDATASET"_"$UUID"/var/lib/AccountsService
zfs create rpool/ROOT/"$RDATASET"_"$UUID"/var/lib/apt
zfs create rpool/ROOT/"$RDATASET"_"$UUID"/var/lib/dpkg
zfs create rpool/ROOT/"$RDATASET"_"$UUID"/var/lib/NetworkManager
zfs create rpool/ROOT/"$RDATASET"_"$UUID"/var/log
zfs create rpool/ROOT/"$RDATASET"_"$UUID"/var/mail
zfs create rpool/ROOT/"$RDATASET"_"$UUID"/var/snap
zfs create rpool/ROOT/"$RDATASET"_"$UUID"/var/spool
zfs create rpool/ROOT/"$RDATASET"_"$UUID"/var/www
zfs create -o com.ubuntu.zsys:bootfs=no \
rpool/ROOT/"$RDATASET"_"$UUID"/tmp
chmod 1777 /mnt/tmp &&



zfs create -o canmount=off -o mountpoint=/ \
rpool/USERDATA
zfs create -o com.ubuntu.zsys:bootfs-datasets=rpool/ROOT/"$RDATASET"_"$UUID" \
-o canmount=on -o mountpoint=/root \
rpool/USERDATA/root_"$UUID"
chmod 700 /mnt/root &&



mkdir /mnt/run &&
mount -t tmpfs tmpfs /mnt/run &&
mkdir /mnt/run/lock &&


debootstrap "$RELEASE" /mnt &&


mkdir /mnt/etc/zfs &&
cp /etc/zfs/zpool.cache /mnt/etc/zfs/ &&


echo "$HOSTNAME" > /mnt/etc/hostname


cp plzno-part2.sh /mnt/root/ &&


cp -r etc/ /mnt/ &&


mount --rbind /dev  /mnt/dev &&
mount --rbind /proc /mnt/proc &&
mount --rbind /sys  /mnt/sys &&
chroot /mnt /usr/bin/env RDATASET=$RDATASET EFILABEL=$EFILABEL DISK=$DISK UUID=$UUID USER=$USER HOSTNAME=$HOSTNAME BOOTID=$BOOTID bash --login

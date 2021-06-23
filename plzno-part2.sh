#!/usr/bin/env bash
set -euo pipefail

echo "Update package index, setup system, and install needed packages" && {
apt update
dpkg-reconfigure locales tzdata keyboard-configuration console-setup
apt install --yes nano dosfstools cryptsetup curl patch ubuntu-standard grub-efi-amd64 grub-efi-amd64-signed linux-image-generic shim-signed zfs-initramfs
}

echo "Format EFI partition and bind /boot/efi/grub" && {
mkdosfs -F 32 -n "$EFILABEL" "$DISK"-part1
mkdir /boot/efi
echo /dev/disk/by-uuid/$(blkid -s UUID -o value $DISK-part1) /boot/efi vfat defaults 0 0 >> /etc/fstab
mount /boot/efi
mkdir /boot/efi/grub /boot/grub
echo /boot/efi/grub /boot/grub none defaults,bind 0 0 >> /etc/fstab
mount /boot/grub
}

echo "Encrypt swap partition" && {
echo swap $DISK-part2 /dev/urandom swap,cipher=aes-xts-plain64:sha256,size=512 >> /etc/crypttab
echo /dev/mapper/swap none swap defaults 0 0 >> /etc/fstab
}

echo "Adding system groups" && {
addgroup --system lpadmin
addgroup --system lxd
addgroup --system sambashare
addgroup --system gpio
addgroup --system i2c
addgroup --system input
addgroup --system spi
}

echo "Patch a dependency loop" && {
curl https://launchpadlibrarian.net/478315221/2150-fix-systemd-dependency-loops.patch | \
sed "s|/etc|/lib|;s|\.in$||" | (cd / ; sudo patch -p1)
}

echo "Rebuild kernel images and install GRUB" && {
update-initramfs -c -k all
update-grub
grub-install --target=x86_64-efi --efi-directory=/boot/efi \
--bootloader-id=$BOOTID --recheck --compress=no
grub-install --target=x86_64-efi --efi-directory=/boot/efi \
--bootloader-id=$BOOTID --recheck --compress=no --removable
}

echo "Copy zfs cache" && {
mkdir /etc/zfs/zfs-list.cache
touch /etc/zfs/zfs-list.cache/bpool
touch /etc/zfs/zfs-list.cache/rpool
ln -s /usr/lib/zfs-linux/zed.d/history_event-zfs-list-cacher.sh /etc/zfs/zed.d
echo "Running zed" && {
timeout -s 15 -k 10 zed -F || true
echo "Fixing filesystem mounts"
sed -Ei "s|/mnt/?|/|" /etc/zfs/zfs-list.cache/bpool
sed -Ei "s|/mnt/?|/|" /etc/zfs/zfs-list.cache/rpool
echo "sed finished"
}

echo "Create user dataset" && {
ROOT_DS=$(zfs list -o name | awk '/ROOT\/"$RDATASET"_/{print $1;exit}')
zfs create -o com.ubuntu.zsys:bootfs-datasets=$ROOT_DS -o canmount=on -o mountpoint=/home/$USER rpool/USERDATA/"$USER"
adduser "$USER"
}

echo "Copy skeleton to new user" && {
cp -a /etc/skel/. /home/$USER
chown -R $USER:$USER /home/$USER
usermod -a -G adm,cdrom,dip,lpadmin,lxd,plugdev,sambashare,sudo,gpio,i2c,input,spi $USER
}

echo "Disable log compression" && {
for file in /etc/logrotate.d/* ; do
    if grep -Eq "(^|[^#y])compress" "$file" ; then
        sed -i -r "s/(^|[^#y])(compress)/\1#\2/" "$file"
    fi
done
}

echo "Create inital system snapshot" && {
zfs snapshot bpool/BOOT/"$RDATASET"_"$UUID"@bpool_install
zfs snapshot rpool/ROOT/"$RDATASET"_"$UUID"@rpool_install
}

echo "Finished! Enjoy the system"

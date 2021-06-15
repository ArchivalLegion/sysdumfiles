#!/bin/bash

apt update &&


dpkg-reconfigure locales tzdata keyboard-configuration console-setup &&


apt install --yes nano &&


apt install --yes dosfstools &&



mkdosfs -F 32 -s 1 -n "$EFILABEL" "$DISK"-part1 &&
mkdir /boot/efi &&
echo /dev/disk/by-uuid/$(blkid -s UUID -o value $DISK-part1) \
/boot/efi vfat defaults 0 0 >> /etc/fstab &&
mount /boot/efi &&



mkdir /boot/efi/grub /boot/grub &&
echo /boot/efi/grub /boot/grub none defaults,bind 0 0 >> /etc/fstab &&
mount /boot/grub &&



apt install --yes \
grub-efi-amd64 grub-efi-amd64-signed linux-image-generic \
shim-signed zfs-initramfs &&



apt remove --purge --yes os-prober &&


apt install --yes cryptsetup &&



echo swap $DISK-part2 /dev/urandom \
swap,cipher=aes-xts-plain64:sha256,size=512 >> /etc/crypttab &&
echo /dev/mapper/swap none swap defaults 0 0 >> /etc/fstab &&


addgroup --system lpadmin &&
addgroup --system lxd &&
addgroup --system sambashare &&


sudo apt install --yes curl patch &&


curl https://launchpadlibrarian.net/478315221/2150-fix-systemd-dependency-loops.patch | \
sed "s|/etc|/lib|;s|\.in$||" | (cd / ; sudo patch -p1) &&


update-initramfs -c -k all &&


update-grub &&


grub-install --target=x86_64-efi --efi-directory=/boot/efi \
--bootloader-id=$BOOTID --recheck --compress=no --removable &&


mkdir /etc/zfs/zfs-list.cache &&
touch /etc/zfs/zfs-list.cache/bpool &&
touch /etc/zfs/zfs-list.cache/rpool &&
ln -s /usr/lib/zfs-linux/zed.d/history_event-zfs-list-cacher.sh /etc/zfs/zed.d &&
echo "WAIT 10 seconds and kill zed"
zed -Fvf &&


sed -Ei "s|/mnt/?|/|" /etc/zfs/zfs-list.cache/bpool &&
sed -Ei "s|/mnt/?|/|" /etc/zfs/zfs-list.cache/rpool &&


ROOT_DS=$(zfs list -o name | awk '/ROOT\/"$RDATASET"_/{print $1;exit}')
zfs create -o com.ubuntu.zsys:bootfs-datasets=$ROOT_DS \
-o canmount=on -o mountpoint=/home/$USER \
rpool/USERDATA/"$USER"_"$UUID" &&
adduser "$USER" &&


cp -a /etc/skel/. /home/$USER &&
chown -R $USER:$USER /home/$USER &&
usermod -a -G adm,cdrom,dip,lpadmin,lxd,plugdev,sambashare,sudo $USER &&


apt dist-upgrade --yes &&


apt install --yes ubuntu-standard &&


for file in /etc/logrotate.d/* ; do
    if grep -Eq "(^|[^#y])compress" "$file" ; then
        sed -i -r "s/(^|[^#y])(compress)/\1#\2/" "$file"
    fi
done

zfs snapshot bpool/BOOT/"$RDATASET"_"$UUID"@install &&
zfs snapshot rpool/ROOT/"$RDATASET"_"$UUID"@install &&

echo "If you've gotten this far, stop being lazy, set root password, do zed -F &"

echo "firefox https://openzfs.github.io/openzfs-docs/Getting%20Started/Ubuntu/Ubuntu%2020.04%20Root%20on%20ZFS.html#step-5-grub-installation &"

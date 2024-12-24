#!/bin/bash
#
# palen1x build script
# Made with <3 https://github.com/palera1n/palen1x
# Modified from https://github.com/asineth0/checkn1x & https://github.com/raspberryenvoie/odysseyn1x :3
#
# Modified by dk865 to integrate chroot support.

[ "$(id -u)" -ne 0 ] && {
    echo 'Please run as root'
    exit 1
}

GREEN="$(tput setaf 2)"
BLUE="$(tput setaf 6)"
NORMAL="$(tput sgr0)"

while [ -z "$VERSION" ]; do
    printf 'Version: '
    read -r VERSION
done

until [ "$ARCH" = 'x86_64' ] || [ "$ARCH" = 'x86' ] || [ "$ARCH" = 'aarch64' ] || [ "$ARCH" = 'armv7' ]; do
    echo '1 x86_64'
    echo '2 x86'
    echo '3 aarch64'
    echo '4 armv7'
    printf 'Which architecture? x86_64 (default), x86, or aarch64 or armv7: '
    read -r input_arch
    [ "$input_arch" = 1 ] && ARCH='x86_64'
    [ "$input_arch" = 2 ] && ARCH='x86'
    [ "$input_arch" = 3 ] && ARCH='aarch64'
    [ "$input_arch" = 4 ] && ARCH='armv7'
    [ -z "$input_arch" ] && ARCH='x86_64'
done

apt-get update
apt-get install -y --no-install-recommends wget gawk debootstrap mtools ca-certificates curl libusb-1.0-0-dev gcc make gzip xz-utils unzip libc6-dev

download_version=$(curl -s https://api.github.com/repos/palera1n/palera1n/releases | grep -m 1 -o '"tag_name": "[^"]*' | sed 's/"tag_name": "//')

PALERA1N_PREFIX="https://github.com/palera1n/palera1n/releases/download/$download_version/palera1n-linux-"
USBMUXD_PREFIX="https://cdn.nickchan.lol/palera1n/artifacts/usbmuxd-static/usbmuxd-linux-"
PATH_VERSION="v3.20"
ROOTFS_VERSION="3.20.0"
ROOTFS_PREFIX="https://dl-cdn.alpinelinux.org/alpine/${PATH_VERSION}/releases"

case "$ARCH" in
    'x86_64')
        ROOTFS="${ROOTFS_PREFIX}/x86_64/alpine-minirootfs-${ROOTFS_VERSION}-x86_64.tar.gz"
        PALERA1N="${PALERA1N_PREFIX}x86_64"
        USBMUXD="${USBMUXD_PREFIX}x86_64"
        ;;
    'x86')
        ROOTFS="${ROOTFS_PREFIX}/x86/alpine-minirootfs-${ROOTFS_VERSION}-x86.tar.gz"
        PALERA1N="${PALERA1N_PREFIX}x86"
        USBMUXD="${USBMUXD_PREFIX}x86"
        ;;
    'aarch64')
        ROOTFS="${ROOTFS_PREFIX}/aarch64/alpine-minirootfs-${ROOTFS_VERSION}-aarch64.tar.gz"
        PALERA1N="${PALERA1N_PREFIX}arm64"
        USBMUXD="${USBMUXD_PREFIX}arm64"
        ;;
    'armv7')
        ROOTFS="${ROOTFS_PREFIX}/armv7/alpine-minirootfs-${ROOTFS_VERSION}-armv7.tar.gz"
        PALERA1N="${PALERA1N_PREFIX}armel"
        USBMUXD="${USBMUXD_PREFIX}armel"
    ;;
esac

echo $PALERA1N
echo $USBMUXD
echo $ROOTFS

# Clean
umount -v work/rootfs/{dev,sys,proc} >/dev/null 2>&1
rm -rf work
mkdir -pv work/rootfs
cd work

curl -sL "$ROOTFS" | tar -xzC rootfs
mount -vo bind /dev rootfs/dev
mount -vt sysfs sysfs rootfs/sys
mount -vt proc proc rootfs/proc
cp /etc/resolv.conf rootfs/etc
cat << ! > rootfs/etc/apk/repositories
http://dl-cdn.alpinelinux.org/alpine/v3.14/main
http://dl-cdn.alpinelinux.org/alpine/edge/community
http://dl-cdn.alpinelinux.org/alpine/edge/testing
!

sleep 2

#
cat << ! | chroot rootfs /usr/bin/env PATH=/usr/bin:/usr/local/bin:/bin:/usr/sbin:/sbin /bin/sh
apk update
apk upgrade
apk add bash alpine-base ncurses udev openssh-client sshpass newt
apk add --no-scripts linux-lts linux-firmware-none
rc-update add bootmisc
rc-update add hwdrivers
rc-update add udev
rc-update add udev-trigger
rc-update add udev-settle
!

# kernel modules
cat << ! > rootfs/etc/mkinitfs/features.d/palen1x.modules
kernel/drivers/usb/host
kernel/drivers/hid/usbhid
kernel/drivers/hid/hid-generic.ko
kernel/drivers/hid/hid-cherry.ko
kernel/drivers/hid/hid-apple.ko
kernel/net/ipv4
!

chroot rootfs /usr/bin/env PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin \
	/sbin/mkinitfs -F "palen1x" -k -t /tmp -q $(ls rootfs/lib/modules)
rm -rf rootfs/lib/modules
mv -v rootfs/tmp/lib/modules rootfs/lib

find 'rootfs/lib/modules' -type f -name "*.ko" -exec strip -v --strip-unneeded {} +
find 'rootfs/lib/modules' -type f -name "*.ko" -exec xz --x86 -ze9T0 {} +

depmod -b rootfs $(ls rootfs/lib/modules)

# create config crap
echo 'palen1x' > rootfs/etc/hostname
echo "PATH=$PATH:$HOME/.local/bin" > rootfs/root/.bashrc # d
echo "export PALEN1X_VERSION='$VERSION'" > rootfs/root/.bashrc
echo '/usr/bin/palen1x_menu' >> rootfs/root/.bashrc
echo "Rootless" > rootfs/usr/bin/.jbtype
echo "-l" > rootfs/usr/bin/.args

# Unmount fs
umount -v rootfs/{dev,sys,proc}

#
curl -Lo rootfs/usr/bin/palera1n "$PALERA1N"
chmod +x rootfs/usr/bin/palera1n

curl -Lo rootfs/usr/sbin/usbmuxd "$USBMUXD"
chmod +x rootfs/usr/sbin/usbmuxd

cp -av ../inittab rootfs/etc
cp -v ../scripts/* rootfs/usr/bin
chmod -v 755 rootfs/usr/local/bin/*
ln -sv sbin/init rootfs/init
ln -sv ../../etc/terminfo rootfs/usr/share/terminfo # fix ncurses

rm -rf tmp/* boot/* var/cache/* # etc/resolv.conf
# Let's keep networking support...

cat << EOF > ../run.sh
echo 'palen1x-chroot $VERSION'
echo 'Enter your sudo password when/if prompted'
sudo -v

echo "Mounting stuff..."
sudo mount --bind /etc/resolv.conf "palen1x/rootfs/etc/resolv.conf"
sudo mount --bind /dev "palen1x/rootfs/dev"
sudo mount --bind /proc "palen1x/rootfs/proc"
sudo mount --bind /sys "palen1x/rootfs/sys"
sudo mount --bind /run "palen1x/rootfs/run"

# Enter chroot environment
echo "Entering chroot environment..."
clear
sudo chroot "palen1x/rootfs" /bin/bash

echo "Exiting chroot environment..."
echo "Unmounting stuff (you may need to re-enter your sudo password)"
sudo umount "palen1x/rootfs/etc/resolv.conf"
sudo umount "palen1x/rootfs/dev"
sudo umount "palen1x/rootfs/proc"
sudo umount "palen1x/rootfs/sys"
sudo umount "palen1x/rootfs/run"

echo "Done!"
sleep 1
exit

EOF


cd ..
chmod -R a+rw .
chmod +x run.sh
rm -rf palen1x
mv work palen1x
echo 'Finished setting up! You may run ./run.sh to enter the enviornment.'

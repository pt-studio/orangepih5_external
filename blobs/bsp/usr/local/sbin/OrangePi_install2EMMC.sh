#!/bin/bash
set -x

command -v kpartx >/dev/null 2>&1 || { echo >&2 "kpartx not installed. Aborting."; exit 1; }
command -v rsync >/dev/null 2>&1 || { echo >&2 "rsync not installed. Aborting."; exit 1; }

if [ "$(id -u)" != "0" ]; then
   echo "Script must be run as root !"
   exit 0
fi

#----------------------------------------------------------
echo ""
echo -n "WARNING: EMMC WILL BE ERASED !, Continue (y/N)?  "
read -n 1 ANSWER

if [ ! "${ANSWER}" = "y" ] ; then
    echo "."
    echo "Canceled.."
    exit 0
fi
echo ""

#----------------------------------------------------------
emmc="/dev/mmcblk0"
boot0="/boot/boot0.bin"
uboot="/boot/uboot.bin"

# Partition Setup
boot0_position=8      # KiB
uboot_position=16400  # KiB
part_position=20480   # KiB
boot_size=64          # MiB

echo "Erasing EMMC..."
dd if=/dev/zero bs=1M count=32 of="$emmc"
sync

echo 'Install Bootloader'
echo '> SPL'
dd if="$boot0" conv=notrunc bs=1k seek=$boot0_position of="$emmc"
echo '> uBoot'
dd if="$uboot" conv=notrunc bs=1k seek=$uboot_position of="$emmc"
sync

echo "Creating new filesystem on EMMC..."
cat <<EOF | fdisk "$IMAGE"
o
n
p
1
$((part_position*2))
+${boot_size}M
t
c
n
p
2
$((part_position*2 + boot_size*1024*2))

t
2
83
w
EOF
sync

kpartx -u $emmc

bootdevice="${emmc}p1"
rootdevice="${emmc}p2"

bootfs_mount="/tmp/orangepi_bootfs"
rootfs_mount="/tmp/orangepi_rootfs"

echo "Copying files to /boot directory"
[[ -d $bootfs_mount ]] && umount $bootfs_mount >/dev/null 2>&1 || true
mkdir -p $bootfs_mount
mount -t vfat $bootdevice $bootfs_mount
rsync -rLtWh --info=progress2,stats1 /boot/ $bootfs_mount/
sync
umount $bootfs_mount

echo "Copying files to root directory"

[[ -d $rootfs_mount ]] && umount $rootfs_mount >/dev/null 2>&1 || true

mkdir -p $rootfs_mount
mount -t ext4 $rootdevice $rootfs_mount

# Add rootfs into Image
rsync -aHWXh \
	--exclude="/boot/*" \
	--exclude="/dev/*" \
	--exclude="/proc/*" \
	--exclude="/run/*" \
	--exclude="/tmp/*" \
	--exclude="/sys/*" \
	--info=progress2,stats1 / $rootfs_mount

echo "Creating uEnv.txt"
cat << EOF > $bootfs_mount/uEnv.txt
console=tty0 console=ttyS0,115200n8 no_console_suspend
cma=96M
kernel_filename=orangepi/uImage
initrd_filename=initrd.gz

EOF

echo "Creating fstab"
cat << EOF > $rootfs_mount/etc/fstab
# Created by OrangePi_install2EMMC.sh
$bootdevice  /boot        vfat  defaults                              1 2
$rootdevice  /            ext4  errors=remount-ro,noatime,nodiratime  1 1
tmpfs           /tmp         tmpfs nodev,nosuid,mode=1777                0 0

EOF

sync

umount $rootfs_mount
rm -rf $rootfs_mount

echo "Done."

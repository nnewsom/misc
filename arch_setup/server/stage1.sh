#!/bin/bash

# this setup script is specifically for EFI systems
# could be modified for BIOS but why bother in this day in age
# to enable EFI on vbox: VM->Settings->System->Motherboard check and enable "Enable EFI (special OSes only)"

# the script creates an encrypted LVM with 100% space allocated to root (/)
# with no swap by default. it will chroot into the build env on completion
# to execute stage2


DEVICE="$1"
if [ -z "$DEVICE" ]
    then
        echo "need path of disk to install. ie. /dev/sda, /dev/nvme0n1";
        exit 1;
fi

if [[ "$DEVICE" =~ ^/dev/nvme0.* ]]
    then
        PART_EFI="$DEVICE"p1;
        PART_ROOT="$DEVICE"p2;
    else
        PART_EFI="$DEVICE"1;
        PART_ROOT="$DEVICE"2;
fi

echo -e "target: $DEVICE\nEFI: $PART_EFI\nROOT: $PART_ROOT"
read -p "look correct? (y/N): " confirm && [[ $confirm == [yY] ]] || exit 1

INSTALL_PACKAGES="arch-install-scripts"
PACSTRAP_PACKAGES=\
"base base-devel efibootmgr vim dialog xterm btrfs-progs "\
"grub mkinitcpio linux linux-firmware pacman-contrib intel-ucode"

pacman -Sy
pacman -S $INSTALL_PACKAGES --noconfirm

cat << EOF | parted $DEVICE
rm 1
rm 2
rm 3
rm 4
mklabel gpt
mkpart ESP fat32 1Mib 512Mib
set 1 boot on
name 1 efi
mkpart primary 512Mib 100%
set 2 root on
name 2 root
print
quit
EOF

mkfs.fat -F32 "$PART_EFI"
mkfs.btrfs -L root "$PART_ROOT"

mount "$PART_ROOT" /mnt
mkdir -p /mnt/boot
mount "$PART_EFI" /mnt/boot

lsblk -f
read -p "partiions correct? (y/N): " confirm && [[ $confirm == [yY] ]] || exit 1
pacstrap /mnt $PACSTRAP_PACKAGES --noconfirm
genfstab -U -p /mnt > /mnt/etc/fstab

cp ./stage2.sh /mnt/stage2.sh
chmod +x /mnt/stage2.sh

echo "stage1 complete. dropping into build root chroot. exec or modify stage2.sh to continue"
arch-chroot /mnt /bin/bash
echo "build complete"

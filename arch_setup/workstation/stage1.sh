#!/bin/bash

# this setup script is specifically for EFI systems
# could be modified for BIOS but why bother in this day in age
# to enable EFI on vbox: VM->Settings->System->Motherboard check and enable "Enable EFI (special OSes only)"

# the script creates an encrypted LVM with 100% space allocated to root (/)
# with no swap by default. it will chroot into the build env on completion
# to execute stage2

ROOT_SIZE="100%FREE"

DEVICE="$1"
if [ -z "$DEVICE" ]
    then
        echo "need path of disk to install. ie. /dev/sda, /dev/nvme0n1";
        exit 1;
fi

if [[ "$DEVICE" =~ ^/dev/nvme0.* ]]
    then
        PART_EFI="$DEVICE"p1;
        PART_LVM="$DEVICE"p2;
    else
        PART_EFI="$DEVICE"1;
        PART_LVM="$DEVICE"2;
fi

echo -e "target: $DEVICE\nEFI: $PART_EFI\nLVM: $PART_LVM"
# read -p "look correct? (y/N): " confirm && [[ $confirm == [yY] ]] || exit 1

INSTALL_PACKAGES="arch-install-scripts"
PACSTRAP_PACKAGES=\
"base base-devel efibootmgr vim dialog xterm btrfs-progs "\
"mkinitcpio linux linux-firmware lvm2 pacman-contrib"
MICROCODE="intel-ucode"
if [ `lscpu | grep -i intel | wc -l` -eq 0 ]
    then
        MICROCODE="amd-ucode"
fi

pacman -Sy
if ! pacman -S $INSTALL_PACKAGES --noconfirm; then
    echo "failed to install base install packages"
    exit 1
fi

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
set 2 lvm on
name 2 lvm
print
quit
EOF

modprobe dm-crypt
modprobe dm-mod

until cryptsetup luksFormat -v -s 512 -h sha512 "$PART_LVM"
do
    echo "failed to luks format. please try again"
    sleep 2
done

until cryptsetup open "$PART_LVM" luks_lvm
do
    echo "failed to open luks. please try again"
    sleep 2
done

pvcreate /dev/mapper/luks_lvm
vgcreate arch /dev/mapper/luks_lvm
lvcreate -n root -l "$ROOT_SIZE" arch

mkfs.fat -F32 "$PART_EFI"
mkfs.btrfs -L root /dev/mapper/arch-root

mount /dev/mapper/arch-root /mnt
mkdir -p /mnt/boot
mount "$PART_EFI" /mnt/boot

lsblk -f "$DEVICE"
read -p "lv groups correct? (y/N): " confirm && [[ $confirm == [yY] ]] || exit 1
if ! pacstrap /mnt $PACSTRAP_PACKAGES $MICROCODE --noconfirm; then
    echo "pacstrap failed"
    exit 1
fi

genfstab -U -p /mnt > /mnt/etc/fstab

cp ./stage2.sh /mnt/stage2.sh
chmod +x /mnt/stage2.sh

LVM_UUID=`blkid -s UUID -o value $PART_LVM`
cat << EOF >> /mnt/stage2_settings.conf
# options
QEMU_GUEST_VM=N
INCLUDE_XFCE=N
COPY_CONFIG_SCRIPTS=N
INCLUDE_VIRTMANAGER=N
ENABLE_AA_PROFILES=N
RANK_MIRRORS=N

# needed for boot config. don't tamper
LVM_UUID=$LVM_UUID
MICROCODE=$MICROCODE
EOF

echo "stage1 complete. dropping into build root chroot. exec stage.sh or modify stage2_settings.conf to continue"
arch-chroot /mnt /bin/bash
echo "build complete"

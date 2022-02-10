#!/bin/bash -x 
ROOT_SIZE="100%FREE"
SWAP_SIZE="1G"

INSTALL_PACKAGES="arch-install-scripts"
PACSTRAP_PACKAGES="base base-devel efibootmgr vim dialog xterm btrfs-progs grub mkinitcpio linux linux-firmware lvm2 pacman-contrib"
PACKAGES="git wget i3lock i3blocks firefox xautolock wpa_supplicant networkmanager alsa-utils git ttf-dejavu ttf-liberation i3-wm i3lock i3blocks lxappearance thunar network-manager-applet terminator compton dmenu feh xorg-server xorg-xinit arc-gtk-theme arc-icon-theme i3status man python-pip python-virtualenv strace"

# stage 1
pacman -Sy
pacman -S $INSTALL_PACKAGES --noconfirm

cat << EOF | parted /dev/sda
mklabel gpt
mkpart ESP fat32 1Mib 200Mib
set 1 boot on
name 1 efi
mkpart primary 200Mib 800Mib
name 2 boot
mkpart primary 800Mib 100%
set 3 lvm on
name 3 lvm
print
quit
EOF

modprobe dm-crypt
modprobe dm-mod

cryptsetup luksFormat -v -s 512 -h sha512 /dev/sda3
cryptsetup open /dev/sda3 luks_lvm
pvcreate /dev/mapper/luks_lvm
vgcreate arch /dev/mapper/luks_lvm
lvcreate -n swap -L "$SWAP_SIZE" -C y arch
lvcreate -n root -l "$ROOT_SIZE" arch

mkfs.fat -F32 /dev/sda1
mkfs.ext4 /dev/sda2
mkfs.btrfs -L root /dev/mapper/arch-root
mkfs.btrfs -L home /dev/mapper/arch-home
mkswap /dev/mapper/arch-swap

swapon /dev/mapper/arch-swap
swapon -a; swapon -s
mount /dev/mapper/arch-root /mnt
mkdir -p /mnt/{home,boot}
mount /dev/sda2 /mnt/boot
mount /dev/mapper/arch-home /mnt/home
mkdir /mnt/boot/efi
mount /dev/sda1 /mnt/boot/efi

lsblk -f
read -p "lv groups correct? (y/N): " confirm && [[ $confirm == [yY] ]] || exit 1
pacstrap /mnt $PACSTRAP_PACKAGES --noconfirm
genfstab -U -p /mnt > /mnt/etc/fstab

cat << END_STAGE2 >> /mnt/stage2.sh
# stage 2
cp /etc/mkinitcpio.conf /etc/mkinitcpio.conf.bak
echo "adding encrypt lvm2 to hooks"
egrep ^HOOKS /etc/mkinitcpio.conf
sed -i 's/block filesystems/block encrypt lvm2 filesystems/g' /etc/mkinitcpio.conf
egrep ^HOOKS /etc/mkinitcpio.conf
read -p "modification correct? (y/N): " confirm && [[ \$confirm == [yY] ]] || exit 1
mkinitcpio -v -p linux
pacman -S grub efibootmgr --noconfirm
grub-install /dev/sda --target=x86_64-efi --efi-directory=/boot/efi
cp /etc/default/grub /etc/default/grub.bak
echo "adding cryptdevice to grub cmdline"
egrep ^GRUB_CMDLINE_LINUX_DEFAULT /etc/default/grub
sed -i 's,GRUB_CMDLINE_LINUX_DEFAULT=",GRUB_CMDLINE_LINUX_DEFAULT="cryptdevice=/dev/sda3:luks_lvm ,g' /etc/default/grub
egrep ^GRUB_CMDLINE_LINUX_DEFAULT /etc/default/grub
read -p "modification correct? (y/N): " confirm && [[ \$confirm == [yY] ]] || exit 1
grub-mkconfig -o /boot/grub/grub.cfg
grub-mkconfig -o /boot/efi/EFI/arch/grub.cfg

read -p "hostname: " username
hostnamectl set-hostname "\$hostname"
echo "setup root password"
passwd root
echo "setup user"
read -p "username: " username
useradd -G wheel,storage,power -m "\$username"
passwd "\$username"

USER_HOMEDIR="/home/\$username"
XINITRC="\$USER_HOMEDIR/.xinitrc"
BASHRC="\$USER_HOMEDIR/.bashrc"
VIMRC="\$USER_HOMEDIR/.vimrc"

cat << EOF > "\$XINITRC"
#!/bin/bash
exec i3
EOF
chown "\$username":"\$username" "\$XINITRC"

cat << EOF >> "\$BASHRC"
alias vi='vim'
alias cat='cat -v'
alias view='vim -R'
alias mv='mv -i'
alias rm='rm -i'
alias cp='cp -i'

EOF
chown "\$username":"\$username" "\$BASHRC"

cat << EOF >> "\$VIMRC"
syntax on
set tabstop=4
set expandtab
set softtabstop=4
set showmatch
set hlsearch
set foldenable
set foldlevelstart=10
set rnu
EOF
chown "\$username":"\$username" "\$VIMRC"

pacman -S $PACKAGES --noconfirm
timedatectl set-timezone America/Los_Angeles
cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup
wget 'https://archlinux.org/mirrorlist/?country=US&protocol=https&ip_version=4' -O /etc/pacman.d/mirrorlist.new
cat -v /etc/pacman.d/mirrorlist.new | egrep "(.edu|rackspace.com|kernel.org)/" | tr -d '#' > /etc/pacman.d/mirrorlist.new.2
rankmirrors -n 6 /etc/pacman.d/mirrorlist.new.2 > /etc/pacman.d/mirrorlist
pacman -Sy
sed -i 's/umask 022/umask 027/g' /etc/profile
systemctl enable NetworkManager

# stage 3
read -p "set up dot files and scripts? (Y/n): " confirm && [[ \$confirm != [nN] ]] || exit 1
cd /tmp
git clone --depth 1 https://github.com/nnewsom/misc.git
mkdir -p "\$USER_HOMEDIR/.config"
cp -r misc/i3 "\$USER_HOMEDIR/.config/"
cp -r misc/terminator "\$USER_HOMEDIR/.config/"
cp -r misc/scripts "\$USER_HOMEDIR/"
chown -R "\$username":"\$username" "\$USER_HOMEDIR"

# stage 4
read -p "virtualbox vm? (y/N): " confirm && [[ \$confirm == [yY] ]] || exit 1
pacman -S virtualbox-guest-utils --noconfirm
systemctl enable vboxservice
END_STAGE2
chmod +x /mnt/stage2.sh
arch-chroot /mnt /bin/bash

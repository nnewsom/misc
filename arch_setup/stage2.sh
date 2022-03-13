#!/bin/bash

# this script is to be run inside arch-chroot of new environment
# the script will do the following:
# * install bootloader
# * create and install initramfs
# * set hostname
# * set root passwd
# * create limited user and set passwd
# * setup local .rc files to user
# * install packages listed in `PACKAGES`
# * set timezone to US/los_angeles
# * pick 6 fastest local US mirrors for pacman
# * set local to en_US.UTF-8
# * set system default umask
# * enable networkmanager service
# * install virtualbox guest if in vm (optional)

PACKAGES=\
"git wget i3lock firefox xautolock "\
"wpa_supplicant networkmanager alsa-utils "\
"ttf-dejavu ttf-liberation i3-wm i3lock "\
"lxappearance thunar network-manager-applet "\
"terminator dmenu feh xorg-server xorg-xrandr "\
"xorg-xinit arc-gtk-theme arc-icon-theme "\
"i3status man python-pip python-virtualenv "\
"strace polkit keepassxc rustup"

# set up initram fs
cp /etc/mkinitcpio.conf /etc/mkinitcpio.conf.bak
echo 'adding `encrypt` and `lvm2` to hooks between `block` and `filesystems`'
egrep ^HOOKS /etc/mkinitcpio.conf
# need to add `encrypt` and `lvm2` after `block` but before `filesystems`
sed -i 's/block filesystems/block encrypt lvm2 filesystems/g' /etc/mkinitcpio.conf
egrep ^HOOKS /etc/mkinitcpio.conf
read -p "modification correct? (y/N): " confirm && [[ $confirm == [yY] ]] || exit 1
mkinitcpio -v -p linux

# install bootloader
read -p "install grub? note: if no grub, will install systemd-boot (Y/n): " confirm
if [[ $confirm != [nN] ]]
    then
        # install grub
        pacman -S grub efibootmgr intel-ucode --noconfirm
        grub-install --target=x86_64-efi --efi-directory=/boot/ --bootloader-id=GRUB
        cp /etc/default/grub /etc/default/grub.bak
        echo "adding cryptdevice to grub cmdline"
        egrep ^GRUB_CMDLINE_LINUX_DEFAULT /etc/default/grub

        # the `REPLACEMEBOOT` tag will be replaced by stage1 to target the UUID of the crypt device
        sed -i \
            's,GRUB_CMDLINE_LINUX_DEFAULT=",GRUB_CMDLINE_LINUX_DEFAULT="REPLACEMEBOOT_OPTIONSREPLACEME ,g' \
            /etc/default/grub

        egrep ^GRUB_CMDLINE_LINUX_DEFAULT /etc/default/grub
        read -p "boot config correct? (y/N): " confirm && [[ $confirm == [yY] ]] || exit 1
        grub-mkconfig -o /boot/grub/grub.cfg
    else
        # install systemdboot
        LOADER_FILE="/boot/loader/loader.conf"
        BOOTCONF_FILE="/boot/loader/entries/arch.conf"
        pacman -S efibootmgr intel-ucode 
        bootctl install
        cat << EOF >> "$LOADER_FILE"
default arch.conf
timeout 0
console-mode max
editor no
EOF
        cat << EOF >> "$BOOTCONF_FILE"
title arch linux
linux /vmlinuz-linux
initrd /intel-ucode.img
initrd /initramfs-linux.img
options REPLACEMEBOOT_OPTIONSREPLACEME rw
EOF
        cat "$BOOTCONF_FILE"
        read -p "boot config correct? (y/N): " confirm && [[ $confirm == [yY] ]] || exit 1

fi

# set sytsem information
# hostname
read -p "hostname: " hostname
hostnamectl set-hostname "$hostname"
# root password
echo "setup root password"
until passwd root
do
    echo "failed to set root password. please try again"
    sleep 2
done

# limited user
echo "setup limited user"
read -p "username: " username
while [[ -z "$username" ]]
do
    echo "incorrect username. please try again."
    read -p "username: " username
done
useradd -G wheel,storage,power,network,audio -m "$username"

until passwd "$username"
do
    echo "failed to set password. please try agian"
    sleep 2
done

# set up local .rc files
USER_HOMEDIR="/home/$username"
XINITRC="$USER_HOMEDIR/.xinitrc"
BASHRC="$USER_HOMEDIR/.bashrc"
VIMRC="$USER_HOMEDIR/.vimrc"

# the export SSH_* is for universal ssh-agent across all terminals
# in i3 session. tldr: unlock ssh key once and use across all 
# terminals 

cat << EOF > "$XINITRC"
#!/bin/bash
eval \$(ssh-agent)
export SSH_AUTH_SOCK
export SSH_AGENT_PID
exec i3
EOF
chown "$username":"$username" "$XINITRC"

# set bashrc aliases
cat << EOF >> "$BASHRC"
alias vi='vim'
alias cat='cat -v'
alias view='vim -R'
alias mv='mv -i'
alias rm='rm -i'
alias cp='cp -i'
alias ls='ls --color=auto'
alias grep='grep --color=auto'

PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\\$ '

EOF
chown "$username":"$username" "$BASHRC"

cat << EOF >> "$VIMRC"
syntax on
set tabstop=4
set expandtab
set softtabstop=4
set showmatch
set hlsearch
set foldenable
set foldlevelstart=10
set rnu
set number
EOF
chown "$username":"$username" "$VIMRC"

# install desired base packages
pacman -S $PACKAGES --noconfirm

# set up timezone
timedatectl set-timezone America/Los_Angeles

# pick fatest local US mirrors
cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup
wget 'https://archlinux.org/mirrorlist/?country=US&protocol=https&ip_version=4' \
-O /etc/pacman.d/mirrorlist.new

cat -v /etc/pacman.d/mirrorlist.new | \
egrep "(.edu|rackspace.com|kernel.org)/" | \
tr -d '#' > /etc/pacman.d/mirrorlist.new.2

rankmirrors -n 6 /etc/pacman.d/mirrorlist.new.2 > /etc/pacman.d/mirrorlist
pacman -Sy

# set system locale to en_US.UTF-8
echo "en_US.UTF-8 UTF-8 >> /etc/locale.gen"
locale-gen
echo "LANG=en_US.UTF-8 > /etc/locale.conf"

# set system default umask to 027 ( rwxrw----- )
sed -i 's/umask 022/umask 027/g' /etc/profile

# enable network manager
systemctl enable NetworkManager

# Setups up configuration and common scripts from misc repo
read -p "set up configurations and copy scripts for misc? (Y/n): " confirm
if [[ $confirm == [yY] ]]
    then
        cd /tmp
        git clone --depth 1 https://github.com/nnewsom/misc.git
        mkdir -p "$USER_HOMEDIR/.config"
        cp -r misc/i3 "$USER_HOMEDIR/.config/"
        cp -r misc/terminator "$USER_HOMEDIR/.config/"
        cp -r misc/scripts "$USER_HOMEDIR/"
        chown -R "$username":"$username" "$USER_HOMEDIR"
fi

# set up virtualbox guest and enable core service
# this doesn't enable clipboard, drag drop etc
# those will need to be enabled manually with `VBoxClient --clipboard`

read -p "virtualbox vm? (y/N): " confirm
if [[ $confirm == [yY] ]]
    then
        pacman -S virtualbox-guest-utils --noconfirm
        systemctl enable vboxservice
        echo 'add `VBoxClient` commands to rc file to enable services on by default'

fi

read -p "add xfce? (y/N): " confirm
if [[ $confirm == [yY] ]]
    then
        pacman -S xfce4 xfce4-goodies --noconfirm
        echo "Don't forget to change xinit if you want this as default"
fi
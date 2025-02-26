#!/bin/bash

# this script is to be run inside arch-chroot of new environment
# the script will do the following:
# * install bootloader
# * create and install initramfs
# * setup firewall
# * set root passwd
# * create limited user and set passwd
# * install packages listed in `PACKAGES`
# * set timezone to US/los_angeles
# * set local to en_US.UTF-8
# * set system default umask
# * enable networkmanager service
# * [optional] pick fastest local US mirrors for pacman
# * [optional] setup local .rc files to user
# * [optional] setup qemu virtmanager
# * [optional] setup qemu guest vm
# * [optional] setup qemu guest vm
# * [optional] setup xfce4 env

PACKAGES=\
"git wget firefox xautolock cronie"\
"wpa_supplicant networkmanager alsa-utils "\
"ttf-dejavu ttf-liberation i3-wm i3lock "\
"lxappearance thunar network-manager-applet "\
"dmenu feh xorg-server xorg-xrandr "\
"xorg-xinit arc-gtk-theme arc-icon-theme "\
"i3status man python-pip python-virtualenv "\
"strace polkit keepassxc rustup pulseaudio "\
"python-notify2 python-psutil syslog-ng dunst "\
"pasystray openssh openbsd-netcat socat "\
"apparmor terminator arandr iptables less"

QEMU_PACKAGES=\
"qemu-desktop virt-manager virt-viewer dnsmasq vde2 bridge-utils "\
"openbsd-netcat dmidecode libguestfs"

# defaults
QEMU_GUEST_VM=N
INCLUDE_XFCE=N
COPY_CONFIG_SCRIPTS=N
INCLUDE_VIRTMANAGER=N
ENABLE_AA_PROFILES=N
RANK_MIRRORS=N
LVM_UUID=""
MICROCODE=""

source stage2_settings.conf

if [[ -z $LVM_UUID ]]
    then
        echo "LVM UUID is missing. cannot install"
        exit 1
fi

if [[ -z $MICROCODE ]]
    then
        echo "microcode is missing. cannot install"
        exit 1
fi

echo "Setup config:"
echo "include XFCE: $INCLUDE_XFCE"
echo "include virtmanage: $INCLUDE_VIRTMANAGER"
echo "include QEMU guest: $QEMU_GUEST_VM"
echo "copy config+scripts: $COPY_CONFIG_SCRIPTS"
echo "enable apparmor + profiles: $ENABLE_AA_PROFILES"
echo "rank mirrors: $RANK_MIRRORS"
read -p "proceed? (y/N): " confirm && [[ $confirm == [yY] ]] || exit 1

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

# set up initram fs
cp /etc/mkinitcpio.conf /etc/mkinitcpio.conf.bak
echo 'adding `encrypt` and `lvm2` to hooks between `block` and `filesystems`'
# need to add `encrypt` and `lvm2` after `block` but before `filesystems`
sed -i 's/block filesystems/block encrypt lvm2 filesystems/g' /etc/mkinitcpio.conf
if ! grep -q "block encrypt lvm2 filesystems" /etc/mkinitcpio.conf
then
    echo "failed to modify mkinitcpio"
    exit 1
fi
mkinitcpio -v -p linux

# install systemdboot
LOADER_FILE="/boot/loader/loader.conf"
BOOTCONF_FILE="/boot/loader/entries/arch.conf"
pacman -S efibootmgr --noconfirm
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
initrd /$MICROCODE.img
initrd /initramfs-linux.img
options cryptdevice=UUID=$LVM_UUID:crypt_lvm root=/dev/mapper/arch-root lsm=landlock,lockdown,yama,integrity,apparmor,bpf audit=1 ipv6.disable=1 rw
EOF

# set up basic ipv4 firewall
iptables -A INPUT -j ACCEPT -i lo -s 127.0.0.0/8 -d 127.0.0.0/8
iptables -A INPUT -j ACCEPT -m state --state RELATED,ESTABLISHED
iptables -A INPUT -j DROP
iptables-save -f /etc/iptables/iptables.rules
systemctl enable iptables

# disable ipv6
sysctl net.ipv6 | grep disable_ipv6 | sed 's/= 0/= 1/g' >> /etc/sysctl.d/40-disable-ipv6.conf



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
cat /dev/null \$HOME/.Xresources | xrdb -merge -
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
alias objdump='objdump -M intel'
alias gdb='gdb -q'

PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\\$ '

EOF
chown "$username":"$username" "$BASHRC"

cat << EOF >> "$VIMRC"
syntax on
set tabstop=4
set expandtab
set shiftwidth=4
set softtabstop=4
set hlsearch
set foldenable
set foldlevelstart=10
set rnu
set number
set mouse=a
set colorcolumn=97
EOF
chown "$username":"$username" "$VIMRC"

# pick fatest local US mirrors
if [[ $RANK_MIRRORS == [yY] ]]
then
    echo "setting up mirror list. can take some time to rank on speed"
    cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup
    curl 'https://archlinux.org/mirrorlist/?country=US&protocol=https&ip_version=4' > /etc/pacman.d/mirrorlist.new

    sed -i 's/^#//g' /etc/pacman.d/mirrorlist.new
    rankmirrors -n 10 /etc/pacman.d/mirrorlist.new > /etc/pacman.d/mirrorlist
    if test "$(wc -l < /etc/pacman.d/mirrorlist)" -eq 0
    then
        echo "failed to setup mirriors. restoring default"
        cp /etc/pacman.d/mirrorlist.backup /etc/pacman.d/mirrorlist
    fi
fi

pacman -Sy

# install desired base packages
pacman -S $PACKAGES --noconfirm

# add the user to syslog group to read logs for notify
gpasswd -a "$username" log

# add new daemon group for auditd to use and add user to group
# change the group in /etc/audit/auditd.conf if needed. this just sets ground work
# to prevent a "oh i need to be in the group and need to log out" momments
groupadd -r audit
gpasswd -a "$username" audit

# set up timezone
timedatectl set-timezone America/Los_Angeles

# set system locale to en_US.UTF-8
echo "en_US.UTF-8 UTF-8 >> /etc/locale.gen"
locale-gen
echo "LANG=en_US.UTF-8 > /etc/locale.conf"

# set system default umask to 027 ( rwxr------ )
## sed -i 's/umask 022/umask 027/g' /etc/profile
echo "umask 027" >> /etc/profile.d/umask.sh

# enable network manager
systemctl enable NetworkManager

# enable log services
sed -i 's/log_group = root/log_group = audit/g' /etc/audit/auditd.conf
systemctl enable auditd
systemctl enable syslog-ng@default.service

# enable cron
systemctl enable cronie.service

# Setups up configuration and common scripts from misc repo
if [[ $COPY_CONFIG_SCRIPTS == [yY] ]]
then
    if [ ! -d "/tmp/misc" ]; then
        git clone --depth 1 https://github.com/nnewsom/misc.git /tmp/misc
    fi
    mkdir -p "$USER_HOMEDIR"/.config/{terminator,i3status}
    cp -r /tmp/misc/i3 "$USER_HOMEDIR/.config/"
    cp -r /tmp/misc/x11/Xresources "$USER_HOMEDIR/.Xresources"
    cp -r /tmp/misc/scripts "$USER_HOMEDIR/"
    cp -r /tmp/misc/terminator/config "$USER_HOMEDIR/.config/terminator/"
    cp -r /tmp/misc/i3status/config "$USER_HOMEDIR/.config/i3status/"
    chown -R "$username":"$username" "$USER_HOMEDIR"
fi

if [[ $ENABLE_AA_PROFILES == [yY] ]]
then
    if [ ! -d "/tmp/misc" ]; then
        git clone --depth 1 https://github.com/nnewsom/misc.git /tmp/misc
    fi
    cp /tmp/misc/apparmor.d/* /etc/apparmor.d/
    systemctl enable apparmor
fi

if [[ $QEMU_GUEST_VM == [yY] ]]
then
    pacman -S spice-vdagent --noconfirm
    systemctl enable sshd
fi

if [[ $INCLUDE_XFCE == [yY] ]]
then
    pacman -S xfce4 xfce4-goodies --noconfirm
    sed -i 's/exec i3/exec startxfce4/g' $XINITRC
fi

if [[ $INCLUDE_VIRTMANAGER == [yY] ]]
then
    pacman -S $QEMU_PACKAGES --noconfirm
    systemctl enable libvirtd.service
    echo 'unix_sock_group = "libvirt"' >> /etc/libvirt/libvirtd.conf
    echo 'unix_sock_rw_perms = "0770"' >> /etc/libvirt/libvirtd.conf
    usermod -a -G libvirt  "$username"
fi

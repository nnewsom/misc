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
CORE_PACKAGES=\
"git wget networkmanager vim python-pip python-virtualenv "\
"strace rustup syslog-ng openbsd-netcat socat openssh"

# set up initram fs
cp /etc/mkinitcpio.conf /etc/mkinitcpio.conf.bak
mkinitcpio -v -p linux

# install bootloader
# install grub
pacman -S grub efibootmgr intel-ucode --noconfirm
grub-install --target=x86_64-efi --efi-directory=/boot/ --bootloader-id=GRUB
cp /etc/default/grub /etc/default/grub.bak
grub-mkconfig -o /boot/grub/grub.cfg

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

USER_HOMEDIR="/home/$username"
XINITRC="$USER_HOMEDIR/.xinitrc"
BASHRC="$USER_HOMEDIR/.bashrc"
VIMRC="$USER_HOMEDIR/.vimrc"

read -p "set up local config/rc files? (Y/n): " confirm
if [[ $confirm == [yY] ]]
then
    # set up local .rc files

    # the export SSH_* is for universal ssh-agent across all terminals
    # in i3 session. tldr: unlock ssh key once and use across all 
    # terminals 

    cat << EOF > "$XINITRC"
    #!/bin/bash
    eval \$(ssh-agent)
    export SSH_AUTH_SOCK
    export SSH_AGENT_PID
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
EOF
    chown "$username":"$username" "$VIMRC"

fi # end setup config

# install core packages
pacman -S $CORE_PACKAGES --noconfirm

# add the user to syslog group to read logs for notify
gpasswd -a "$username" log

# add new daemon group for auditd to use and add user to group
groupadd -r audit

# set up timezone
timedatectl set-timezone America/Los_Angeles

# pick fatest local US mirrors
cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup
wget 'https://archlinux.org/mirrorlist/?country=US&protocol=https&ip_version=4' \
-O /etc/pacman.d/mirrorlist.new

cat -v /etc/pacman.d/mirrorlist.new | \
grep -E "(rackspace.com|kernel.org)/" | \
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

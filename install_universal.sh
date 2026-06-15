#!/bin/sh
# ==============================================================================
# IDEMPOTENT INSTALLATION AND CONFIGURATION SCRIPT FOR FREEBSD
# Target: Universal Desktop Deployment (FreeBSD 14.x & 15.x)
# Version: 6.0 (Absolute Idempotence, Safe Bootloader, Precise pkg naming)
# File: install_universal.sh
# ==============================================================================

# Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "🚨 This script must be run as root (superuser)." 1>&2
    exit 1
fi

bsddialog --title "⚠️ IMPORTANT WARNING ⚠️" \
          --yesno "This script will deeply modify your FreeBSD system.\n\nThe author declines any responsibility in case of data loss or instability.\n\nHave you backed up your data and do you accept the risks?" 10 75
if [ $? -ne 0 ]; then
    clear
    echo "❌ Installation cancelled."
    exit 0
fi

MENU_OUT=$(mktemp)
MAJOR_VERSION=$(uname -K | cut -c 1-2)

# ==============================================================================
# 0. ENGINE: TRUE IDEMPOTENT CONFIGURATION SETTERS
# ==============================================================================
# Safely set variables in /boot/loader.conf
set_loader() {
    sysrc -f /boot/loader.conf "$1=$2" > /dev/null
}

# Safely set variables in /etc/rc.conf
set_rc() {
    sysrc "$1=$2" > /dev/null
}

# Safely append to kld_list in /etc/rc.conf (prevents duplicate module loading)
add_kld() {
    sysrc kld_list+=" $1" > /dev/null
}

# Safely set variables in /etc/sysctl.conf
set_sysctl() {
    sed -i '' "/^$1=/d" /etc/sysctl.conf
    echo "$1=$2" >> /etc/sysctl.conf
    sysctl "$1=$2" >/dev/null 2>&1 || true
}

# Safely manage /etc/fstab entries
set_fstab() {
    MOUNT_POINT=$(echo "$1" | awk '{print $2}')
    sed -i '' "\\| $MOUNT_POINT |d" /etc/fstab
    echo "$1" >> /etc/fstab
}

# ==============================================================================
# 1. INTERACTIVE SELECTION MENUS
# ==============================================================================
bsddialog --title "FreeBSD Target Version" \
          --menu "Select your installed FreeBSD version branch:" 15 70 2 \
          "1" "FreeBSD 14.x-RELEASE" \
          "2" "FreeBSD 15.x-RELEASE (or higher)" 2> "$MENU_OUT"
OS_CHOICE=$(cat "$MENU_OUT")

bsddialog --title "System Language" \
          --menu "Select the primary working language:" 15 70 5 \
          "1" "Swiss French (fr_CH.UTF-8)" \
          "2" "French (fr_FR.UTF-8)" \
          "3" "German (de_DE.UTF-8)" \
          "4" "Italian (it_IT.UTF-8)" \
          "5" "Portuguese (pt_PT.UTF-8)" 2> "$MENU_OUT"
LANG_CHOICE=$(cat "$MENU_OUT")

bsddialog --title "Keyboard Layout" \
          --menu "Select your X11/Graphical keyboard layout:" 17 75 7 \
          "1" "Swiss French (ch fr)" \
          "2" "Swiss German (ch de)" \
          "3" "Swiss Italian (ch it)" \
          "4" "French (fr)" \
          "5" "German (de)" \
          "6" "Italian (it)" \
          "7" "Portuguese (pt)" 2> "$MENU_OUT"
KBD_CHOICE=$(cat "$MENU_OUT")

bsddialog --title "CPU Configuration" \
          --menu "Select your CPU processor architecture:" 15 70 3 \
          "1" "AMD (Ryzen / Threadripper / EPYC)" \
          "2" "Intel (Core / Xeon)" \
          "3" "None / Keep system default" 2> "$MENU_OUT"
CPU_CHOICE=$(cat "$MENU_OUT")

bsddialog --title "Video Configuration" \
          --menu "Select your graphics card driver:" 16 75 5 \
          "1" "NVIDIA RTX / Ampere (Official proprietary driver)" \
          "2" "AMD Radeon (Open-source KMS driver)" \
          "3" "Intel Graphics (Open-source KMS driver)" \
          "4" "Framebuffer (SCFB/VESA generic fallback)" \
          "5" "None / Keep system default" 2> "$MENU_OUT"
GPU_CHOICE=$(cat "$MENU_OUT")

bsddialog --title "Desktop Environment" \
          --menu "Select the primary user interface:" 15 70 5 \
          "1" "KDE Plasma 6 (Modern, Wayland & X11)" \
          "2" "XFCE 4 (Lightweight, Stable & X11)" \
          "3" "MATE Desktop (Traditional & X11)" \
          "4" "None (Server setup or manual management)" 2> "$MENU_OUT"
DE_CHOICE=$(cat "$MENU_OUT")

THEME_NASA=1
if [ "$DE_CHOICE" -ne 4 ]; then
    bsddialog --title "SDDM Theme Customization" \
              --yesno "Do you want to install and configure the custom NASA SDDM login theme and FreeBSD boot logos?" 10 75
    THEME_NASA=$?
fi

bsddialog --title "Software Selection" \
          --checklist "Choose the components and applications to install:" 20 75 6 \
          "INTERNET" "Firefox, additional fonts, web productivity tools" ON \
          "MEDIA" "VLC, FFmpeg, MPV, Pipewire/Pulse audio stack" ON \
          "VBOX" "VirtualBox (Kernel emulation, devfs & groups)" OFF \
          "XRDP" "Remote Desktop Protocol (RDP) server access" OFF \
          "SAMBA" "Samba network share (Configures /home/share)" OFF 2> "$MENU_OUT"
APP_CHOICES=$(cat "$MENU_OUT")

case "$LANG_CHOICE" in
    1) SYS_LANG="fr_CH.UTF-8"; SYS_LC="fr_CH"; CLASS_NAME="swissfrench" ;;
    2) SYS_LANG="fr_FR.UTF-8"; SYS_LC="fr_FR"; CLASS_NAME="french" ;;
    3) SYS_LANG="de_DE.UTF-8"; SYS_LC="de_DE"; CLASS_NAME="german" ;;
    4) SYS_LANG="it_IT.UTF-8"; SYS_LC="it_IT"; CLASS_NAME="italian" ;;
    5) SYS_LANG="pt_PT.UTF-8"; SYS_LC="pt_PT"; CLASS_NAME="portuguese" ;;
    *) SYS_LANG="fr_CH.UTF-8"; SYS_LC="fr_CH"; CLASS_NAME="swissfrench" ;;
esac

case "$KBD_CHOICE" in
    1) KBD_LAYOUT="ch"; KBD_VARIANT="fr" ;;
    2) KBD_LAYOUT="ch"; KBD_VARIANT="de" ;;
    3) KBD_LAYOUT="ch"; KBD_VARIANT="it" ;;
    4) KBD_LAYOUT="fr"; KBD_VARIANT="" ;;
    5) KBD_LAYOUT="de"; KBD_VARIANT="" ;;
    6) KBD_LAYOUT="it"; KBD_VARIANT="" ;;
    7) KBD_LAYOUT="pt"; KBD_VARIANT="" ;;
    *) KBD_LAYOUT="ch"; KBD_VARIANT="fr" ;;
esac

clear
echo "=========================================================================="
echo "🚀 AGGRESSIVELY FORCING REPOSITORY TO QUARTERLY BRANCH..."
echo "=========================================================================="

rm -rf /usr/local/etc/pkg/repos/*
mkdir -p /usr/local/etc/pkg/repos

cat > /etc/pkg/FreeBSD.conf << 'EOF'
FreeBSD: {
  url: "pkg+https://pkg.FreeBSD.org/${ABI}/quarterly",
  mirror_type: "srv",
  signature_type: "fingerprints",
  fingerprints: "/usr/share/keys/pkg",
  enabled: yes
}
EOF

pkg update -f
pkg upgrade -y

# ==============================================================================
# 2. SYSTEM OPTIMIZATIONS AND SILENT BOOT
# ==============================================================================
echo "⚙️  Optimizing boot loader configuration and boot silence..."

set_loader "boot_mute" "YES"
set_loader "splash_changer_enable" "YES"
set_loader "autoboot_delay" "3"
set_loader "tmpfs_load" "YES"
set_loader "aio_load" "YES"
set_rc "rc_startmsgs" "NO"

set_sysctl "kern.sched.preempt_thresh" "224"
set_sysctl "kern.ipc.shm_allow_removed" "1"
set_sysctl "net.local.stream.recvspace" "65536"
set_sysctl "net.local.stream.sendspace" "65536"
set_sysctl "vfs.usermount" "1"

if ! grep -q "run_rc_script .\*_rc_elem" /etc/rc; then
    sed -i '' 's/run_rc_script ${_rc_elem} ${_boot}/run_rc_script ${_rc_elem} ${_boot} > \/dev\/null/g' /etc/rc
fi

# ==============================================================================
# 3. CPU MANAGEMENT
# ==============================================================================
case "$CPU_CHOICE" in
    1)
        echo "🧠 Configuring AMD microcode updates and hardware sensors..."
        set_loader "amdtemp_load" "YES"
        pkg install -y cpu-microcode
        set_loader "cpu_microcode_load" "YES"
        set_loader "cpu_microcode_name" "/boot/firmware/amd-ucode.bin"
        ;;
    2)
        echo "🧠 Configuring Intel microcode updates and hardware sensors..."
        set_loader "coretemp_load" "YES"
        pkg install -y cpu-microcode
        set_loader "cpu_microcode_load" "YES"
        set_loader "cpu_microcode_name" "/boot/firmware/intel-ucode.bin"
        ;;
    *)
        echo "🟡 No custom CPU architecture microcode configured."
        ;;
esac

# ==============================================================================
# 4. LINUX COMPATIBILITY LAYER
# ==============================================================================
echo "🐧 Activating Linux binary compatibility layer..."
set_rc "linux_enable" "YES"
# Load linux modules safely at runtime, NOT in loader.conf
add_kld "linux linux64"

# ==============================================================================
# 5. BASE SYSTEM REQUIREMENTS & DESKTOP GRAPHICAL LOCALIZATION
# ==============================================================================
echo "🌐 Configuring graphical localization (${SYS_LANG}) and core utilities..."
pkg install -y doas unzip libzip wget git htop neofetch python3 btop ImageMagick7 smartmontools dbus avahi seatd fusefs-ntfs fusefs-ext2

set_rc "smartd_enable" "YES"
if [ ! -f /usr/local/etc/smartd.conf ]; then
    cp /usr/local/etc/smartd.conf.sample /usr/local/etc/smartd.conf
fi

set_rc "moused_enable" "YES"
set_rc "dbus_enable" "YES"
set_rc "avahi_enable" "YES"
set_rc "seatd_enable" "YES"

set_fstab "proc /proc procfs rw 0 0"
set_fstab "fdesc /dev/fd fdescfs rw 0 0"
mount -a

if ! grep -q "${CLASS_NAME}|" /etc/login.conf; then
    cat << EOF >> /etc/login.conf

${CLASS_NAME}|Localized Users Accounts:\
        :charset=UTF-8:\
        :lang=${SYS_LANG}:\
        :lc_all=${SYS_LC}:\
        :lc_collate=${SYS_LC}:\
        :lc_ctype=${SYS_LC}:\
        :lc_messages=${SYS_LC}:\
        :tc=default:
EOF
    cap_mkdb /etc/login.conf
fi

echo "defaultclass=${CLASS_NAME}" > /etc/adduser.conf

if id "administrateur" >/dev/null 2>&1; then
    pw usermod administrateur -L ${CLASS_NAME}
fi
pw usermod root -L ${CLASS_NAME}

# ==============================================================================
# 6. DEVFS HARDWARE RULES
# ==============================================================================
echo "🖨️  Configuring DEVFS hardware rule filters..."

cat > /etc/devfs.rules << 'EOF'
[localrules=5]
add path 'da*' mode 0660 group operator
add path 'cd*' mode 0660 group operator
add path 'uscanner*' mode 0660 group operator
add path 'xpt*' mode 660 group operator
add path 'pass*' mode 660 group operator
add path 'md*' mode 0660 group operator
add path 'msdosfs/*' mode 0660 group operator
add path 'ext2fs/*' mode 0660 group operator
add path 'ntfs/*' mode 0660 group operator
add path 'usb/*' mode 0660 group operator
add path 'unlpt*' mode 0660 group cups
add path 'lpt*' mode 0660 group cups
EOF

set_rc "devfs_system_ruleset" "localrules"
service devfs restart

add_kld "fusefs ext2fs"

# ==============================================================================
# 7. GRAPHICS CARD DRIVERS
# ==============================================================================
case "$GPU_CHOICE" in
    1)
        echo "🟢 Installing and configuring NVIDIA proprietary driver..."
        pkg install -y xorg nvidia-driver nvidia-settings nvidia-xconfig wayland xwayland
        
        # Load nvidia safely at runtime, NOT in bootloader to prevent panics
        add_kld "nvidia-modeset"
        set_loader "hw.nvidiadrm.modeset" "1"
        set_loader "hw.nvidia.registry.EnableGpuFirmware" "1"
        
        if [ ! -f /etc/X11/xorg.conf ] && [ ! -f /usr/local/etc/X11/xorg.conf ]; then
            nvidia-xconfig --silent
        fi
        ;;
    2)
        echo "🔴 Installing and configuring AMD Radeon driver..."
        pkg install -y xorg drm-kmod wayland xwayland
        add_kld "amdgpu"
        ;;
    3)
        echo "🔵 Installing and configuring Intel Graphics driver..."
        pkg install -y xorg drm-kmod wayland xwayland
        add_kld "i915kms"
        ;;
    4)
        echo "⚪ Installing Framebuffer (SCFB/VESA) drivers..."
        pkg install -y xorg xf86-video-scfb xf86-video-vesa wayland xwayland
        ;;
    *)
        echo "🟡 No additional graphics drivers were selected."
        ;;
esac

mkdir -p /usr/local/etc/X11/xorg.conf.d
cat > /usr/local/etc/X11/xorg.conf.d/20-keyboards.conf << EOF
Section "ServerFlags"
        Option "DontZap" "false"
EndSection

Section "InputClass"
        Identifier "All Keyboards"
        MatchIsKeyboard "yes"
        Option "XkbLayout" "${KBD_LAYOUT}"
EOF
if [ -n "${KBD_VARIANT}" ]; then
    echo "        Option \"XkbVariant\" \"${KBD_VARIANT}\"" >> /usr/local/etc/X11/xorg.conf.d/20-keyboards.conf
fi
cat >> /usr/local/etc/X11/xorg.conf.d/20-keyboards.conf << EOF
        Option "XkbOptions" "terminate:ctrl_alt_bksp" 
EndSection
EOF

# ==============================================================================
# 8. DESKTOP ENVIRONMENT CONFIGURATION
# ==============================================================================
STARTWM_EXEC=""

case "$DE_CHOICE" in
    1)
        echo "🔵 Deploying KDE Plasma 6 environment..."
        # Using atomic package structure natively supported by FreeBSD 14 & 15 ports
        pkg install -y sddm pavucontrol kate konsole ark dolphin
        pkg install -y plasma6-plasma-workspace plasma6-kwin plasma6-breeze plasma6-sddm-kcm plasma6-kscreenlocker plasma6-kwayland plasma-wayland-protocols
        set_rc "sddm_enable" "YES"
        STARTWM_EXEC="exec startplasma-x11"
        ;;
    2)
        echo "🟤 Deploying XFCE 4 desktop environment..."
        pkg install -y xfce sddm pavucontrol
        set_rc "sddm_enable" "YES"
        STARTWM_EXEC="exec startxfce4"
        ;;
    3)
        echo "🟢 Deploying MATE Desktop environment..."
        pkg install -y mate sddm pavucontrol
        set_rc "sddm_enable" "YES"
        STARTWM_EXEC="exec mate-session"
        ;;
    *)
        echo "🟡 No desktop environment deployment requested."
        ;;
esac

if [ "$DE_CHOICE" -ne 4 ]; then
    echo "⌨️  Applying SDDM startup keyboard enforcement script..."
    mkdir -p /usr/local/share/sddm/scripts
    cat > /usr/local/share/sddm/scripts/Xsetup << EOF
#!/bin/sh
if [ -x /usr/local/bin/setxkbmap ]; then
    if [ -n "${KBD_VARIANT}" ]; then
        /usr/local/bin/setxkbmap ${KBD_LAYOUT} ${KBD_VARIANT}
    else
        /usr/local/bin/setxkbmap ${KBD_LAYOUT}
    fi
fi
EOF
    chmod 555 /usr/local/share/sddm/scripts/Xsetup
fi

if [ "$DE_CHOICE" -ne 4 ] && [ "$THEME_NASA" -eq 0 ]; then
    echo "🎨 Extracting and applying custom NASA SDDM theme and boot logos..."
    git clone https://github.com/msartor99/FreeBSD14 /tmp/fb14_assets

    cd /usr/local/share/sddm/themes
    mkdir -p nasa
    cp -r ./maldives/* ./nasa/ 2>/dev/null
    cd nasa
    cp /tmp/fb14_assets/Main.qml . 2>/dev/null
    cp /tmp/fb14_assets/metadata.desktop . 2>/dev/null
    rm -f background.jpg background.png
    cp /tmp/fb14_assets/nasa2560login.jpg background.jpg 2>/dev/null
    cp /tmp/fb14_assets/nasa2560login.jpg background.png 2>/dev/null

    cat > /usr/local/etc/sddm.conf << EOF
[Theme]
Current=nasa
[General]
background=background.png
displayFont="Montserrat"
EOF

    cd /

    mkdir -p /boot/images
    cp -r /tmp/fb14_assets/freebsd-brand-rev.png /boot/images 2>/dev/null
    cp -r /tmp/fb14_assets/freebsd-logo-rev.png  /boot/images 2>/dev/null
    cp -r /tmp/fb14_assets/nasa1920.png /boot/images/splash.png 2>/dev/null
    set_loader "splash" '"/boot/images/splash.png"'
    
    echo "🌠 Downloading and applying NASA Wallpaper..."
    fetch -o /tmp/fb14_assets/nasa_4k_wallpaper.jpg https://raw.githubusercontent.com/msartor99/FreeBSD14/ffdccbb160df14397836ce9b3b361c9ab87f97a9/wp8860763-nasa-4k-wallpapers.jpg
    
    if [ -f /tmp/fb14_assets/nasa_4k_wallpaper.jpg ]; then
        case "$DE_CHOICE" in
            1) 
                mkdir -p /usr/local/share/wallpapers/NASA_4K/contents/images
                cp /tmp/fb14_assets/nasa_4k_wallpaper.jpg /usr/local/share/wallpapers/NASA_4K/contents/images/1920x1080.jpg
                cp /tmp/fb14_assets/nasa_4k_wallpaper.jpg /usr/local/share/wallpapers/NASA_4K/contents/images/2560x1440.jpg
                cp /tmp/fb14_assets/nasa_4k_wallpaper.jpg /usr/local/share/wallpapers/NASA_4K/contents/images/3840x2160.jpg
                cat > /usr/local/share/wallpapers/NASA_4K/metadata.desktop << 'EOF_KDE'
[Desktop Entry]
Name=NASA 4K
X-KDE-PluginInfo-Name=NASA_4K
X-KDE-PluginInfo-Author=System
X-KDE-PluginInfo-License=GPLv3
EOF_KDE
                mkdir -p /usr/share/skel/dot.config
                cat > /usr/share/skel/dot.config/kscreenlockerrc << 'EOF_SKEL'
[Wallpaper][org.kde.image][General]
Image=/usr/local/share/wallpapers/NASA_4K
EOF_SKEL
                if [ -d /home/administrateur ]; then
                    mkdir -p /home/administrateur/.config
                    cat > /home/administrateur/.config/kscreenlockerrc << 'EOF_ADMIN'
[Wallpaper][org.kde.image][General]
Image=/usr/local/share/wallpapers/NASA_4K
EOF_ADMIN
                    chown -R administrateur:wheel /home/administrateur/.config
                fi
                ;;
            2) 
                mkdir -p /usr/local/share/backgrounds/xfce
                cp /tmp/fb14_assets/nasa_4k_wallpaper.jpg /usr/local/share/backgrounds/xfce/NASA_4K.jpg
                mkdir -p /usr/local/etc/xdg/xfce4/xfconf/xfce-perchannel-xml
                cat > /usr/local/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml << 'EOF_XFCE'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-desktop" version="1.0">
  <property name="backdrop" type="empty">
    <property name="screen0" type="empty">
      <property name="monitor0" type="empty">
        <property name="workspace0" type="empty">
          <property name="last-image" type="string" value="/usr/local/share/backgrounds/xfce/NASA_4K.jpg"/>
        </property>
      </property>
    </property>
  </property>
</channel>
EOF_XFCE
                ;;
            3) 
                mkdir -p /usr/local/share/backgrounds/mate/nature
                cp /tmp/fb14_assets/nasa_4k_wallpaper.jpg /usr/local/share/backgrounds/mate/NASA_4K.jpg
                if [ -d /usr/local/share/glib-2.0/schemas ]; then
                    cat > /usr/local/share/glib-2.0/schemas/99_nasa_wallpaper.gschema.override << 'EOF_MATE'
[org.mate.background]
picture-filename='/usr/local/share/backgrounds/mate/NASA_4K.jpg'
EOF_MATE
                    glib-compile-schemas /usr/local/share/glib-2.0/schemas/ 2>/dev/null
                fi
                ;;
        esac
    fi
fi

# ==============================================================================
# 9. OPTIONAL APPLICATION METAPACKAGES
# ==============================================================================
if echo "$APP_CHOICES" | grep -q "INTERNET"; then
    echo "🌐 Deploying internet browsers and system typography fonts..."
    pkg install -y firefox chromium thunderbird
    pkg install -y cantarell-fonts droid-fonts-ttf inconsolata-ttf noto-basic noto-emoji roboto-fonts-ttf ubuntu-font webfonts terminus-font terminus-ttf dejavu nerd-fonts twemoji-color-font-ttf
fi

if echo "$APP_CHOICES" | grep -q "MEDIA"; then
    echo "🎵 Deploying system sound servers and multimedia frameworks..."
    pkg install -y pulseaudio pipewire wireplumber freedesktop-sound-theme vlc ffmpeg mpv kdenlive webcamd v4l-utils
    set_rc "webcamd_enable" "YES"
    
    if [ "$GPU_CHOICE" -eq 1 ]; then
        set_sysctl "hw.snd.default_unit" "1"
    fi
fi

if echo "$APP_CHOICES" | grep -q "VBOX"; then
    echo "📦 Configuring VirtualBox virtualization layer..."
    if [ "$MAJOR_VERSION" -eq 15 ]; then
        pkg install -y virtualbox-ose virtualbox-ose-kmod
    else
        # FreeBSD 14 fallback handling for vbox port structure
        pkg install -y virtualbox-ose
    fi
    set_loader "vboxdrv_load" "YES"
    set_rc "vboxnet_enable" "YES"
    
    kldload -n vboxdrv 2>/dev/null
    pw groupmod vboxusers -m root 2>/dev/null
    if id "administrateur" >/dev/null 2>&1; then
        pw groupmod vboxusers -m administrateur 2>/dev/null
    fi
    
    if ! grep -q "vboxnetctl" /etc/devfs.conf; then
        echo "own vboxnetctl root:vboxusers" >> /etc/devfs.conf
        echo "perm vboxnetctl 0660" >> /etc/devfs.conf
    fi
    
    if ! grep -q "\[system=11\]" /etc/devfs.rules; then
        cat << 'EOF' >> /etc/devfs.rules
[system=11]
add path 'usb/*' mode 0660 group operator
add path 'video*' mode 0660 group operator
EOF
    fi
fi

if echo "$APP_CHOICES" | grep -q "XRDP"; then
    echo "🖥️  Configuring XRDP remote gateway server access..."
    pkg install -y xrdp xorgxrdp
    set_rc "xrdp_enable" "YES"
    set_rc "xrdp_sesman_enable" "YES"
    
    mkdir -p /usr/local/etc/xrdp
    if [ -f /usr/local/etc/xrdp/startwm.sh ] && [ ! -f /usr/local/etc/xrdp/startwm.sh.backup ]; then
        mv /usr/local/etc/xrdp/startwm.sh /usr/local/etc/xrdp/startwm.sh.backup
    fi
    
    cat > /usr/local/etc/xrdp/startwm.sh << EOF
#!/bin/sh
export LANG=${SYS_LANG}
export LC_ALL=${SYS_LANG}
\$STARTWM_EXEC
EOF
    chmod 555 /usr/local/etc/xrdp/startwm.sh
fi

if echo "$APP_CHOICES" | grep -q "SAMBA"; then
    echo "📂 Deploying Samba file sharing server maps..."
    
    bsddialog --title "Samba Domain / Workgroup" --inputbox "Enter Workgroup or Domain name:" 10 65 "HOMELAB" 2> "$MENU_OUT"
    SMB_WORKGROUP=$(cat "$MENU_OUT")
    
    bsddialog --title "Samba Share Label" --inputbox "Enter custom network Share Name:" 10 65 "Share" 2> "$MENU_OUT"
    SMB_SHARE_NAME=$(cat "$MENU_OUT")
    
    SMB_USER_VALID=1
    while [ $SMB_USER_VALID -ne 0 ]; do
        bsddialog --title "Samba Access Authorization" --inputbox "Enter username allowed to connect to this share:" 10 65 "administrateur" 2> "$MENU_OUT"
        SMB_USERNAME=$(cat "$MENU_OUT")
        
        if id "$SMB_USERNAME" >/dev/null 2>&1; then
            SMB_USER_VALID=0
        else
            bsddialog --title "User Account Not Found" \
                      --yesno "The user '$SMB_USERNAME' does not exist on this machine.\n\nWould you like to execute 'adduser' right now to instantiate this account?" 12 70
            if [ $? -eq 0 ]; then
                clear
                echo "👥 Dropping to console to launch standard interactive FreeBSD 'adduser' utility..."
                echo "--------------------------------------------------------------------------"
                adduser
                echo "--------------------------------------------------------------------------"
                if id "$SMB_USERNAME" >/dev/null 2>&1; then
                    SMB_USER_VALID=0
                else
                    bsddialog --title "Verification Failure" --msgbox "Verification failed. The account name was still not resolved. Please try again." 10 65
                fi
            else
                :
            fi
        fi
    done
    
    clear
    echo "🔐 Setting up Samba access tokens for user: $SMB_USERNAME..."
    echo "Please define the user's password mapping below."
    pkg install -y samba419
    smbpasswd -a "$SMB_USERNAME"
    
    mkdir -p /home/share
    chmod 777 /home/share
    
    cat > /usr/local/etc/smb4.conf << EOF
[global]
    unix charset = UTF-8
    workgroup = ${SMB_WORKGROUP}
    server string = FreeBSD
    interfaces = 127.0.0.0/8 192.168.22.0/24
    bind interfaces only = yes
    map to guest = bad user

[${SMB_SHARE_NAME}]
    path = /home/share
    writable = yes
    valid users = ${SMB_USERNAME}
    guest ok = no
    force create mode = 0775
    force directory mode = 0775
EOF
    set_rc "samba_server_enable" "YES"
fi

# ==============================================================================
# 10. MARVELL/AQUANTIA 10GB LAN HARDWARE WORKAROUND (FAST BINARY INSTALL)
# ==============================================================================
if pciconf -lv | grep -iqE "Aquantia|vendor=0x1d6a|device=0xd107|device=0x07b1"; then
    bsddialog --title "Aquantia 10GbE Driver Detected" \
              --yesno "An Aquantia/Marvell hardware network controller was detected.\n\nDo you want to inject the FAST pre-compiled Aquantia 10Gb network driver binary (optimized for Lenovo P620/AQtion chips)?" 12 70
    if [ $? -eq 0 ]; then
        echo "🌐 Injecting pre-compiled Aquantia 10Gb network interface driver..."

        MODULE_DIR="/boot/modules"
        DRIVER_NAME="if_atlantic"
        INTERFACE_NAME="aq0"

        # Cleanup old leftovers
        sed -i '' '/if_atlantic/d' /boot/loader.conf 2>/dev/null
        sed -i '' '/if_aq/d' /boot/loader.conf 2>/dev/null
        sed -i '' '/hw.aq/d' /boot/loader.conf 2>/dev/null
        sed -i '' '/dev.aq/d' /boot/loader.conf 2>/dev/null
        
        rm -f "${MODULE_DIR}/if_atlantic.ko"
        rm -f "${MODULE_DIR}/if_aq.ko"
        rm -f "/tmp/if_atlantic.ko"

        if [ "$MAJOR_VERSION" -eq 15 ]; then
            echo " ⚙️ Fetching binary for FreeBSD 15.x..."
            URL="https://raw.githubusercontent.com/msartor99/FreeBSD15-aquantia-P620/cac5ac6ac55c4c08dce89b8a59a6204267c7d5f9/FB15_if_atlantic.ko"
        elif [ "$MAJOR_VERSION" -eq 14 ]; then
            echo " ⚙️ Fetching binary for FreeBSD 14.x..."
            URL="https://raw.githubusercontent.com/msartor99/FreeBSD15-aquantia-P620/cac5ac6ac55c4c08dce89b8a59a6204267c7d5f9/FB14_if_atlantic.ko"
        fi

        fetch -o "/tmp/if_atlantic.ko" "$URL"
        if [ -f "/tmp/if_atlantic.ko" ]; then
            mkdir -p "$MODULE_DIR"
            mv "/tmp/if_atlantic.ko" "${MODULE_DIR}/if_atlantic.ko"
            chmod 555 "${MODULE_DIR}/if_atlantic.ko"
            
            set_loader "${DRIVER_NAME}_load" "YES"
            set_loader "hw.pci.enable_aspm" "0"
            set_loader "hw.dmar.enable" "0"
            set_loader "hw.aq.num_queues" "8"
            set_loader "dev.aq.0.iflib.override_nrxqs" "8"
            set_loader "dev.aq.0.iflib.override_ntxqs" "8"
            set_loader "dev.aq.0.iflib.override_nrxds" "1024"
            set_loader "dev.aq.0.iflib.override_ntxds" "1024"

            set_sysctl "dev.aq.0.eee_enable" "0"
            set_sysctl "dev.aq.0.fc_rx" "0"
            set_sysctl "dev.aq.0.fc_tx" "0"

            set_rc "ifconfig_${INTERFACE_NAME}" '"DHCP -tso -lro -txcsum -rxcsum -vlanhwtso"'
            echo " [✓] Network driver injected and hardware limits enforced."
        else
            echo " ❌ ERROR: Failed to download the binary."
        fi
    fi
else
    echo "ℹ️  No Aquantia/Marvell 10GbE hardware found on this system bus. Skipping network workaround."
fi

rm -f "$MENU_OUT"

echo "=========================================================================="
echo "✅ Configuration and deployment finished idempotently!"
echo "⚠️  Please reboot your system to apply all changes."
echo "=========================================================================="

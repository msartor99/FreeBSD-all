#!/bin/sh
# ==============================================================================
# IDEMPOTENT INSTALLATION AND CONFIGURATION SCRIPT FOR FREEBSD
# Target: Universal Desktop Deployment (Workstations & Laptops)
# Version: 8.1 (Pure X11 Edition + MS Teams & Office 365 Web Integration)
# ==============================================================================

# Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "🚨 This script must be run as root (superuser)." 1>&2
    exit 1
fi

# ==============================================================================
# 0. DISCLAIMER AND RISK ACCEPTANCE
# ==============================================================================
bsddialog --title "⚠️ IMPORTANT WARNING ⚠️" \
          --yesno "This script will deeply modify your FreeBSD system:\n\n\
- Bulk installation of system packages and software.\n\
- Critical modification of boot configuration (/boot/loader.conf).\n\
- Adjustments to core kernel parameters (/etc/sysctl.conf).\n\
- Setup of X11 graphical environment and Desktop settings.\n\n\
The author declines any responsibility in case of data loss or instability.\n\n\
Have you backed up your data and do you accept the risks?" 16 75

if [ $? -ne 0 ]; then
    clear
    stty sane
    echo "❌ Installation cancelled by the user. No changes were made."
    exit 0
fi

# ------------------------------------------------------------------------------
# TERMINAL CORRUPTION PROTECTION (TRAP)
# Prevents PuTTY from getting stuck in "no-echo" or black/white mode if aborted.
# ------------------------------------------------------------------------------
MENU_OUT=$(mktemp)
trap 'rm -f "$MENU_OUT"; stty sane; clear; echo "❌ Script interrupted! Terminal restored."; exit 1' INT TERM

# Helper function to append a line cleanly only if it doesn't exist yet
add_line_if_missing() {
    LINE="$1"
    FILE="$2"
    [ ! -f "$FILE" ] && touch "$FILE"
    grep -qF -- "$LINE" "$FILE" || echo "$LINE" >> "$FILE"
}

# ==============================================================================
# 1. INTERACTIVE SELECTION MENUS (bsddialog)
# ==============================================================================

# Main Username
bsddialog --title "System User Creation" \
          --inputbox "Enter the main administrator username to create or update:" 10 65 "administrateur" 2> "$MENU_OUT"
MAIN_USER=$(cat "$MENU_OUT")
[ -z "$MAIN_USER" ] && MAIN_USER="administrateur"

# FreeBSD Version Selection Menu
bsddialog --title "FreeBSD Target Version" \
          --menu "Select your installed FreeBSD version branch:" 15 70 2 \
          "1" "FreeBSD 15.x-RELEASE/STABLE" \
          "2" "FreeBSD 14.x-RELEASE" 2> "$MENU_OUT"
OS_CHOICE=$(cat "$MENU_OUT")

# Machine Type (Desktop vs Laptop)
bsddialog --title "Machine Profile" \
          --menu "Select the type of hardware for power/network optimizations:" 15 70 2 \
          "1" "Desktop / Workstation (Performance focus)" \
          "2" "Laptop / Notebook (Battery, WiFi & Suspend focus)" 2> "$MENU_OUT"
MACHINE_TYPE=$(cat "$MENU_OUT")

# Language Selection Menu
bsddialog --title "System Language" \
          --menu "Select the primary working language:" 15 70 5 \
          "1" "Swiss French (fr_CH.UTF-8)" \
          "2" "French (fr_FR.UTF-8)" \
          "3" "German (de_DE.UTF-8)" \
          "4" "Italian (it_IT.UTF-8)" \
          "5" "Portuguese (pt_PT.UTF-8)" 2> "$MENU_OUT"
LANG_CHOICE=$(cat "$MENU_OUT")

# Keyboard Layout Selection Menu
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

# CPU Architecture Selection Menu
bsddialog --title "CPU Configuration" \
          --menu "Select your CPU processor architecture:" 15 70 3 \
          "1" "AMD (Ryzen / Threadripper / EPYC)" \
          "2" "Intel (Core / Xeon)" \
          "3" "None / Keep system default" 2> "$MENU_OUT"
CPU_CHOICE=$(cat "$MENU_OUT")

# Graphics Card Selection Menu
bsddialog --title "Video Configuration" \
          --menu "Select your graphics card driver:" 16 75 5 \
          "1" "NVIDIA RTX / Quadro / GTX (Proprietary driver)" \
          "2" "AMD Radeon (Open-source KMS driver)" \
          "3" "Intel Graphics (Open-source KMS driver)" \
          "4" "Framebuffer / Virtual Machine (VMware/VBox/SCFB)" \
          "5" "None / Keep system default" 2> "$MENU_OUT"
GPU_CHOICE=$(cat "$MENU_OUT")

# NVIDIA Sub-menu
NVIDIA_BRANCH=""
if [ "$GPU_CHOICE" -eq 1 ]; then
    bsddialog --title "NVIDIA Driver Version" \
              --menu "Select the NVIDIA driver branch for your GPU:" 18 75 6 \
              "latest" "Latest default driver (Currently 595.x)" \
              "580" "Version 580.x (For recent/Quadro GPUs)" \
              "470" "Version 470.x (Legacy branch)" \
              "390" "Version 390.x (Legacy branch)" \
              "340" "Version 340.x (Legacy branch)" \
              "304" "Version 304.x (Legacy branch)" 2> "$MENU_OUT"
    NVIDIA_BRANCH=$(cat "$MENU_OUT")
    [ -z "$NVIDIA_BRANCH" ] && NVIDIA_BRANCH="latest"
fi

# Desktop Environment Selection Menu
bsddialog --title "Desktop Environment" \
          --menu "Select the primary user interface:" 16 75 6 \
          "1" "KDE Plasma 6 (Stable X11)" \
          "2" "XFCE 4 (Lightweight, Stable & X11)" \
          "3" "MATE Desktop (Traditional & X11)" \
          "4" "Gershwin Desktop (Mac-like GNUstep & X11)" \
          "5" "None (Server setup or manual management)" 2> "$MENU_OUT"
DE_CHOICE=$(cat "$MENU_OUT")

# Optional NASA Theme Menu
THEME_NASA=1
if [ "$DE_CHOICE" -ne 5 ]; then
    bsddialog --title "Theme Customization" \
              --yesno "Do you want to install the custom NASA boot/shutdown splash and 4K wallpapers?" 10 75
    THEME_NASA=$?
fi

# Software Component Selection Menu
bsddialog --title "Software Selection" \
          --checklist "Choose the components and applications to install:" 21 75 8 \
          "INTERNET" "Firefox, Thunderbird, Tor" ON \
          "OFFICE" "MS Teams & Office 365 Web (Chromium + WebApps)" ON \
          "FONTS" "Essential system fonts and emojis" ON \
          "MEDIA" "VLC, FFmpeg, MPV, Pipewire/Pulse audio stack" ON \
          "VBOX" "VirtualBox (Kernel emulation, devfs & groups)" OFF \
          "XRDP" "Remote Desktop Protocol (RDP) server access" OFF \
          "SAMBA" "Samba network share (Configures /home/share)" OFF \
          "AQUANTIA" "Aquantia 10GbE Network Driver (Lenovo P620)" OFF 2> "$MENU_OUT"
APP_CHOICES=$(cat "$MENU_OUT")

# Assign derived variables based on choices
[ "$OS_CHOICE" -eq 1 ] && SAMBA_PKG="samba419" VBOX_PKG="virtualbox-ose" || SAMBA_PKG="samba416" VBOX_PKG="virtualbox-ose-72"

if [ "$NVIDIA_BRANCH" = "latest" ]; then
    NV_PKG="nvidia-driver"
    NV_LINUX_PKG="linux-nvidia-libs"
else
    NV_PKG="nvidia-driver-${NVIDIA_BRANCH}"
    NV_LINUX_PKG="linux-nvidia-libs-${NVIDIA_BRANCH}"
fi

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

# Release the trap and temp file before proceeding to logged operations
trap - INT TERM
rm -f "$MENU_OUT"
clear
stty sane

# ==============================================================================
# START OF LOGGED EXECUTION BLOCK
# ==============================================================================
MASTER_LOG="/var/log/install_universal.log"
echo "📝 Automatic installation is starting. All actions will be logged to:"
echo "   -> $MASTER_LOG"
sleep 2

{
echo "=========================================================================="
echo "🚀 Synchronizing PKG Repositories with Ports Tree (LATEST branch)..."
echo "=========================================================================="
mkdir -p /usr/local/etc/pkg/repos.disabled
mv /usr/local/etc/pkg/repos/FreeBSD-ports*.conf /usr/local/etc/pkg/repos.disabled/ 2>/dev/null || true
sed -i '' 's/quarterly/latest/g' /etc/pkg/FreeBSD.conf

echo "=========================================================================="
echo "🔄 Fetching and applying FreeBSD base system patches..."
echo "=========================================================================="
env PAGER=cat freebsd-update --not-running-from-cron fetch install || true
env ASSUME_ALWAYS_YES=YES pkg bootstrap -f
env REPOS_DIR=/etc/pkg pkg update -f
env REPOS_DIR=/etc/pkg pkg upgrade -y

# ==============================================================================
# 2. CORE KERNEL MODULES PRE-LOAD
# ==============================================================================
echo "=========================================================================="
echo "🔧 Pre-loading kernel compatibility modules..."
echo "=========================================================================="
sysrc linux_enable="YES"
sysrc linux64_enable="YES"
kldload -n linux 2>/dev/null || true
kldload -n linux64 2>/dev/null || true
service linux start 2>/dev/null || true

# ==============================================================================
# 3. BULK PACKAGE INSTALLATION (PURE BINARY & X11)
# ==============================================================================
echo "=========================================================================="
echo "📦 Compiling software list and performing bulk installation..."
echo "=========================================================================="

PKG_LIST="linux-rl9 doas unzip wget git htop neofetch python3 bashtop ImageMagick7 smartmontools dbus avahi seatd fusefs-ntfs fusefs-ext2"
PKG_LIST="$PKG_LIST xorg xauth xinit xterm consolekit2 cmake ninja jsoncpp pkgconf"

[ "$MACHINE_TYPE" -eq 2 ] && PKG_LIST="$PKG_LIST networkmgr sudo acpi_call"
[ "$CPU_CHOICE" -ne 3 ] && PKG_LIST="$PKG_LIST cpu-microcode"

# Dropped Wayland and DRM modules for maximum X11 stability
case "$GPU_CHOICE" in
    1) PKG_LIST="$PKG_LIST $NV_PKG $NV_LINUX_PKG" ;;
    2) PKG_LIST="$PKG_LIST drm-kmod gpu-firmware-amd-kmod" ;;
    3) PKG_LIST="$PKG_LIST drm-kmod" ;;
    4) PKG_LIST="$PKG_LIST xf86-video-scfb xf86-video-vmware xf86-video-vesa" ;;
esac

case "$DE_CHOICE" in
    1) PKG_LIST="$PKG_LIST pavucontrol kate konsole ark dolphin Kvantum plasma6-plasma-desktop kf6-frameworks qt6-5compat plasma6-kwin sddm" ;;
    2) PKG_LIST="$PKG_LIST xfce sddm pavucontrol" ;;
    3) PKG_LIST="$PKG_LIST mate sddm pavucontrol" ;;
    4) PKG_LIST="$PKG_LIST sddm pavucontrol xfce4-wm gmake llvm curl bash sudo" ;;
esac

echo "$APP_CHOICES" | grep -q "INTERNET" && PKG_LIST="$PKG_LIST firefox thunderbird"
echo "$APP_CHOICES" | grep -q "FONTS" && PKG_LIST="$PKG_LIST noto-basic noto-emoji webfonts hack-font roboto-fonts-ttf"
echo "$APP_CHOICES" | grep -q "MEDIA" && PKG_LIST="$PKG_LIST pulseaudio pipewire wireplumber vlc ffmpeg multimedia/mpv kdenlive webcamd v4l-utils"
echo "$APP_CHOICES" | grep -q "OFFICE" && PKG_LIST="$PKG_LIST chromium webfonts webcamd v4l-utils pulseaudio"
echo "$APP_CHOICES" | grep -q "VBOX" && PKG_LIST="$PKG_LIST ${VBOX_PKG}"
echo "$APP_CHOICES" | grep -q "XRDP" && PKG_LIST="$PKG_LIST xrdp xorgxrdp"
echo "$APP_CHOICES" | grep -q "SAMBA" && PKG_LIST="$PKG_LIST ${SAMBA_PKG}"
echo "$APP_CHOICES" | grep -q "AQUANTIA" && PKG_LIST="$PKG_LIST git gmake"

# Unlock NVIDIA packages to ensure idempotency
if [ "$GPU_CHOICE" -eq 1 ]; then
    env REPOS_DIR=/etc/pkg pkg unlock -yq "$NV_PKG" "$NV_LINUX_PKG" 2>/dev/null || true
fi

# Single fast transaction
env REPOS_DIR=/etc/pkg pkg install -y $PKG_LIST
if [ $? -ne 0 ]; then
    echo "🚨 FATAL ERROR: Bulk package installation failed."
    exit 1
fi

# ==============================================================================
# 4. USER CREATION
# ==============================================================================
echo "👤 Setting up user: $MAIN_USER..."
if ! id "$MAIN_USER" >/dev/null 2>&1; then
    pw useradd "$MAIN_USER" -m -G wheel,operator,video -s /bin/sh -c "System Administrator"
else
    pw usermod "$MAIN_USER" -G wheel,operator,video -s /bin/sh
fi
echo "defaultclass=${CLASS_NAME}" > /etc/adduser.conf
pw usermod root -L ${CLASS_NAME}
pw usermod "$MAIN_USER" -L ${CLASS_NAME}

# ==============================================================================
# 5. SYSTEM OPTIMIZATIONS & SERVICES CONFIGURATION
# ==============================================================================
echo "⚙️  Optimizing boot loader and kernel parameters..."

sysrc -f /boot/loader.conf boot_mute="YES"
sysrc rc_startmsgs="NO"
sysrc -f /boot/loader.conf autoboot_delay="3"
sysrc -f /boot/loader.conf tmpfs_load="YES"
sysrc -f /boot/loader.conf aio_load="YES"

add_line_if_missing 'net.inet.tcp.soreceive_stream="1"' /boot/loader.conf
add_line_if_missing 'net.isr.defaultqlimit="2048"' /boot/loader.conf
add_line_if_missing 'net.link.ifqmaxlen="2048"' /boot/loader.conf
sysrc kld_list+="cc_htcp"

add_line_if_missing "kern.ipc.shm_allow_removed=1" /etc/sysctl.conf
add_line_if_missing "kern.ipc.shm_use_phys=1" /etc/sysctl.conf
add_line_if_missing "net.local.stream.recvspace=65536" /etc/sysctl.conf
add_line_if_missing "net.local.stream.sendspace=65536" /etc/sysctl.conf
add_line_if_missing "vfs.usermount=1" /etc/sysctl.conf
add_line_if_missing "hw.kbd.keymap_restrict_change=4" /etc/sysctl.conf
add_line_if_missing "kern.evdev.rcpt_mask=12" /etc/sysctl.conf

if ! grep -q "run_rc_script .\*_rc_elem.*> /dev/null" /etc/rc; then
    sed -i '' 's/run_rc_script ${_rc_elem} ${_boot}/run_rc_script ${_rc_elem} ${_boot} > \/dev\/null/g' /etc/rc
fi

if [ "$MACHINE_TYPE" -eq 2 ]; then
    add_line_if_missing 'machdep.hwpstate_pkg_ctrl="0"' /boot/loader.conf
    add_line_if_missing 'hw.pci.do_power_nodriver="3"' /boot/loader.conf
    add_line_if_missing 'vfs.zfs.txg.timeout="10"' /boot/loader.conf
    add_line_if_missing 'hw.snd.latency="7"' /etc/sysctl.conf
    sysrc performance_cx_lowest="Cmax"
    sysrc economy_cx_lowest="Cmax"
    sysrc kld_list+="acpi_ibm"
    
    mkdir -p /usr/local/etc/sudoers.d
    echo "%operator ALL=NOPASSWD: /usr/local/bin/networkmgr" > /usr/local/etc/sudoers.d/networkmgr
    chmod 0440 /usr/local/etc/sudoers.d/networkmgr
fi

case "$CPU_CHOICE" in
    1)
        sysrc -f /boot/loader.conf amdtemp_load="YES"
        sysrc -f /boot/loader.conf cpu_microcode_load="YES"
        sysrc -f /boot/loader.conf cpu_microcode_name="/boot/firmware/amd-ucode.bin"
        ;;
    2)
        sysrc -f /boot/loader.conf coretemp_load="YES"
        sysrc -f /boot/loader.conf cpu_microcode_load="YES"
        sysrc -f /boot/loader.conf cpu_microcode_name="/boot/firmware/intel-ucode.bin"
        ;;
esac

sysrc smartd_enable="YES"
[ ! -f /usr/local/etc/smartd.conf ] && cp /usr/local/etc/smartd.conf.sample /usr/local/etc/smartd.conf
sysrc dbus_enable="YES"
sysrc avahi_enable="YES"
sysrc seatd_enable="YES"

add_line_if_missing "proc /proc procfs rw 0 0" /etc/fstab
add_line_if_missing "fdesc /dev/fd fdescfs rw 0 0" /etc/fstab

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

cat > /etc/devfs.rules << 'EOF'
[localrules=10]
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
add path 'drm/*' mode 0660 group video
add path 'video*' mode 0660 group video
add path 'backlight/*' mode 0660 group operator
EOF
sysrc devfs_system_ruleset="localrules"
sysrc kld_list+="fusefs ext2fs"

# ==============================================================================
# 6. XORG CONFIGURATION
# ==============================================================================
echo "🖥️  Configuring X.org and Graphics Drivers..."
mkdir -p /usr/local/etc/X11/xorg.conf.d

case "$GPU_CHOICE" in
    1)
        sysrc kld_list+="nvidia-modeset"
        add_line_if_missing 'hw.nvidia.registry.EnableGpuFirmware="1"' /boot/loader.conf
        
        cat > /usr/local/etc/X11/xorg.conf.d/20-nvidia.conf << 'EOF'
Section "Device"
    Identifier "NVIDIA Card"
    Driver     "nvidia"
EndSection
EOF
        bsddialog --title "NVIDIA Package Lock" \
                  --yesno "Do you want to lock the NVIDIA driver packages?\n\nThis prevents 'pkg upgrade' from automatically updating them and potentially dropping support for your GPU." 12 70
        if [ $? -eq 0 ]; then
            env REPOS_DIR=/etc/pkg pkg lock -q -y "$NV_PKG" 2>/dev/null || true
            env REPOS_DIR=/etc/pkg pkg lock -q -y "$NV_LINUX_PKG" 2>/dev/null || true
        fi
        ;;
    2)
        sysrc kld_list+="amdgpu"
        add_line_if_missing 'hw.amdgpu.si_support="1"' /boot/loader.conf
        add_line_if_missing 'hw.amdgpu.cik_support="1"' /boot/loader.conf
        add_line_if_missing 'hw.radeon.si_support="0"' /boot/loader.conf
        add_line_if_missing 'hw.radeon.cik_support="0"' /boot/loader.conf
        ;;
    3)
        sysrc kld_list+="i915kms"
        ;;
esac

cat > /usr/local/etc/X11/xorg.conf.d/20-keyboards.conf << EOF
Section "ServerFlags"
        Option "DontZap" "false"
EndSection
Section "InputClass"
        Identifier "All Keyboards"
        MatchIsKeyboard "yes"
        Option "XkbLayout" "${KBD_LAYOUT}"
EOF
[ -n "${KBD_VARIANT}" ] && echo "        Option \"XkbVariant\" \"${KBD_VARIANT}\"" >> /usr/local/etc/X11/xorg.conf.d/20-keyboards.conf
echo "        Option \"XkbOptions\" \"terminate:ctrl_alt_bksp\"" >> /usr/local/etc/X11/xorg.conf.d/20-keyboards.conf
echo "EndSection" >> /usr/local/etc/X11/xorg.conf.d/20-keyboards.conf

# ==============================================================================
# 7. DESKTOP ENVIRONMENT CONFIGURATION
# ==============================================================================
STARTWM_EXEC=""
case "$DE_CHOICE" in
    1)
        sysrc sddm_enable="YES"
        STARTWM_EXEC="exec startplasma-x11"
        ;;
    2)
        sysrc sddm_enable="YES"
        STARTWM_EXEC="exec startxfce4"
        ;;
    3)
        sysrc sddm_enable="YES"
        STARTWM_EXEC="exec mate-session"
        ;;
    4)
        echo "=========================================================================="
        echo "🍎 Building Gershwin Desktop & GNUstep System..."
        echo "=========================================================================="
        if [ ! -d /Developer ]; then
            git clone https://github.com/gershwin-desktop/gershwin-developer.git /Developer
            /Developer/Library/Scripts/bootstrap.sh
            /Developer/Library/Scripts/checkout.sh
            make -C /Developer install
        fi
        
        mkdir -p /usr/local/share/xsessions
        cat > /usr/local/share/xsessions/gershwin.desktop << 'EOF'
[Desktop Entry]
Name=Gershwin Desktop
Comment=GNUstep-based Mac-like Desktop
Exec=/System/Library/Scripts/Gershwin.sh
Type=Application
EOF
        sysrc sddm_enable="YES"
        ;;
esac

# SDDM Configuration & Keyboard Fixes
if [ "$DE_CHOICE" -ne 5 ]; then
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

    mkdir -p /usr/local/etc/sddm.conf.d
    # Use Breeze as default to avoid SDDM Qt6 PAM authentication errors
    cat > /usr/local/etc/sddm.conf.d/20-theme.conf << EOF
[Theme]
Current=breeze
EOF

    mkdir -p /var/db/sddm/.config
    cat > /var/db/sddm/.config/kxkbrc << EOF
[Layout]
DisplayNames=
LayoutList=${KBD_LAYOUT}
Use=true
VariantList=${KBD_VARIANT}
EOF
    chown -R sddm:sddm /var/db/sddm/.config 2>/dev/null || true
    pw groupmod video -m sddm 2>/dev/null || true
    pw groupmod video -m "$MAIN_USER" 2>/dev/null || true
fi

# NASA Theme (Boot Splash & KDE Wallpaper)
if [ "$DE_CHOICE" -ne 5 ] && [ "$THEME_NASA" -eq 0 ]; then
    echo "🎨 Applying custom NASA Boot Splash & Wallpapers..."
    mkdir -p /tmp/fb14_assets
    fetch -o /tmp/fb14_assets/nasa1920.png https://raw.githubusercontent.com/msartor99/FreeBSD14/ffdccbb160df14397836ce9b3b361c9ab87f97a9/nasa1920.png 2>/dev/null
    fetch -o /tmp/fb14_assets/nasa_4k_wallpaper.jpg https://raw.githubusercontent.com/msartor99/FreeBSD14/ffdccbb160df14397836ce9b3b361c9ab87f97a9/wp8860763-nasa-4k-wallpapers.jpg 2>/dev/null
    
    # Kernel Boot Splash Logic
    if [ -f /tmp/fb14_assets/nasa1920.png ]; then
        mkdir -p /boot/images
        cp -r /tmp/fb14_assets/nasa1920.png /boot/images/splash.png
        sysrc splash_changer_enable="YES"
        sysrc -f /boot/loader.conf splash="/boot/images/splash.png"
        sysrc -f /boot/loader.conf shutdown_splash="/boot/images/splash.png"
    fi
    
    # KDE 4K Wallpaper Setup
    if [ "$DE_CHOICE" -eq 1 ] && [ -f /tmp/fb14_assets/nasa_4k_wallpaper.jpg ]; then
        mkdir -p /usr/local/share/wallpapers/NASA_4K/contents/images
        cp /tmp/fb14_assets/nasa_4k_wallpaper.jpg /usr/local/share/wallpapers/NASA_4K/contents/images/3840x2160.jpg
        cat > /usr/local/share/wallpapers/NASA_4K/metadata.desktop << 'EOF_KDE'
[Desktop Entry]
Name=NASA 4K
X-KDE-PluginInfo-Name=NASA_4K
EOF_KDE
        mkdir -p /usr/share/skel/dot.config
        echo -e "[Wallpaper][org.kde.image][General]\nImage=/usr/local/share/wallpapers/NASA_4K" > /usr/share/skel/dot.config/kscreenlockerrc
        if [ -d "/home/$MAIN_USER" ]; then
            mkdir -p "/home/$MAIN_USER/.config"
            echo -e "[Wallpaper][org.kde.image][General]\nImage=/usr/local/share/wallpapers/NASA_4K" > "/home/$MAIN_USER/.config/kscreenlockerrc"
            chown -R "$MAIN_USER:wheel" "/home/$MAIN_USER/.config"
        fi
    fi
fi

# ==============================================================================
# 8. APP METAPACKAGES CONFIGURATION
# ==============================================================================
if echo "$APP_CHOICES" | grep -q -e "MEDIA" -e "OFFICE"; then
    sysrc webcamd_enable="YES"
    [ "$GPU_CHOICE" -eq 1 ] && add_line_if_missing "hw.snd.default_unit=1" /etc/sysctl.conf
fi

if echo "$APP_CHOICES" | grep -q "OFFICE"; then
    echo "💼 Configuring MS Teams & Office 365 Web Apps..."
    mkdir -p /usr/local/share/applications
    
    # MS Teams WebApp with User-Agent spoofing to bypass Microsoft OS block
    cat > /usr/local/share/applications/msteams.desktop << 'EOF'
[Desktop Entry]
Name=Microsoft Teams
Comment=MS Teams Web App (Chromium Engine)
Exec=chromium --user-agent="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36" --app=https://teams.microsoft.com
Icon=chromium
Terminal=false
Type=Application
Categories=Network;Chat;
EOF

    # Office 365 WebApp
    cat > /usr/local/share/applications/office365.desktop << 'EOF'
[Desktop Entry]
Name=Microsoft Office 365
Comment=MS Office 365 Web App
Exec=chromium --app=https://www.office.com
Icon=chromium
Terminal=false
Type=Application
Categories=Office;
EOF
fi

if echo "$APP_CHOICES" | grep -q "VBOX"; then
    sysrc -f /boot/loader.conf vboxdrv_load="YES"
    sysrc vboxnet_enable="YES"
    pw groupmod vboxusers -m root 2>/dev/null
    pw groupmod vboxusers -m "$MAIN_USER" 2>/dev/null
    add_line_if_missing "own vboxnetctl root:vboxusers" /etc/devfs.conf
    add_line_if_missing "perm vboxnetctl 0660" /etc/devfs.conf
fi

if echo "$APP_CHOICES" | grep -q "XRDP"; then
    sysrc xrdp_enable="YES"
    sysrc xrdp_sesman_enable="YES"
    mkdir -p /usr/local/etc/xrdp
    cat > /usr/local/etc/xrdp/startwm.sh << EOF
#!/bin/sh
export LANG=${SYS_LANG}
export LC_ALL=${SYS_LANG}
\$STARTWM_EXEC
EOF
    chmod 555 /usr/local/etc/xrdp/startwm.sh
fi

if echo "$APP_CHOICES" | grep -q "SAMBA"; then
    smbpasswd -a "$MAIN_USER"
    mkdir -p /home/share
    chmod 777 /home/share
    cat > /usr/local/etc/smb4.conf << EOF
[global]
    unix charset = UTF-8
    workgroup = HOMELAB
    server string = FreeBSD
    map to guest = bad user
[Share]
    path = /home/share
    writable = yes
    valid users = ${MAIN_USER}
    guest ok = no
    force create mode = 0775
EOF
    sysrc samba_server_enable="YES"
fi

# ==============================================================================
# 9. AQUANTIA NETWORK DRIVER (Lenovo P620)
# ==============================================================================
if echo "$APP_CHOICES" | grep -q "AQUANTIA"; then
    echo "=========================================================================="
    echo "🌐 Compiling Aquantia Network Driver (Lenovo P620)..."
    echo "=========================================================================="
    if ! kldstat | grep -q if_atlantic && [ ! -f /boot/modules/if_atlantic.ko ]; then
        mkdir -p /usr/local/src
        [ ! -d /usr/local/src/FreeBSD15-aquantia-P620 ] && git clone https://github.com/msartor99/FreeBSD15-aquantia-P620 /usr/local/src/FreeBSD15-aquantia-P620 >/dev/null 2>&1
        cd /usr/local/src/FreeBSD15-aquantia-P620
        if make clean && make && make install >/dev/null 2>&1; then
            sysrc -f /boot/loader.conf if_atlantic_load="YES"
        fi
    fi
fi

echo "✅ Installation complete! A reboot is required."

} 2>&1 | tee -a "$MASTER_LOG"
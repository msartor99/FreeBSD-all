#!/bin/sh
# ==============================================================================
# IDEMPOTENT INSTALLATION AND CONFIGURATION SCRIPT FOR FREEBSD
# File: install-workstation-v9.6.sh
# Target: Universal Desktop Deployment (Workstations & Laptops - FreeBSD 15.x/14.x)
# Version: 9.6 (Fixed Pipe Hang, Updated PKG Names, Full X11/Plasma 6, XRDP & Gershwin)
# ==============================================================================

set -e

# Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "🚨 This script must be run as root (superuser)." 1>&2
    exit 1
fi

if ! bsddialog --title "⚠️ IMPORTANT WARNING ⚠️" \
          --yesno "This script will deeply modify your FreeBSD system:\n\n\
- Bulk installation of system packages and software.\n\
- Critical modification of boot configuration (/boot/loader.conf).\n\
- Adjustments to core kernel parameters (/etc/sysctl.conf).\n\
- Setup of robust X11 graphical environment and Desktop settings.\n\n\
The author declines any responsibility in case of data loss or instability.\n\n\
Have you backed up your data and do you accept the risks?" 16 75; then
    clear
    stty sane
    echo "❌ Installation cancelled by the user. No changes were made."
    exit 0
fi

MENU_OUT=$(mktemp)
trap 'rm -f "$MENU_OUT"; stty sane; clear; echo "❌ Script interrupted! Terminal restored."; exit 1' INT TERM

add_line_if_missing() {
    LINE="$1"
    FILE="$2"
    [ ! -f "$FILE" ] && touch "$FILE"
    grep -qF -- "$LINE" "$FILE" || echo "$LINE" >> "$FILE"
}

# ==============================================================================
# 1. INTERACTIVE SELECTION MENUS
# ==============================================================================
bsddialog --title "System User Creation" \
          --inputbox "Enter the main administrator username to create or update:" 10 65 "administrateur" 2> "$MENU_OUT" || true
MAIN_USER=$(cat "$MENU_OUT")
[ -z "$MAIN_USER" ] && MAIN_USER="administrateur"

# PKG Repository Branch Selection Menu
bsddialog --title "Package Repository Branch" \
          --menu "Select the FreeBSD package repository branch:" 15 70 2 \
          "1" "latest (Recommended for KDE Plasma 6 & recent packages)" \
          "2" "quarterly (Default quarterly stable branch)" 2> "$MENU_OUT" || true
PKG_BRANCH_CHOICE=$(cat "$MENU_OUT")
[ -z "$PKG_BRANCH_CHOICE" ] && PKG_BRANCH_CHOICE="1"

bsddialog --title "FreeBSD Target Version" \
          --menu "Select your installed FreeBSD version branch:" 15 70 2 \
          "1" "FreeBSD 15.x-RELEASE/STABLE" \
          "2" "FreeBSD 14.x-RELEASE" 2> "$MENU_OUT" || true
OS_CHOICE=$(cat "$MENU_OUT")
[ -z "$OS_CHOICE" ] && OS_CHOICE="1"

bsddialog --title "Machine Profile" \
          --menu "Select the type of hardware for power/network optimizations:" 15 70 2 \
          "1" "Desktop / Workstation (Performance focus)" \
          "2" "Laptop / Notebook (Battery, WiFi & Suspend focus)" 2> "$MENU_OUT" || true
MACHINE_TYPE=$(cat "$MENU_OUT")
[ -z "$MACHINE_TYPE" ] && MACHINE_TYPE="1"

bsddialog --title "System Language" \
          --menu "Select the primary working language:" 15 70 5 \
          "1" "Swiss French (fr_CH.UTF-8)" \
          "2" "French (fr_FR.UTF-8)" \
          "3" "German (de_DE.UTF-8)" \
          "4" "Italian (it_IT.UTF-8)" \
          "5" "Portuguese (pt_PT.UTF-8)" 2> "$MENU_OUT" || true
LANG_CHOICE=$(cat "$MENU_OUT")
[ -z "$LANG_CHOICE" ] && LANG_CHOICE="1"

bsddialog --title "Keyboard Layout" \
          --menu "Select your X11/Graphical keyboard layout:" 17 75 7 \
          "1" "Swiss French (ch fr)" \
          "2" "Swiss German (ch de)" \
          "3" "Swiss Italian (ch it)" \
          "4" "French (fr)" \
          "5" "German (de)" \
          "6" "Italian (it)" \
          "7" "Portuguese (pt)" 2> "$MENU_OUT" || true
KBD_CHOICE=$(cat "$MENU_OUT")
[ -z "$KBD_CHOICE" ] && KBD_CHOICE="1"

bsddialog --title "CPU Configuration" \
          --menu "Select your CPU processor architecture:" 15 70 3 \
          "1" "AMD (Ryzen / Threadripper / EPYC)" \
          "2" "Intel (Core / Xeon)" \
          "3" "None / Keep system default" 2> "$MENU_OUT" || true
CPU_CHOICE=$(cat "$MENU_OUT")
[ -z "$CPU_CHOICE" ] && CPU_CHOICE="3"

bsddialog --title "Video Configuration" \
          --menu "Select your graphics card driver:" 16 75 5 \
          "1" "NVIDIA RTX / Quadro / GTX (Proprietary driver)" \
          "2" "AMD Radeon (Open-source KMS driver)" \
          "3" "Intel Graphics (Open-source KMS driver)" \
          "4" "Framebuffer / Virtual Machine (VMware/VBox/SCFB)" \
          "5" "None / Keep system default" 2> "$MENU_OUT" || true
GPU_CHOICE=$(cat "$MENU_OUT")
[ -z "$GPU_CHOICE" ] && GPU_CHOICE="5"

NVIDIA_BRANCH=""
LOCK_NVIDIA=1
if [ "$GPU_CHOICE" = "1" ]; then
    bsddialog --title "NVIDIA Driver Version" \
              --menu "Select the NVIDIA driver branch for your GPU:" 18 75 6 \
              "latest" "Latest default driver" \
              "580" "Version 580.x (For recent/Quadro GPUs)" \
              "470" "Version 470.x (Legacy branch)" \
              "390" "Version 390.x (Legacy branch)" \
              "340" "Version 340.x (Legacy branch)" \
              "304" "Version 304.x (Legacy branch)" 2> "$MENU_OUT" || true
    NVIDIA_BRANCH=$(cat "$MENU_OUT")
    [ -z "$NVIDIA_BRANCH" ] && NVIDIA_BRANCH="latest"

    # Ask before entering the piped logging block to avoid subshell hang
    if bsddialog --title "NVIDIA Package Lock" \
                 --yesno "Do you want to lock the NVIDIA driver packages after installation to prevent unintended upgrades?" 10 70; then
        LOCK_NVIDIA=0
    else
        LOCK_NVIDIA=1
    fi
fi

bsddialog --title "Desktop Environment" \
          --menu "Select the primary user interface:" 16 75 5 \
          "1" "KDE Plasma 6 (Stable X11 / Wayland)" \
          "2" "XFCE 4 (Lightweight, Stable & X11)" \
          "3" "MATE Desktop (Traditional & X11)" \
          "4" "Gershwin Desktop (Mac-like GNUstep & X11)" \
          "5" "None (Server setup or manual management)" 2> "$MENU_OUT" || true
DE_CHOICE=$(cat "$MENU_OUT")
[ -z "$DE_CHOICE" ] && DE_CHOICE="1"

THEME_NASA=1
if [ "$DE_CHOICE" != "5" ]; then
    if bsddialog --title "Theme Customization" \
                 --yesno "Do you want to install the custom NASA boot/shutdown splash and SDDM/KDE wallpapers?" 10 75; then
        THEME_NASA=0
    else
        THEME_NASA=1
    fi
fi

bsddialog --title "Software Selection" \
          --checklist "Choose the components and applications to install:" 21 75 8 \
          "INTERNET" "Firefox, Thunderbird" ON \
          "OFFICE" "MS Teams & Office 365 Web (Chromium + WebApps)" ON \
          "FONTS" "Essential system fonts and emojis" ON \
          "MEDIA" "VLC, FFmpeg, MPV, Pipewire/Pulse audio stack" ON \
          "VBOX" "VirtualBox 7.2 (Kernel emulation, devfs & groups)" OFF \
          "XRDP" "Remote Desktop Protocol (RDP) server access" OFF \
          "SAMBA" "Samba network share (Configures /home/share)" OFF \
          "AQUANTIA" "Aquantia 10GbE Network Driver (Lenovo P620)" OFF 2> "$MENU_OUT" || true
APP_CHOICES=$(cat "$MENU_OUT")

SAMBA_PASS=""
if echo "$APP_CHOICES" | grep -q "SAMBA"; then
    bsddialog --title "Samba Password" \
              --passwordbox "Enter the Samba password for user '${MAIN_USER}' (leave empty to set manually later):" 10 70 2> "$MENU_OUT" || true
    SAMBA_PASS=$(cat "$MENU_OUT")
fi

# Derived variables
case "$PKG_BRANCH_CHOICE" in
    1) PKG_BRANCH="latest" ;;
    2) PKG_BRANCH="quarterly" ;;
    *) PKG_BRANCH="latest" ;;
esac

SAMBA_PKG="samba420"
VBOX_PKG="virtualbox-ose-72"

if [ "$NVIDIA_BRANCH" = "latest" ]; then
    NV_PKG="nvidia-driver"
    NV_LINUX_PKG="linux-nvidia-libs"
else
    NV_PKG="nvidia-driver-${NVIDIA_BRANCH}"
    NV_LINUX_PKG="linux-nvidia-libs-${NVIDIA_BRANCH}"
fi

case "$LANG_CHOICE" in
    1) SYS_LANG="fr_CH.UTF-8"; SYS_LC="fr_CH.UTF-8"; CLASS_NAME="swissfrench" ;;
    2) SYS_LANG="fr_FR.UTF-8"; SYS_LC="fr_FR.UTF-8"; CLASS_NAME="french" ;;
    3) SYS_LANG="de_DE.UTF-8"; SYS_LC="de_DE.UTF-8"; CLASS_NAME="german" ;;
    4) SYS_LANG="it_IT.UTF-8"; SYS_LC="it_IT.UTF-8"; CLASS_NAME="italian" ;;
    5) SYS_LANG="pt_PT.UTF-8"; SYS_LC="pt_PT.UTF-8"; CLASS_NAME="portuguese" ;;
    *) SYS_LANG="fr_CH.UTF-8"; SYS_LC="fr_CH.UTF-8"; CLASS_NAME="swissfrench" ;;
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

trap - INT TERM
rm -f "$MENU_OUT"
clear
stty sane

MASTER_LOG="/var/log/install_universal.log"
echo "📝 Automatic installation is starting. All actions will be logged to: $MASTER_LOG"
sleep 2

{
# ==============================================================================
# 2. SYSTEM PREPARATION & PKG
# ==============================================================================
echo "🚀 Configuring PKG Repository to '${PKG_BRANCH}' branch..."
mkdir -p /usr/local/etc/pkg/repos
cat > /usr/local/etc/pkg/repos/FreeBSD.conf << EOF
FreeBSD: {
  url: "pkg+https://pkg.FreeBSD.org/\${ABI}/${PKG_BRANCH}",
  mirror_type: "srv",
  signature_type: "fingerprints",
  fingerprints: "/usr/share/keys/pkg",
  enabled: yes
}
EOF
if [ -f /etc/pkg/FreeBSD.conf ]; then
    sed -i '' 's/enabled:[[:space:]]*yes/enabled: no/' /etc/pkg/FreeBSD.conf 2>/dev/null || true
fi

if [ ! -f /var/db/pkg/local.sqlite ]; then
    env ASSUME_ALWAYS_YES=YES pkg bootstrap -f
fi
env ASSUME_ALWAYS_YES=YES REPOS_DIR=/usr/local/etc/pkg/repos pkg update -f
env ASSUME_ALWAYS_YES=YES REPOS_DIR=/usr/local/etc/pkg/repos pkg upgrade -y

echo "🔧 Pre-loading kernel compatibility modules..."
sysrc linux_enable="YES"
kldload -n linux 2>/dev/null || true
kldload -n linux64 2>/dev/null || true
service linux start 2>/dev/null || true

# ==============================================================================
# 3. BULK PACKAGE INSTALLATION (PURE BINARY & X11)
# ==============================================================================
PKG_LIST="linux_base-rl9 doas unzip wget htop fastfetch python3 btop ImageMagick7 smartmontools dbus avahi-app seatd cups fusefs-ntfs fusefs-ext2"
PKG_LIST="$PKG_LIST xorg xauth xinit xterm consolekit2 setxkbmap"

[ "$MACHINE_TYPE" = "2" ] && PKG_LIST="$PKG_LIST networkmgr sudo acpi_call"
[ "$CPU_CHOICE" != "3" ] && PKG_LIST="$PKG_LIST cpu-microcode"

case "$GPU_CHOICE" in
    1) PKG_LIST="$PKG_LIST $NV_PKG $NV_LINUX_PKG" ;;
    2) PKG_LIST="$PKG_LIST drm-kmod gpu-firmware-amd-kmod" ;;
    3) PKG_LIST="$PKG_LIST drm-kmod gpu-firmware-intel-kmod" ;;
    4) PKG_LIST="$PKG_LIST xf86-video-scfb xf86-video-vmware xf86-video-vesa" ;;
esac

case "$DE_CHOICE" in
    1) PKG_LIST="$PKG_LIST pavucontrol kate konsole ark dolphin Kvantum plasma6-plasma kf6-frameworks qt6-5compat sddm xwayland" ;;
    2) PKG_LIST="$PKG_LIST xfce sddm pavucontrol" ;;
    3) PKG_LIST="$PKG_LIST mate sddm pavucontrol" ;;
    4) PKG_LIST="$PKG_LIST sddm pavucontrol xfce4-wm gmake llvm curl bash sudo git" ;;
esac

echo "$APP_CHOICES" | grep -q "INTERNET" && PKG_LIST="$PKG_LIST firefox thunderbird"
echo "$APP_CHOICES" | grep -q "FONTS" && PKG_LIST="$PKG_LIST noto-basic noto-emoji webfonts hack-font roboto-fonts-ttf"
echo "$APP_CHOICES" | grep -q "MEDIA" && PKG_LIST="$PKG_LIST pulseaudio pipewire wireplumber vlc ffmpeg mpv kdenlive webcamd v4l-utils"
echo "$APP_CHOICES" | grep -q "OFFICE" && PKG_LIST="$PKG_LIST chromium webfonts webcamd v4l-utils pulseaudio"
echo "$APP_CHOICES" | grep -q "VBOX" && PKG_LIST="$PKG_LIST ${VBOX_PKG}"
echo "$APP_CHOICES" | grep -q "XRDP" && PKG_LIST="$PKG_LIST xrdp xorgxrdp"
echo "$APP_CHOICES" | grep -q "SAMBA" && PKG_LIST="$PKG_LIST ${SAMBA_PKG}"
echo "$APP_CHOICES" | grep -q "AQUANTIA" && PKG_LIST="$PKG_LIST git gmake"

if [ "$GPU_CHOICE" = "1" ]; then
    env REPOS_DIR=/usr/local/etc/pkg/repos pkg unlock -yq "$NV_PKG" "$NV_LINUX_PKG" 2>/dev/null || true
fi

if ! env ASSUME_ALWAYS_YES=YES REPOS_DIR=/usr/local/etc/pkg/repos pkg install -y $PKG_LIST; then
    echo "🚨 FATAL ERROR: Bulk package installation failed."
    exit 1
fi

# ==============================================================================
# 4. SYSTEM & USER SETUP
# ==============================================================================
if ! id "$MAIN_USER" >/dev/null 2>&1; then
    pw useradd "$MAIN_USER" -u 1001 -m -G wheel,operator,video -s /bin/sh -c "System Administrator"
else
    pw usermod "$MAIN_USER" -G wheel,operator,video -s /bin/sh
fi

for GRP in wheel operator video seatd cups vboxusers; do
    if pw groupshow "$GRP" >/dev/null 2>&1; then
        pw groupmod "$GRP" -m "$MAIN_USER" 2>/dev/null || true
    fi
done

echo "defaultclass=${CLASS_NAME}" > /etc/adduser.conf
if ! grep -q "^${CLASS_NAME}|" /etc/login.conf; then
    cat << EOF >> /etc/login.conf

${CLASS_NAME}|Localized Users Accounts:\\
	:charset=UTF-8:\\
	:lang=${SYS_LANG}:\\
	:lc_all=${SYS_LC}:\\
	:lc_collate=${SYS_LC}:\\
	:lc_ctype=${SYS_LC}:\\
	:lc_messages=${SYS_LC}:\\
	:tc=default:
EOF
    cap_mkdb /etc/login.conf
fi
pw usermod root -L "${CLASS_NAME}"
pw usermod "$MAIN_USER" -L "${CLASS_NAME}"

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

if [ "$MACHINE_TYPE" = "2" ]; then
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
        sysrc -f /boot/loader.conf amdtemp_load="YES" cpu_microcode_load="YES" cpu_microcode_name="/boot/firmware/amd-ucode.bin"
        sysrc microcode_update_enable="YES"
        ;;
    2)
        sysrc -f /boot/loader.conf coretemp_load="YES" cpu_microcode_load="YES" cpu_microcode_name="/boot/firmware/intel-ucode.bin"
        sysrc microcode_update_enable="YES"
        ;;
esac

sysrc smartd_enable="YES"
[ ! -f /usr/local/etc/smartd.conf ] && [ -f /usr/local/etc/smartd.conf.sample ] && cp /usr/local/etc/smartd.conf.sample /usr/local/etc/smartd.conf
sysrc dbus_enable="YES"
sysrc avahi_daemon_enable="YES"
sysrc seatd_enable="YES"
sysrc cupsd_enable="YES"

add_line_if_missing "proc /proc procfs rw 0 0" /etc/fstab
add_line_if_missing "fdesc /dev/fd fdescfs rw 0 0" /etc/fstab

cat > /etc/devfs.rules << 'EOF'
[localrules=10]
add path 'da*' mode 0660 group operator
add path 'cd*' mode 0660 group operator
add path 'uscanner*' mode 0660 group operator
add path 'xpt*' mode 0660 group operator
add path 'pass*' mode 0660 group operator
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

# Configure doas for wheel group
if [ ! -f /usr/local/etc/doas.conf ]; then
    echo "permit persist :wheel" > /usr/local/etc/doas.conf
    chmod 0600 /usr/local/etc/doas.conf
fi

# ==============================================================================
# 5. GRAPHICS & DESKTOP ENVIRONMENT CONFIGURATION
# ==============================================================================
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
        if [ "$LOCK_NVIDIA" -eq 0 ]; then
            env REPOS_DIR=/usr/local/etc/pkg/repos pkg lock -q -y "$NV_PKG" 2>/dev/null || true
            env REPOS_DIR=/usr/local/etc/pkg/repos pkg lock -q -y "$NV_LINUX_PKG" 2>/dev/null || true
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

STARTWM_EXEC=""
case "$DE_CHOICE" in
    1) sysrc sddm_enable="YES"; STARTWM_EXEC="exec ck-launch-session startplasma-x11" ;;
    2) sysrc sddm_enable="YES"; STARTWM_EXEC="exec ck-launch-session startxfce4" ;;
    3) sysrc sddm_enable="YES"; STARTWM_EXEC="exec ck-launch-session mate-session" ;;
    4)
        sysrc sddm_enable="YES"
        STARTWM_EXEC="exec ck-launch-session startxfce4"
        if [ ! -d /usr/local/src/gershwin-desktop ]; then
            mkdir -p /usr/local/src
            git clone https://github.com/gershwin-desktop/gershwin-desktop.git /usr/local/src/gershwin-desktop 2>/dev/null || true
        fi
        ;;
esac

if [ -n "$STARTWM_EXEC" ] && [ -d "/home/$MAIN_USER" ]; then
    cat > "/home/$MAIN_USER/.xinitrc" << EOF
#!/bin/sh
export LANG=${SYS_LANG}
export LC_ALL=${SYS_LC}
${STARTWM_EXEC}
EOF
    chown
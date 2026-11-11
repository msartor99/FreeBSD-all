#!/bin/sh
# ==============================================================================
# IDEMPOTENT INSTALLATION AND CONFIGURATION SCRIPT FOR FREEBSD
# File: install-workstation-v10.2.sh
# Target: Universal Desktop Deployment (Workstations & Laptops - FreeBSD 15.1 / 14.x)
# Version: 10.2 (Fetches theme.conf, metadata.desktop & nasa2560login.jpg from GitHub)
# ==============================================================================

set -e

# Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "🚨 This script must be run as root (superuser)." 1>&2
    exit 1
fi

if ! bsddialog --title "⚠️ IMPORTANT WARNING ⚠️" \
          --yesno "This script will deeply modify your FreeBSD system:\n\n- Enforces stable QUARTERLY repository first (downgrades & stabilizes if 'latest' was active).\n- Bulk installation of system packages and software.\n- Critical modification of boot configuration (/boot/loader.conf).\n- Adjustments to core kernel parameters (/etc/sysctl.conf).\n- Setup of robust X11 graphical environment and Desktop settings.\n- Optional switch & upgrade to 'latest' package branch at the very end.\n\nThe author declines any responsibility in case of data loss or instability.\n\nHave you backed up your data and do you accept the risks?" 18 78; then
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

bsddialog --title "FreeBSD Target Version" \
          --menu "Select your installed FreeBSD version branch:" 15 70 2 \
          "1" "FreeBSD 15.x-RELEASE/STABLE (FreeBSD-ports & FreeBSD-ports-kmods)" \
          "2" "FreeBSD 14.x-RELEASE (FreeBSD & FreeBSD-kmods)" 2> "$MENU_OUT" || true
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
          "1" "NVIDIA RTX / Quadro / GTX (Proprietary driver + split kmod)" \
          "2" "AMD Radeon (Open-source KMS driver)" \
          "3" "Intel Graphics (Open-source KMS driver)" \
          "4" "Framebuffer / Virtual Machine (VMware/VBox/SCFB)" \
          "5" "None / Keep system default" 2> "$MENU_OUT" || true
GPU_CHOICE=$(cat "$MENU_OUT")
[ -z "$GPU_CHOICE" ] && GPU_CHOICE="5"

NVIDIA_BRANCH=""
NVIDIA_DRM_CHOICE=1
LOCK_NVIDIA=1
if [ "$GPU_CHOICE" = "1" ]; then
    bsddialog --title "NVIDIA Driver Branch (FreeBSD 15.1 Split Architecture)" \
              --menu "Select the NVIDIA driver branch matching your GPU architecture:" 19 78 7 \
              "latest" "595.x Production Branch (Turing RTX 20xx / Quadro RTX & newer ONLY)" \
              "580" "580.x LTS/Legacy Branch (Maxwell/Pascal/Volta GTX 9xx/10xx, Quadro P/M)" \
              "devel" "615.x New Feature Branch (nvidia-driver-devel)" \
              "470" "470.x Legacy Branch (Kepler GKxxx / Quadro Kxxx)" \
              "390" "390.x Legacy Branch (Fermi GFxxx)" \
              "340" "340.x Legacy Branch (Tesla G80-GT200)" \
              "304" "304.x Legacy Branch (NV4x/G7x)" 2> "$MENU_OUT" || true
    NVIDIA_BRANCH=$(cat "$MENU_OUT")
    [ -z "$NVIDIA_BRANCH" ] && NVIDIA_BRANCH="latest"

    if [ "$NVIDIA_BRANCH" = "latest" ] || [ "$NVIDIA_BRANCH" = "580" ] || [ "$NVIDIA_BRANCH" = "devel" ]; then
        if bsddialog --title "NVIDIA DRM KMS Module (nvidia-drm-kmod)" \
                     --yesno "Do you want to install nvidia-drm-kmod (DRM KMS support for Wayland/Plasma 6)?\n\nSelect No for pure classic X11 (nvidia-modeset only)." 11 75; then
            NVIDIA_DRM_CHOICE=0
        else
            NVIDIA_DRM_CHOICE=1
        fi
    fi

    if bsddialog --title "NVIDIA Package Lock" \
                 --yesno "Do you want to lock the NVIDIA driver and kernel module packages after installation?" 10 75; then
        LOCK_NVIDIA=0
    else
        LOCK_NVIDIA=1
    fi
fi

bsddialog --title "Desktop Environment" \
          --menu "Select the primary user interface:" 16 75 5 \
          "1" "KDE Plasma 6 (Stable X11 & Wayland)" \
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
          "VBOX" "VirtualBox 7.2 (virtualbox-ose-72 + kmod-72)" OFF \
          "XRDP" "Remote Desktop Protocol (RDP) server access" OFF \
          "SAMBA" "Samba 4.20 network share (Configures /home/share)" OFF \
          "AQUANTIA" "Aquantia 10GbE Network Driver (Lenovo P620)" OFF 2> "$MENU_OUT" || true
APP_CHOICES=$(cat "$MENU_OUT")

SAMBA_PASS=""
if echo "$APP_CHOICES" | grep -q "SAMBA"; then
    bsddialog --title "Samba Password" \
              --passwordbox "Enter the Samba password for user '${MAIN_USER}' (leave empty to set manually later):" 10 70 2> "$MENU_OUT" || true
    SAMBA_PASS=$(cat "$MENU_OUT")
fi

# Derived variables
SAMBA_PKG="samba420"
VBOX_PKG="virtualbox-ose-72 virtualbox-ose-kmod-72"

# NVIDIA split package resolution (Userland + Split Kernel Module + Linux Libs + Optional DRM Kmod)
NV_DRM_PKG=""
if [ "$NVIDIA_BRANCH" = "latest" ]; then
    NV_PKG="nvidia-driver"
    NV_KMOD_PKG="nvidia-kmod"
    NV_LINUX_PKG="linux-nvidia-libs"
    [ "$NVIDIA_DRM_CHOICE" -eq 0 ] && NV_DRM_PKG="nvidia-drm-kmod"
else
    NV_PKG="nvidia-driver-${NVIDIA_BRANCH}"
    NV_KMOD_PKG="nvidia-kmod-${NVIDIA_BRANCH}"
    NV_LINUX_PKG="linux-nvidia-libs-${NVIDIA_BRANCH}"
    [ "$NVIDIA_DRM_CHOICE" -eq 0 ] && NV_DRM_PKG="nvidia-drm-kmod-${NVIDIA_BRANCH}"
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
# 2. SYSTEM PREPARATION & IDEMPOTENT REPO CHECK (RETROGRADE LATEST -> QUARTERLY)
# ==============================================================================
echo "🔍 Checking current PKG repository configuration..."
mkdir -p /usr/local/etc/pkg/repos

NEED_DOWNGRADE_STABILIZE=0

# Check if any config in /etc/pkg or /usr/local/etc/pkg/repos is currently pointing to 'latest'
if grep -Eq "(/latest|kmods_latest)" /etc/pkg/FreeBSD.conf /usr/local/etc/pkg/repos/*.conf 2>/dev/null; then
    echo "⚠️ Detected 'latest' branch in PKG configuration! Retrograding to 'quarterly' for stability..."
    NEED_DOWNGRADE_STABILIZE=1
fi

# Clean any custom repo files in /usr/local/etc/pkg/repos that might override quarterly
for CONF_FILE in /usr/local/etc/pkg/repos/*.conf; do
    [ -e "$CONF_FILE" ] || continue
    if [ "$CONF_FILE" != "/usr/local/etc/pkg/repos/FreeBSD.conf" ]; then
        rm -f "$CONF_FILE"
    fi
done

# Ensure /etc/pkg/FreeBSD.conf is restored to default enabled quarterly state
if [ -f /etc/pkg/FreeBSD.conf ]; then
    sed -i '' 's/enabled:[[:space:]]*no/enabled: yes/g' /etc/pkg/FreeBSD.conf 2>/dev/null || true
    sed -i '' 's/\/latest/\/quarterly/g' /etc/pkg/FreeBSD.conf 2>/dev/null || true
    sed -i '' 's/kmods_latest_/kmods_quarterly_/g' /etc/pkg/FreeBSD.conf 2>/dev/null || true
fi

# Explicitly write QUARTERLY configuration to /usr/local/etc/pkg/repos/FreeBSD.conf
if grep -q "FreeBSD-ports:" /etc/pkg/FreeBSD.conf 2>/dev/null || [ "$OS_CHOICE" = "1" ]; then
    cat > /usr/local/etc/pkg/repos/FreeBSD.conf << 'EOF'
FreeBSD-ports: {
  url: "pkg+https://pkg.FreeBSD.org/${ABI}/quarterly",
  enabled: yes
}
FreeBSD-ports-kmods: {
  url: "pkg+https://pkg.FreeBSD.org/${ABI}/kmods_quarterly_${VERSION_MINOR}",
  enabled: yes
}
EOF
else
    cat > /usr/local/etc/pkg/repos/FreeBSD.conf << 'EOF'
FreeBSD: {
  url: "pkg+https://pkg.FreeBSD.org/${ABI}/quarterly",
  enabled: yes
}
FreeBSD-kmods: {
  url: "pkg+https://pkg.FreeBSD.org/${ABI}/kmods_quarterly_${VERSION_MINOR}",
  enabled: yes
}
EOF
fi

# Update base system only if traditional non-pkgbase install is used
if ! pkg info -e FreeBSD-runtime 2>/dev/null; then
    env PAGER=cat freebsd-update --not-running-from-cron fetch install || true
fi

if [ ! -f /var/db/pkg/local.sqlite ]; then
    env ASSUME_ALWAYS_YES=YES pkg bootstrap -f
fi

# Unlock all potentially locked packages before stabilizing repositories
pkg unlock -a -q -y 2>/dev/null || true

env ASSUME_ALWAYS_YES=YES pkg update -f

if [ "$NEED_DOWNGRADE_STABILIZE" -eq 1 ]; then
    echo "🔄 Retrograding and stabilizing all installed packages to QUARTERLY (pkg upgrade -f -y)..."
    env ASSUME_ALWAYS_YES=YES pkg upgrade -f -y
    env ASSUME_ALWAYS_YES=YES pkg autoremove -y || true
    echo "✅ System successfully stabilized on QUARTERLY branch."
else
    echo "✅ System is already on QUARTERLY branch. Running standard pkg upgrade..."
    env ASSUME_ALWAYS_YES=YES pkg upgrade -y
fi

echo "🔧 Pre-loading kernel compatibility modules..."
sysrc linux_enable="YES"
kldload -n linux 2>/dev/null || true
kldload -n linux64 2>/dev/null || true
service linux start 2>/dev/null || true

# ==============================================================================
# 3. BULK PACKAGE INSTALLATION (ON STABLE QUARTERLY BRANCH)
# ==============================================================================
PKG_LIST="linux_base-rl9 doas unzip wget htop fastfetch python3 btop ImageMagick7 smartmontools dbus avahi-app seatd cups fusefs-ntfs fusefs-ext2"
PKG_LIST="$PKG_LIST xorg xauth xinit xterm consolekit2 setxkbmap"

[ "$MACHINE_TYPE" = "2" ] && PKG_LIST="$PKG_LIST networkmgr sudo acpi_call"
[ "$CPU_CHOICE" != "3" ] && PKG_LIST="$PKG_LIST cpu-microcode"

case "$GPU_CHOICE" in
    1) PKG_LIST="$PKG_LIST $NV_KMOD_PKG $NV_PKG $NV_LINUX_PKG $NV_DRM_PKG" ;;
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

if ! env ASSUME_ALWAYS_YES=YES pkg install -y $PKG_LIST; then
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
    printf "\n%s|Localized Users Accounts:\\\\\n\t:charset=UTF-8:\\\\\n\t:lang=%s:\\\\\n\t:lc_all=%s:\\\\\n\t:lc_collate=%s:\\\\\n\t:lc_ctype=%s:\\\\\n\t:lc_messages=%s:\\\\\n\t:tc=default:\n" \
        "$CLASS_NAME" "$SYS_LANG" "$SYS_LC" "$SYS_LC" "$SYS_LC" "$SYS_LC" >> /etc/login.conf
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
        if [ "$NVIDIA_DRM_CHOICE" -eq 0 ]; then
            sysrc kld_list+="nvidia-drm"
            add_line_if_missing 'hw.nvidiadrm.modeset="1"' /boot/loader.conf
        elif [ "$NVIDIA_BRANCH" = "340" ] || [ "$NVIDIA_BRANCH" = "304" ]; then
            sysrc kld_list+="nvidia"
        else
            sysrc kld_list+="nvidia-modeset"
        fi
        add_line_if_missing 'hw.nvidia.registry.EnableGpuFirmware="1"' /boot/loader.conf
        cat > /usr/local/etc/X11/xorg.conf.d/20-nvidia.conf << 'EOF'
Section "Device"
    Identifier "NVIDIA Card"
    Driver     "nvidia"
EndSection
EOF
        if [ "$LOCK_NVIDIA" -eq 0 ]; then
            pkg lock -q -y "$NV_KMOD_PKG" "$NV_PKG" "$NV_LINUX_PKG" $NV_DRM_PKG 2>/dev/null || true
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
    chown "$MAIN_USER:$MAIN_USER" "/home/$MAIN_USER/.xinitrc"
    chmod 0755 "/home/$MAIN_USER/.xinitrc"
fi

# ==============================================================================
# 6. NASA THEME & SDDM (CUSTOM 'nasa' THEME CLONED FROM 'maldives' + GITHUB CONFIGS)
# ==============================================================================
rm -f /usr/share/skel/dot.config/kscreenlockerrc 2>/dev/null || true
if [ -d "/home/$MAIN_USER" ]; then
    rm -f "/home/$MAIN_USER/.config/kscreenlockerrc" 2>/dev/null || true
fi

if [ "$DE_CHOICE" != "5" ]; then
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
    chmod 0755 /usr/local/share/sddm/scripts/Xsetup
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

    # Default SDDM theme before NASA customization
    cat > /usr/local/etc/sddm.conf << 'EOF'
[Theme]
Current=breeze
EOF

    if [ "$THEME_NASA" -eq 0 ]; then
        mkdir -p /tmp/fb_nasa_assets

        # Fetch NASA assets, theme.conf, and metadata.desktop from msartor99 GitHub repositories
        for REPO_URL in \
            "https://raw.githubusercontent.com/msartor99/FreeBSD15/main" \
            "https://raw.githubusercontent.com/msartor99/FreeBSD15/master" \
            "https://raw.githubusercontent.com/msartor99/FreeBSD14/main" \
            "https://raw.githubusercontent.com/msartor99/FreeBSD14/master" \
            "https://raw.githubusercontent.com/msartor99/FreeBSD14/ffdccbb160df14397836ce9b3b361c9ab87f97a9"; do
            [ ! -s /tmp/fb_nasa_assets/nasa1920.png ] && fetch -q -o /tmp/fb_nasa_assets/nasa1920.png "${REPO_URL}/nasa1920.png" 2>/dev/null || true
            [ ! -s /tmp/fb_nasa_assets/nasa2560login.jpg ] && fetch -q -o /tmp/fb_nasa_assets/nasa2560login.jpg "${REPO_URL}/nasa2560login.jpg" 2>/dev/null || true
            [ ! -s /tmp/fb_nasa_assets/nasa_4k_wallpaper.jpg ] && fetch -q -o /tmp/fb_nasa_assets/nasa_4k_wallpaper.jpg "${REPO_URL}/wp8860763-nasa-4k-wallpapers.jpg" 2>/dev/null || true
            [ ! -s /tmp/fb_nasa_assets/theme.conf ] && fetch -q -o /tmp/fb_nasa_assets/theme.conf "${REPO_URL}/theme.conf" 2>/dev/null || true
            [ ! -s /tmp/fb_nasa_assets/metadata.desktop ] && fetch -q -o /tmp/fb_nasa_assets/metadata.desktop "${REPO_URL}/metadata.desktop" 2>/dev/null || true
        done

        # Fallback if nasa2560login.jpg wasn't found under that exact filename on remote
        if [ ! -s /tmp/fb_nasa_assets/nasa2560login.jpg ]; then
            if [ -s /tmp/fb_nasa_assets/nasa_4k_wallpaper.jpg ]; then
                cp /tmp/fb_nasa_assets/nasa_4k_wallpaper.jpg /tmp/fb_nasa_assets/nasa2560login.jpg
            elif [ -s /tmp/fb_nasa_assets/nasa1920.png ]; then
                cp /tmp/fb_nasa_assets/nasa1920.png /tmp/fb_nasa_assets/nasa2560login.jpg
            fi
        fi

        # 1. Kernel Boot Splash (Disabled for NVIDIA to prevent Panic)
        if [ "$GPU_CHOICE" != "1" ] && [ -s /tmp/fb_nasa_assets/nasa1920.png ]; then
            mkdir -p /boot/images
            cp /tmp/fb_nasa_assets/nasa1920.png /boot/images/splash.png
            sysrc splash_changer_enable="YES"
            sysrc -f /boot/loader.conf splash="/boot/images/splash.png"
            sysrc -f /boot/loader.conf shutdown_splash="/boot/images/splash.png"
        fi

        # 2. SDDM Customization: Clone 'maldives' into 'nasa' and replace with GitHub files
        SDDM_THEMES_DIR="/usr/local/share/sddm/themes"
        if [ -d "${SDDM_THEMES_DIR}/maldives" ] && [ -s /tmp/fb_nasa_assets/nasa2560login.jpg ]; then
            echo "🎨 Creating SDDM 'nasa' theme from 'maldives'..."
            rm -rf "${SDDM_THEMES_DIR}/nasa"
            cp -R "${SDDM_THEMES_DIR}/maldives" "${SDDM_THEMES_DIR}/nasa"

            # Copy background image
            cp /tmp/fb_nasa_assets/nasa2560login.jpg "${SDDM_THEMES_DIR}/nasa/nasa2560login.jpg"
            chmod 0644 "${SDDM_THEMES_DIR}/nasa/nasa2560login.jpg"

            # Replace theme.conf with the one downloaded from GitHub (or fallback to sed update)
            if [ -s /tmp/fb_nasa_assets/theme.conf ]; then
                cp /tmp/fb_nasa_assets/theme.conf "${SDDM_THEMES_DIR}/nasa/theme.conf"
                chmod 0644 "${SDDM_THEMES_DIR}/nasa/theme.conf"
            elif [ -f "${SDDM_THEMES_DIR}/nasa/theme.conf" ]; then
                sed -i '' 's|^background=.*|background=nasa2560login.jpg|g' "${SDDM_THEMES_DIR}/nasa/theme.conf"
            fi

            # Replace metadata.desktop with the one downloaded from GitHub (or fallback to sed update)
            if [ -s /tmp/fb_nasa_assets/metadata.desktop ]; then
                cp /tmp/fb_nasa_assets/metadata.desktop "${SDDM_THEMES_DIR}/nasa/metadata.desktop"
                chmod 0644 "${SDDM_THEMES_DIR}/nasa/metadata.desktop"
            elif [ -f "${SDDM_THEMES_DIR}/nasa/metadata.desktop" ]; then
                sed -i '' 's|^Name=.*|Name=NASA|g' "${SDDM_THEMES_DIR}/nasa/metadata.desktop"
                sed -i '' 's|^Theme-Id=.*|Theme-Id=nasa|g' "${SDDM_THEMES_DIR}/nasa/metadata.desktop"
            fi

            # Activate 'nasa' theme in SDDM configuration
            cat > /usr/local/etc/sddm.conf << 'EOF'
[Theme]
Current=nasa
EOF
            mkdir -p /usr/local/etc/sddm.conf.d
            cat > /usr/local/etc/sddm.conf.d/theme.conf << 'EOF'
[Theme]
Current=nasa
EOF
            echo "✅ SDDM 'nasa' theme created and updated with GitHub theme.conf, metadata.desktop, and nasa2560login.jpg."
        fi

        # 3. KDE Plasma 4K Wallpaper
        if [ "$DE_CHOICE" = "1" ] && [ -s /tmp/fb_nasa_assets/nasa_4k_wallpaper.jpg ]; then
            mkdir -p /usr/local/share/wallpapers/NASA_4K/contents/images
            cp /tmp/fb_nasa_assets/nasa_4k_wallpaper.jpg /usr/local/share/wallpapers/NASA_4K/contents/images/3840x2160.jpg
            cat > /usr/local/share/wallpapers/NASA_4K/metadata.desktop << 'EOF_KDE'
[Desktop Entry]
Name=NASA 4K
X-KDE-PluginInfo-Name=NASA_4K
EOF_KDE
            echo "ℹ️  NASA 4K wallpaper has been safely added to the system."
        fi
        rm -rf /tmp/fb_nasa_assets
    fi
fi

# ==============================================================================
# 7. APPLICATIONS SETUP (TEAMS, OFFICE365, VBOX, XRDP, SAMBA, AQUANTIA)
# ==============================================================================
if echo "$APP_CHOICES" | grep -q -e "MEDIA" -e "OFFICE"; then
    sysrc webcamd_enable="YES"
    [ "$GPU_CHOICE" = "1" ] && add_line_if_missing "hw.snd.default_unit=1" /etc/sysctl.conf
fi

if echo "$APP_CHOICES" | grep -q "OFFICE"; then
    mkdir -p /usr/local/share/applications
    cat > /usr/local/share/applications/msteams.desktop << 'EOF'
[Desktop Entry]
Name=Microsoft Teams
Comment=MS Teams Web App (Chromium Engine)
Exec=chromium --user-agent="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36" --app=https://teams.microsoft.com
Icon=chromium
Terminal=false
Type=Application
Categories=Network;Chat;
EOF
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
    pw groupmod vboxusers -m root 2>/dev/null || true
    pw groupmod vboxusers -m "$MAIN_USER" 2>/dev/null || true
    add_line_if_missing "own vboxnetctl root:vboxusers" /etc/devfs.conf
    add_line_if_missing "perm vboxnetctl 0660" /etc/devfs.conf
fi

if echo "$APP_CHOICES" | grep -q "XRDP"; then
    sysrc xrdp_enable="YES"
    sysrc xrdp_sesman_enable="YES"
    if [ -n "$STARTWM_EXEC" ]; then
        mkdir -p /usr/local/etc/xrdp
        cat > /usr/local/etc/xrdp/startwm.sh << EOF
#!/bin/sh
export LANG=${SYS_LANG}
export LC_ALL=${SYS_LC}
${STARTWM_EXEC}
EOF
        chmod 0755 /usr/local/etc/xrdp/startwm.sh
    fi
fi

if echo "$APP_CHOICES" | grep -q "SAMBA"; then
    if [ -n "$SAMBA_PASS" ]; then
        (echo "$SAMBA_PASS"; echo "$SAMBA_PASS") | smbpasswd -s -a "$MAIN_USER" >/dev/null 2>&1 || true
    fi
    mkdir -p /home/share
    chown "$MAIN_USER:wheel" /home/share
    chmod 0775 /home/share
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

if echo "$APP_CHOICES" | grep -q "AQUANTIA"; then
    if ! kldstat | grep -q if_atlantic && [ ! -f /boot/modules/if_atlantic.ko ]; then
        mkdir -p /usr/local/src
        if [ ! -d /usr/local/src/FreeBSD15-aquantia-P620 ]; then
            git clone https://github.com/msartor99/FreeBSD15-aquantia-P620 /usr/local/src/FreeBSD15-aquantia-P620 >/dev/null 2>&1 || true
        fi
        if [ -d /usr/local/src/FreeBSD15-aquantia-P620 ]; then
            cd /usr/local/src/FreeBSD15-aquantia-P620
            if make clean && make && make install >/dev/null 2>&1; then
                sysrc -f /boot/loader.conf if_atlantic_load="YES"
            fi
        fi
    fi
fi

echo "✅ Base installation on QUARTERLY branch complete!"
} 2>&1 | tee -a "$MASTER_LOG"

# ==============================================================================
# 8. POST-INSTALL: OPTIONAL SWITCH & UPGRADE TO 'LATEST' REPOSITORY
# ==============================================================================
if bsddialog --title "Switch to LATEST Repository Branch?" \
             --yesno "All base packages and desktop components are now safely installed and stabilized on the QUARTERLY repository.\n\nDo you want to switch your package repository to 'latest' now and upgrade installed packages?\n\n(Note: If any package is currently missing on the 'latest' build server, your already-installed quarterly packages will remain intact)." 14 76; then
    {
        echo "🔄 Switching PKG repositories to 'latest' branch..."
        mkdir -p /usr/local/etc/pkg/repos
        if grep -q "FreeBSD-ports:" /etc/pkg/FreeBSD.conf 2>/dev/null || [ "$OS_CHOICE" = "1" ]; then
            cat > /usr/local/etc/pkg/repos/FreeBSD.conf << 'EOF'
FreeBSD-ports: {
  url: "pkg+https://pkg.FreeBSD.org/${ABI}/latest",
  enabled: yes
}
FreeBSD-ports-kmods: {
  url: "pkg+https://pkg.FreeBSD.org/${ABI}/kmods_latest_${VERSION_MINOR}",
  enabled: yes
}
EOF
        else
            cat > /usr/local/etc/pkg/repos/FreeBSD.conf << 'EOF'
FreeBSD: {
  url: "pkg+https://pkg.FreeBSD.org/${ABI}/latest",
  enabled: yes
}
FreeBSD-kmods: {
  url: "pkg+https://pkg.FreeBSD.org/${ABI}/kmods_latest_${VERSION_MINOR}",
  enabled: yes
}
EOF
        fi

        env ASSUME_ALWAYS_YES=YES pkg update -f
        env ASSUME_ALWAYS_YES=YES pkg upgrade -y || echo "⚠️ Some packages could not be upgraded from 'latest' right now, keeping existing quarterly versions."
        echo "✅ Repository switch to 'latest' completed!"
    } 2>&1 | tee -a "$MASTER_LOG"
else
    echo "ℹ️  Keeping system on the default stable 'quarterly' repository branch." | tee -a "$MASTER_LOG"
fi

echo "🎉 All tasks finished! Please reboot your FreeBSD system."
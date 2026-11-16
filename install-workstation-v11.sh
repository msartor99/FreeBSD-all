#!/bin/sh
# ==============================================================================
# IDEMPOTENT POST-INSTALLATION AND WORKSTATION SCRIPT FOR FREEBSD 15.1
# File: install-workstation-v11.1.sh
# Target: Workstation & Desktop Deployment (X11 Enforced, Auto-Hardware Detection)
# Version: 11.1 (Master Fusion + Default 'No' on Latest Repository Switch)
# ==============================================================================

set -e

BACKTITLE="FreeBSD 15.1 Workstation Configuration (v11.1)"

# ---------------------------------------------------------
# 0. Root Check, Cancellation & Trap Handlers
# ---------------------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root (superuser)." 1>&2
    exit 1
fi

handle_cancel() {
    clear
    stty sane
    echo "Operation canceled by the user. No changes were made."
    exit 1
}

trap 'stty sane; clear; echo "Script interrupted! Terminal restored."; exit 1' INT TERM

# Non-destructive helper functions (Preserves Aquantia & custom configs)
apply_sysctl() {
    local key="$1"
    local val="$2"
    [ ! -f /etc/sysctl.conf ] && touch /etc/sysctl.conf
    if grep -q "^${key}=" /etc/sysctl.conf; then
        sed -i '' -e "s|^${key}=.*|${key}=${val}|" /etc/sysctl.conf
    else
        echo "${key}=${val}" >> /etc/sysctl.conf
    fi
}

add_line_if_missing() {
    local line="$1"
    local file="$2"
    [ ! -f "$file" ] && touch "$file"
    grep -qF -- "$line" "$file" || echo "$line" >> "$file"
}

# ---------------------------------------------------------
# 1. Welcome Screen / Disclaimer
# ---------------------------------------------------------
DISCLAIMER="WARNING:

This automated script will configure your FreeBSD 15.1 system into a complete workstation:
- Stabilizes PKG on QUARTERLY repository first (with optional switch to LATEST at the end).
- Auto-detects CPU (AMD/Intel microcode & thermal sensors) and NVIDIA GPU architecture.
- Deploys Xorg, your chosen Desktop Environment (X11 strictly enforced), and SDDM.
- Configures modern Audio stack (PipeWire/PulseAudio), Linuxulator (rl9), and USB devfs rules.
- Resizes boot splash screen to your native resolution & optionally installs NASA SDDM theme.
- Preserves existing hardware configurations (such as Aquantia 10GbE sysctl tunings).

Do you want to begin the configuration process?"

if ! bsddialog --backtitle "$BACKTITLE" --title "Disclaimer" --clear --yesno "$DISCLAIMER" 19 80; then
    handle_cancel
fi

# ---------------------------------------------------------
# 2. Target User Selection (Default: administrateur)
# ---------------------------------------------------------
set --
FOUND_ADMIN=0
while IFS=: read -r _user _pass _uid _gid _rest; do
    if [ "$_uid" -ge 1000 ] && [ "$_uid" -lt 65000 ]; then
        set -- "$@" "$_user" "UID: $_uid"
        [ "$_user" = "administrateur" ] && FOUND_ADMIN=1
    fi
done < /etc/passwd

if [ "$FOUND_ADMIN" -eq 0 ]; then
    set -- "administrateur" "Create default admin (UID 1001)" "$@"
fi

exec 3>&1
TARGET_USER=$(bsddialog --backtitle "$BACKTITLE" --title "User Selection" --clear \
    --default-item "administrateur" \
    --menu "Select or create the main administrator user:" 15 65 6 "$@" 2>&1 1>&3)
MENU_EXIT=$?
exec 3>&-

[ $MENU_EXIT -ne 0 ] && handle_cancel

# ---------------------------------------------------------
# 3. Desktop Environment Selection
# ---------------------------------------------------------
exec 3>&1
DE_CHOICE=$(bsddialog --backtitle "$BACKTITLE" --title "Desktop Environment" --clear \
    --menu "Select your preferred Desktop (X11 strictly enforced):" 15 70 4 \
    "gnome"   "GNOME (Modern & Feature-rich, cleaned X11 session)" \
    "plasma6" "KDE Plasma 6 (Highly Customizable)" \
    "xfce"    "XFCE 4 (Lightweight & Fast)" \
    "mate"    "MATE Desktop (Classic & Stable)" \
    2>&1 1>&3)
MENU_EXIT=$?
exec 3>&-

[ $MENU_EXIT -ne 0 ] && handle_cancel

case "$DE_CHOICE" in
    "gnome")
        DE_PKGS="gnome gnome-tweaks gnome-themes-extra"
        STARTWM_EXEC="exec gnome-session"
        ;;
    "plasma6")
        DE_PKGS="plasma6-plasma kf6-frameworks qt6-5compat konsole dolphin kate ark Kvantum xwayland"
        STARTWM_EXEC="exec ck-launch-session startplasma-x11"
        ;;
    "xfce")
        DE_PKGS="xfce xfce4-goodies"
        STARTWM_EXEC="exec ck-launch-session startxfce4"
        ;;
    "mate")
        DE_PKGS="mate"
        STARTWM_EXEC="exec ck-launch-session mate-session"
        ;;
esac

# ---------------------------------------------------------
# 4. NVIDIA GPU Auto-Detection & Split Driver Selection
# ---------------------------------------------------------
DETECTED_NVIDIA=$(pciconf -lv | awk -F"'" '/vendor.*NVIDIA/ {getline; print $2}' | head -n 1)
NVIDIA_DEFAULT_CHOICE="latest"

if [ -n "$DETECTED_NVIDIA" ]; then
    case "$DETECTED_NVIDIA" in
        *GeForce*4[0-9][0-9]* | *GeForce*5[0-9][0-9]* | *Quadro\ 4000* | *Quadro\ 5000* | *Quadro\ 6000* | *NVS\ 4200* | *NVS\ 5200*)
            NVIDIA_DEFAULT_CHOICE="390"
            ;;
        *GeForce*6[0-9][0-9]* | *GeForce*7[0-4][0-9]* | *GeForce*7[6-9][0-9]* | *Quadro\ K* | *NVS\ 310* | *NVS\ 510*)
            NVIDIA_DEFAULT_CHOICE="470"
            ;;
        *GeForce*9[0-9][0-9]* | *GeForce*10[0-9][0-9]* | *Quadro\ M* | *Quadro\ P* | *TITAN\ X* | *TITAN\ V*)
            NVIDIA_DEFAULT_CHOICE="580"
            ;;
        *)
            NVIDIA_DEFAULT_CHOICE="latest"
            ;;
    esac
    NVIDIA_MSG="Detected GPU: $DETECTED_NVIDIA\n\nBased on the 2026 NVIDIA support matrix, the recommended driver branch has been pre-selected:"
else
    NVIDIA_MSG="No NVIDIA GPU was automatically detected.\n\nSelect the NVIDIA driver branch for your hardware:"
fi

exec 3>&1
NVIDIA_CHOICE=$(bsddialog --backtitle "$BACKTITLE" --title "NVIDIA Drivers (FreeBSD 15.1 Split Architecture)" --clear \
    --default-item "$NVIDIA_DEFAULT_CHOICE" \
    --menu "$NVIDIA_MSG" 17 78 4 \
    "latest" "Production Branch (Turing, Ampere, Ada, Blackwell)" \
    "580"    "Legacy Maxwell/Pascal/Volta (GTX 900/10-series, Quadro P/M)" \
    "470"    "Legacy Kepler (GeForce 600/700, Quadro K)" \
    "390"    "Legacy Fermi (GeForce 400/500, Quadro Fermi)" \
    2>&1 1>&3)
MENU_EXIT=$?
exec 3>&-

[ $MENU_EXIT -ne 0 ] && handle_cancel

if [ "$NVIDIA_CHOICE" = "latest" ]; then
    NVIDIA_PKG="nvidia-driver nvidia-kmod linux-nvidia-libs"
else
    NVIDIA_PKG="nvidia-driver-${NVIDIA_CHOICE} nvidia-kmod-${NVIDIA_CHOICE} linux-nvidia-libs-${NVIDIA_CHOICE}"
fi

LOCK_NVIDIA=1
if bsddialog --backtitle "$BACKTITLE" --title "NVIDIA Package Lock" --clear \
    --yesno "Do you want to lock the NVIDIA driver and kernel module packages after installation to prevent unintended breakage during upgrades?" 10 75; then
    LOCK_NVIDIA=0
fi

# ---------------------------------------------------------
# 5. Screen Resolution & Theme Customization
# ---------------------------------------------------------
exec 3>&1
RES_CHOICE=$(bsddialog --backtitle "$BACKTITLE" --title "Screen Resolution" --clear \
    --default-item "2560x1440" \
    --menu "Select your native monitor resolution for the boot splash screen:" 15 65 4 \
    "1920x1080" "Full HD (16:9)" \
    "1920x1200" "WUXGA (16:10)" \
    "2560x1440" "QHD / 2K (16:9)" \
    "3840x2160" "4K UHD (16:9)" \
    2>&1 1>&3)
MENU_EXIT=$?
exec 3>&-

[ $MENU_EXIT -ne 0 ] && handle_cancel

exec 3>&1
SDDM_THEME_CHOICE=$(bsddialog --backtitle "$BACKTITLE" --title "SDDM Login Theme" --clear \
    --menu "Select the visual theme for the SDDM login screen:" 13 70 2 \
    "nasa"     "Custom NASA Theme (Cloned from Maldives + GitHub assets)" \
    "maldives" "Standard Maldives Theme (Clean FreeBSD default)" \
    2>&1 1>&3)
MENU_EXIT=$?
exec 3>&-

[ $MENU_EXIT -ne 0 ] && handle_cancel

# ---------------------------------------------------------
# 6. Optional Software & Services Checklist
# ---------------------------------------------------------
exec 3>&1
APP_CHOICES=$(bsddialog --backtitle "$BACKTITLE" --title "Software & Services Selection" --clear \
    --checklist "Select additional applications and services to configure:" 18 78 6 \
    "INTERNET" "Firefox, Thunderbird & Telegram Desktop" ON \
    "OFFICE"   "MS Teams & Office 365 WebApps (Chromium engine)" ON \
    "FONTS"    "Essential desktop fonts & Noto Emojis" ON \
    "VBOX"     "VirtualBox 7.2 (virtualbox-ose-72 + kmod)" OFF \
    "XRDP"     "Remote Desktop Protocol (RDP) server access" OFF \
    "SAMBA"    "Samba 4.20 network share (Configures /home/share)" OFF \
    2>&1 1>&3)
MENU_EXIT=$?
exec 3>&-

[ $MENU_EXIT -ne 0 ] && handle_cancel

SAMBA_PASS=""
if echo "$APP_CHOICES" | grep -q "SAMBA"; then
    exec 3>&1
    SAMBA_PASS=$(bsddialog --backtitle "$BACKTITLE" --title "Samba Password" --clear \
        --passwordbox "Enter the Samba password for user '${TARGET_USER}' (leave empty to set manually later):" 10 70 2>&1 1>&3 || true)
    exec 3>&-
fi

# ---------------------------------------------------------
# 7. Auto-detect CPU, Locale & Keyboard from System
# ---------------------------------------------------------
CPU_MODEL=$(sysctl -n hw.model 2>/dev/null || echo "Unknown")
CPU_TYPE="generic"
case "$CPU_MODEL" in
    *AMD*|*Threadripper*|*Ryzen*|*EPYC*) CPU_TYPE="amd" ;;
    *Intel*|*Core*|*Xeon*)               CPU_TYPE="intel" ;;
esac

KEYMAP=$(sysrc -n keymap 2>/dev/null || echo "ch.acc.kbd")

LOCALE_CHOICE="fr_CH.UTF-8"
LOGIN_CLASS="french"
XKB_LAYOUT="ch"
XKB_VARIANT="fr"

case "$KEYMAP" in
    *ch*)
        LOCALE_CHOICE="fr_CH.UTF-8"
        LOGIN_CLASS="french"
        XKB_LAYOUT="ch"
        XKB_VARIANT="fr"
        ;;
    *fr*|*be*)
        LOCALE_CHOICE="fr_FR.UTF-8"
        LOGIN_CLASS="french"
        XKB_LAYOUT="fr"
        XKB_VARIANT=""
        ;;
    *sg*)
        LOCALE_CHOICE="de_CH.UTF-8"
        LOGIN_CLASS="german"
        XKB_LAYOUT="ch"
        XKB_VARIANT="de"
        ;;
    *de*)
        LOCALE_CHOICE="de_DE.UTF-8"
        LOGIN_CLASS="german"
        XKB_LAYOUT="de"
        XKB_VARIANT=""
        ;;
    *us*)
        LOCALE_CHOICE="en_US.UTF-8"
        LOGIN_CLASS="default"
        XKB_LAYOUT="us"
        XKB_VARIANT=""
        ;;
esac

# ---------------------------------------------------------
# 8. Final Confirmation
# ---------------------------------------------------------
CONFIRM="All necessary information has been collected:

- User:        $TARGET_USER
- CPU Model:   $CPU_TYPE ($CPU_MODEL)
- Desktop:     $DE_CHOICE (X11 enforced, SDDM Theme: $SDDM_THEME_CHOICE)
- NVIDIA:      $NVIDIA_CHOICE ($NVIDIA_PKG)
- Splash Res:  $RES_CHOICE (v2-blue.png)
- Keymap:      $KEYMAP -> Locale: $LOCALE_CHOICE ($XKB_LAYOUT $XKB_VARIANT)
- Extra Apps:  $APP_CHOICES

Package installation and system configuration will now begin.
All output will be logged to /var/log/install_workstation.log.
Do you want to proceed?"

if ! bsddialog --backtitle "$BACKTITLE" --title "Confirmation" --clear --yesno "$CONFIRM" 19 75; then
    handle_cancel
fi

trap - INT TERM
clear
stty sane

MASTER_LOG="/var/log/install_workstation.log"
echo "=== Starting Automated Installation (Logged to $MASTER_LOG) ==="

{
# =========================================================
# BEGIN TECHNICAL EXECUTION
# =========================================================

# 1. Repository Stabilization (QUARTERLY First)
echo "[+] Checking and stabilizing PKG repositories on QUARTERLY branch..."
mkdir -p /usr/local/etc/pkg/repos
NEED_DOWNGRADE_STABILIZE=0

if grep -Eq "(/latest|kmods_latest)" /etc/pkg/FreeBSD.conf /usr/local/etc/pkg/repos/*.conf 2>/dev/null; then
    echo "[!] Detected 'latest' branch in PKG configuration. Retrograding to 'quarterly' for initial stability..."
    NEED_DOWNGRADE_STABILIZE=1
fi

for CONF_FILE in /usr/local/etc/pkg/repos/*.conf; do
    [ -e "$CONF_FILE" ] || continue
    if [ "$CONF_FILE" != "/usr/local/etc/pkg/repos/FreeBSD.conf" ]; then
        rm -f "$CONF_FILE"
    fi
done

if [ -f /etc/pkg/FreeBSD.conf ]; then
    sed -i '' 's/enabled:[[:space:]]*no/enabled: yes/g' /etc/pkg/FreeBSD.conf 2>/dev/null || true
    sed -i '' 's/\/latest/\/quarterly/g' /etc/pkg/FreeBSD.conf 2>/dev/null || true
    sed -i '' 's/kmods_latest_/kmods_quarterly_/g' /etc/pkg/FreeBSD.conf 2>/dev/null || true
fi

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

if [ ! -f /var/db/pkg/local.sqlite ]; then
    env ASSUME_ALWAYS_YES=YES pkg bootstrap -f
fi

pkg unlock -a -q -y 2>/dev/null || true
env ASSUME_ALWAYS_YES=YES pkg update -f

if [ "$NEED_DOWNGRADE_STABILIZE" -eq 1 ]; then
    env ASSUME_ALWAYS_YES=YES pkg upgrade -f -y
    env ASSUME_ALWAYS_YES=YES pkg autoremove -y || true
else
    env ASSUME_ALWAYS_YES=YES pkg upgrade -y
fi

# 2. Pre-requisites (Enable Linux Kernel modules before pkg install)
echo "[+] Loading 64-bit Linux kernel modules..."
kldload -n linux >/dev/null 2>&1 || true
kldload -n linux64 >/dev/null 2>&1 || true

sysrc linux_enable="YES"
sysrc linux_mounts_enable="YES"
service linux start >/dev/null 2>&1 || true

# 3. Dynamic Package List Construction & Installation
echo "[+] Building package list and installing software..."
PKG_LIST="xorg xauth xinit xterm setxkbmap consolekit2 $DE_PKGS sddm"
PKG_LIST="$PKG_LIST vlc ffmpeg mpv gstreamer1-plugins gstreamer1-plugins-bad gstreamer1-plugins-ugly"
PKG_LIST="$PKG_LIST pulseaudio pipewire wireplumber pavucontrol freedesktop-sound-theme webcamd v4l-utils"
PKG_LIST="$PKG_LIST bsdisks fusefs-ntfs fusefs-exfat fusefs-ext2"
PKG_LIST="$PKG_LIST cups cups-filters gutenprint hplip system-config-printer"
PKG_LIST="$PKG_LIST unzip wget htop btop fastfetch smartmontools dbus avahi-app seatd ImageMagick7"
PKG_LIST="$PKG_LIST $NVIDIA_PKG nvidia-settings nvidia-xconfig linux-rl9"

[ "$CPU_TYPE" != "generic" ] && PKG_LIST="$PKG_LIST cpu-microcode"

echo "$APP_CHOICES" | grep -q "INTERNET" && PKG_LIST="$PKG_LIST firefox thunderbird telegram-desktop"
echo "$APP_CHOICES" | grep -q "OFFICE"   && PKG_LIST="$PKG_LIST chromium webfonts"
echo "$APP_CHOICES" | grep -q "FONTS"    && PKG_LIST="$PKG_LIST noto-basic noto-emoji webfonts hack-font roboto-fonts-ttf"
echo "$APP_CHOICES" | grep -q "VBOX"     && PKG_LIST="$PKG_LIST virtualbox-ose-72 virtualbox-ose-kmod-72"
echo "$APP_CHOICES" | grep -q "XRDP"     && PKG_LIST="$PKG_LIST xrdp xorgxrdp"
echo "$APP_CHOICES" | grep -q "SAMBA"    && PKG_LIST="$PKG_LIST samba420"

env ASSUME_ALWAYS_YES=YES pkg install -y $PKG_LIST

if [ "$LOCK_NVIDIA" -eq 0 ]; then
    echo "[+] Locking NVIDIA packages..."
    pkg lock -q -y $NVIDIA_PKG 2>/dev/null || true
fi

# 4. Custom Splash Screen & Bootloader Optimizations
echo "[+] Configuring custom splash screen (Native PNG for vt) and loader.conf..."
mkdir -p /boot/images

fetch -o /tmp/v2-blue.png https://raw.githubusercontent.com/msartor99/FreeBSD14/main/v2-blue.png || true

if [ -f "/tmp/v2-blue.png" ]; then
    if [ "$RES_CHOICE" != "2560x1440" ]; then
        echo "[+] Resizing PNG splash screen to $RES_CHOICE in /tmp..."
        magick /tmp/v2-blue.png -resize "${RES_CHOICE}!" /tmp/splash.png || cp /tmp/v2-blue.png /tmp/splash.png
    else
        cp /tmp/v2-blue.png /tmp/splash.png
    fi
    cp /tmp/splash.png /boot/images/splash.png
fi

sysrc -f /boot/loader.conf splash="/boot/images/splash.png"
sysrc -f /boot/loader.conf shutdown_splash="/boot/images/splash.png"
sysrc -f /boot/loader.conf boot_mute="YES"
sysrc -f /boot/loader.conf autoboot_delay="3"
sysrc -f /boot/loader.conf tmpfs_load="YES"
sysrc -f /boot/loader.conf aio_load="YES"
sysrc -f /boot/loader.conf sound_load="YES"
sysrc -f /boot/loader.conf snd_hda_load="YES"
sysrc -f /boot/loader.conf hw.nvidia.registry.EnableGpuFirmware="1"

# Clean up any legacy BMP variables
sysrc -f /boot/loader.conf -x splash_bmp_load 2>/dev/null || true
sysrc -f /boot/loader.conf -x bitmap_load 2>/dev/null || true
sysrc -f /boot/loader.conf -x bitmap_name 2>/dev/null || true

# CPU Microcode & Thermal Sensors
if [ "$CPU_TYPE" = "amd" ]; then
    sysrc -f /boot/loader.conf amdtemp_load="YES"
    sysrc -f /boot/loader.conf cpu_microcode_load="YES"
    sysrc -f /boot/loader.conf cpu_microcode_name="/boot/firmware/amd-ucode.bin"
    sysrc microcode_update_enable="YES"
elif [ "$CPU_TYPE" = "intel" ]; then
    sysrc -f /boot/loader.conf coretemp_load="YES"
    sysrc -f /boot/loader.conf cpu_microcode_load="YES"
    sysrc -f /boot/loader.conf cpu_microcode_name="/boot/firmware/intel-ucode.bin"
    sysrc microcode_update_enable="YES"
fi

# 5. Kernel Optimizations (Non-destructive for Aquantia)
echo "[+] Setting up kernel parameters (sysctl.conf)..."
apply_sysctl "kern.ipc.shm_allow_removed" "1"
apply_sysctl "kern.ipc.shm_use_phys" "1"
apply_sysctl "net.local.stream.recvspace" "65536"
apply_sysctl "net.local.stream.sendspace" "65536"
apply_sysctl "vfs.usermount" "1"
apply_sysctl "hw.snd.default_unit" "1"
apply_sysctl "hw.kbd.keymap_restrict_change" "4"
apply_sysctl "kern.evdev.rcpt_mask" "12"

service sysctl reload >/dev/null 2>&1 || true

# 6. System Services, File Systems & Devfs Rules
echo "[+] Configuring system services (rc.conf, fstab, devfs.rules)..."
sysrc rc_startmsgs="NO"
sysrc dbus_enable="YES"
sysrc sddm_enable="YES"
sysrc sddm_lang="$LOCALE_CHOICE"
sysrc cupsd_enable="YES"
sysrc avahi_daemon_enable="YES"
sysrc seatd_enable="YES"
sysrc webcamd_enable="YES"
sysrc smartd_enable="YES"

[ ! -f /usr/local/etc/smartd.conf ] && [ -f /usr/local/etc/smartd.conf.sample ] && cp /usr/local/etc/smartd.conf.sample /usr/local/etc/smartd.conf

for mod in nvidia-modeset fusefs ext2fs; do
    if ! sysrc -n kld_list 2>/dev/null | grep -qw "$mod"; then
        sysrc kld_list+="$mod"
    fi
done

if ! grep -qw "^proc" /etc/fstab; then
    echo "proc		/proc		procfs	rw		0	0" >> /etc/fstab
fi
if [ ! -d "/proc/0" ] && [ -d "/proc" ]; then
    mount -t procfs proc /proc || true
fi

if ! grep -qw "^fdesc" /etc/fstab; then
    echo "fdescfs		/dev/fd		fdescfs	rw		0	0" >> /etc/fstab
fi
if [ ! -d "/dev/fd/0" ] && [ -d "/dev/fd" ]; then
    mount -t fdescfs fdescfs /dev/fd || true
fi

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
service devfs restart >/dev/null 2>&1 || true

# 7. User Creation, Groups & Localization
echo "[+] Configuring user account ($TARGET_USER) and localization..."
if ! id "$TARGET_USER" >/dev/null 2>&1; then
    pw useradd "$TARGET_USER" -u 1001 -m -G wheel,operator,video -s /bin/sh -c "System Administrator"
fi

if ! pw groupshow cups >/dev/null 2>&1; then pw groupadd cups; fi

for GRP in wheel operator video seatd cups vboxusers; do
    if pw groupshow "$GRP" >/dev/null 2>&1; then
        if ! pw groupshow "$GRP" | grep -qw "$TARGET_USER"; then
            pw groupmod "$GRP" -m "$TARGET_USER" 2>/dev/null || true
        fi
    fi
done

if [ "$LOGIN_CLASS" != "default" ]; then
    if ! grep -q "^${LOGIN_CLASS}|" /etc/login.conf; then
        cat >> /etc/login.conf << EOF

${LOGIN_CLASS}|Localized Users Accounts:\\
    :charset=UTF-8:\\
    :lang=${LOCALE_CHOICE}:\\
    :setenv=LC_ALL=${LOCALE_CHOICE},LC_COLLATE=${LOCALE_CHOICE},LC_CTYPE=${LOCALE_CHOICE},LC_MESSAGES=${LOCALE_CHOICE}:\\
    :tc=default:
EOF
    fi

    if [ -f /etc/adduser.conf ] && grep -q "^defaultclass=" /etc/adduser.conf; then
        sed -i '' -e "s/^defaultclass=.*/defaultclass=${LOGIN_CLASS}/" /etc/adduser.conf
    else
        echo "defaultclass=${LOGIN_CLASS}" >> /etc/adduser.conf
    fi
fi

cap_mkdb /etc/login.conf
pw usermod root -L "$LOGIN_CLASS"
pw usermod "$TARGET_USER" -L "$LOGIN_CLASS"

if [ -d "/home/$TARGET_USER" ]; then
    cat > "/home/$TARGET_USER/.xinitrc" << EOF
#!/bin/sh
export LANG=${LOCALE_CHOICE}
export LC_ALL=${LOCALE_CHOICE}
${STARTWM_EXEC}
EOF
    chown "$TARGET_USER:$TARGET_USER" "/home/$TARGET_USER/.xinitrc"
    chmod 0755 "/home/$TARGET_USER/.xinitrc"
fi

# 8. X11, SDDM, GNOME Cleanup & NASA Theme Configuration
echo "[+] Configuring Xorg, SDDM, Keyboard, and Desktop sessions..."
mkdir -p /usr/local/etc/X11/xorg.conf.d
cat <<EOF > /usr/local/etc/X11/xorg.conf.d/00-keyboard.conf
Section "ServerFlags"
    Option "DontZap" "false"
EndSection

Section "InputClass"
    Identifier "system-keyboard"
    MatchIsKeyboard "on"
    Option "XkbLayout" "$XKB_LAYOUT"
    Option "XkbVariant" "$XKB_VARIANT"
    Option "XkbOptions" "terminate:ctrl_alt_bksp"
EndSection
EOF

/usr/local/bin/nvidia-xconfig

echo "[+] Forcing X11: Disabling Wayland sessions for SDDM..."
if [ -d "/usr/local/share/wayland-sessions" ]; then
    mv /usr/local/share/wayland-sessions /usr/local/share/wayland-sessions.disabled || true
fi

if [ "$DE_CHOICE" = "gnome" ]; then
    echo "[+] Cleaning up redundant GNOME session entries (Keeping only gnome-xorg)..."
    [ -f "/usr/local/share/xsessions/gnome.desktop" ] && mv /usr/local/share/xsessions/gnome.desktop /usr/local/share/xsessions/gnome.desktop.disabled
    [ -f "/usr/local/share/xsessions/gnome-classic.desktop" ] && mv /usr/local/share/xsessions/gnome-classic.desktop /usr/local/share/xsessions/gnome-classic.desktop.disabled
    [ -f "/usr/local/share/xsessions/gnome-classic-xorg.desktop" ] && mv /usr/local/share/xsessions/gnome-classic-xorg.desktop /usr/local/share/xsessions/gnome-classic-xorg.desktop.disabled
fi

# SDDM Keyboard enforcement (Xsetup + kxkbrc)
XSETUP_FILE="/usr/local/share/sddm/scripts/Xsetup"
mkdir -p /usr/local/share/sddm/scripts
cat > "$XSETUP_FILE" << EOF
#!/bin/sh
if [ -x /usr/local/bin/setxkbmap ]; then
    if [ -n "${XKB_VARIANT}" ]; then
        /usr/local/bin/setxkbmap ${XKB_LAYOUT} ${XKB_VARIANT}
    else
        /usr/local/bin/setxkbmap ${XKB_LAYOUT}
    fi
fi
EOF
chmod 0755 "$XSETUP_FILE"

mkdir -p /var/db/sddm/.config
cat > /var/db/sddm/.config/kxkbrc << EOF
[Layout]
DisplayNames=
LayoutList=${XKB_LAYOUT}
Use=true
VariantList=${XKB_VARIANT}
EOF
chown -R sddm:sddm /var/db/sddm/.config 2>/dev/null || true
pw groupmod video -m sddm 2>/dev/null || true

# SDDM Theme Setup (Maldives or Custom NASA)
ACTIVE_SDDM_THEME="maldives"
if [ "$SDDM_THEME_CHOICE" = "nasa" ]; then
    mkdir -p /tmp/fb_nasa_assets
    for REPO_URL in \
        "https://raw.githubusercontent.com/msartor99/FreeBSD15/main" \
        "https://raw.githubusercontent.com/msartor99/FreeBSD14/main"; do
        [ ! -s /tmp/fb_nasa_assets/nasa2560login.jpg ] && fetch -q -o /tmp/fb_nasa_assets/nasa2560login.jpg "${REPO_URL}/nasa2560login.jpg" 2>/dev/null || true
        [ ! -s /tmp/fb_nasa_assets/nasa_4k_wallpaper.jpg ] && fetch -q -o /tmp/fb_nasa_assets/nasa_4k_wallpaper.jpg "${REPO_URL}/wp8860763-nasa-4k-wallpapers.jpg" 2>/dev/null || true
        [ ! -s /tmp/fb_nasa_assets/theme.conf ] && fetch -q -o /tmp/fb_nasa_assets/theme.conf "${REPO_URL}/theme.conf" 2>/dev/null || true
        [ ! -s /tmp/fb_nasa_assets/metadata.desktop ] && fetch -q -o /tmp/fb_nasa_assets/metadata.desktop "${REPO_URL}/metadata.desktop" 2>/dev/null || true
    done

    SDDM_THEMES_DIR="/usr/local/share/sddm/themes"
    if [ -d "${SDDM_THEMES_DIR}/maldives" ] && [ -s /tmp/fb_nasa_assets/nasa2560login.jpg ]; then
        echo "[+] Creating custom 'nasa' SDDM theme..."
        rm -rf "${SDDM_THEMES_DIR}/nasa"
        cp -R "${SDDM_THEMES_DIR}/maldives" "${SDDM_THEMES_DIR}/nasa"
        cp /tmp/fb_nasa_assets/nasa2560login.jpg "${SDDM_THEMES_DIR}/nasa/nasa2560login.jpg"
        chmod 0644 "${SDDM_THEMES_DIR}/nasa/nasa2560login.jpg"

        if [ -s /tmp/fb_nasa_assets/theme.conf ]; then
            cp /tmp/fb_nasa_assets/theme.conf "${SDDM_THEMES_DIR}/nasa/theme.conf"
            chmod 0644 "${SDDM_THEMES_DIR}/nasa/theme.conf"
        elif [ -f "${SDDM_THEMES_DIR}/nasa/theme.conf" ]; then
            sed -i '' 's|^background=.*|background=nasa2560login.jpg|g' "${SDDM_THEMES_DIR}/nasa/theme.conf"
        fi

        if [ -s /tmp/fb_nasa_assets/metadata.desktop ]; then
            cp /tmp/fb_nasa_assets/metadata.desktop "${SDDM_THEMES_DIR}/nasa/metadata.desktop"
            chmod 0644 "${SDDM_THEMES_DIR}/nasa/metadata.desktop"
        fi
        ACTIVE_SDDM_THEME="nasa"
    fi

    if [ "$DE_CHOICE" = "plasma6" ] && [ -s /tmp/fb_nasa_assets/nasa_4k_wallpaper.jpg ]; then
        mkdir -p /usr/local/share/wallpapers/NASA_4K/contents/images
        cp /tmp/fb_nasa_assets/nasa_4k_wallpaper.jpg /usr/local/share/wallpapers/NASA_4K/contents/images/3840x2160.jpg
        cat > /usr/local/share/wallpapers/NASA_4K/metadata.desktop << 'EOF_KDE'
[Desktop Entry]
Name=NASA 4K
X-KDE-PluginInfo-Name=NASA_4K
EOF_KDE
    fi
fi

mkdir -p /usr/local/etc/sddm.conf.d
cat <<EOF > /usr/local/etc/sddm.conf.d/10-x11-theme.conf
[General]
DisplayServer=x11

[Theme]
Current=$ACTIVE_SDDM_THEME
EOF

# 9. Optional Applications Configuration (Office WebApps, VBox, XRDP, Samba)
if echo "$APP_CHOICES" | grep -q "OFFICE"; then
    echo "[+] Creating MS Teams and Office 365 WebApp launchers..."
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
    echo "[+] Configuring VirtualBox 7.2 services and permissions..."
    sysrc -f /boot/loader.conf vboxdrv_load="YES"
    sysrc vboxnet_enable="YES"
    pw groupmod vboxusers -m root 2>/dev/null || true
    pw groupmod vboxusers -m "$TARGET_USER" 2>/dev/null || true
    add_line_if_missing "own vboxnetctl root:vboxusers" /etc/devfs.conf
    add_line_if_missing "perm vboxnetctl 0660" /etc/devfs.conf
fi

if echo "$APP_CHOICES" | grep -q "XRDP"; then
    echo "[+] Configuring XRDP remote desktop server..."
    sysrc xrdp_enable="YES"
    sysrc xrdp_sesman_enable="YES"
    mkdir -p /usr/local/etc/xrdp
    cat > /usr/local/etc/xrdp/startwm.sh << EOF
#!/bin/sh
export LANG=${LOCALE_CHOICE}
export LC_ALL=${LOCALE_CHOICE}
${STARTWM_EXEC}
EOF
    chmod 0755 /usr/local/etc/xrdp/startwm.sh
fi

if echo "$APP_CHOICES" | grep -q "SAMBA"; then
    echo "[+] Configuring Samba 4.20 share (/home/share)..."
    if [ -n "$SAMBA_PASS" ]; then
        (echo "$SAMBA_PASS"; echo "$SAMBA_PASS") | smbpasswd -s -a "$TARGET_USER" >/dev/null 2>&1 || true
    fi
    mkdir -p /home/share
    chown "$TARGET_USER:wheel" /home/share
    chmod 0775 /home/share
    cat > /usr/local/etc/smb4.conf << EOF
[global]
    unix charset = UTF-8
    workgroup = HOMELAB
    server string = FreeBSD Workstation
    map to guest = bad user
[Share]
    path = /home/share
    writable = yes
    valid users = ${TARGET_USER}
    guest ok = no
    force create mode = 0775
EOF
    sysrc samba_server_enable="YES"
fi

echo "[+] Base installation on QUARTERLY branch completed successfully!"
} 2>&1 | tee -a "$MASTER_LOG"

# =========================================================
# 10. OPTIONAL SWITCH TO 'LATEST' REPOSITORY BRANCH (DEFAULT: NO)
# =========================================================
if bsddialog --backtitle "$BACKTITLE" --title "Switch to LATEST Repository Branch?" --clear --defaultno \
    --yesno "All base packages and desktop components are now safely installed on the QUARTERLY repository.\n\nDo you want to switch your package repository to 'latest' now and upgrade installed packages?\n(Recommended: Select 'No' to avoid missing packages during Poudriere build cycles)." 13 78; then
    {
        echo "[+] Switching PKG repositories to 'latest' branch..."
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
        env ASSUME_ALWAYS_YES=YES pkg update -f
        env ASSUME_ALWAYS_YES=YES pkg upgrade -y || echo "[-] Warning: Some packages could not be upgraded right now, keeping quarterly versions."
        echo "[+] Repository switch to 'latest' completed!"
    } 2>&1 | tee -a "$MASTER_LOG"
else
    echo "[i] Keeping system on the stable 'quarterly' repository branch." | tee -a "$MASTER_LOG"
fi

# =========================================================
# END OF EXECUTION
# =========================================================
bsddialog --backtitle "$BACKTITLE" --title "Success" --clear \
    --msgbox "Installation and configuration completed successfully!\n\nFull log saved to: $MASTER_LOG\nPlease restart the system to initialize SDDM ($DE_CHOICE on X11)." 11 65

clear
echo "Type 'reboot' to restart your workstation."
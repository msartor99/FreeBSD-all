#!/bin/sh
#
# Interactive Post-Installation Script (FreeBSD 15.1)
# Uses bsddialog to configure Desktop Environment, SDDM, Linuxulator, NVIDIA, Audio and system optimizations.
# Asks for display resolution to auto-scale the PNG splash screen.
# Strictly enforces X11, keeps one clean GNOME session (gnome-xorg), and preserves custom configs.
#

set -e

BACKTITLE="FreeBSD 15.1 Post-Installation Configuration"

# ---------------------------------------------------------
# Cancellation Handler Function
# ---------------------------------------------------------
handle_cancel() {
    clear
    echo "Operation canceled by the user. No changes were made."
    exit 1
}

# ---------------------------------------------------------
# 1. Welcome Screen / Disclaimer
# ---------------------------------------------------------
DISCLAIMER="WARNING:

This automated script will configure your base system into a complete workstation:
- Install Xorg, your chosen Desktop Environment, SDDM, and standard utilities.
- Auto-detect NVIDIA GPU and deploy the correct driver (X11 only) + Linuxulator.
- Configure modern Audio stack (PipeWire/PulseAudio) and HDA kernel modules.
- Optimize the kernel and boot process (with custom-scaled native PNG splash).
- Auto-configure X11 keyboard layout & custom login class based on rc.conf.
- Add user to required groups (wheel, operator, video, cups).

Do you want to begin the configuration process?"

if ! bsddialog --backtitle "$BACKTITLE" --title "Disclaimer" --clear --yesno "$DISCLAIMER" 17 75; then
    handle_cancel
fi

# ---------------------------------------------------------
# 2. Target User Selection
# ---------------------------------------------------------
set --
while IFS=: read -r _user _pass _uid _gid _rest; do
    if [ "$_uid" -ge 1000 ] && [ "$_uid" -lt 65000 ]; then
        set -- "$@" "$_user" "UID: $_uid"
    fi
done < /etc/passwd

if [ $# -eq 0 ]; then
    bsddialog --backtitle "$BACKTITLE" --title "Error" --clear --msgbox "No regular user found in /etc/passwd!" 8 50
    exit 1
fi

exec 3>&1
TARGET_USER=$(bsddialog --backtitle "$BACKTITLE" --title "User Selection" --clear \
    --menu "Select the user to configure (administrative rights):" 15 60 5 "$@" 2>&1 1>&3)
MENU_EXIT=$?
exec 3>&-

[ $MENU_EXIT -ne 0 ] && handle_cancel

# ---------------------------------------------------------
# 3. Desktop Environment Selection
# ---------------------------------------------------------
exec 3>&1
DE_CHOICE=$(bsddialog --backtitle "$BACKTITLE" --title "Desktop Environment" --clear \
    --menu "Select your preferred Desktop (X11 strictly enforced):" 15 70 4 \
    "gnome"   "GNOME (Modern & Feature-rich)" \
    "plasma6" "KDE Plasma 6 (Highly Customizable)" \
    "xfce"    "XFCE (Lightweight & Fast)" \
    "mate"    "MATE (Classic & Stable)" \
    2>&1 1>&3)
MENU_EXIT=$?
exec 3>&-

[ $MENU_EXIT -ne 0 ] && handle_cancel

case "$DE_CHOICE" in
    "gnome")   DE_PKGS="gnome gnome-tweaks gnome-themes-extra" ;;
    "plasma6") DE_PKGS="plasma6" ;;
    "xfce")    DE_PKGS="xfce xfce4-goodies" ;;
    "mate")    DE_PKGS="mate" ;;
esac

# ---------------------------------------------------------
# 4. NVIDIA GPU Auto-Detection & Selection
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
    NVIDIA_MSG="Detected GPU: $DETECTED_NVIDIA\n\nBased on the NVIDIA support matrix, the recommended driver branch has been pre-selected for you."
else
    NVIDIA_MSG="No NVIDIA GPU was automatically detected.\n\nChoose the driver version suitable for your graphics card:"
fi

exec 3>&1
NVIDIA_CHOICE=$(bsddialog --backtitle "$BACKTITLE" --title "NVIDIA Drivers" --clear \
    --default-item "$NVIDIA_DEFAULT_CHOICE" \
    --menu "$NVIDIA_MSG" 17 75 4 \
    "latest" "Turing, Ampere, Ada (RTX 20+ / GTX 16+)" \
    "580"    "Legacy Maxwell/Pascal/Volta (GTX 900/10-series, Quadro P)" \
    "470"    "Legacy Kepler (GeForce 600/700, Quadro K)" \
    "390"    "Legacy Fermi (GeForce 400/500, Quadro Fermi)" \
    2>&1 1>&3)
MENU_EXIT=$?
exec 3>&-

[ $MENU_EXIT -ne 0 ] && handle_cancel

case "$NVIDIA_CHOICE" in
    "390") NVIDIA_PKG="nvidia-driver-390" ;;
    "470") NVIDIA_PKG="nvidia-driver-470" ;;
    "580") NVIDIA_PKG="nvidia-driver-580" ;;
    *)     NVIDIA_PKG="nvidia-driver" ;;
esac

# ---------------------------------------------------------
# 5. Screen Resolution Selection
# ---------------------------------------------------------
exec 3>&1
RES_CHOICE=$(bsddialog --backtitle "$BACKTITLE" --title "Screen Resolution" --clear \
    --menu "Select your native monitor resolution for the boot splash screen:" 15 65 4 \
    "1920x1080" "Full HD (16:9)" \
    "1920x1200" "WUXGA (16:10)" \
    "2560x1440" "QHD / 2K (16:9)" \
    "3840x2160" "4K UHD (16:9)" \
    2>&1 1>&3)
MENU_EXIT=$?
exec 3>&-

[ $MENU_EXIT -ne 0 ] && handle_cancel

# ---------------------------------------------------------
# 6. Auto-detect Locale & Keyboard from rc.conf
# ---------------------------------------------------------
KEYMAP=$(sysrc -n keymap 2>/dev/null || echo "us")

LOCALE_CHOICE="en_US.UTF-8"
LOGIN_CLASS="default"
XKB_LAYOUT="us"
XKB_VARIANT=""

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
        ;;
esac

# ---------------------------------------------------------
# 7. Final Confirmation
# ---------------------------------------------------------
CONFIRM="All necessary information has been collected:

- User:       $TARGET_USER
- Desktop:    $DE_CHOICE
- NVIDIA:     $NVIDIA_PKG
- Resolution: $RES_CHOICE
- Auto-detect Keymap: $KEYMAP
  -> Locale:  $LOCALE_CHOICE (Class: $LOGIN_CLASS)
  -> X11:     $XKB_LAYOUT (Variant: $XKB_VARIANT)

Package installation and system configuration will now begin.
Do you want to proceed?"

if ! bsddialog --backtitle "$BACKTITLE" --title "Confirmation" --clear --yesno "$CONFIRM" 17 65; then
    handle_cancel
fi

# =========================================================
# BEGIN TECHNICAL EXECUTION
# =========================================================
clear
echo "=== Starting Installation and Configuration ==="

# 1. Pre-requisites (Enable Linux Kernel modules before pkg install)
echo "[+] Loading 64-bit Linux kernel modules for pkg installation..."
kldload linux >/dev/null 2>&1 || true
kldload linux64 >/dev/null 2>&1 || true

sysrc linux_enable="YES"
sysrc linux_mounts_enable="YES"

# 2. Package Installation
echo "[+] Installing software (this may take a while)..."
pkg update
pkg install -y \
  xorg $DE_PKGS sddm \
  firefox thunderbird telegram-desktop \
  vlc ffmpeg gstreamer1-plugins gstreamer1-plugins-bad gstreamer1-plugins-ugly \
  pulseaudio pipewire wireplumber pavucontrol freedesktop-sound-theme \
  bsdisks fusefs-ntfs fusefs-exfat \
  cups cups-filters gutenprint hplip system-config-printer \
  ImageMagick7 \
  $NVIDIA_PKG nvidia-settings nvidia-xconfig linux-rl9

# 3. Custom Splash Screen & Boot Optimizations
echo "[+] Configuring custom splash screen (Native PNG for vt)..."
mkdir -p /boot/images

# Step A: Download to /tmp
fetch -o /tmp/v2-blue.png https://raw.githubusercontent.com/msartor99/FreeBSD14/main/v2-blue.png || true

# Step B: Resize in /tmp, then copy to final destination
if [ -f "/tmp/v2-blue.png" ]; then
    if [ "$RES_CHOICE" != "2560x1440" ]; then
        echo "[+] Resizing PNG splash screen to exactly $RES_CHOICE in /tmp..."
        magick /tmp/v2-blue.png -resize "${RES_CHOICE}!" /tmp/splash.png || cp /tmp/v2-blue.png /tmp/splash.png
    else
        cp /tmp/v2-blue.png /tmp/splash.png
    fi
    
    # Step C: Copy to /boot/images/ (keeping files in /tmp for debugging)
    cp /tmp/splash.png /boot/images/splash.png
fi

# Step D: Apply configuration to loader.conf
sysrc -f /boot/loader.conf splash="/boot/images/splash.png"
sysrc -f /boot/loader.conf shutdown_splash="/boot/images/splash.png"
sysrc -f /boot/loader.conf boot_mute="YES"
sysrc -f /boot/loader.conf autoboot_delay="3"
sysrc -f /boot/loader.conf tmpfs_load="YES"
sysrc -f /boot/loader.conf sound_load="YES"
sysrc -f /boot/loader.conf snd_hda_load="YES"
sysrc rc_startmsgs="NO"

# Clean up any legacy BMP variables just in case
sysrc -f /boot/loader.conf -x splash_bmp_load 2>/dev/null || true
sysrc -f /boot/loader.conf -x bitmap_load 2>/dev/null || true
sysrc -f /boot/loader.conf -x bitmap_name 2>/dev/null || true

# 4. Kernel Optimizations
echo "[+] Setting up kernel parameters (sysctl.conf)..."
apply_sysctl() {
    local key="$1"
    local val="$2"
    if grep -q "^${key}=" /etc/sysctl.conf; then
        sed -i '' -e "s|^${key}=.*|${key}=${val}|" /etc/sysctl.conf
    else
        echo "${key}=${val}" >> /etc/sysctl.conf
    fi
}

apply_sysctl "kern.ipc.shm_allow_removed" "1"
apply_sysctl "net.local.stream.recvspace" "65536"
apply_sysctl "net.local.stream.sendspace" "65536"
apply_sysctl "vfs.usermount" "1"
apply_sysctl "hw.snd.default_unit" "1"

service sysctl reload >/dev/null 2>&1 || true

# 5. System Services & File Systems
echo "[+] Configuring system services (rc.conf & fstab)..."
sysrc dbus_enable="YES"
sysrc sddm_enable="YES"
sysrc cupsd_enable="YES"
sysrc sddm_lang="$LOCALE_CHOICE"

service linux start >/dev/null 2>&1 || true

for mod in nvidia-modeset fusefs; do
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

if ! grep -qw "^fdescfs" /etc/fstab; then
    echo "fdescfs		/dev/fd		fdescfs	rw		0	0" >> /etc/fstab
fi
if [ ! -d "/dev/fd/0" ] && [ -d "/dev/fd" ]; then
    mount -t fdescfs fdescfs /dev/fd || true
fi

# 6. SDDM Theme, X11 Keyboard, GNOME Sessions & NVIDIA Configuration
echo "[+] Configuring Display Manager and Desktop Environment..."

mkdir -p /usr/local/etc/X11/xorg.conf.d
cat <<EOF > /usr/local/etc/X11/xorg.conf.d/00-keyboard.conf
Section "InputClass"
    Identifier "system-keyboard"
    MatchIsKeyboard "on"
    Option "XkbLayout" "$XKB_LAYOUT"
    Option "XkbVariant" "$XKB_VARIANT"
EndSection
EOF

mkdir -p /usr/local/etc/sddm.conf.d
cat <<EOF > /usr/local/etc/sddm.conf.d/10-x11-theme.conf
[General]
DisplayServer=x11

[Theme]
Current=maldives
EOF

echo "[+] Forcing X11: Disabling Wayland sessions for SDDM..."
if [ -d "/usr/local/share/wayland-sessions" ]; then
    mv /usr/local/share/wayland-sessions /usr/local/share/wayland-sessions.disabled || true
fi

if [ "$DE_CHOICE" = "gnome" ]; then
    echo "[+] Cleaning up redundant GNOME session entries..."
    # Disable default Wayland launcher and Classic modes, keeping only gnome-xorg.desktop
    if [ -f "/usr/local/share/xsessions/gnome.desktop" ]; then
        mv /usr/local/share/xsessions/gnome.desktop /usr/local/share/xsessions/gnome.desktop.disabled
    fi
    if [ -f "/usr/local/share/xsessions/gnome-classic.desktop" ]; then
        mv /usr/local/share/xsessions/gnome-classic.desktop /usr/local/share/xsessions/gnome-classic.desktop.disabled
    fi
    if [ -f "/usr/local/share/xsessions/gnome-classic-xorg.desktop" ]; then
        mv /usr/local/share/xsessions/gnome-classic-xorg.desktop /usr/local/share/xsessions/gnome-classic-xorg.desktop.disabled
    fi
fi

XSETUP_FILE="/usr/local/share/sddm/scripts/Xsetup"
mkdir -p /usr/local/share/sddm/scripts
touch "$XSETUP_FILE"
chmod +x "$XSETUP_FILE"

if [ -n "$XKB_VARIANT" ]; then
    grep -q "setxkbmap $XKB_LAYOUT $XKB_VARIANT" "$XSETUP_FILE" || echo "setxkbmap $XKB_LAYOUT $XKB_VARIANT" >> "$XSETUP_FILE"
else
    grep -q "setxkbmap $XKB_LAYOUT" "$XSETUP_FILE" || echo "setxkbmap $XKB_LAYOUT" >> "$XSETUP_FILE"
fi

/usr/local/bin/nvidia-xconfig

# 7. User and Groups
echo "[+] Applying permissions and groups for $TARGET_USER..."
if ! pw groupshow cups >/dev/null 2>&1; then pw groupadd cups; fi

for GRP in wheel operator video cups; do
    if pw groupshow "$GRP" >/dev/null 2>&1; then
        if ! pw groupshow "$GRP" | grep -qw "$TARGET_USER"; then
            pw groupmod "$GRP" -m "$TARGET_USER"
        fi
    fi
done

# 8. Localization (Login classes & adduser.conf)
echo "[+] Configuring system locale and custom login classes..."
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

# =========================================================
# END OF EXECUTION
# =========================================================
bsddialog --backtitle "$BACKTITLE" --title "Success" --clear \
    --msgbox "Installation and configuration completed successfully!\n\nWayland and redundant sessions have been disabled.\nPlease restart the system to initialize SDDM ($DE_CHOICE on X11)." 11 60

clear
echo "Type 'reboot' to restart."
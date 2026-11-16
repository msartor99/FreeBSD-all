#!/bin/sh
#
# Interactive Post-Installation Script (FreeBSD 15.1)
# Uses bsddialog to configure GNOME, SDDM, Linuxulator, NVIDIA, and system optimizations.
# Automatically infers locale and X11 keyboard layout from rc.conf keymap.
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
- Install Xorg, GNOME, SDDM, and standard utilities.
- Deploy NVIDIA drivers and Linuxulator.
- Optimize the kernel and boot process.
- Auto-configure X11 keyboard layout & locale based on rc.conf.
- Add user to required groups (wheel, operator, video, cups).

Do you want to begin the configuration process?"

if ! bsddialog --backtitle "$BACKTITLE" --title "Disclaimer" --clear --yesno "$DISCLAIMER" 15 75; then
    handle_cancel
fi

# ---------------------------------------------------------
# 2. Target User Selection (Safe POSIX array building)
# ---------------------------------------------------------
# Clear positional parameters to securely build the menu array
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
# 3. NVIDIA Driver Selection
# ---------------------------------------------------------
exec 3>&1
NVIDIA_CHOICE=$(bsddialog --backtitle "$BACKTITLE" --title "NVIDIA Drivers" --clear \
    --menu "Choose the driver version suitable for your graphics card:" 15 70 3 \
    "latest" "Recent cards (Default)" \
    "580"    "Intermediate generation" \
    "470"    "Older cards (e.g., Kepler architecture)" \
    2>&1 1>&3)
MENU_EXIT=$?
exec 3>&-

[ $MENU_EXIT -ne 0 ] && handle_cancel

case "$NVIDIA_CHOICE" in
    "470") NVIDIA_PKG="nvidia-driver-470" ;;
    "580") NVIDIA_PKG="nvidia-driver-580" ;;
    *)     NVIDIA_PKG="nvidia-driver" ;;
esac

# ---------------------------------------------------------
# 4. Auto-detect Locale & Keyboard from rc.conf
# ---------------------------------------------------------
KEYMAP=$(sysrc -n keymap 2>/dev/null || echo "us")

# Defaults
LOCALE_CHOICE="en_US.UTF-8"
LOGIN_CLASS="default"
XKB_LAYOUT="us"
XKB_VARIANT=""

# Translate FreeBSD console keymap to Locale and X11 layout
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
    *sg*) # Swiss German
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
# 5. Final Confirmation
# ---------------------------------------------------------
CONFIRM="All necessary information has been collected:

- User:       $TARGET_USER
- NVIDIA:     $NVIDIA_PKG
- Auto-detect Keymap: $KEYMAP
  -> Locale:  $LOCALE_CHOICE
  -> X11:     $XKB_LAYOUT (Variant: $XKB_VARIANT)

Package installation and system configuration will now begin.
Do you want to proceed?"

if ! bsddialog --backtitle "$BACKTITLE" --title "Confirmation" --clear --yesno "$CONFIRM" 15 65; then
    handle_cancel
fi

# =========================================================
# BEGIN TECHNICAL EXECUTION
# =========================================================
clear
echo "=== Starting Installation and Configuration ==="

# 1. Package Installation
echo "[+] Installing software (this may take a while)..."
pkg update
pkg install -y \
  xorg gnome gnome-tweaks gnome-themes-extra sddm \
  firefox thunderbird telegram-desktop \
  vlc ffmpeg gstreamer1-plugins gstreamer1-plugins-bad gstreamer1-plugins-ugly \
  bsdisks fusefs-ntfs fusefs-exfat \
  cups cups-filters gutenprint hplip system-config-printer \
  $NVIDIA_PKG nvidia-settings linux-rl9

# 2. Boot Optimizations
echo "[+] Configuring bootloader (loader.conf)..."
sysrc -f /boot/loader.conf boot_mute="YES"
sysrc -f /boot/loader.conf autoboot_delay="3"
sysrc -f /boot/loader.conf tmpfs_load="YES"
sysrc rc_startmsgs="NO"

# 3. Kernel Optimizations
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

apply_sysctl "kern.sched.preempt_thresh" "224"
apply_sysctl "kern.ipc.shm_allow_removed" "1"
apply_sysctl "net.local.stream.recvspace" "65536"
apply_sysctl "net.local.stream.sendspace" "65536"
apply_sysctl "vfs.usermount" "1"

service sysctl reload || true

# 4. System Services & Linuxulator
echo "[+] Configuring system services (rc.conf & fstab)..."
sysrc dbus_enable="YES"
sysrc sddm_enable="YES"
sysrc cupsd_enable="YES"
sysrc linux_enable="YES"
sysrc linux_mounts_enable="YES"

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

# 5. SDDM Theme & Keyboard Configuration
echo "[+] Configuring SDDM (Maldives theme) and X11 Keyboard..."
mkdir -p /usr/local/etc/sddm.conf.d
printf "[Theme]\nCurrent=maldives\n" > /usr/local/etc/sddm.conf.d/10-theme.conf

mkdir -p /usr/local/etc/X11/xorg.conf.d
cat <<EOF > /usr/local/etc/X11/xorg.conf.d/00-keyboard.conf
Section "InputClass"
    Identifier "system-keyboard"
    MatchIsKeyboard "on"
    Option "XkbLayout" "$XKB_LAYOUT"
    Option "XkbVariant" "$XKB_VARIANT"
EndSection
EOF

# 6. User and Groups
echo "[+] Applying permissions and groups for $TARGET_USER..."
if ! pw groupshow cups >/dev/null 2>&1; then pw groupadd cups; fi

for GRP in wheel operator video cups; do
    if pw groupshow "$GRP" >/dev/null 2>&1; then
        if ! pw groupshow "$GRP" | grep -qw "$TARGET_USER"; then
            pw groupmod "$GRP" -m "$TARGET_USER"
        fi
    fi
done

# 7. Localization
echo "[+] Configuring system locale ($LOCALE_CHOICE)..."
if [ "$LOGIN_CLASS" != "default" ]; then
    sed -i '' -e "/^${LOGIN_CLASS}|/,/:tc=default:/ s/:lang=[^:]*:/:lang=${LOCALE_CHOICE}:/" /etc/login.conf
    sed -i '' -e "/^${LOGIN_CLASS}|/,/:tc=default:/ s/:charset=[^:]*:/:charset=UTF-8:/" /etc/login.conf
fi

cap_mkdb /etc/login.conf
pw usermod root -L "$LOGIN_CLASS"
pw usermod "$TARGET_USER" -L "$LOGIN_CLASS"

# =========================================================
# END OF EXECUTION
# =========================================================
bsddialog --backtitle "$BACKTITLE" --title "Success" --clear \
    --msgbox "Installation and configuration completed successfully!\n\nPlease restart the system to initialize SDDM, the Linuxulator, and NVIDIA drivers." 10 60

clear
echo "Type 'reboot' to restart."
#!/bin/sh
# ==============================================================================
# File: install-workstation-v5.5.sh
# Version: 5.5 (2026-11-09)
# Description: Interactive, idempotent FreeBSD 15.1 X11 Workstation Installer
# Target OS: FreeBSD 15.1-RELEASE (amd64) - Pure X11 / Xorg (No Wayland)
# Verified Packages against FreeBSD 15.1 Official Ports Tree (Nov 2026):
#   - NVIDIA Legacy 470 (Kepler & Maxwell: Quadro K-series, Quadro M4000 -> nvidia-driver-470 / nvidia-kmod-470)
#   - NVIDIA Legacy 580 (Pascal & Maxwell: Quadro P2000, P4000, M4000 -> nvidia-driver-580 / nvidia-kmod-580)
#   - NVIDIA Current 595+ (Turing/Ampere/Ada: Quadro RTX 4000, RTX A4000, RTX 4000, RTX 3060 -> nvidia-driver / nvidia-kmod)
#   - AMD Radeon RX 550 (drm-kmod + gpu-firmware-kmod + xf86-video-amdgpu)
#   - Hybrid Intel + NVIDIA Optimus (drm-kmod + nvidia-driver + nvidia-kmod)
#   - Pure POSIX sh PCI BusID parser for HP Z4 G4 / Xeon multi-root PCIe
#   - Custom SDDM 'nasa' theme cloned from 'maldives' (/tmp/fb14 assets + QtVersion=6 metadata.desktop)
# ==============================================================================

set -e

VERSION="5.5"
DEFAULT_USER="administrateur"
DEFAULT_UID="1001"
BACKTITLE="FreeBSD 15.1 Workstation Installer v${VERSION} (X11 Edition)"
TMP_CHOICE="/tmp/bsddialog_choice.$$"

# Clean up temporary file on exit
trap 'rm -f "${TMP_CHOICE}"' EXIT INT TERM

export PATH="/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin"
export TERM="${TERM:-xterm}"

# ------------------------------------------------------------------------------
# 0. Root Privilege & Environment Check
# ------------------------------------------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root (use su - or doas/sudo)." >&2
    exit 1
fi

if ! command -v bsddialog >/dev/null 2>&1; then
    echo "ERROR: bsddialog is not available on this base system." >&2
    exit 1
fi

# ------------------------------------------------------------------------------
# Helper Functions for Strict Idempotence & Pure POSIX PCI BusID Detection
# ------------------------------------------------------------------------------

set_sysctl_conf() {
    _key="$1"
    _val="$2"
    _file="/etc/sysctl.conf"
    touch "${_file}"
    if grep -q "^${_key}=" "${_file}" 2>/dev/null; then
        sed -i '' "s|^${_key}=.*|${_key}=${_val}|" "${_file}"
    else
        echo "${_key}=${_val}" >> "${_file}"
    fi
}

set_sshd_config() {
    _key="$1"
    _val="$2"
    _file="/etc/ssh/sshd_config"
    if grep -q "^#*[[:space:]]*${_key}[[:space:]]" "${_file}" 2>/dev/null; then
        sed -i '' "s|^#*[[:space:]]*${_key}[[:space:]].*|${_key} ${_val}|" "${_file}"
    else
        echo "${_key} ${_val}" >> "${_file}"
    fi
}

ensure_fstab_entry() {
    _spec="$1"
    _mp="$2"
    _type="$3"
    _opts="$4"
    _dump="$5"
    _pass="$6"
    if ! awk -v mp="${_mp}" '$2 == mp { found=1 } END { exit !found }' /etc/fstab 2>/dev/null; then
        printf "%-10s %-12s %-10s %-6s %-3s %s\n" "${_spec}" "${_mp}" "${_type}" "${_opts}" "${_dump}" "${_pass}" >> /etc/fstab
    fi
}

# Pure POSIX /bin/sh PCI BusID parser for FreeBSD pciconf -l
# Format parsed: vgapci0@pci0:33:0:0: ... (4 fields) OR vgapci0@pci0:0:33:0:0: ... (5 fields)
get_vga_busid() {
    _pci_tok=$(pciconf -l 2>/dev/null | grep "^vgapci" | head -n 1 | cut -d' ' -f1 | cut -f1)
    if [ -n "${_pci_tok}" ]; then
        _addr="${_pci_tok#*@pci}"
        _addr="${_addr%:}"
        _old_ifs="${IFS}"
        IFS=":"
        set -- ${_addr}
        IFS="${_old_ifs}"
        if [ "$#" -eq 4 ]; then
            echo "PCI:$2:$3:$4"
        elif [ "$#" -eq 5 ]; then
            echo "PCI:$3:$4:$5"
        fi
    fi
}

# ------------------------------------------------------------------------------
# Hardware Auto-Detection (Pre-selects defaults in bsddialog)
# ------------------------------------------------------------------------------
CPU_MODEL=$(sysctl -n hw.model 2>/dev/null || echo "Unknown")
INTEL_ON="on"
AMD_CPU_ON="off"
case "${CPU_MODEL}" in
    *AMD*|*amd*)
        INTEL_ON="off"
        AMD_CPU_ON="on"
        ;;
esac

VGA_INFO=$(pciconf -lv 2>/dev/null | grep -B4 -i "VGA" || true)
DETECTED_BUSID=$(get_vga_busid)

NV470_ON="off"
NV580_ON="on"
NVCUR_ON="off"
AMD_GPU_ON="off"
HYBRID_ON="off"

case "${VGA_INFO}" in
    *M4000*|*M2000*|*K5200*|*K4200*|*K2200*|*Kepler*)
        NV470_ON="on"
        NV580_ON="off"
        ;;
    *P2000*|*P4000*|*GTX\ 10*)
        NV580_ON="on"
        ;;
    *RTX*|*A4000*|*3060*)
        NV580_ON="off"
        NVCUR_ON="on"
        ;;
    *Radeon*|*AMD*|*ATI*|*RX\ 550*)
        NV580_ON="off"
        AMD_GPU_ON="on"
        ;;
esac

# ------------------------------------------------------------------------------
# 1. Interactive TUI Menus (bsddialog writing to temp file via 2> TMP_CHOICE)
# ------------------------------------------------------------------------------

# 1.1 Disclaimer Acceptance
if ! bsddialog --backtitle "${BACKTITLE}" \
    --title "DISCLAIMER OF LIABILITY" \
    --ok-label "I Accept" \
    --cancel-label "Decline & Exit" \
    --yesno "WARNING: This automated script will install packages and modify core FreeBSD 15.1 system configuration files (/boot/loader.conf, /etc/rc.conf, /etc/sysctl.conf, /etc/login.conf, /etc/devfs.rules, X11 configs).\n\nAlthough designed to be strictly idempotent, this software is provided 'AS IS' without warranty of any kind. The author assumes no responsibility or liability for any data loss, hardware damage, or system instability.\n\nDo you accept full responsibility and wish to proceed?" 16 76; then
    echo "Installation cancelled by operator (disclaimer declined)."
    exit 0
fi

# 1.2 Class 1: CPU Model Selection (Radiolist)
if ! bsddialog --backtitle "${BACKTITLE}" \
    --title "1/5 - Processor Architecture" \
    --radiolist "Detected CPU: ${CPU_MODEL}\nSelect the installed CPU model (Space to select, Enter to confirm):" 13 76 2 \
    "INTEL" "Intel CPU / Xeon W-21xx (coretemp + intel-ucode.bin)" "${INTEL_ON}" \
    "AMD"   "AMD CPU (amdtemp + amd-ucode.bin)" "${AMD_CPU_ON}" \
    2> "${TMP_CHOICE}"; then
    echo "Cancelled at CPU selection."
    exit 0
fi
CPU_CHOICE=$(tr -d '"' < "${TMP_CHOICE}")

if [ -z "${CPU_CHOICE}" ]; then
    echo "ERROR: No CPU architecture selected. Exiting."
    exit 1
fi

# 1.3 Class 2: Graphic Card Selection (Radiolist)
if ! bsddialog --backtitle "${BACKTITLE}" \
    --title "2/5 - Graphics Card Driver (Pure X11 - BusID: ${DETECTED_BUSID:-Auto})" \
    --radiolist "Select the graphics hardware configuration (Space to select):" 16 84 5 \
    "NVIDIA_470" "NVIDIA Maxwell/Kepler (Quadro M4000, M2000, K5200) -> 470-Legacy" "${NV470_ON}" \
    "NVIDIA_580" "NVIDIA Pascal/Maxwell (Quadro P2000, P4000, M4000) -> 580-LTS" "${NV580_ON}" \
    "NVIDIA_CUR" "NVIDIA RTX (Quadro RTX 4000, RTX A4000, RTX 4000, RTX 3060) -> 595+" "${NVCUR_ON}" \
    "AMD"        "AMD Radeon RX 550 (drm-kmod + amdgpu + TearFree)" "${AMD_GPU_ON}" \
    "HYBRID"     "Hybrid Intel + NVIDIA Optimus (i915kms + nvidia-modeset)" "${HYBRID_ON}" \
    2> "${TMP_CHOICE}"; then
    echo "Cancelled at GPU selection."
    exit 0
fi
GPU_CHOICE=$(tr -d '"' < "${TMP_CHOICE}")

if [ -z "${GPU_CHOICE}" ]; then
    echo "ERROR: No GPU configuration selected. Exiting."
    exit 1
fi

# 1.4 Screen Resolution Management (Native vs 4K 3840x2160 Downscale to 2560x1440)
if ! bsddialog --backtitle "${BACKTITLE}" \
    --title "3/5 - Display Resolution Policy" \
    --radiolist "Select how the GPU driver should handle display resolution:" 13 78 2 \
    "AUTO"        "Native EDID Auto-Detection (Let the GPU driver manage resolution)" on \
    "FORCE_1440P" "4K Monitor (3840x2160) -> Force downscale to 2560x1440" off \
    2> "${TMP_CHOICE}"; then
    echo "Cancelled at Display Resolution selection."
    exit 0
fi
RES_CHOICE=$(tr -d '"' < "${TMP_CHOICE}")

if [ -z "${RES_CHOICE}" ]; then
    RES_CHOICE="AUTO"
fi

# 1.5 Class 3: Desktop Environments Selection (Checklist)
if ! bsddialog --backtitle "${BACKTITLE}" \
    --title "4/5 - Desktop Environments (X11)" \
    --checklist "Select one or more Desktop Environments (Space to toggle):" 13 76 3 \
    "PLASMA6" "KDE Plasma 6 Desktop (X11 session + KDE base apps)" on \
    "MATE"    "MATE Desktop Environment" off \
    "XFCE4"   "XFCE 4 Lightweight Desktop + Goodies" off \
    2> "${TMP_CHOICE}"; then
    echo "Cancelled at Desktop selection."
    exit 0
fi
DE_CHOICES=$(tr -d '"' < "${TMP_CHOICE}")

# 1.6 Class 4: Application Suites Selection (Checklist)
if ! bsddialog --backtitle "${BACKTITLE}" \
    --title "5/5 - Application Suites & Categories" \
    --checklist "Select the software categories to install (Space to toggle):" 14 76 4 \
    "MULTIMEDIA" "Multimedia (VLC, MPV, FFmpeg, GStreamer, DVD/BluRay)" on \
    "OFFICE"     "Office & Web (Firefox, LibreOffice FR, Thunderbird, Okular)" on \
    "VIRT"       "Virtualization (VirtualBox 7.2 + Kernel Modules & USB)" on \
    "FONTS"      "Extended Fonts (Noto, Liberation, DejaVu, Droid, Webfonts)" on \
    2> "${TMP_CHOICE}"; then
    echo "Cancelled at Application selection."
    exit 0
fi
APP_CHOICES=$(tr -d '"' < "${TMP_CHOICE}")

# 1.7 Final Summary Confirmation
if ! bsddialog --backtitle "${BACKTITLE}" \
    --title "Confirm Configuration" \
    --ok-label "Start Install" \
    --cancel-label "Cancel" \
    --yesno "Ready to apply idempotent configuration:\n\n- CPU Profile : ${CPU_CHOICE}\n- GPU Driver  : ${GPU_CHOICE} (BusID: ${DETECTED_BUSID:-Auto})\n- Resolution  : ${RES_CHOICE}\n- Desktops    : ${DE_CHOICES:-None}\n- App Suites  : ${APP_CHOICES:-None}\n- SDDM Theme  : nasa (Qt6 custom metadata.desktop)\n- Default User: ${DEFAULT_USER} (Swiss French locale & X11 layout)\n\nProceed with installation?" 17 76; then
    echo "Installation aborted by operator."
    exit 0
fi

echo "======================================================================"
echo " Starting FreeBSD 15.1 Workstation Deployment (v${VERSION})..."
echo "======================================================================"

# ------------------------------------------------------------------------------
# 2. Package Manager Bootstrap & Base Privileges
# ------------------------------------------------------------------------------
echo "[1/11] Updating package repositories and installing privilege tools..."
env ASSUME_ALWAYS_YES=yes pkg bootstrap -f
pkg update -f
pkg install -y sudo doas

mkdir -p /usr/local/etc/sudoers.d
echo "%wheel ALL=(ALL:ALL) ALL" > /usr/local/etc/sudoers.d/wheel
chmod 0440 /usr/local/etc/sudoers.d/wheel

cat > /usr/local/etc/doas.conf << 'EOF'
permit persist :wheel
permit nopass root as root
EOF
chmod 0600 /usr/local/etc/doas.conf

# ------------------------------------------------------------------------------
# 3. Base System, SSH, Boot Loader & Sysctl Tuning
# ------------------------------------------------------------------------------
echo "[2/11] Applying base system, SSH, loader.conf, and sysctl tuning..."
sysrc sshd_enable="YES"
set_sshd_config "PermitRootLogin" "yes"
service sshd restart || service sshd start || true

if [ -f /bin/freebsd-update ] || [ -f /usr/sbin/freebsd-update ]; then
    PAGER=/bin/cat freebsd-update --not-running-from-cron fetch install || true
fi

sysrc -f /boot/loader.conf boot_mute="YES"
sysrc -f /boot/loader.conf autoboot_delay="3"
sysrc -f /boot/loader.conf tmpfs_load="YES"
sysrc -f /boot/loader.conf aio_load="YES"
sysrc -f /boot/loader.conf sound_load="YES"
sysrc -f /boot/loader.conf snd_hda_load="YES"

# Apply or remove 2560x1440 cap in loader.conf depending on 4K screen choice
if [ "${RES_CHOICE}" = "FORCE_1440P" ]; then
    sysrc -f /boot/loader.conf efi_max_resolution="1440p"
    sysrc -f /boot/loader.conf kern.vt.fb.default_mode="2560x1440"
else
    sysrc -f /boot/loader.conf -x efi_max_resolution 2>/dev/null || true
    sysrc -f /boot/loader.conf -x kern.vt.fb.default_mode 2>/dev/null || true
fi

# Clean up any leftover Wayland/DRM tunable in loader.conf that breaks X11 on M4000/P4000
sysrc -f /boot/loader.conf -x hw.nvidiadrm.modeset 2>/dev/null || true
sysrc -f /boot/loader.conf -x hw.nvidia.registry.EnableGpuFirmware 2>/dev/null || true

sysrc rc_startmsgs="NO"

set_sysctl_conf "kern.sched.preempt_thresh" "224"
set_sysctl_conf "kern.ipc.shm_allow_removed" "1"
set_sysctl_conf "net.local.stream.recvspace" "65536"
set_sysctl_conf "net.local.stream.sendspace" "65536"
set_sysctl_conf "vfs.usermount" "1"
set_sysctl_conf "hw.snd.default_unit" "1"
service sysctl reload || true

# ------------------------------------------------------------------------------
# 4. French / Swiss-Romand Locale Class & Default User Setup
# ------------------------------------------------------------------------------
echo "[3/11] Configuring UTF-8 French login class and user ${DEFAULT_USER}..."
if ! grep -q "^french|French Users Accounts:" /etc/login.conf 2>/dev/null; then
    cat >> /etc/login.conf << 'EOF'

french|French Users Accounts:\
	:charset=UTF-8:\
	:lang=fr_CH.UTF-8:\
	:setenv=LC_ALL=fr_CH.UTF-8,LC_COLLATE=fr_CH.UTF-8,LC_CTYPE=fr_CH.UTF-8,LC_MESSAGES=fr_CH.UTF-8:\
	:tc=default:
EOF
    cap_mkdb /etc/login.conf
fi

echo "defaultclass=french" > /etc/adduser.conf

if ! pw usershow "${DEFAULT_USER}" >/dev/null 2>&1; then
    pw useradd -n "${DEFAULT_USER}" -u "${DEFAULT_UID}" -m -s /bin/sh -L french -G wheel,operator,video
fi

pw usermod "${DEFAULT_USER}" -L french
pw usermod root -L french
for _grp in wheel operator video; do
    pw groupmod "${_grp}" -m "${DEFAULT_USER}" 2>/dev/null || true
done

# ------------------------------------------------------------------------------
# 5. CPU Microcode & Thermal Sensors (Class 1)
# ------------------------------------------------------------------------------
echo "[4/11] Configuring CPU microcode and thermal driver (${CPU_CHOICE})..."
pkg install -y cpu-microcode
sysrc -f /boot/loader.conf cpu_microcode_load="YES"
sysrc microcode_update_enable="YES"

case "${CPU_CHOICE}" in
    INTEL)
        sysrc -f /boot/loader.conf -x amdtemp_load 2>/dev/null || true
        sysrc -f /boot/loader.conf coretemp_load="YES"
        sysrc -f /boot/loader.conf cpu_microcode_name="/boot/firmware/intel-ucode.bin"
        kldload -n coretemp 2>/dev/null || true
        ;;
    AMD)
        sysrc -f /boot/loader.conf -x coretemp_load 2>/dev/null || true
        sysrc -f /boot/loader.conf amdtemp_load="YES"
        sysrc -f /boot/loader.conf cpu_microcode_name="/boot/firmware/amd-ucode.bin"
        kldload -n amdtemp 2>/dev/null || true
        ;;
esac
service microcode_update start || true

# ------------------------------------------------------------------------------
# 6. Linuxulator, Base Utilities, CUPS, USB & Devfs Rules
# ------------------------------------------------------------------------------
echo "[5/11] Installing Linux compatibility (Rocky 9), base utilities, and CUPS..."
sysrc linux_enable="YES"
sysrc linux_mounts_enable="YES"
service linux start || true
pkg install -y linux-rl9

pkg install -y unzip libzip wget git htop btop fastfetch python3 ImageMagick7 smartmontools

if [ ! -f /usr/local/etc/smartd.conf ] && [ -f /usr/local/etc/smartd.conf.sample ]; then
    cp /usr/local/etc/smartd.conf.sample /usr/local/etc/smartd.conf
fi
sysrc smartd_enable="YES"
service smartd restart || service smartd start || true

pkg install -y cups gutenprint cups-filters hplip system-config-printer
pkg install -y fusefs-ntfs fusefs-ext2 fusefs-hfsfuse

sysrc kld_list+="fusefs ext2fs"
kldload -n fusefs 2>/dev/null || true
kldload -n ext2fs 2>/dev/null || true

pw groupmod cups -m "${DEFAULT_USER}" 2>/dev/null || true
sysrc cupsd_enable="YES"
service cupsd restart || service cupsd start || true

pkg install -y pulseaudio pipewire wireplumber pavucontrol freedesktop-sound-theme

# ------------------------------------------------------------------------------
# 7. Xorg Server & Swiss-Romand Keyboard Configuration
# ------------------------------------------------------------------------------
echo "[6/11] Installing Xorg (X11) and configuring Swiss French keyboard..."
pkg install -y xorg dbus avahi signal-cli xdg-user-dirs octopkg

sysrc dbus_enable="YES"
sysrc avahi_daemon_enable="YES"

ensure_fstab_entry "proc"  "/proc"   "procfs"  "rw" "0" "0"
ensure_fstab_entry "fdesc" "/dev/fd" "fdescfs" "rw" "0" "0"
mount -a || true

service dbus restart || service dbus start || true
service avahi-daemon restart || service avahi-daemon start || true

# Remove any legacy monolithic /etc/X11/xorg.conf generated by nvidia-xconfig
rm -f /etc/X11/xorg.conf /usr/local/etc/X11/xorg.conf

mkdir -p /usr/local/etc/X11/xorg.conf.d
cat > /usr/local/etc/X11/xorg.conf.d/20-keyboards.conf << 'EOF'
Section "ServerFlags"
    Option "DontZap" "false"
EndSection

Section "InputClass"
    Identifier      "All Keyboards"
    MatchIsKeyboard "yes"
    Option          "XkbLayout" "ch"
    Option          "XkbVariant" "fr"
    Option          "XkbOptions" "terminate:ctrl_alt_bksp"
EndSection
EOF

# ------------------------------------------------------------------------------
# 8. Graphics Driver & X11 Display Configuration (Class 2)
# ------------------------------------------------------------------------------
# Re-detect BusID right before writing Xorg config in case kernel modules changed vgapci
DETECTED_BUSID=$(get_vga_busid)
echo "[7/11] Installing GPU driver and X11 configuration (${GPU_CHOICE}, BusID: ${DETECTED_BUSID:-Auto}, Res: ${RES_CHOICE})..."

# Clean conflicting GPU kernel modules from kld_list before adding the selected one
sysrc kld_list-="nvidia" 2>/dev/null || true
sysrc kld_list-="nvidia-modeset" 2>/dev/null || true
sysrc kld_list-="nvidia-drm" 2>/dev/null || true
sysrc kld_list-="amdgpu" 2>/dev/null || true
sysrc kld_list-="i915kms" 2>/dev/null || true
sysrc -x nvidia_modeset_enable 2>/dev/null || true

write_nvidia_xorg_conf() {
    _busid_line=""
    if [ -n "${DETECTED_BUSID}" ]; then
        _busid_line="    BusID          \"${DETECTED_BUSID}\""
    fi

    if [ "${RES_CHOICE}" = "FORCE_1440P" ]; then
        cat > /usr/local/etc/X11/xorg.conf.d/10-nvidia.conf << EOF
Section "Device"
    Identifier     "NVIDIA Card"
    Driver         "nvidia"
${_busid_line}
    Option         "ModeValidation" "NoMaxResolutionCheck"
EndSection

Section "Monitor"
    Identifier     "Monitor0"
    VendorName     "Unknown"
    ModelName      "Unknown"
EndSection

Section "Screen"
    Identifier     "Screen0"
    Device         "NVIDIA Card"
    Monitor        "Monitor0"
    DefaultDepth    24
    Option         "MetaModes" "2560x1440 +0+0"
    SubSection "Display"
        Depth       24
        Modes      "2560x1440"
    EndSubSection
EndSection
EOF
    else
        # Default: Let the NVIDIA driver manage native resolution + explicit PCI BusID for HP Z4 G4 Xeon
        cat > /usr/local/etc/X11/xorg.conf.d/10-nvidia.conf << EOF
Section "Device"
    Identifier     "NVIDIA Card"
    Driver         "nvidia"
${_busid_line}
EndSection
EOF
    fi
}

write_amd_xorg_conf() {
    _busid_line=""
    if [ -n "${DETECTED_BUSID}" ]; then
        _busid_line="    BusID          \"${DETECTED_BUSID}\""
    fi

    if [ "${RES_CHOICE}" = "FORCE_1440P" ]; then
        cat > /usr/local/etc/X11/xorg.conf.d/10-amdgpu.conf << EOF
Section "Device"
    Identifier     "AMD Radeon RX 550"
    Driver         "amdgpu"
${_busid_line}
    Option         "TearFree" "true"
EndSection

Section "Monitor"
    Identifier     "Monitor0"
    Option         "PreferredMode" "2560x1440"
EndSection

Section "Screen"
    Identifier     "Screen0"
    Device         "AMD Radeon RX 550"
    Monitor        "Monitor0"
    DefaultDepth    24
    SubSection "Display"
        Depth       24
        Modes      "2560x1440"
    EndSubSection
EndSection
EOF
    else
        cat > /usr/local/etc/X11/xorg.conf.d/10-amdgpu.conf << EOF
Section "Device"
    Identifier     "AMD Radeon RX 550"
    Driver         "amdgpu"
${_busid_line}
    Option         "TearFree" "true"
EndSection
EOF
    fi
}

case "${GPU_CHOICE}" in
    NVIDIA_470)
        # Supports Maxwell (Quadro M4000, M2000) & Kepler (Quadro K5200, K4200, K2200)
        rm -f /usr/local/etc/X11/xorg.conf.d/10-amdgpu.conf
        kldunload nvidia-modeset nvidia 2>/dev/null || true
        pkg delete -y nvidia-drm-kmod nvidia-drm-61-kmod nvidia-drm-66-kmod nvidia-drm-612-kmod \
            nvidia-drm-kmod-580 nvidia-drm-61-kmod-580 nvidia-drm-66-kmod-580 nvidia-drm-612-kmod-580 \
            nvidia-driver nvidia-kmod linux-nvidia-libs \
            nvidia-driver-580 nvidia-kmod-580 linux-nvidia-libs-580 2>/dev/null || true

        pkg install -y nvidia-driver-470 nvidia-kmod-470 linux-nvidia-libs-470 libc6-shim nvidia-settings
        pkg install -y libva-vdpau-driver libva-utils

        sysrc kld_list+="nvidia-modeset"
        kldload -n nvidia 2>/dev/null || true
        kldload -n nvidia-modeset 2>/dev/null || true

        write_nvidia_xorg_conf
        ;;
    NVIDIA_580)
        # Supports Pascal (Quadro P2000, P4000) & Maxwell (Quadro M4000)
        rm -f /usr/local/etc/X11/xorg.conf.d/10-amdgpu.conf
        kldunload nvidia-modeset nvidia 2>/dev/null || true
        pkg delete -y nvidia-drm-kmod nvidia-drm-61-kmod nvidia-drm-66-kmod nvidia-drm-612-kmod \
            nvidia-drm-kmod-580 nvidia-drm-61-kmod-580 nvidia-drm-66-kmod-580 nvidia-drm-612-kmod-580 \
            nvidia-driver nvidia-kmod linux-nvidia-libs \
            nvidia-driver-470 nvidia-kmod-470 linux-nvidia-libs-470 2>/dev/null || true

        pkg install -y nvidia-driver-580 nvidia-kmod-580 linux-nvidia-libs-580 libc6-shim nvidia-settings
        pkg install -y libva-vdpau-driver libva-utils

        sysrc kld_list+="nvidia-modeset"
        kldload -n nvidia 2>/dev/null || true
        kldload -n nvidia-modeset 2>/dev/null || true

        write_nvidia_xorg_conf
        ;;
    NVIDIA_CUR)
        # Supports Turing, Ampere, Ada: Quadro RTX 4000, RTX A4000, RTX 4000, GeForce RTX 3060
        rm -f /usr/local/etc/X11/xorg.conf.d/10-amdgpu.conf
        kldunload nvidia-modeset nvidia 2>/dev/null || true
        pkg delete -y nvidia-drm-kmod nvidia-drm-61-kmod nvidia-drm-66-kmod nvidia-drm-612-kmod \
            nvidia-drm-kmod-580 nvidia-drm-61-kmod-580 nvidia-drm-66-kmod-580 nvidia-drm-612-kmod-580 \
            nvidia-driver-580 nvidia-kmod-580 linux-nvidia-libs-580 \
            nvidia-driver-470 nvidia-kmod-470 linux-nvidia-libs-470 2>/dev/null || true

        pkg install -y nvidia-driver nvidia-kmod linux-nvidia-libs libc6-shim nvidia-settings
        pkg install -y libva-vdpau-driver libva-utils

        sysrc kld_list+="nvidia-modeset"
        kldload -n nvidia 2>/dev/null || true
        kldload -n nvidia-modeset 2>/dev/null || true

        write_nvidia_xorg_conf
        ;;
    AMD)
        rm -f /usr/local/etc/X11/xorg.conf.d/10-nvidia.conf
        pkg install -y drm-kmod gpu-firmware-kmod xf86-video-amdgpu
        pkg install -y mesa-gallium-va mesa-gallium-vdpau libva-utils
        sysrc kld_list+="amdgpu"
        kldload -n amdgpu 2>/dev/null || true

        write_amd_xorg_conf
        ;;
    HYBRID)
        rm -f /usr/local/etc/X11/xorg.conf.d/10-nvidia.conf
        rm -f /usr/local/etc/X11/xorg.conf.d/10-amdgpu.conf
        pkg install -y drm-kmod gpu-firmware-kmod nvidia-driver nvidia-kmod nvidia-settings
        pkg install -y libva-intel-media-driver libva-vdpau-driver libva-utils
        sysrc kld_list+="i915kms nvidia-modeset"
        ;;
esac

# ------------------------------------------------------------------------------
# 9. SDDM Display Manager & Custom NASA Theme Creation (Qt6)
# ------------------------------------------------------------------------------
echo "[8/11] Configuring SDDM, creating custom 'nasa' theme, and setting boot splash..."
pkg install -y sddm
sysrc sddm_enable="YES"
sysrc sddm_lang="fr_CH.UTF-8"

# Clean up any conflicting SDDM drop-in files from previous runs
rm -rf /usr/local/etc/sddm.conf.d

if [ -f /usr/local/share/sddm/scripts/Xsetup ]; then
    if ! grep -q "setxkbmap ch fr" /usr/local/share/sddm/scripts/Xsetup; then
        echo "setxkbmap ch fr" >> /usr/local/share/sddm/scripts/Xsetup
    fi
fi

# Clone assets repository into /tmp/fb14 if not already present
if [ ! -d /tmp/fb14 ] && [ -d /tmp/fb14_assets ]; then
    cp -R /tmp/fb14_assets /tmp/fb14
elif [ ! -d /tmp/fb14 ]; then
    git clone https://github.com/msartor99/FreeBSD14 /tmp/fb14 || true
fi

# 1. Create /usr/local/share/sddm/themes/nasa
mkdir -p /usr/local/share/sddm/themes/nasa

# 2. Copy the entire maldives theme into nasa
if [ -d /usr/local/share/sddm/themes/maldives ]; then
    cp -R /usr/local/share/sddm/themes/maldives/* /usr/local/share/sddm/themes/nasa/
fi

# 3. Transfer nasa2560login.jpg from /tmp/fb14 into nasa and copy it to nasa.jpg (and background.jpg)
if [ -f /tmp/fb14/nasa2560login.jpg ]; then
    cp -f /tmp/fb14/nasa2560login.jpg /usr/local/share/sddm/themes/nasa/nasa2560login.jpg
    cp -f /usr/local/share/sddm/themes/nasa/nasa2560login.jpg /usr/local/share/sddm/themes/nasa/nasa.jpg
    cp -f /usr/local/share/sddm/themes/nasa/nasa2560login.jpg /usr/local/share/sddm/themes/nasa/background.jpg
fi

# 4. Write the exact metadata.desktop for the nasa theme (with [SddmGreeterTheme] header for SDDM parser)
cat > /usr/local/share/sddm/themes/nasa/metadata.desktop << 'EOF'
[SddmGreeterTheme]
Description=NASA Theme
Author=Nasa Group
Copyright=(c) 2026, Nasa Group co.
License=CC-BY-SA
Type=sddm-theme
Version=0.1
Website=https://github.com/sddm/sddm
Screenshot=nasa.jpg
MainScript=Main.qml
ConfigFile=theme.conf
TranslationsDirectory=translations
Email=nasagroup@nasa.gov
Theme-Id=nasa
Theme-API=2.0
QtVersion=6
EOF

# Point theme.conf to nasa.jpg so Main.qml loads it natively
cat > /usr/local/share/sddm/themes/nasa/theme.conf << 'EOF'
[General]
background=nasa.jpg
EOF

# Ensure Qt6 QML path resolution works in Main.qml and ComboBox.qml
for _t in maldives nasa; do
    _tdir="/usr/local/share/sddm/themes/${_t}"
    if [ -f "${_tdir}/Main.qml" ]; then
        sed -i '' 's|source: config\.background|source: Qt.resolvedUrl(config.background)|g' "${_tdir}/Main.qml"
        sed -i '' 's|source: "rectangle\.png"|source: Qt.resolvedUrl("rectangle.png")|g' "${_tdir}/Main.qml"
        sed -i '' 's|arrowIcon: "angle-down\.png"|arrowIcon: Qt.resolvedUrl("angle-down.png")|g' "${_tdir}/Main.qml"
    fi
done

if [ -f /usr/local/lib/qt6/qml/SddmComponents/ComboBox.qml ]; then
    sed -i '' 's/onWheel: {/onWheel: function(wheel) {/g' /usr/local/lib/qt6/qml/SddmComponents/ComboBox.qml
fi

cat > /usr/local/etc/sddm.conf << 'EOF'
[General]
DisplayServer=x11
InputMethod=
GreeterEnvironment=QT_IM_MODULE=

[X11]
ServerPath=/usr/local/bin/X
DisplayCommand=/usr/local/share/sddm/scripts/Xsetup

[Theme]
Current=nasa
background=nasa.jpg
displayFont="Montserrat"
EOF

if [ -f /tmp/fb14/nasa1920.png ]; then
    mkdir -p /boot/images
    cp -f /tmp/fb14/nasa1920.png /boot/images/splash.png
    sysrc -f /boot/loader.conf splash_changer_enable="YES"
    sysrc -f /boot/loader.conf splash="/boot/images/splash.png"
    sysrc -f /boot/loader.conf shutdown_splash="/boot/images/splash.png"
fi

# ------------------------------------------------------------------------------
# 10. Desktop Environments Installation (Class 3)
# ------------------------------------------------------------------------------
echo "[9/11] Installing selected Desktop Environments (${DE_CHOICES})..."
for _de in ${DE_CHOICES}; do
    case "${_de}" in
        PLASMA6)
            pkg install -y plasma6-plasma plasma6-kwin-x11
            # NOTE: On FreeBSD pkg, 'Kvantum' (x11-themes/Kvantum) has a capital 'K'
            pkg install -y kate konsole ark remmina dolphin Kvantum
            ;;
        MATE)
            pkg install -y mate
            ;;
        XFCE4)
            pkg install -y xfce xfce4-goodies
            ;;
    esac
done

# ------------------------------------------------------------------------------
# 11. Application Suites Installation (Class 4) & Devfs Rules
# ------------------------------------------------------------------------------
echo "[10/11] Installing selected Application Suites (${APP_CHOICES})..."
VBOX_DEVFS_RULE=""

for _app in ${APP_CHOICES}; do
    case "${_app}" in
        MULTIMEDIA)
            pkg install -y vlc mpv ffmpeg
            pkg install -y gstreamer1-plugins-all gstreamer1-libav libbluray libdvdread libdvdnav
            ;;
        OFFICE)
            pkg install -y firefox fr-libreoffice thunderbird okular
            ;;
        VIRT)
            pkg install -y virtualbox-ose-72
            sysrc -f /boot/loader.conf vboxdrv_load="YES"
            sysrc vboxnet_enable="YES"
            kldload -n vboxdrv 2>/dev/null || true
            service vboxnet restart || service vboxnet start || true
            pw groupmod vboxusers -m root 2>/dev/null || true
            pw groupmod vboxusers -m "${DEFAULT_USER}" 2>/dev/null || true
            VBOX_DEVFS_RULE="add path 'vboxnetctl' mode 0660 group vboxusers"
            ;;
        FONTS)
            pkg install -y webfonts dejavu liberation-fonts-ttf noto-basic droid-fonts-ttf cantarell-fonts
            fc-cache -f 2>/dev/null || true
            ;;
    esac
done

echo "[11/11] Writing unified /etc/devfs.rules and restarting devfs..."
cat > /etc/devfs.rules << EOF
[localrules=5]
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
add path 'video*' mode 0660 group operator
add path 'unlpt*' mode 0660 group cups
add path 'lpt*' mode 0660 group cups
add path 'ulpt*' mode 0660 group cups
${VBOX_DEVFS_RULE}
EOF

sysrc devfs_system_ruleset="localrules"
service devfs restart || true

# ------------------------------------------------------------------------------
# Completion Dialog
# ------------------------------------------------------------------------------
bsddialog --backtitle "${BACKTITLE}" \
    --title "Installation Complete" \
    --msgbox "FreeBSD 15.1 X11 Workstation configuration (v${VERSION}) has completed successfully!\n\nAll configurations were applied idempotently.\nPlease reboot the system ('reboot') to load all kernel modules and start SDDM." 11 72

echo "Deployment complete. Run 'reboot' to start your FreeBSD 15.1 workstation."
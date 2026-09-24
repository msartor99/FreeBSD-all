#!/bin/sh
# ==============================================================================
# IDEMPOTENT INSTALLATION AND CONFIGURATION SCRIPT FOR FREEBSD
# Target: Universal Desktop Deployment (Workstations & Laptops)
# Version: 6.51 (Corrected: Driver 550 restored, nvidia-drm, POSIX sh, /usr/src)
# ==============================================================================

if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root (superuser)." 1>&2
    exit 1
fi

# ==============================================================================
# 0. DISCLAIMER AND RISK ACCEPTANCE
# ==============================================================================
bsddialog --title "IMPORTANT WARNING" \
          --yesno "This script will deeply modify your FreeBSD system:\n\n\
- Bulk installation of system packages and software.\n\
- Critical modification of boot configuration (/boot/loader.conf).\n\
- Adjustments to core kernel parameters (/etc/sysctl.conf).\n\
- Custom compilation of SDDM, Qt6-Wayland and NVIDIA DRM from ports.\n\n\
Have you backed up your data and do you accept the risks?" 16 75

if [ $? -ne 0 ]; then
    clear
    echo "Installation cancelled by the user. No changes were made."
    exit 0
fi

MENU_OUT=$(mktemp)

add_line_if_missing() {
    LINE="$1"
    FILE="$2"
    [ ! -f "$FILE" ] && touch "$FILE"
    grep -qF -- "$LINE" "$FILE" || echo "$LINE" >> "$FILE"
}

# ==============================================================================
# 1. INTERACTIVE SELECTION MENUS (bsddialog)
# ==============================================================================

bsddialog --title "System User Creation" \
          --inputbox "Enter the main administrator username to create or update:" 10 65 "administrateur" 2> "$MENU_OUT"
MAIN_USER=$(cat "$MENU_OUT")
[ -z "$MAIN_USER" ] && MAIN_USER="administrateur"

bsddialog --title "FreeBSD Target Version" \
          --menu "Select your installed FreeBSD version branch:" 15 70 2 \
          "1" "FreeBSD 15.x-RELEASE/STABLE" \
          "2" "FreeBSD 14.x-RELEASE" 2> "$MENU_OUT"
OS_CHOICE=$(cat "$MENU_OUT")
[ -z "$OS_CHOICE" ] && OS_CHOICE="1"

bsddialog --title "Machine Profile" \
          --menu "Select the type of hardware for power/network optimizations:" 15 70 2 \
          "1" "Desktop / Workstation (Performance focus)" \
          "2" "Laptop / Notebook (Battery, WiFi & Suspend focus)" 2> "$MENU_OUT"
MACHINE_TYPE=$(cat "$MENU_OUT")
[ -z "$MACHINE_TYPE" ] && MACHINE_TYPE="1"

bsddialog --title "System Language" \
          --menu "Select the primary working language:" 15 70 5 \
          "1" "Swiss French (fr_CH.UTF-8)" \
          "2" "French (fr_FR.UTF-8)" \
          "3" "German (de_DE.UTF-8)" \
          "4" "Italian (it_IT.UTF-8)" \
          "5" "Portuguese (pt_PT.UTF-8)" 2> "$MENU_OUT"
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
          "7" "Portuguese (pt)" 2> "$MENU_OUT"
KBD_CHOICE=$(cat "$MENU_OUT")
[ -z "$KBD_CHOICE" ] && KBD_CHOICE="1"

bsddialog --title "CPU Configuration" \
          --menu "Select your CPU processor architecture:" 15 70 3 \
          "1" "AMD (Ryzen / Threadripper / EPYC)" \
          "2" "Intel (Core / Xeon)" \
          "3" "None / Keep system default" 2> "$MENU_OUT"
CPU_CHOICE=$(cat "$MENU_OUT")
[ -z "$CPU_CHOICE" ] && CPU_CHOICE="1"

bsddialog --title "Video Configuration" \
          --menu "Select your graphics card driver:" 16 75 5 \
          "1" "NVIDIA RTX / Quadro / GTX (Proprietary driver)" \
          "2" "AMD Radeon (Open-source KMS driver)" \
          "3" "Intel Graphics (Open-source KMS driver)" \
          "4" "Framebuffer / Virtual Machine (VMware/VBox/SCFB)" \
          "5" "None / Keep system default" 2> "$MENU_OUT"
GPU_CHOICE=$(cat "$MENU_OUT")
[ -z "$GPU_CHOICE" ] && GPU_CHOICE="1"

NVIDIA_BRANCH=""
if [ "$GPU_CHOICE" -eq 1 ]; then
    NVIDIA_MODEL=$(pciconf -lv | grep -i -A 2 "vendor.*'NVIDIA" | grep "device" | cut -d"'" -f2 | head -n 1)
    [ -z "$NVIDIA_MODEL" ] && NVIDIA_MODEL="Unknown NVIDIA GPU"
    
    RECOMMENDED_DRIVER="latest"
    if echo "$NVIDIA_MODEL" | grep -qiE "GTX 10|Quadro P|P[0-9]{3,4}|TITAN X"; then
        RECOMMENDED_DRIVER="550"
    elif echo "$NVIDIA_MODEL" | grep -qiE "GTX 9|GTX 8|Quadro M"; then
        RECOMMENDED_DRIVER="470"
    elif echo "$NVIDIA_MODEL" | grep -qiE "GTX 7|GTX 6|Quadro K"; then
        RECOMMENDED_DRIVER="390"
    fi
    
    bsddialog --title "NVIDIA Driver Version" \
              --menu "Detected GPU: ${NVIDIA_MODEL}\nRecommended Driver: ${RECOMMENDED_DRIVER}\n\nSelect the NVIDIA driver branch for your GPU:" 18 75 5 \
              "latest" "Latest driver (RTX / Ada / Ampere / Turing)" \
              "550"    "Version 550.x (Pascal / Quadro P2000 / GTX 10xx)" \
              "470"    "Version 470.x (Maxwell / Kepler)" \
              "390"    "Version 390.x (Legacy branch)" \
              "340"    "Version 340.x (Legacy branch)" 2> "$MENU_OUT"
    NVIDIA_BRANCH=$(cat "$MENU_OUT")
    [ -z "$NVIDIA_BRANCH" ] && NVIDIA_BRANCH="$RECOMMENDED_DRIVER"
fi

bsddialog --title "Desktop Environment" \
          --menu "Select the primary user interface:" 16 75 5 \
          "1" "KDE Plasma 6 (Modern, Wayland & X11)" \
          "2" "XFCE 4 (Lightweight, Stable & X11)" \
          "3" "MATE Desktop (Traditional & X11)" \
          "4" "Gershwin Desktop (Mac-like GNUstep & X11)" \
          "5" "None (Server setup or manual management)" 2> "$MENU_OUT"
DE_CHOICE=$(cat "$MENU_OUT")
[ -z "$DE_CHOICE" ] && DE_CHOICE="1"

THEME_NASA=1
if [ "$DE_CHOICE" -ne 5 ]; then
    bsddialog --title "SDDM Theme Customization" \
              --yesno "Do you want to install and configure the custom NASA SDDM login theme and FreeBSD boot logos?" 10 75
    THEME_NASA=$?
fi

bsddialog --title "Software Selection" \
          --checklist "Choose the components and applications to install:" 21 75 7 \
          "INTERNET" "Firefox, Chromium, Thunderbird" ON \
          "FONTS" "Essential system fonts and emojis" ON \
          "MEDIA" "VLC, FFmpeg, MPV, Pipewire/Pulse audio stack" ON \
          "VBOX" "VirtualBox (Kernel emulation, devfs & groups)" OFF \
          "XRDP" "Remote Desktop Protocol (RDP) server access" OFF \
          "SAMBA" "Samba network share (Configures /home/share)" OFF \
          "AQUANTIA" "Aquantia 10GbE Network Driver (Lenovo P620)" OFF 2> "$MENU_OUT"
APP_CHOICES=$(cat "$MENU_OUT")

[ "$OS_CHOICE" -eq 1 ] && SAMBA_PKG="samba419" VBOX_PKG="virtualbox-ose" || SAMBA_PKG="samba416" VBOX_PKG="virtualbox-ose-72"

if [ "$NVIDIA_BRANCH" = "latest" ]; then
    PORT_NVIDIA="x11/nvidia-driver"
    PORT_NVIDIA_DRM="graphics/nvidia-drm-kmod"
    NV_PKG="nvidia-driver"
    NV_DRM_PKG="nvidia-drm-kmod"
else
    PORT_NVIDIA="x11/nvidia-driver-${NVIDIA_BRANCH}"
    PORT_NVIDIA_DRM="graphics/nvidia-drm-${NVIDIA_BRANCH}-kmod"
    NV_PKG="nvidia-driver-${NVIDIA_BRANCH}"
    NV_DRM_PKG="nvidia-drm-${NVIDIA_BRANCH}-kmod"
fi

case "$LANG_CHOICE" in
    1) SYS_LANG="fr_CH.UTF-8"; CLASS_NAME="swissfrench" ;;
    2) SYS_LANG="fr_FR.UTF-8"; CLASS_NAME="french" ;;
    3) SYS_LANG="de_DE.UTF-8"; CLASS_NAME="german" ;;
    4) SYS_LANG="it_IT.UTF-8"; CLASS_NAME="italian" ;;
    5) SYS_LANG="pt_PT.UTF-8"; CLASS_NAME="portuguese" ;;
    *) SYS_LANG="fr_CH.UTF-8"; CLASS_NAME="swissfrench" ;;
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

rm -f "$MENU_OUT"
clear

# ==============================================================================
# 2. CONFIGURATION DU DÉPÔT LATEST ET MISE À JOUR
# ==============================================================================
MASTER_LOG="/var/log/install_universal.log"
echo "Automatic installation is starting. Logs: $MASTER_LOG"
sleep 2

{
echo "=== Configuring PKG Repository to LATEST ==="
mkdir -p /usr/local/etc/pkg/repos
cat << 'EOF' > /usr/local/etc/pkg/repos/FreeBSD.conf
FreeBSD: {
  url: "pkg+http://pkg.FreeBSD.org/${ABI}/latest"
}
EOF

echo "=== Fetching Base System Updates & Bootstrapping PKG ==="
env PAGER=cat freebsd-update --not-running-from-cron fetch install || true
env ASSUME_ALWAYS_YES=YES pkg bootstrap -f
pkg update -f
pkg upgrade -y

# ==============================================================================
# 3. NETTOYAGE PRÉVENTIF DES PILOTES GPU
# ==============================================================================
GPU_STATE_FILE="/root/.current_gpu_state"
PREV_GPU=$(cat "$GPU_STATE_FILE" 2>/dev/null)

if [ -n "$PREV_GPU" ] && [ "$PREV_GPU" != "$GPU_CHOICE" ]; then
    echo "=== Cleaning up legacy GPU configurations ==="
    sed -i '' '/hw.nvidiadrm.modeset/d' /boot/loader.conf 2>/dev/null || true
    sed -i '' '/hw.nvidia.registry.EnableGpuFirmware/d' /boot/loader.conf 2>/dev/null || true
    sed -i '' '/nvidia-drm.modeset/d' /boot/loader.conf 2>/dev/null || true
    sed -i '' '/hw.amdgpu./d' /boot/loader.conf 2>/dev/null || true
    sed -i '' '/hw.radeon./d' /boot/loader.conf 2>/dev/null || true
    
    CURRENT_KLD=$(sysrc -n kld_list 2>/dev/null)
    NEW_KLD=$(echo "$CURRENT_KLD" | sed -E 's/(nvidia-modeset|nvidia-drm|amdgpu|radeonkms|i915kms)//g' | tr -s ' ' | sed 's/^ *//;s/ *$//')
    sysrc kld_list="$NEW_KLD"
    
    if [ "$PREV_GPU" -eq 1 ]; then
        pkg unlock -yq nvidia-driver nvidia-driver-550 nvidia-driver-470 nvidia-drm-kmod nvidia-drm-550-kmod 2>/dev/null || true
        pkg delete -y nvidia-driver nvidia-driver-550 nvidia-driver-470 nvidia-drm-kmod nvidia-drm-550-kmod 2>/dev/null || true
        rm -f /usr/local/etc/X11/xorg.conf.d/20-nvidia.conf
    fi
    if [ "$PREV_GPU" -eq 2 ] || [ "$PREV_GPU" -eq 3 ]; then
        pkg delete -y drm-kmod gpu-firmware-amd-kmod 2>/dev/null || true
    fi
fi
echo "$GPU_CHOICE" > "$GPU_STATE_FILE"

# ==============================================================================
# 4. INSTALLATION DES PAQUETS BINAIRES
# ==============================================================================
echo "=== Installing core packages ==="

PKG_LIST="doas unzip wget git htop neofetch python3 bashtop ImageMagick7 smartmontools dbus avahi seatd fusefs-ntfs fusefs-ext2"
PKG_LIST="$PKG_LIST xorg xauth xinit xterm consolekit2 cmake ninja jsoncpp pkgconf"

[ "$MACHINE_TYPE" -eq 2 ] && PKG_LIST="$PKG_LIST networkmgr sudo acpi_call"
[ "$CPU_CHOICE" -ne 3 ] && PKG_LIST="$PKG_LIST cpu-microcode sensors"

case "$GPU_CHOICE" in
    1) PKG_LIST="$PKG_LIST wayland xwayland" ;;
    2) PKG_LIST="$PKG_LIST drm-kmod gpu-firmware-amd-kmod wayland xwayland" ;;
    3) PKG_LIST="$PKG_LIST drm-kmod wayland xwayland" ;;
    4) PKG_LIST="$PKG_LIST xf86-video-scfb xf86-video-vmware xf86-video-vesa wayland xwayland" ;;
esac

case "$DE_CHOICE" in
    1) PKG_LIST="$PKG_LIST pavucontrol kate konsole ark dolphin Kvantum plasma6-plasma qt6-wayland sddm" ;;
    2) PKG_LIST="$PKG_LIST xfce sddm pavucontrol" ;;
    3) PKG_LIST="$PKG_LIST mate sddm pavucontrol" ;;
    4) PKG_LIST="$PKG_LIST sddm pavucontrol xfce4-wm gmake llvm curl bash sudo" ;;
esac

echo "$APP_CHOICES" | grep -q "INTERNET" && PKG_LIST="$PKG_LIST firefox chromium thunderbird"
echo "$APP_CHOICES" | grep -q "FONTS" && PKG_LIST="$PKG_LIST noto-basic noto-emoji webfonts cantarell-fonts roboto-fonts-ttf"
echo "$APP_CHOICES" | grep -q "MEDIA" && PKG_LIST="$PKG_LIST pulseaudio pipewire wireplumber vlc ffmpeg multimedia/mpv webcamd v4l-utils"
echo "$APP_CHOICES" | grep -q "VBOX" && PKG_LIST="$PKG_LIST ${VBOX_PKG}"
echo "$APP_CHOICES" | grep -q "XRDP" && PKG_LIST="$PKG_LIST xrdp xorgxrdp"
echo "$APP_CHOICES" | grep -q "SAMBA" && PKG_LIST="$PKG_LIST ${SAMBA_PKG}"

pkg install -y $PKG_LIST

# ==============================================================================
# 5. CONFIGURATION UTILISATEUR & LOCALES
# ==============================================================================
echo "=== Setting up user: $MAIN_USER ==="
if ! id "$MAIN_USER" >/dev/null 2>&1; then
    pw useradd "$MAIN_USER" -m -s /bin/sh -c "System Administrator"
fi

for grp in wheel operator video; do
    pw groupmod "$grp" -m "$MAIN_USER"
done

if ! grep -q "${CLASS_NAME}|" /etc/login.conf; then
    cat << EOF >> /etc/login.conf

${CLASS_NAME}|Localized Users Accounts:\
        :charset=UTF-8:\
        :lang=${SYS_LANG}:\
        :tc=default:
EOF
    cap_mkdb /etc/login.conf
fi

echo "defaultclass=${CLASS_NAME}" > /etc/adduser.conf
pw usermod root -L "${CLASS_NAME}"
pw usermod "$MAIN_USER" -L "${CLASS_NAME}"

# ==============================================================================
# 6. OPTIMISATIONS SYSTÈME ET SERVICES
# ==============================================================================
echo "=== Optimizing boot loader and kernel parameters ==="

sysrc -f /boot/loader.conf boot_mute="YES"
sysrc splash_changer_enable="YES"
sysrc rc_startmsgs="NO"
sysrc -f /boot/loader.conf autoboot_delay="3"
sysrc -f /boot/loader.conf tmpfs_load="YES"
sysrc -f /boot/loader.conf aio_load="YES"

add_line_if_missing 'net.inet.tcp.soreceive_stream="1"' /boot/loader.conf
add_line_if_missing 'net.isr.defaultqlimit="2048"' /boot/loader.conf
add_line_if_missing 'net.link.ifqmaxlen="2048"' /boot/loader.conf
sysrc kld_list+=" cc_htcp"

add_line_if_missing "kern.sched.preempt_thresh=224" /etc/sysctl.conf
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
    sysrc kld_list+=" acpi_ibm"
    
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

sysrc linux_enable="YES"
sysrc linux64_enable="YES"
sysrc linux_mounts_enable="YES"
sysrc smartd_enable="YES"
[ ! -f /usr/local/etc/smartd.conf ] && cp /usr/local/etc/smartd.conf.sample /usr/local/etc/smartd.conf 2>/dev/null || true
sysrc dbus_enable="YES"
sysrc avahi_enable="YES"
sysrc seatd_enable="YES"

[ ! -d /proc ] && mkdir -p /proc
add_line_if_missing "proc /proc procfs rw 0 0" /etc/fstab
add_line_if_missing "fdesc /dev/fd fdescfs rw 0 0" /etc/fstab

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
sysrc kld_list+=" fusefs ext2fs"

# ==============================================================================
# 7. PILOTES VIDÉO & XORG
# ==============================================================================
echo "=== Configuring Graphics and Keyboards ==="
mkdir -p /usr/local/etc/X11/xorg.conf.d

case "$GPU_CHOICE" in
    1)
        sysrc kld_list+=" nvidia-modeset nvidia-drm"
        add_line_if_missing 'hw.nvidiadrm.modeset="1"' /boot/loader.conf
        add_line_if_missing 'hw.nvidia.registry.EnableGpuFirmware="1"' /boot/loader.conf
        add_line_if_missing 'nvidia-drm.modeset="1"' /boot/loader.conf
        
        cat > /usr/local/etc/X11/xorg.conf.d/20-nvidia.conf << 'EOF'
Section "Device"
    Identifier "NVIDIA Card"
    Driver     "nvidia"
EndSection
EOF
        ;;
    2)
        sysrc kld_list+=" amdgpu"
        add_line_if_missing 'hw.amdgpu.si_support="1"' /boot/loader.conf
        add_line_if_missing 'hw.amdgpu.cik_support="1"' /boot/loader.conf
        add_line_if_missing 'hw.radeon.si_support="0"' /boot/loader.conf
        add_line_if_missing 'hw.radeon.cik_support="0"' /boot/loader.conf
        ;;
    3)
        sysrc kld_list+=" i915kms"
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
# 8. ENVIRONNEMENT DE BUREAU ET COMPILATION CIBLÉE (WAYLAND + NVIDIA)
# ==============================================================================
STARTWM_EXEC=""

case "$DE_CHOICE" in
    1)
        sysrc sddm_enable="YES"
        STARTWM_EXEC="exec ck-launch-session dbus-run-session startplasma-x11"
        
        FLAG_FILE="/root/.compilation_graphique_terminee"
        LOG_FILE="/var/log/compilation_graphique.log"

        if [ ! -f "$FLAG_FILE" ]; then
            echo "=== Syncing Ports and Kernel Sources ==="
            if [ ! -d /usr/ports/.git ]; then
                git clone --depth 1 https://git.freebsd.org/ports.git /usr/ports
            else
                git -C /usr/ports pull
            fi

            if [ ! -f /usr/src/sys/conf/newvers.sh ]; then
                echo "-> Fetching /usr/src for kernel modules (releng/15.1)..."
                git clone --depth 1 -b releng/15.1 https://git.freebsd.org/src.git /usr/src
            fi
            
            grep -q "OPTIONS_SET.*WAYLAND" /etc/make.conf 2>/dev/null || echo "OPTIONS_SET+=WAYLAND NVIDIA EGL" >> /etc/make.conf
            
            if [ "$GPU_CHOICE" -eq 1 ]; then
                echo "-> Compiling $PORT_NVIDIA and $PORT_NVIDIA_DRM..."
                cd "/usr/ports/$PORT_NVIDIA" && make BATCH=yes install clean >> "$LOG_FILE" 2>&1
                cd "/usr/ports/$PORT_NVIDIA_DRM" && make BATCH=yes install clean >> "$LOG_FILE" 2>&1
            fi

            echo "-> Compiling qt6-wayland from source..."
            pkg delete -y -f qt6-wayland >/dev/null 2>&1 || true
            cd /usr/ports/graphics/qt6-wayland
            make BATCH=yes CMAKE_ARGS+="-DQT_NO_PACKAGE_VERSION_CHECK=TRUE" install clean >> "$LOG_FILE" 2>&1

            echo "-> Compiling SDDM from source..."
            pkg delete -y -f sddm >/dev/null 2>&1 || true
            cd /usr/ports/x11/sddm
            make BATCH=yes install clean >> "$LOG_FILE" 2>&1

            echo "-> Locking compiled packages against pkg upgrade..."
            [ "$GPU_CHOICE" -eq 1 ] && pkg lock -y "$NV_PKG" "$NV_DRM_PKG" 2>/dev/null || true
            pkg lock -y qt6-wayland sddm 2>/dev/null || true
            
            touch "$FLAG_FILE"
            echo "-> Compilation finished successfully."
        fi
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
        echo "=== Building Gershwin Desktop ==="
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
        STARTWM_EXEC="exec /System/Library/Scripts/Gershwin.sh"
        ;;
esac

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

    # SDDM Wayland Wrapper
    cat > /usr/local/share/sddm/scripts/wayland-session << EOF
#!/bin/sh
export KWIN_FORCE_SW_CURSOR=1
export WLR_NO_HARDWARE_CURSORS=1
export QT_QPA_PLATFORM=wayland
export LIBSEAT_BACKEND=seatd
export LANG=${SYS_LANG}
export LC_ALL=${SYS_LANG}

export XDG_RUNTIME_DIR=/tmp/xdg-\$(id -u)
rm -rf \$XDG_RUNTIME_DIR
mkdir -p \$XDG_RUNTIME_DIR
chmod 700 \$XDG_RUNTIME_DIR
rm -f /tmp/wayland-* 2>/dev/null

exec ck-launch-session dbus-run-session "\$@"
EOF
    chmod 555 /usr/local/share/sddm/scripts/wayland-session

    mkdir -p /usr/local/etc/sddm.conf.d
    cat > /usr/local/etc/sddm.conf.d/wayland-session.conf << 'EOF'
[Wayland]
SessionScript=/usr/local/share/sddm/scripts/wayland-session
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
fi

# NASA Theme
if [ "$DE_CHOICE" -ne 5 ] && [ "$THEME_NASA" -eq 0 ]; then
    echo "=== Applying custom NASA SDDM theme ==="
    git clone https://github.com/msartor99/FreeBSD14 /tmp/fb14_assets
    mkdir -p /usr/local/share/sddm/themes/nasa
    cp /usr/local/share/sddm/themes/maldives/* /usr/local/share/sddm/themes/nasa/ 2>/dev/null || true
    cp /tmp/fb14_assets/Main.qml /usr/local/share/sddm/themes/nasa/ 2>/dev/null || true
    cp /tmp/fb14_assets/metadata.desktop /usr/local/share/sddm/themes/nasa/ 2>/dev/null || true
    
    sed -i '' 's/import QtQuick 2.*/import QtQuick/' /usr/local/share/sddm/themes/nasa/Main.qml 2>/dev/null || true
    sed -i '' 's/import QtQuick.Controls 1.*/import QtQuick.Controls/' /usr/local/share/sddm/themes/nasa/Main.qml 2>/dev/null || true
    sed -i '' 's/import QtQuick.Controls 2.*/import QtQuick.Controls/' /usr/local/share/sddm/themes/nasa/Main.qml 2>/dev/null || true
    sed -i '' 's/import QtQuick.Window 2.*/import QtQuick.Window/' /usr/local/share/sddm/themes/nasa/Main.qml 2>/dev/null || true
    sed -i '' 's/import QtGraphicalEffects.*/import Qt5Compat.GraphicalEffects/' /usr/local/share/sddm/themes/nasa/Main.qml 2>/dev/null || true

    rm -f /usr/local/share/sddm/themes/nasa/background.* /usr/local/share/sddm/themes/nasa/preview.*
    cp /tmp/fb14_assets/nasa2560login.jpg /usr/local/share/sddm/themes/nasa/background.jpg 2>/dev/null || true
    cp /tmp/fb14_assets/nasa2560login.jpg /usr/local/share/sddm/themes/nasa/preview.png 2>/dev/null || true

    cat > /usr/local/etc/sddm.conf.d/20-theme.conf << EOF
[Theme]
Current=nasa
EOF
    mkdir -p /boot/images
    cp /tmp/fb14_assets/nasa1920.png /boot/images/splash.png 2>/dev/null || true
    sysrc -f /boot/loader.conf splash="/boot/images/splash.png"
    sysrc -f /boot/loader.conf shutdown_splash="/boot/images/splash.png"
    
    fetch -o /tmp/nasa_4k_wallpaper.jpg https://raw.githubusercontent.com/msartor99/FreeBSD14/ffdccbb160df14397836ce9b3b361c9ab87f97a9/wp8860763-nasa-4k-wallpapers.jpg 2>/dev/null || true
    if [ -f /tmp/nasa_4k_wallpaper.jpg ] && [ "$DE_CHOICE" -eq 1 ]; then
        mkdir -p /usr/local/share/wallpapers/NASA_4K/contents/images
        cp /tmp/nasa_4k_wallpaper.jpg /usr/local/share/wallpapers/NASA_4K/contents/images/3840x2160.jpg
        cat > /usr/local/share/wallpapers/NASA_4K/metadata.desktop << 'EOF_KDE'
[Desktop Entry]
Name=NASA 4K
X-KDE-PluginInfo-Name=NASA_4K
EOF_KDE
        mkdir -p /usr/share/skel/dot.config
        printf "[Wallpaper][org.kde.image][General]\nImage=/usr/local/share/wallpapers/NASA_4K\n" > /usr/share/skel/dot.config/kscreenlockerrc
        if [ -d "/home/$MAIN_USER" ]; then
            mkdir -p "/home/$MAIN_USER/.config"
            printf "[Wallpaper][org.kde.image][General]\nImage=/usr/local/share/wallpapers/NASA_4K\n" > "/home/$MAIN_USER/.config/kscreenlockerrc"
            chown -R "$MAIN_USER:wheel" "/home/$MAIN_USER/.config"
        fi
    fi
fi

# ==============================================================================
# 9. MODULES OPTIONNELS (VBOX, XRDP, SAMBA, AQUANTIA)
# ==============================================================================
if echo "$APP_CHOICES" | grep -q "MEDIA"; then
    sysrc webcamd_enable="YES"
    [ "$GPU_CHOICE" -eq 1 ] && add_line_if_missing "hw.snd.default_unit=1" /etc/sysctl.conf
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
    mkdir -p /usr/local/etc/xrdp
    cat > /usr/local/etc/xrdp/startwm.sh << EOF
#!/bin/sh
export LANG=${SYS_LANG}
export LC_ALL=${SYS_LANG}
$STARTWM_EXEC
EOF
    chmod 555 /usr/local/etc/xrdp/startwm.sh
fi

if echo "$APP_CHOICES" | grep -q "SAMBA"; then
    mkdir -p /home/share
    chmod 775 /home/share
    chown "$MAIN_USER:wheel" /home/share
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
    echo "Note: Define Samba password manually after reboot: smbpasswd -a $MAIN_USER"
fi

if echo "$APP_CHOICES" | grep -q "AQUANTIA"; then
    echo "=== Compiling Aquantia Network Driver (Lenovo P620) ==="
    if [ ! -f /usr/src/sys/conf/newvers.sh ]; then
        git clone --depth 1 -b releng/15.1 https://git.freebsd.org/src.git /usr/src
    fi
    if ! kldstat | grep -q if_atlantic && [ ! -f /boot/modules/if_atlantic.ko ]; then
        mkdir -p /usr/local/src
        [ ! -d /usr/local/src/FreeBSD15-aquantia-P620 ] && git clone https://github.com/msartor99/FreeBSD15-aquantia-P620 /usr/local/src/FreeBSD15-aquantia-P620 >/dev/null 2>&1
        cd /usr/local/src/FreeBSD15-aquantia-P620
        if make clean && make && make install >/dev/null 2>&1; then
            sysrc -f /boot/loader.conf if_atlantic_load="YES"
        fi
    fi
fi

echo "Installation complete. System is ready. Reboot recommended."

} 2>&1 | tee -a "$MASTER_LOG"
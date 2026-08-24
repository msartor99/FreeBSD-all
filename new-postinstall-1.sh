#!/bin/sh
# ==============================================================================
# Script de post-installation complet - Lenovo P620 (ThreadRipper, RTX 4000)
# Système : FreeBSD 15.1-RELEASE + Wayland + Plasma 6 + Pilote NVIDIA 610
# ==============================================================================

if [ "$(id -u)" -ne 0 ]; then
    echo "Erreur : ce script doit être exécuté en tant que root."
    exit 1
fi

echo "=== Mise à jour du système de base ==="
env PAGER=cat freebsd-update fetch install
env ASSUME_ALWAYS_YES=YES pkg bootstrap
pkg update

echo "=== Optimisations du démarrage (Silent Boot & Loader) ==="
for boot_conf in \
    'boot_mute="YES"' \
    'splash_changer_enable="YES"' \
    'autoboot_delay="3"' \
    'tmpfs_load="YES"' \
    'aio_load="YES"' \
    'amdtemp_load="YES"' \
    'cpu_microcode_load="YES"' \
    'cpu_microcode_name="/boot/firmware/amd-ucode.bin"' \
    'hw.nvidiadrm.modeset="1"' \
    'hw.nvidia.registry.EnableGpuFirmware="1"' \
    'nvidia-drm.modeset="1"'; do
    grep -q "^${boot_conf%=*}" /boot/loader.conf || echo "$boot_conf" >> /boot/loader.conf
done

# Masquer les messages de démarrage rc
sed -i '' 's/run_rc_script ${_rc_elem} ${_boot}/run_rc_script ${_rc_elem} ${_boot} > \/dev\/null/g' /etc/rc
sysrc rc_startmsgs="NO"

echo "=== Paramètres Kernel (Sysctl) & Routage Wayland ==="
for sysctl_conf in \
    "kern.sched.preempt_thresh=224" \
    "kern.ipc.shm_allow_removed=1" \
    "net.local.stream.recvspace=65536" \
    "net.local.stream.sendspace=65536" \
    "vfs.usermount=1" \
    "hw.snd.default_unit=1" \
    "kern.evdev.rcpt_mask=12"; do
    grep -q "^${sysctl_conf%=*}" /etc/sysctl.conf 2>/dev/null || echo "$sysctl_conf" >> /etc/sysctl.conf
    sysctl "$sysctl_conf" >/dev/null 2>&1
done

echo "=== Configuration AMD CPU & Région ==="
pkg install -y sensors cpu-microcode
sysrc keymap="ch-fr.acc.kbd"

if ! grep -q "french|French" /etc/login.conf 2>/dev/null; then
    cat << 'EOF' >> /etc/login.conf
french|French Users Accounts:\
    :charset=UTF-8:\
    :lang=fr_CH.UTF-8:\
    :tc=default:
EOF
    cap_mkdb /etc/login.conf
fi
echo 'defaultclass=french' > /etc/adduser.conf

if ! id -u administrateur >/dev/null 2>&1; then
    pw useradd -n administrateur -c "Administrateur Système" -L french -m -s /bin/sh
else
    pw usermod administrateur -L french
fi

# Le groupe video est le seul nécessaire pour /dev/dri/card0
for group in wheel operator video; do
    pw groupmod "$group" -m administrateur
done
pw usermod root -L french

echo "=== Variables globales Wayland & NVIDIA (.profile) ==="
for prof in /home/administrateur/.profile /root/.profile; do
    [ ! -f "$prof" ] && touch "$prof"
    grep -q "KWIN_FORCE_SW_CURSOR" "$prof" || echo 'export KWIN_FORCE_SW_CURSOR=1' >> "$prof"
    grep -q "WLR_NO_HARDWARE_CURSORS" "$prof" || echo 'export WLR_NO_HARDWARE_CURSORS=1' >> "$prof"
    grep -q "QT_QPA_PLATFORM" "$prof" || echo 'export QT_QPA_PLATFORM=wayland' >> "$prof"
done
chown administrateur:administrateur /home/administrateur/.profile

echo "=== Utilitaires, Polices et Logiciels ==="
# Installation préventive de rust et xcb-util-cursor pour sécuriser la compilation future
pkg install -y doas unzip libzip wget git htop neofetch python3 bashtop ImageMagick7 smartmontools \
    rust xcb-util-cursor cups gutenprint cups-filters hplip system-config-printer \
    fusefs-ntfs fusefs-ext2 fusefs-hfsfuse xorg dbus avahi signal-cli seatd portmaster sddm \
    pavucontrol kate konsole ark remmina dolphin Kvantum pulseaudio pipewire wireplumber \
    audio/freedesktop-sound-theme firefox vlc ffmpeg libva-vdpau-driver libva-utils libdvdread \
    libdvdnav xdg-user-dirs octopkg multimedia/mpv gstreamer1-plugins-all gstreamer1-libav \
    libbluray eom firefox-esr chromium thunderbird cantarell-fonts droid-fonts-ttf inconsolata-ttf \
    noto-basic noto-emoji roboto-fonts-ttf ubuntu-font webfonts terminus-font terminus-ttf \
    x11-themes/papirus-icon-theme x11-themes/cursor-neutral-white-theme \
    x11-themes/qogir-icon-themes x11-themes/win98se-icon-theme

pkg install -y --g "plasma6-*" "kf6*"
pkg install -y wayland xwayland qt6-wayland

echo "=== Gestion des périphériques (Devfs, Fstab) ==="
if ! grep -q "\[localrules=5\]" /etc/devfs.rules 2>/dev/null; then
    cat >>/etc/devfs.rules <<EOF
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
fi

grep -q "procfs" /etc/fstab || echo "proc        /proc       procfs       rw       0       0" >> /etc/fstab
grep -q "fdescfs" /etc/fstab || echo "fdesc      /dev/fd      fdescfs      rw       0       0" >> /etc/fstab

echo "=== Configuration des Services (rc.conf) ==="
sysrc linux_enable="YES"
sysrc linux64_enable="YES"
sysrc linux_mounts_enable="YES"
sysrc smartd_enable="YES"
sysrc cupsd_enable="YES"
sysrc devfs_system_ruleset="localrules"
sysrc kld_list+="fusefs ext2fs nvidia-modeset nvidia-drm"
sysrc dbus_enable="YES"
sysrc avahi_enable="YES"
sysrc seatd_enable="YES"
sysrc sddm_enable="YES"
sysrc sddm_lang="ch_CH"
sysrc moused_enable="NO" # Crucial pour débloquer la souris sous Wayland
sysrc sound_load="YES"
sysrc snd_hda_load="YES"

echo "=== Configuration Xorg (Clavier) ==="
mkdir -p /usr/local/etc/X11/xorg.conf.d
cat >/usr/local/etc/X11/xorg.conf.d/20-keyboards.conf <<EOF
Section "ServerFlags"
    Option "DontZap" "false"
EndSection
Section "InputClass"
    Identifier "All Keyboards"
    MatchIsKeyboard "yes"
    Option "XkbLayout" "ch"
    Option "XkbVariant" "fr"
    Option "XkbOptions" "terminate:ctrl_alt_bksp" 
EndSection
EOF

echo "=== Compilation Hybride (Wayland + NVIDIA Ports) ==="
[ ! -d /usr/ports/.git ] && git clone --depth 1 https://git.freebsd.org/ports.git /usr/ports
grep -q "OPTIONS_SET.*WAYLAND" /etc/make.conf 2>/dev/null || echo "OPTIONS_SET=WAYLAND NVIDIA EGL" >> /etc/make.conf

FLAG_FILE="/root/.compilation_graphique_terminee"
LOG_FILE="/var/log/compilation_graphique.log"

if [ -f "$FLAG_FILE" ]; then
    echo "-> La compilation personnalisée a déjà été effectuée."
else
    echo "-> Début de la compilation ciblée (NVIDIA + Qt6-Wayland)... Patientez."
    
    # 1. Compilation des pilotes NVIDIA
    cd /usr/ports/x11/nvidia-driver && make BATCH=yes install clean >> "$LOG_FILE" 2>&1
    cd /usr/ports/graphics/nvidia-drm-kmod && make BATCH=yes install clean >> "$LOG_FILE" 2>&1
    
    # 2. Re-compilation de qt6-wayland (Désinstallation préalable pour éviter l'erreur de version)
    pkg delete -y -f qt6-wayland >/dev/null 2>&1 || true
    cd /usr/ports/graphics/qt6-wayland
    make BATCH=yes CMAKE_ARGS+="-DQT_NO_PACKAGE_VERSION_CHECK=TRUE" install clean >> "$LOG_FILE" 2>&1
    
    touch "$FLAG_FILE"
    echo "-> Compilation terminée avec succès !"
fi

nvidia-xconfig >/dev/null 2>&1 || true

echo "=== Compilation Pilote Réseau Aquantia ==="
if ! kldstat | grep -q if_atlantic && [ ! -f /boot/modules/if_atlantic.ko ]; then
    mkdir -p /usr/local/src
    [ ! -d /usr/local/src/FreeBSD15-aquantia-P620 ] && git clone https://github.com/msartor99/FreeBSD15-aquantia-P620 /usr/local/src/FreeBSD15-aquantia-P620 >/dev/null 2>&1
    cd /usr/local/src/FreeBSD15-aquantia-P620
    if make clean && make && make install >/dev/null 2>&1; then
        sysrc -f /boot/loader.conf if_atlantic_load="YES"
    fi
fi

echo "=== SDDM et Splash Screen ==="
cat > /usr/local/share/sddm/scripts/Xsetup <<EOF
setxkbmap ch fr
EOF

mkdir -p /usr/local/etc/sddm.conf.d
cat > /usr/local/etc/sddm.conf.d/theme.conf <<EOF
[Theme]
Current=maldives
EOF
cat > /usr/local/etc/sddm.conf <<EOF
[General]
InputMethod=""
EOF

if [ ! -f /boot/images/splash.png ]; then
    mkdir -p /boot/images
    cd /tmp
    wget -q https://kamila.is/media/v2.png -O v2.png
    if [ -f v2.png ]; then
        magick convert v2.png -resize 1920x1080 v2hd.png
        cp v2hd.png /boot/images/splash.png
        sysrc -f /boot/loader.conf splash="/boot/images/splash.png"
    fi
fi

echo "=== Opération terminée avec succès. Un redémarrage (reboot) est nécessaire. ==="
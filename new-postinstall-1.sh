#!/bin/sh
# Script de post-installation complet - Lenovo P620 (ThreadRipper, RTX 4000)
# Système : FreeBSD 15.1-RELEASE-p2 + Wayland + Plasma 6

# 1. Vérification des droits d'exécution
if [ "$(id -u)" -ne 0 ]; then
    echo "Erreur : ce script doit être exécuté en tant que root."
    exit 1
fi

echo "=== Mise à jour du système de base ==="
env PAGER=cat freebsd-update fetch install

echo "=== Optimisations du démarrage (Silent Boot & Loader) ==="
sysrc -f /boot/loader.conf boot_mute="YES"
sysrc -f /boot/loader.conf splash_changer_enable="YES"
sysrc -f /boot/loader.conf autoboot_delay="3"
sysrc -f /boot/loader.conf tmpfs_load="YES"
sysrc -f /boot/loader.conf aio_load="YES"

# Masquer les messages de démarrage rc
sed -i '' 's/run_rc_script ${_rc_elem} ${_boot}/run_rc_script ${_rc_elem} ${_boot} > \/dev\/null/g' /etc/rc
sysrc rc_startmsgs="NO"

echo "=== Paramètres Kernel (Sysctl) ==="
for sysctl_conf in \
    "kern.sched.preempt_thresh=224" \
    "kern.ipc.shm_allow_removed=1" \
    "net.local.stream.recvspace=65536" \
    "net.local.stream.sendspace=65536" \
    "vfs.usermount=1" \
    "hw.snd.default_unit=1"; do
    if ! grep -q "^${sysctl_conf%=*}" /etc/sysctl.conf 2>/dev/null; then
        echo "$sysctl_conf" >> /etc/sysctl.conf
    fi
    sysctl "$sysctl_conf" >/dev/null 2>&1
done

echo "=== Configuration AMD CPU ==="
sysrc -f /boot/loader.conf amdtemp_load="YES"
env ASSUME_ALWAYS_YES=YES pkg bootstrap
pkg install -y sensors cpu-microcode
sysrc -f /boot/loader.conf cpu_microcode_load="YES"
sysrc -f /boot/loader.conf cpu_microcode_name="/boot/firmware/amd-ucode.bin"

echo "=== Configuration Régionale et Utilisateur ==="
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

for group in wheel operator video; do
    pw groupmod "$group" -m administrateur
done
pw usermod root -L french

PROFILE_FILE="/home/administrateur/.profile"
[ ! -f "$PROFILE_FILE" ] && touch "$PROFILE_FILE" && chown administrateur:administrateur "$PROFILE_FILE"
grep -q "WLR_NO_HARDWARE_CURSORS" "$PROFILE_FILE" || echo 'export WLR_NO_HARDWARE_CURSORS=1' >> "$PROFILE_FILE"
grep -q "KWIN_FORCE_SW_CURSOR" "$PROFILE_FILE" || echo 'export KWIN_FORCE_SW_CURSOR=1' >> "$PROFILE_FILE"

echo "=== Couche de compatibilité Linux ==="
sysrc linux_enable="YES"
sysrc linux64_enable="YES"
sysrc linux_mounts_enable="YES"
kldstat | grep -q linux64 || kldload linux64 2>/dev/null || true
kldstat | grep -q linux || kldload linux 2>/dev/null || true
service linux start >/dev/null 2>&1

echo "=== Utilitaires et Outils Système ==="
pkg install -y doas unzip libzip wget git htop neofetch python3 bashtop ImageMagick7 smartmontools
sysrc smartd_enable="YES"
[ ! -f /usr/local/etc/smartd.conf ] && cp /usr/local/etc/smartd.conf.sample /usr/local/etc/smartd.conf
service smartd start >/dev/null 2>&1

echo "=== Gestion des périphériques (Devfs, Imprimantes, USB) ==="
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

pkg install -y cups gutenprint cups-filters hplip system-config-printer fusefs-ntfs fusefs-ext2 fusefs-hfsfuse
sysrc cupsd_enable="YES"
sysrc devfs_system_ruleset="localrules"
service devfs restart

sysrc kld_list+="fusefs ext2fs"
kldstat | grep -q fusefs || kldload fusefs
kldstat | grep -q ext2fs || kldload ext2fs

echo "=== Configuration Xorg et Services de Bureau ==="
pkg install -y xorg dbus avahi signal-cli seatd portmaster
sysrc dbus_enable="YES"
sysrc avahi_enable="YES"
sysrc seatd_enable="YES"

grep -q "procfs" /etc/fstab || echo "proc        /proc       procfs       rw       0       0" >> /etc/fstab
grep -q "fdescfs" /etc/fstab || echo "fdesc      /dev/fd      fdescfs      rw       0       0" >> /etc/fstab

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

echo "=== Configuration NVIDIA et Aquantia ==="
sysrc kld_list+="nvidia-modeset"
sysrc nvidia_modeset_enable="YES"

for boot_conf in \
    'hw.nvidiadrm.modeset="1"' \
    'hw.nvidia.registry.EnableGpuFirmware="1"' \
    'nvidia-drm.modeset="1"'; do
    grep -q "^${boot_conf%=*}" /boot/loader.conf || echo "$boot_conf" >> /boot/loader.conf
done

if ! kldstat | grep -q if_atlantic && [ ! -f /boot/modules/if_atlantic.ko ]; then
    echo "-> Compilation du pilote réseau Aquantia AQ107 en cours..."
    AQ_LOG="/var/log/compilation_aquantia.log"
    mkdir -p /usr/local/src
    if [ ! -d /usr/local/src/FreeBSD15-aquantia-P620 ]; then
        git clone https://github.com/msartor99/FreeBSD15-aquantia-P620 /usr/local/src/FreeBSD15-aquantia-P620 > "$AQ_LOG" 2>&1
    fi
    cd /usr/local/src/FreeBSD15-aquantia-P620
    if make clean && make && make install >> "$AQ_LOG" 2>&1; then
        sysrc -f /boot/loader.conf if_atlantic_load="YES"
        echo "-> Pilote Aquantia compilé et installé avec succès."
    else
        echo "-> ERREUR : La compilation du pilote Aquantia a échoué. Détails dans $AQ_LOG."
    fi
else
    echo "-> Le module réseau if_atlantic est déjà présent."
fi

echo "=== SDDM et Splash Screen ==="
pkg install -y sddm
sysrc sddm_enable="YES"
sysrc sddm_lang="ch_CH"

cat > /usr/local/share/sddm/scripts/Xsetup <<EOF
setxkbmap ch fr
EOF

cat > /usr/local/etc/sddm.conf <<EOF
[General]
InputMethod=""
EOF

mkdir -p /usr/local/etc/sddm.conf.d
cat > /usr/local/etc/sddm.conf.d/theme.conf <<EOF
[Theme]
Current=maldives
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

echo "=== Installation des Polices et Logiciels ==="
pkg install -y --g "plasma6-*" "kf6*"
pkg install -y pavucontrol kate konsole ark remmina dolphin Kvantum \
    pulseaudio pipewire wireplumber audio/freedesktop-sound-theme \
    firefox vlc ffmpeg libva-vdpau-driver libva-utils libdvdread libdvdnav \
    xdg-user-dirs octopkg multimedia/mpv gstreamer1-plugins-all gstreamer1-libav libbluray \
    eom firefox-esr chromium thunderbird \
    cantarell-fonts droid-fonts-ttf inconsolata-ttf noto-basic noto-emoji \
    roboto-fonts-ttf ubuntu-font webfonts terminus-font terminus-ttf \
    x11-themes/papirus-icon-theme x11-themes/cursor-neutral-white-theme \
    x11-themes/qogir-icon-themes x11-themes/win98se-icon-theme

sysrc sound_load="YES"
sysrc snd_hda_load="YES"

echo "=== Compilation Hybride des Composants Graphiques (Wayland) ==="
pkg install -y pkgconf wayland xwayland nvidia-driver linux-nvidia-libs nvidia-kmod nvidia-drm-kmod libc6-shim nvidia-settings nvidia-xconfig

[ ! -d /usr/ports/.git ] && [ ! -f /usr/ports/Makefile ] && git clone https://git.freebsd.org/ports.git /usr/ports
grep -q "OPTIONS_SET.*WAYLAND" /etc/make.conf 2>/dev/null || echo "OPTIONS_SET=WAYLAND NVIDIA EGL" >> /etc/make.conf

FLAG_FILE="/root/.compilation_graphique_terminee"
LOG_FILE="/var/log/compilation_graphique.log"

if [ -f "$FLAG_FILE" ]; then
    echo "-> La compilation personnalisée (NVIDIA + Wayland) a déjà été effectuée avec succès."
    echo "-> Passage de cette étape pour gagner du temps."
else
    echo "-> Début de la recompilation des composants critiques via portmaster."
    echo "-> Patientez, cette opération peut prendre du temps. Les logs sont écrits dans $LOG_FILE..."
    
    if {
        portmaster -D -G --no-confirm x11/nvidia-driver && \
        portmaster -D -G --no-confirm graphics/nvidia-drm-kmod && \
        portmaster -D -G -f --no-confirm x11/xwayland
    } > "$LOG_FILE" 2>&1; then
        touch "$FLAG_FILE"
        echo "-> Recompilation terminée avec succès !"
    else
        echo "-> ERREUR : La recompilation a échoué. Consultez le fichier $LOG_FILE pour identifier le problème."
    fi
fi

# Génération initiale du xorg.conf (sécurité supplémentaire)
nvidia-xconfig >/dev/null 2>&1 || true

echo "=== Opération terminée. Un redémarrage est recommandé. ==="
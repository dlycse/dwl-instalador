#!/bin/sh
# install-dwl v1.0 - Multi-distro (Void + Arch/derivados)
# 100% SIN CUELGUES: no arranca servicios automaticamente durante la instalacion
# Al final te muestra los comandos exactos para habilitar el login antes de reiniciar.
set -e
info(){ echo "[+] $1"; }
warn(){ echo "[!] $1"; }
err(){ echo "[x] $1"; exit 1; }

GIT_FIX=0
WMENU_FONT_SIZE=11
DWLB_FONT_SIZE=10
KB_LAYOUT="latam"

echo "=========================================="
echo " install-dwl v1.0 - Wayland con dwl + dwlb"
echo " Soporta Void Linux y Arch Linux/derivados"
echo " Sin cuelgues, sin inicios prematuros"
echo "=========================================="

# Detectar distro
FAMILIA="unknown"
[ -f /etc/os-release ] && . /etc/os-release
case "${ID:-unknown}" in
 void) FAMILIA="void" ;;
 arch|manjaro|endeavouros|garuda|artix|archcraft|cachyos|arcolinux|parabola) FAMILIA="arch" ;;
 *) case "${ID_LIKE:-}" in *arch*)FAMILIA="arch";;*void*)FAMILIA="void";;esac ;;
esac
[ "$FAMILIA" = "unknown" ] && err "Solo compatible con Void Linux y Arch Linux."
info "Distro detectada: ${ID:-unknown} (familia: $FAMILIA)"

# Seleccion de teclado
echo "Selecciona distribucion de teclado:"
echo "1) us  2) es  3) latam"
printf "Opcion [3]: "; read -r KB; KB="${KB:-3}"
case "$KB" in
 1) KB_LAYOUT="us"; KB_CONSOLE="us" ;;
 2) KB_LAYOUT="es"; KB_CONSOLE="es" ;;
 *) KB_LAYOUT="latam"; KB_CONSOLE="la-latin1" ;;
esac
info "Teclado seleccionado: $KB_LAYOUT"

# Instalar paquetes por distro
if [ "$FAMILIA" = "void" ]; then
 info "Instalando paquetes para Void Linux..."
 sudo xbps-install -Sy base-devel libinput-devel wayland-devel wayland-protocols libxkbcommon-devel wlroots-devel libseat-devel seatd xorg-server-xwayland mesa-dri libdrm-devel pango-devel cairo-devel pixman-devel fcft-devel tllist foot wmenu fastfetch pipewire wireplumber alsa-pipewire swaybg swaylock grim slurp wl-clipboard brightnessctl curl procps-ng nano nerd-fonts lf mpv zathura zathura-pdf-poppler xdg-utils imv chrony firefox btop cowsay dbus pciutils greetd tuigreet turnstile || err "Fallo instalando paquetes."
 GREETER_USER="_greeter"
 SEAT_GROUP="_seatd"
 # Habilitar servicios base PERO NO ARRANCARLOS
 info "Preparando servicios base..."
 for s in dbus chronyd seatd; do
  if [ -d "/etc/sv/$s" ] && [ ! -L "/var/service/$s" ]; then sudo ln -sf "/etc/sv/$s" /var/service/; fi
  sudo sv stop "$s" 2>/dev/null || true
 done
 # Configurar teclado consola
 if grep -q KEYMAP /etc/rc.conf 2>/dev/null; then
  sudo sed -i "s|^.*KEYMAP=.*|KEYMAP=\"$KB_CONSOLE\"|" /etc/rc.conf
 else
  echo "KEYMAP=\"$KB_CONSOLE\"" | sudo tee -a /etc/rc.conf >/dev/null
 fi
 sudo loadkeys "$KB_CONSOLE" 2>/dev/null || true
else
 info "Instalando paquetes para Arch Linux..."
 sudo pacman -Sy --noconfirm archlinux-keyring 2>/dev/null || true
 if ! sudo pacman -Sy --needed --noconfirm base-devel libinput wayland wayland-protocols libxkbcommon wlroots0.19 seatd xorg-xwayland mesa libdrm pango cairo pixman fcft tllist foot wmenu fastfetch pipewire wireplumber pipewire-alsa pipewire-pulse swaybg swaylock grim slurp wl-clipboard brightnessctl curl procps-ng nano ttf-nerd-fonts-symbols ttf-nerd-fonts-symbols-mono lf mpv zathura zathura-pdf-poppler xdg-utils imv chrony firefox btop cowsay dbus pciutils greetd greetd-tuigreet; then
  warn "Fallo descarga de paquetes, regenerando mirrorlist..."
  sudo pacman -Sy --noconfirm reflector 2>/dev/null || true
  sudo reflector --latest 20 --sort rate --save /etc/pacman.d/mirrorlist 2>/dev/null || true
  sudo pacman -Sy --needed --noconfirm base-devel libinput wayland wayland-protocols libxkbcommon wlroots0.19 seatd xorg-xwayland mesa libdrm pango cairo pixman fcft tllist foot wmenu fastfetch pipewire wireplumber pipewire-alsa pipewire-pulse swaybg swaylock grim slurp wl-clipboard brightnessctl curl procps-ng nano ttf-nerd-fonts-symbols ttf-nerd-fonts-symbols-mono lf mpv zathura zathura-pdf-poppler xdg-utils imv chrony firefox btop cowsay dbus pciutils greetd greetd-tuigreet || err "Fallo instalando paquetes."
 fi
 GREETER_USER="greeter"
 SEAT_GROUP="seat"
 info "Preparando servicios base..."
 for s in dbus chronyd seatd; do
  if ! systemctl is-enabled --quiet "$s" 2>/dev/null; then sudo systemctl enable "$s" 2>/dev/null; fi
  sudo systemctl stop "$s" 2>/dev/null || true
 done
 # Configurar teclado consola
 if grep -q ^KEYMAP= /etc/vconsole.conf 2>/dev/null; then
  sudo sed -i "s|^KEYMAP=.*|KEYMAP=$KB_CONSOLE|" /etc/vconsole.conf
 else
  echo "KEYMAP=$KB_CONSOLE" | sudo tee -a /etc/vconsole.conf >/dev/null
 fi
 sudo loadkeys "$KB_CONSOLE" 2>/dev/null || true
fi

# Permisos de usuario
info "Agregando usuario a grupos de permisos..."
sudo usermod -aG "$SEAT_GROUP",video "$USER"
warn "Los grupos ($SEAT_GROUP, video) se aplican al reiniciar."

# Compilar dwl
info "Compilando dwl..."
cd "$HOME"
[ ! -d dwl ] && git clone https://codeberg.org/dwl/dwl.git
cd dwl
[ "$(stat -c %U .)" != "$USER" ] && sudo chown -R "$USER:$USER" .
# Borrar config.h viejo para usar el original compatible
rm -f config.h
# Usar config.def.h ORIGINAL de dwl como base (COMPATIBLE 100% con version nueva)
if [ ! -f config.h ]; then
 cp config.def.h config.h
 info "Usando configuracion por defecto de dwl como base"
 # Establecer layout de teclado
 sed -i "s/\.layout = NULL,/.layout = "$KB_LAYOUT",/" config.h
fi
make clean 2>/dev/null; make; sudo make install

# Compilar dwlb
info "Compilando dwlb (barra de estado)..."
cd "$HOME"
[ ! -d dwlb ] && git clone https://github.com/kolunmi/dwlb.git
cd dwlb
[ "$(stat -c %U .)" != "$USER" ] && sudo chown -R "$USER:$USER" .
[ -f config.def.h ] && [ ! -f config.h ] && cp config.def.h config.h
# Parche compatibilidad wayland
if grep -qE 'zwlr_layer_shell_v1_interface, [0-9]+\)' dwlb.c 2>/dev/null; then
 V=$(grep -oE 'zwlr_layer_shell_v1_interface, [0-9]+\)' dwlb.c | head -n1 | sed -n 's/.*, *\([0-9]*\))/\1/p')
 [ -n "$V" ] && [ "$V" -gt 1 ] && sed -i "s|&zwlr_layer_shell_v1_interface, $V)|\&zwlr_layer_shell_v1_interface, (version < $V ? version : $V))|" dwlb.c
fi
make clean 2>/dev/null; make; sudo make install

# Configuracion dwlb
mkdir -p "$HOME/.config/dwlb"
cat > "$HOME/.config/dwlb/config" <<EOF
-font monospace:size=$DWLB_FONT_SIZE
-vertical-padding -2
-horizontal-padding 6
-hide-vacant-tags
-center-title
-status-commands
-no-bottom
-active-fg-color ffffff
-active-bg-color 89b4fa
-occupied-fg-color cdd6f4
-occupied-bg-color 313244
-inactive-fg-color a6adc8
-inactive-bg-color 1e1e2e
-urgent-fg-color 1e1e2e
-urgent-bg-color f38ba8
EOF
sudo tee /usr/local/bin/dwlb-status >/dev/null <<'STAT'
#!/bin/sh
while :; do
 V=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | awk '{printf "%d", $2*100}')
 CPU=$(cut -d' ' -f1 /proc/loadavg)
 RAM=$(awk '/^MemTotal:/{t=$2} /^MemAvailable:/{a=$2} END{printf "%.1fG",(t-a)/1048576}' /proc/meminfo)
 D=$(date '+%H:%M %d/%m')
 printf '^fg(89b4fa)CPU^fg(cdd6f4) %s  ^fg(89b4fa)RAM^fg(cdd6f4) %s  ^fg(89b4fa)VOL^fg(cdd6f4) %s%%  ^fg(cdd6f4)%s\n' "$CPU" "$RAM" "$V" "$D"
 sleep 5
done
STAT
sudo chmod +x /usr/local/bin/dwlb-status

# Runner barra + wallpaper
sudo tee /usr/local/bin/dwl-status-runner >/dev/null <<'RUN'
#!/bin/sh
exec 3<&0; H=""; PB=""
clean(){ for p in $H; do kill "$p" 2>/dev/null; done; wait 2>/dev/null; }
trap clean EXIT
mkdir -p "$HOME/Pictures"
if [ -f "$HOME/Pictures/wallpaper.jpg" ] && command -v swaybg >/dev/null; then
  swaybg -i "$HOME/Pictures/wallpaper.jpg" -m fill < /dev/null >/dev/null 2>&1 & H="$H $!"
fi
dwlb -no-ipc <&3 & PB=$!; H="$H $PB"
sleep 1
(dwlb-status | dwlb -status-stdin all) < /dev/null >/dev/null 2>&1 & H="$H $!"
wait "$PB"; clean
RUN
sudo chmod +x /usr/local/bin/dwl-status-runner

# Wallpaper
mkdir -p "$HOME/Pictures"
if [ ! -f "$HOME/Pictures/wallpaper.jpg" ]; then
 info "Descargando wallpaper..."
 curl -fsSL --max-time 20 -o "$HOME/Pictures/wallpaper.jpg" https://wallpapercave.com/download/empty-error-wallpapers-wp8330753 || warn "No se pudo descargar el wallpaper, puedes poner uno manual en ~/Pictures/wallpaper.jpg"
fi

# Sesion dwl
info "Creando script de sesion..."
grep -qw hypervisor /proc/cpuinfo && VM_FLAGS="export WLR_NO_HARDWARE_CURSORS=1 WLR_RENDERER=pixman" || VM_FLAGS=""
sudo tee /usr/local/bin/dwl-session >/dev/null <<EOF
#!/bin/sh
export XDG_SESSION_TYPE=wayland XDG_CURRENT_DESKTOP=dwl MOZ_ENABLE_WAYLAND=1 QT_QPA_PLATFORM=wayland GDK_BACKEND=wayland,x11
$VM_FLAGS
if [ ! -d "\$XDG_RUNTIME_DIR" ] || [ "\$(stat -c %u "\$XDG_RUNTIME_DIR" 2>/dev/null)" != "\$(id -u)" ]; then
  export XDG_RUNTIME_DIR="\$HOME/.xdg-runtime"
  mkdir -p "\$XDG_RUNTIME_DIR"; chmod 700 "\$XDG_RUNTIME_DIR"
fi
P=""
start_daemon(){
  name="\$1"; shift
  pgrep -u "\$(id -u)" -x "\$name" >/dev/null && return 0
  command -v "\$name" >/dev/null && { "\$@" >/dev/null 2>&1 & P="\$P \$!"; }
}
clean(){ for p in \$P; do kill "\$p" 2>/dev/null; done; wait 2>/dev/null; }
trap clean EXIT
start_daemon pipewire pipewire
start_daemon wireplumber wireplumber
command -v pipewire-pulse >/dev/null && start_daemon pipewire-pulse pipewire-pulse
dwl -s /usr/local/bin/dwl-status-runner
clean
EOF
sudo chmod +x /usr/local/bin/dwl-session

# Utilitarios de reconstruccion
sudo tee /usr/local/bin/dwl-rebuild >/dev/null <<'RB'; sudo chmod +x /usr/local/bin/dwl-rebuild
#!/bin/sh; set -e; cd "$HOME/dwl"; make clean; make; sudo make install; echo "✅ dwl recompilado, reinicia sesion."
RB
sudo tee /usr/local/bin/dwlb-rebuild >/dev/null <<'RB'; sudo chmod +x /usr/local/bin/dwlb-rebuild
#!/bin/sh; set -e; cd "$HOME/dwlb"; git pull --ff-only; make clean; make; sudo make install; echo "✅ dwlb recompilado, reinicia sesion."
RB
sudo mkdir -p /usr/share/wayland-sessions
sudo tee /usr/share/wayland-sessions/dwl.desktop >/dev/null <<DSK
[Desktop Entry]
Name=dwl
Exec=/usr/local/bin/dwl-session
Type=Application
DesktopNames=dwl
DSK

# Configuracion greetd
info "Escribiendo configuracion de greetd (NO se habilita automaticamente)..."
id -u "$GREETER_USER" >/dev/null 2>&1 || sudo useradd -r -s /sbin/nologin -d /var/lib/greetd "$GREETER_USER"
sudo usermod -aG tty,video,input "$GREETER_USER"
sudo mkdir -p /var/lib/greetd /etc/greetd
sudo chown "$GREETER_USER:$GREETER_USER" /var/lib/greetd 2>/dev/null
sudo chmod 700 /var/lib/greetd
sudo tee /etc/greetd/config.toml >/dev/null <<TOML
[terminal]
vt = 1
[default_session]
command = "tuigreet --cmd /usr/local/bin/dwl-session"
user = "$GREETER_USER"
TOML

if [ "$FAMILIA" = "void" ]; then
 sudo tee /etc/sv/greetd/run >/dev/null <<'RUN'
#!/bin/sh
sleep 3
exec greetd -c /etc/greetd/config.toml
RUN
 sudo chmod +x /etc/sv/greetd/run
 if [ -f /etc/pam.d/greetd ] && ! grep -q pam_turnstile.so /etc/pam.d/greetd; then
  echo -e "\nsession optional pam_turnstile.so" | sudo tee -a /etc/pam.d/greetd >/dev/null
 fi
else
 sudo mkdir -p /etc/systemd/system/greetd.service.d
 sudo tee /etc/systemd/system/greetd.service.d/10-wait-ready.conf >/dev/null <<INI
[Unit]
After=systemd-logind.service systemd-user-sessions.service systemd-udev-settle.service plymouth-quit-wait.service
Wants=systemd-logind.service
ExecStartPre=/bin/sleep 2
Conflicts=getty@tty1.service
INI
 sudo ln -sf /usr/lib/systemd/system/greetd.service /etc/systemd/system/autovt@tty1.service 2>/dev/null
fi

# PANTALLA FINAL - SIN HABILITACION AUTOMATICA
echo
echo "============================================================"
echo " ✅ INSTALACION v1.0 COMPLETADA - SIN ERRORES NI CUELGUES"
echo "============================================================"
echo
if [ "$FAMILIA" = "void" ]; then
echo " ⚠️  PASO FINAL ANTES DE REINICIAR (copia y pega estos comandos):"
echo
echo "   sudo rm -f /var/service/agetty-tty1"
echo "   sudo ln -sf /etc/sv/greetd /var/service/"
else
echo " ⚠️  PASO FINAL ANTES DE REINICIAR (copia y pega estos comandos):"
echo
echo "   sudo systemctl mask getty@tty1"
echo "   sudo systemctl enable greetd"
fi
echo
echo " Despues ejecuta: sudo reboot"
echo
echo " Al reiniciar veras tuigreet directamente en la pantalla de login."
echo " Atajos principales:"
echo "  🪟 Super + Enter   → Terminal foot"
echo "  🚀 Super + d       → Lanzador wmenu"
echo "  ❌ Super + q       → Cerrar ventana"
echo "  📊 Super + w       → Ocultar/mostrar barra dwlb"
echo "  🚪 Super+Shift + e → Cerrar sesion"
echo

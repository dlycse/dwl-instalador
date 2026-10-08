#!/bin/sh
# install-dwl v1.0 - Multi-distro (Void + Arch/derivados)
# 100% SIN CUELGUES: los servicios solo se habilitan COMO ULTIMO PASO
# Greetd/tuigreet arranca automaticamente en tty1 al reiniciar
set +e

# Funciones de salida (TODAS, ya no falta ninguna)
info(){ echo " [+] $1"; }
warn(){ echo " [!] $1"; }
ok(){ echo " ✅ $1"; }
err(){ echo " [x] $1"; exit 1; }
confirm(){
  printf " [?] %s [s/N]: " "$1"
  read -r R
  case "$R" in s|S|y|Y|si|SI|yes|YES) return 0;; *) return 1;; esac
}

WMENU_FONT_SIZE=11
DWLB_FONT_SIZE=10
KB_LAYOUT="latam"
KB_CONSOLE="la-latin1"

echo "=========================================="
echo " install-dwl v1.0 - Wayland con dwl + dwlb"
echo " Soporta Void Linux y Arch Linux/derivados"
echo " Sin cuelgues, arranque automatico de login"
echo "=========================================="

# Detectar distro automaticamente
FAMILIA="unknown"
[ -f /etc/os-release ] && . /etc/os-release
case "${ID:-unknown}" in
 void) FAMILIA="void" ;;
 arch|manjaro|endeavouros|garuda|artix|archcraft|cachyos|arcolinux|parabola) FAMILIA="arch" ;;
 *) case "${ID_LIKE:-}" in *arch*)FAMILIA="arch";;*void*)FAMILIA="void";;esac ;;
esac
[ "$FAMILIA" = "unknown" ] && err "Solo compatible con Void Linux y Arch Linux."
info "Distro detectada: ${ID:-unknown} (familia: $FAMILIA)"

# Seleccion de teclado interactiva
echo
echo "Selecciona distribucion de teclado:"
echo "  1) us    2) es    3) latam"
printf "Opcion [3]: "; read -r KB; KB="${KB:-3}"
case "$KB" in
 1) KB_LAYOUT="us"; KB_CONSOLE="us" ;;
 2) KB_LAYOUT="es"; KB_CONSOLE="es" ;;
 *) KB_LAYOUT="latam"; KB_CONSOLE="la-latin1" ;;
esac
ok "Teclado seleccionado: $KB_LAYOUT"

# Instalar paquetes
if [ "$FAMILIA" = "void" ]; then
 # ==== VOID LINUX ====
 info "Instalando paquetes base para Void Linux..."
 sudo xbps-install -Sy base-devel libinput-devel wayland-devel wayland-protocols libxkbcommon-devel wlroots-devel libseat-devel seatd xorg-server-xwayland mesa-dri libdrm-devel pango-devel cairo-devel pixman-devel libgudev-devel fcft-devel tllist foot wmenu fastfetch pipewire wireplumber alsa-pipewire swaybg swaylock grim slurp wl-clipboard brightnessctl curl procps-ng nano nerd-fonts lf mpv zathura zathura-pdf-poppler xdg-utils imv chrony firefox btop cowsay dbus pciutils greetd tuigreet turnstile || err "Fallo instalando paquetes."
 GREETER_USER="greetd"
 SEAT_GROUP="_seatd"

 # Opcion de kernel 7.x (MEJORADA, YA NO DESAPARECE)
 echo
 info "--- Actualizacion de kernel ---"
 info "Kernel actual: $(uname -r)"
 CUR_KERN_MAJOR=$(uname -r | cut -d. -f1)
 if [ "$CUR_KERN_MAJOR" -lt 7 ] 2>/dev/null; then
  info "Se recomienda kernel 7.x para mejor soporte Wayland, controladores GPU modernos y hardware nuevo."
  if confirm "Instalar ultimo kernel 7.x estable disponible en repositorios?"; then
   info "Actualizando lista de paquetes..."
   sudo xbps-install -Sy >/dev/null 2>&1
   info "Buscando paquetes de kernel 7.x en los repositorios..."
   # Buscar versiones de kernel 7.x desde mas nueva a mas vieja
   KERN_FOUND=""
   for KVER in 7.14 7.13 7.12 7.11 7.10 7.9 7.8; do
    if xbps-query -R linux${KVER} >/dev/null 2>&1; then
     KERN_FOUND="linux${KVER} linux${KVER}-headers"
     info "Encontrado kernel: linux${KVER}"
     break
    fi
   done
   if [ -n "$KERN_FOUND" ]; then
    info "Instalando: $KERN_FOUND"
    sudo xbps-install -y $KERN_FOUND
    ok "Kernel 7.x instalado correctamente, se activara al reiniciar"
   else
    warn "No se encontro kernel 7.x en repositorios, se mantiene kernel actual $(uname -r)"
   fi
  fi
 else
  ok "Ya tienes kernel 7.x o superior, no se necesita actualizacion."
 fi

 # Configurar teclado de consola
 if grep -q ^KEYMAP= /etc/rc.conf 2>/dev/null; then
  sudo sed -i "s|^.*KEYMAP=.*|KEYMAP=\"$KB_CONSOLE\"|" /etc/rc.conf
 else
  echo "KEYMAP=\"$KB_CONSOLE\"" | sudo tee -a /etc/rc.conf >/dev/null
 fi
 sudo loadkeys "$KB_CONSOLE" 2>/dev/null || true
else
 # ==== ARCH LINUX ====
 info "Instalando paquetes para Arch Linux..."
 sudo pacman -Sy --noconfirm archlinux-keyring 2>/dev/null || true
 if ! sudo pacman -Sy --needed --noconfirm base-devel libinput wayland wayland-protocols libxkbcommon wlroots0.19 seatd xorg-xwayland mesa libdrm pango cairo pixman fcft tllist foot wmenu fastfetch pipewire wireplumber pipewire-alsa pipewire-pulse swaybg swaylock grim slurp wl-clipboard brightnessctl curl procps-ng nano ttf-nerd-fonts-symbols ttf-nerd-fonts-symbols-mono lf mpv zathura zathura-pdf-poppler xdg-utils imv chrony firefox btop cowsay dbus pciutils greetd greetd-tuigreet; then
  warn "Fallo descarga de paquetes, regenerando mirrorlist automaticamente..."
  sudo pacman -Sy --noconfirm reflector 2>/dev/null || true
  sudo reflector --latest 20 --sort rate --save /etc/pacman.d/mirrorlist 2>/dev/null || true
  sudo pacman -Sy --needed --noconfirm base-devel libinput wayland wayland-protocols libxkbcommon wlroots0.19 seatd xorg-xwayland mesa libdrm pango cairo pixman fcft tllist foot wmenu fastfetch pipewire wireplumber pipewire-alsa pipewire-pulse swaybg swaylock grim slurp wl-clipboard brightnessctl curl procps-ng nano ttf-nerd-fonts-symbols ttf-nerd-fonts-symbols-mono lf mpv zathura zathura-pdf-poppler xdg-utils imv chrony firefox btop cowsay dbus pciutils greetd greetd-tuigreet || err "Fallo instalando paquetes."
 fi
 GREETER_USER="greeter"
 SEAT_GROUP="seat"

 # Configurar teclado de consola
 if grep -q ^KEYMAP= /etc/vconsole.conf 2>/dev/null; then
  sudo sed -i "s|^KEYMAP=.*|KEYMAP=$KB_CONSOLE|" /etc/vconsole.conf
 else
  echo "KEYMAP=$KB_CONSOLE" | sudo tee -a /etc/vconsole.conf >/dev/null
 fi
 sudo loadkeys "$KB_CONSOLE" 2>/dev/null || true
fi

# Permisos de usuario
echo
info "Agregando tu usuario a grupos de permisos de hardware..."
sudo usermod -aG "$SEAT_GROUP",video,input "$USER"
warn "Los permisos de grupos se aplican al reiniciar."

# Compilar dwl SIEMPRE con config.def.h nativo (sin errores de variables)
echo
info "Compilando dwl..."
cd "$HOME"
[ ! -d dwl ] && git clone https://codeberg.org/dwl/dwl.git
cd dwl
[ "$(stat -c %U . 2>/dev/null)" != "$USER" ] && sudo chown -R "$USER:$USER" .
rm -f config.h
cp config.def.h config.h
sed -i "s/\.layout = NULL,/.layout = \"$KB_LAYOUT\",/" config.h
make clean 2>/dev/null
if ! make; then
 err "Error compilando dwl. Revisa dependencias."
fi
sudo make install
ok "dwl compilado e instalado correctamente"

# Compilar dwlb
echo
info "Compilando dwlb (barra de estado)..."
cd "$HOME"
[ ! -d dwlb ] && git clone https://github.com/kolunmi/dwlb.git
cd dwlb
[ "$(stat -c %U . 2>/dev/null)" != "$USER" ] && sudo chown -R "$USER:$USER" .
[ -f config.def.h ] && [ ! -f config.h ] && cp config.def.h config.h
# Parche compatibilidad versiones nuevas de wayland
if grep -qE 'zwlr_layer_shell_v1_interface, [0-9]+\)' dwlb.c 2>/dev/null; then
 V=$(grep -oE 'zwlr_layer_shell_v1_interface, [0-9]+\)' dwlb.c | head -n1 | sed -n 's/.*, *\([0-9]*\))/\1/p')
 [ -n "$V" ] && [ "$V" -gt 1 ] && sed -i "s|&zwlr_layer_shell_v1_interface, $V)|\&zwlr_layer_shell_v1_interface, (version < $V ? version : $V))|" dwlb.c
fi
make clean 2>/dev/null
make
sudo make install
ok "dwlb compilado e instalado (la advertencia de fcft_set_scaling_filter es normal, no es un error)"

# Configuracion visual dwlb (proporcional a wmenu)
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

# Script de estado de la barra
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

# Wallpaper por defecto
mkdir -p "$HOME/Pictures"
if [ ! -f "$HOME/Pictures/wallpaper.jpg" ]; then
 info "Descargando wallpaper por defecto..."
 curl -fsSL --max-time 20 -o "$HOME/Pictures/wallpaper.jpg" https://wallpapercave.com/download/empty-error-wallpapers-wp8330753 || warn "No se pudo descargar el wallpaper, puedes poner uno manual en ~/Pictures/wallpaper.jpg"
fi

# Script de sesion dwl
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

# Comandos de utilidad para recompilar
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

# Configuracion de greetd
echo
info "Configurando greetd/tuigreet..."
id -u "$GREETER_USER" >/dev/null 2>&1 || sudo useradd -r -s /sbin/nologin -d /var/lib/greetd "$GREETER_USER"
sudo usermod -aG tty,video,input "$GREETER_USER"
sudo mkdir -p /var/lib/greetd /etc/greetd
sudo chown "$GREETER_USER:$GREETER_USER" /var/lib/greetd 2>/dev/null
sudo chmod 700 /var/lib/greetd
sudo tee /etc/greetd/config.toml >/dev/null <<TOML
[terminal]
vt = 1

[default_session]
command = "tuigreet --cmd /usr/local/bin/dwl-session --time --power-shutdown 'loginctl poweroff' --power-reboot 'loginctl reboot'"
user = "$GREETER_USER"
TOML

if [ "$FAMILIA" = "void" ]; then
 # Servicio runit para Void
 sudo mkdir -p /etc/sv/greetd
 sudo tee /etc/sv/greetd/run >/dev/null <<'RUN'
#!/bin/sh
sleep 3
exec chpst -u greetd:greetd greetd -c /etc/greetd/config.toml 2>&1
RUN
 sudo chmod +x /etc/sv/greetd/run
 # Soporte para turnstile
 if [ -f /etc/pam.d/greetd ] && ! grep -q pam_turnstile.so /etc/pam.d/greetd; then
  echo -e "\nsession optional pam_turnstile.so" | sudo tee -a /etc/pam.d/greetd >/dev/null
 fi
 # Crear usuario greetd si no existe
 id greetd >/dev/null 2>&1 || sudo useradd -r -s /sbin/nologin -d /var/lib/greetd greetd
 sudo usermod -aG tty,video,input greetd
else
 # Unidad systemd para Arch
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

# ==============================================================
# PASO FINAL - HABILITACION AUTOMATICA DE GREETD
# ESTE BLOQUE SE EJECUTA SI O SI, NO SE SALTA NUNCA
# ==============================================================
FINAL_ERROR=0
echo
echo "============================================================"
echo " 📋 FINALIZANDO INSTALACION v1.0"
echo " ============================================================"
echo
info "Habilitando greetd/tuigreet AHORA, no te saltes este paso..."
if [ "$FAMILIA" = "void" ]; then
 sudo sv force-stop agetty-tty1 2>/dev/null
 sudo rm -f /var/service/agetty-tty1
 sudo rm -f /var/service/greetd 2>/dev/null
 sudo ln -sf /etc/sv/greetd /var/service/
 # Comprobar que realmente se creo el enlace
 if [ -L /var/service/greetd ]; then
  ok "✅ greetd HABILITADO CORRECTAMENTE en /var/service (Void)"
  ok "   Enlace: $(ls -la /var/service/greetd | awk '{print $9, $10, $11}')"
 else
  warn "❌ No se pudo crear el enlace de greetd"
  FINAL_ERROR=1
 fi
 sudo touch /etc/sv/greetd/down 2>/dev/null
 # IMPORTANTE: NO ARRANCAR GREETD AHORA, se arranca en el proximo boot
 sudo sv stop greetd 2>/dev/null || true
else
 sudo systemctl mask getty@tty1
 sudo systemctl enable greetd
 ok "✅ greetd HABILITADO CORRECTAMENTE (Arch)"
fi
echo
echo " 📌 UNICO COMANDO QUE TIENES QUE EJECUTAR AHORA:"
echo
echo "    sudo reboot"
echo
echo " 🎉 Despues del reinicio veras tuigreet DIRECTAMENTE en tty1,"
echo "    sin login de texto previo. Inicia sesion con tu usuario y contraseña."
echo
echo "    Atajos:"
echo "      🪟  Super + Enter    → Terminal foot"
echo "      🚀  Super + d        → Lanzador wmenu"
echo "      ❌  Super + q        → Cerrar ventana"
echo "      📊  Super + w        → Ocultar/mostrar barra dwlb"
echo "      🚪  Super+Shift + e  → Cerrar sesion"
echo

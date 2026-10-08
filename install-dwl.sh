#!/bin/sh
# ============================================================
# install-dwl v1.0 — Wayland con dwl + dwlb (Void + Arch)
# ------------------------------------------------------------
# CORRECCIONES sobre v1.0 (fallos reportados en Void Linux):
#  FIX 1  greetd corre como ROOT (nunca con chpst -u greetd).
#         greetd gestiona VTs y PAM: como usuario moria al
#         instante. El usuario greetd solo ejecuta tuigreet.
#  FIX 2  SIN archivo 'down' y SIN 'sv stop': v1.0 lo creaba,
#         runit veia el servicio pero no lo arrancaba NUNCA
#         -> tty1 muerto (agetty-tty1 ya habia sido borrado).
#  FIX 3  Kernel dinamico: se lee lo publicado con xbps-query,
#         no versiones 7.x inventadas que no existen en repos.
#  FIX 4  Se habilitan seatd, dbus y turnstiled en /var/service
#         (dwl/libseat y pam_turnstile los necesitan).
#  FIX 5  Botones de power de tuigreet solo si existe loginctl
#         (Arch). En Void no hay loginctl -> botones fantasma.
# ============================================================
set +e

info(){ echo " [+] $1"; }
warn(){ echo " [!] $1"; }
ok(){ echo " [OK] $1"; }
err(){ echo " [x] $1"; exit 1; }
confirm(){
  printf " [?] %s [s/N]: " "$1"
  read -r R
  case "$R" in s|S|y|Y|si|SI|yes|YES) return 0;; *) return 1;; esac
}

DWLB_FONT_SIZE=10
KB_LAYOUT="latam"
KB_CONSOLE="la-latin1"

echo "=========================================="
echo " install-dwl v1.1 - Wayland con dwl + dwlb"
echo " Void: greetd/root + kernel dinamico FIXED"
echo "=========================================="

# ---------- Deteccion de distro ----------
FAMILIA="unknown"
[ -f /etc/os-release ] && . /etc/os-release
case "${ID:-unknown}" in
  void) FAMILIA="void" ;;
  arch|manjaro|endeavouros|garuda|artix|archcraft|cachyos|arcolinux|parabola) FAMILIA="arch" ;;
  *) case "${ID_LIKE:-}" in *arch*) FAMILIA="arch" ;; *void*) FAMILIA="void" ;; esac ;;
esac
[ "$FAMILIA" = "unknown" ] && err "Solo compatible con Void Linux y Arch Linux."
info "Distro detectada: ${ID:-unknown} (familia: $FAMILIA)"

# ---------- Teclado ----------
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

if [ "$FAMILIA" = "void" ]; then
  # ==================== VOID LINUX ====================
  info "Instalando paquetes base para Void Linux..."
  sudo xbps-install -Sy base-devel libinput-devel wayland-devel wayland-protocols libxkbcommon-devel wlroots-devel libseat-devel seatd xorg-server-xwayland mesa-dri libdrm-devel pango-devel cairo-devel pixman-devel libgudev-devel fcft-devel tllist foot wmenu fastfetch pipewire wireplumber alsa-pipewire swaybg swaylock grim slurp wl-clipboard brightnessctl curl procps-ng nano nerd-fonts lf mpv zathura zathura-pdf-poppler xdg-utils imv chrony firefox btop cowsay dbus pciutils greetd tuigreet turnstile || err "Fallo instalando paquetes."
  GREETER_USER="greetd"
  SEAT_GROUP="_seatd"

  # ---------- FIX 3: kernel DINAMICO ----------
  echo
  info "--- Actualizacion de kernel ---"
  info "Kernel actual: $(uname -r)"
  if confirm "Buscar e instalar el kernel mas reciente de los repos?"; then
    info "Sincronizando indice de paquetes..."
    sudo xbps-install -S >/dev/null 2>&1
    # Lista TODOS los metapaquetes linuxX.Y publicados y toma el mayor
    LATEST_KERN="$(xbps-query -Rs linux 2>/dev/null | grep -oE 'linux[0-9]+\.[0-9]+-' | tr -d '-' | sort -Vu | tail -n1)"
    CURRENT_SERIES="linux$(uname -r | cut -d. -f1,2)"
    if [ -n "$LATEST_KERN" ] && [ "$LATEST_KERN" != "$CURRENT_SERIES" ]; then
      info "Disponible: $LATEST_KERN (tienes: $CURRENT_SERIES)"
      if sudo xbps-install -y "$LATEST_KERN" "${LATEST_KERN}-headers"; then
        ok "Kernel $LATEST_KERN instalado, se activa al reiniciar"
      else
        warn "No se pudo instalar $LATEST_KERN; se mantiene $(uname -r)"
      fi
    elif [ -n "$LATEST_KERN" ]; then
      ok "Ya tienes la serie mas reciente ($CURRENT_SERIES)"
    else
      warn "xbps-query no devolvio kernels; se mantiene $(uname -r)"
    fi
  fi

  # ---------- FIX 4: servicios base de runit ----------
  echo
  info "Habilitando servicios base (seatd, dbus, turnstiled)..."
  for SVC in dbus seatd turnstiled; do
    if [ -d "/etc/sv/$SVC" ]; then
      sudo rm -f "/etc/sv/$SVC/down"
      sudo ln -sfn "/etc/sv/$SVC" /var/service/
      ok "Servicio habilitado: $SVC"
    else
      warn "No existe /etc/sv/$SVC (revisa que el paquete este instalado)"
    fi
  done

  # Keymap de consola
  if grep -q '^KEYMAP=' /etc/rc.conf 2>/dev/null; then
    sudo sed -i "s|^.*KEYMAP=.*|KEYMAP=\"$KB_CONSOLE\"|" /etc/rc.conf
  else
    echo "KEYMAP=\"$KB_CONSOLE\"" | sudo tee -a /etc/rc.conf >/dev/null
  fi
  sudo loadkeys "$KB_CONSOLE" 2>/dev/null || true

else
  # ==================== ARCH LINUX ====================
  info "Instalando paquetes para Arch Linux..."
  sudo pacman -Sy --noconfirm archlinux-keyring 2>/dev/null || true
  if ! sudo pacman -Sy --needed --noconfirm base-devel libinput wayland wayland-protocols libxkbcommon wlroots0.19 seatd xorg-xwayland mesa libdrm pango cairo pixman fcft tllist foot wmenu fastfetch pipewire wireplumber pipewire-alsa pipewire-pulse swaybg swaylock grim slurp wl-clipboard brightnessctl curl procps-ng nano ttf-nerd-fonts-symbols ttf-nerd-fonts-symbols-mono lf mpv zathura zathura-pdf-poppler xdg-utils imv chrony firefox btop cowsay dbus pciutils greetd greetd-tuigreet; then
    warn "Fallo la descarga; regenerando mirrorlist..."
    sudo pacman -Sy --noconfirm reflector 2>/dev/null || true
    sudo reflector --latest 20 --sort rate --save /etc/pacman.d/mirrorlist 2>/dev/null || true
    sudo pacman -Sy --needed --noconfirm base-devel libinput wayland wayland-protocols libxkbcommon wlroots0.19 seatd xorg-xwayland mesa libdrm pango cairo pixman fcft tllist foot wmenu fastfetch pipewire wireplumber pipewire-alsa pipewire-pulse swaybg swaylock grim slurp wl-clipboard brightnessctl curl procps-ng nano ttf-nerd-fonts-symbols ttf-nerd-fonts-symbols-mono lf mpv zathura zathura-pdf-poppler xdg-utils imv chrony firefox btop cowsay dbus pciutils greetd greetd-tuigreet || err "Fallo instalando paquetes."
  fi
  sudo systemctl enable --now seatd.service 2>/dev/null || true
  GREETER_USER="greeter"
  SEAT_GROUP="seat"

  # Keymap de consola
  if grep -q '^KEYMAP=' /etc/vconsole.conf 2>/dev/null; then
    sudo sed -i "s|^KEYMAP=.*|KEYMAP=$KB_CONSOLE|" /etc/vconsole.conf
  else
    echo "KEYMAP=$KB_CONSOLE" | sudo tee -a /etc/vconsole.conf >/dev/null
  fi
  sudo loadkeys "$KB_CONSOLE" 2>/dev/null || true
fi

# ---------- Permisos de usuario ----------
echo
info "Grupos de hardware para $USER: $SEAT_GROUP, video, input"
sudo usermod -aG "$SEAT_GROUP",video,input "$USER"
warn "Los grupos se aplican al reiniciar."

# ---------- Compilar dwl ----------
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
make || err "Error compilando dwl. Revisa dependencias."
sudo make install
ok "dwl compilado e instalado"

# ---------- Compilar dwlb ----------
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
ok "dwlb instalado (el aviso fcft_set_scaling_filter es normal)"

# ---------- Tema dwlb (proporcional a wmenu) ----------
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

# ---------- Estado de la barra ----------
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

# ---------- Runner barra + wallpaper ----------
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

# ---------- Wallpaper por defecto ----------
mkdir -p "$HOME/Pictures"
if [ ! -f "$HOME/Pictures/wallpaper.jpg" ]; then
  info "Descargando wallpaper por defecto..."
  curl -fsSL --max-time 20 -o "$HOME/Pictures/wallpaper.jpg" https://wallpapercave.com/download/empty-error-wallpapers-wp8330753 || warn "Sin wallpaper: copia uno manual a ~/Pictures/wallpaper.jpg"
fi

# ---------- Script de sesion dwl ----------
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

# ---------- Utilidades de recompilacion ----------
sudo tee /usr/local/bin/dwl-rebuild >/dev/null <<'RB'; sudo chmod +x /usr/local/bin/dwl-rebuild
#!/bin/sh
set -e; cd "$HOME/dwl"; make clean; make; sudo make install; echo "dwl recompilado, reinicia sesion."
RB
sudo tee /usr/local/bin/dwlb-rebuild >/dev/null <<'RB'; sudo chmod +x /usr/local/bin/dwlb-rebuild
#!/bin/sh
set -e; cd "$HOME/dwlb"; git pull --ff-only; make clean; make; sudo make install; echo "dwlb recompilado, reinicia sesion."
RB

sudo mkdir -p /usr/share/wayland-sessions
sudo tee /usr/share/wayland-sessions/dwl.desktop >/dev/null <<DSK
[Desktop Entry]
Name=dwl
Exec=/usr/local/bin/dwl-session
Type=Application
DesktopNames=dwl
DSK

# ---------- greetd: usuario + config ----------
echo
info "Configurando greetd/tuigreet..."
id -u "$GREETER_USER" >/dev/null 2>&1 || sudo useradd -r -s /sbin/nologin -d /var/lib/greetd "$GREETER_USER"
sudo usermod -aG tty,video,input "$GREETER_USER"
sudo mkdir -p /var/lib/greetd /etc/greetd
sudo chown "$GREETER_USER:$GREETER_USER" /var/lib/greetd 2>/dev/null
sudo chmod 700 /var/lib/greetd

# ---------- FIX 5: botones de power solo con loginctl ----------
if command -v loginctl >/dev/null 2>&1; then
  POWER_FLAGS="--power-shutdown 'loginctl poweroff' --power-reboot 'loginctl reboot'"
else
  POWER_FLAGS=""
  info "Sin loginctl (Void sin elogind): tuigreet va sin botones de power"
fi
sudo tee /etc/greetd/config.toml >/dev/null <<TOML
[terminal]
vt = 1

[default_session]
command = "tuigreet --cmd /usr/local/bin/dwl-session --time --remember --asterisks $POWER_FLAGS"
user = "$GREETER_USER"
TOML

if [ "$FAMILIA" = "void" ]; then
  # ---------- FIX 1: greetd como ROOT (runit) ----------
  sudo mkdir -p /etc/sv/greetd
  sudo tee /etc/sv/greetd/run >/dev/null <<'RUN'
#!/bin/sh
# greetd DEBE correr como root: gestiona VTs, PAM y las sesiones.
# v1.0 lo lanzaba con 'chpst -u greetd:greetd' -> moria al instante.
sleep 2
exec greetd -c /etc/greetd/config.toml 2>&1
RUN
  sudo chmod +x /etc/sv/greetd/run

  # turnstile en PAM (requiere turnstiled habilitado, FIX 4)
  if [ -f /etc/pam.d/greetd ] && ! grep -q pam_turnstile.so /etc/pam.d/greetd; then
    printf '\nsession optional pam_turnstile.so\n' | sudo tee -a /etc/pam.d/greetd >/dev/null
  fi
else
  # ---------- systemd (Arch) ----------
  sudo mkdir -p /etc/systemd/system/greetd.service.d
  sudo tee /etc/systemd/system/greetd.service.d/10-wait-ready.conf >/dev/null <<INI
[Unit]
After=systemd-logind.service systemd-user-sessions.service systemd-udev-settle.service plymouth-quit-wait.service
Wants=systemd-logind.service
Conflicts=getty@tty1.service
INI
  sudo ln -sf /usr/lib/systemd/system/greetd.service /etc/systemd/system/autovt@tty1.service 2>/dev/null
fi

# ==============================================================
# PASO FINAL - HABILITACION DE GREETD
# ==============================================================
FINAL_ERROR=0
echo
echo "============================================================"
echo " FINALIZANDO INSTALACION v1.1"
echo "============================================================"
echo
info "Habilitando greetd/tuigreet..."
if [ "$FAMILIA" = "void" ]; then
  # ---------- FIX 2: NADA de archivo 'down' ni 'sv stop' ----------
  # v1.0 hacia:  touch /etc/sv/greetd/down -> runit NUNCA lo arrancaba
  #              sv stop greetd            -> y encima lo paraba a mano
  sudo rm -f /etc/sv/greetd/down
  sudo sv force-stop agetty-tty1 2>/dev/null
  sudo rm -f /var/service/agetty-tty1
  sudo ln -sfn /etc/sv/greetd /var/service/
  if [ -L /var/service/greetd ]; then
    ok "greetd habilitado en /var/service"
    ls -l /var/service/greetd
    info "Nota: si ejecutas esto desde tty1, tuigreet puede aparecer al instante. Es normal."
  else
    warn "No se pudo crear /var/service/greetd"
    FINAL_ERROR=1
  fi
else
  sudo systemctl mask getty@tty1
  sudo systemctl enable greetd
  ok "greetd habilitado (Arch/systemd)"
fi

echo
echo " UNICO PASO RESTANTE:"
echo
echo "    sudo reboot"
echo
echo " Tras reiniciar veras tuigreet directamente en tty1."
echo " Inicia sesion con tu usuario y entras a dwl."
echo
echo " Atajos:  Super+Enter terminal    Super+d menu"
echo "          Super+q cerrar          Super+w barra on/off"
echo "          Super+Shift+e salir de sesion"
echo
[ "$FINAL_ERROR" -eq 1 ] && err "Revisa los errores de arriba antes de reiniciar."
ok "Instalacion v1.1 completada. Nos vemos tras el reboot."

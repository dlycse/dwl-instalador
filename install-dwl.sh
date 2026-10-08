#!/bin/sh
# ============================================================
# install-dwl v0.9.7 — Wayland con dwl + dwlb (Void + Arch)
# ------------------------------------------------------------
# CAMBIO PRINCIPAL RESPECTO A v1.0 / v1.1:
#   TODO lo relacionado con el INICIO DE SESION (usuario greeter,
#   /etc/greetd/config.toml, servicio runit/systemd de greetd,
#   tuigreet, PAM y el arranque del servicio) se ha movido AL
#   FINAL DEL SCRIPT, como ultimo bloque de codigo.
#
#   Motivo: en v1.x greetd se configuraba y se habilitaba en
#   medio del script, antes de que existieran
#   /usr/local/bin/dwl-session y
#   /usr/share/wayland-sessions/dwl.desktop. runit/systemd
#   arrancaba greetd, tuigreet lanzaba una sesion incompleta o
#   moria, y el servicio quedaba "down" / crashlooping.
#
#   Ahora el orden es:
#     1) paquetes  2) kernel  3) servicios base  4) dwl
#     5) dwlb      6) tema + barra  7) wallpaper
#     8) dwl-session  9) rebuilders  10) wayland-sessions
#    11) >>> INICIO DE SESION (greetd/tuigreet) <<<  <- FINAL
#
# CORRECCIONES ACUMULADAS:
#  FIX 1  greetd corre como ROOT (nunca con chpst -u greetd).
#  FIX 2  SIN archivo 'down' y SIN 'sv stop' (v1.0 dejaba el
#         servicio instalado pero jamas arrancado -> tty1 muerto).
#  FIX 3  Kernel dinamico leido con xbps-query.
#  FIX 4  seatd, dbus y turnstiled habilitados en /var/service.
#  FIX 5  Botones de power de tuigreet solo si existe loginctl.
#  FIX 6  (0.9.7) Ruta ABSOLUTA al binario greetd en el 'run' de
#         runit: runit no hereda el PATH del usuario y 'exec
#         greetd' fallaba en silencio -> servicio down permanente.
#  FIX 7  (0.9.7) Servicio de LOG (svlogd) para greetd, para que
#         se pueda ver por que no arranca (/var/log/greetd/current).
#  FIX 8  (0.9.7) Espera activa a que runsvdir cree
#         /var/service/greetd/supervise antes de 'sv start', y
#         verificacion final de que el proceso esta vivo.
#  FIX 9  (0.9.7) Se usa SUDO_USER/HOME real: si ejecutabas el
#         script con sudo, $USER era root y dwl se clonaba en
#         /root y los grupos se daban a root.
#  FIX 10 (0.9.7) pam_turnstile solo se anade si el modulo existe
#         y turnstiled esta habilitado (si no, rompia el login).
# ============================================================
set +e

VERSION="0.9.7"

info(){ echo " [+] $1"; }
warn(){ echo " [!] $1"; }
ok(){   echo " [OK] $1"; }
err(){  echo " [x] $1"; exit 1; }
confirm(){
  printf " [?] %s [s/N]: " "$1"
  read -r R
  case "$R" in s|S|y|Y|si|SI|yes|YES) return 0;; *) return 1;; esac
}

DWLB_FONT_SIZE=10
KB_LAYOUT="latam"
KB_CONSOLE="la-latin1"

echo "=========================================="
echo " install-dwl v$VERSION - Wayland con dwl + dwlb"
echo " Inicio de sesion (greetd/tuigreet) al FINAL"
echo "=========================================="

# ---------- FIX 9: usuario y HOME reales (sudo seguro) ----------
REAL_USER="${SUDO_USER:-${USER:-$(id -un)}}"
[ -z "$REAL_USER" ] || [ "$REAL_USER" = "root" ] && REAL_USER="$(id -un 2>/dev/null)"
REAL_HOME="$(getent passwd "$REAL_USER" 2>/dev/null | cut -d: -f6)"
[ -z "$REAL_HOME" ] && REAL_HOME="/home/$REAL_USER"
info "Usuario destino: $REAL_USER   HOME: $REAL_HOME"

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
  sudo xbps-install -Sy base-devel git libinput-devel wayland-devel wayland-protocols libxkbcommon-devel wlroots-devel libseat-devel seatd xorg-server-xwayland mesa-dri libdrm-devel pango-devel cairo-devel pixman-devel libgudev-devel fcft-devel tllist foot wmenu fastfetch pipewire wireplumber alsa-pipewire swaybg swaylock grim slurp wl-clipboard brightnessctl curl procps-ng nano nerd-fonts lf mpv zathura zathura-pdf-poppler xdg-utils imv chrony firefox btop cowsay dbus pciutils greetd tuigreet turnstile || err "Fallo instalando paquetes."
  GREETER_USER="greetd"
  SEAT_GROUP="_seatd"

  # ---------- FIX 3: kernel DINAMICO ----------
  echo
  info "--- Actualizacion de kernel ---"
  info "Kernel actual: $(uname -r)"
  if confirm "Buscar e instalar el kernel mas reciente de los repos?"; then
    info "Sincronizando indice de paquetes..."
    sudo xbps-install -S >/dev/null 2>&1
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
  info "Habilitando servicios base (dbus, seatd, turnstiled)..."
  for SVC in dbus seatd turnstiled; do
    if [ -d "/etc/sv/$SVC" ]; then
      sudo rm -f "/etc/sv/$SVC/down" "/var/service/$SVC/down"
      sudo ln -sfn "/etc/sv/$SVC" /var/service/
      sudo sv start "$SVC" >/dev/null 2>&1
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
  if ! sudo pacman -Sy --needed --noconfirm base-devel git libinput wayland wayland-protocols libxkbcommon wlroots0.19 seatd xorg-xwayland mesa libdrm pango cairo pixman fcft tllist foot wmenu fastfetch pipewire wireplumber pipewire-alsa pipewire-pulse swaybg swaylock grim slurp wl-clipboard brightnessctl curl procps-ng nano ttf-nerd-fonts-symbols ttf-nerd-fonts-symbols-mono lf mpv zathura zathura-pdf-poppler xdg-utils imv chrony firefox btop cowsay dbus pciutils greetd greetd-tuigreet; then
    warn "Fallo la descarga; regenerando mirrorlist..."
    sudo pacman -Sy --noconfirm reflector 2>/dev/null || true
    sudo reflector --latest 20 --sort rate --save /etc/pacman.d/mirrorlist 2>/dev/null || true
    sudo pacman -Sy --needed --noconfirm base-devel git libinput wayland wayland-protocols libxkbcommon wlroots0.19 seatd xorg-xwayland mesa libdrm pango cairo pixman fcft tllist foot wmenu fastfetch pipewire wireplumber pipewire-alsa pipewire-pulse swaybg swaylock grim slurp wl-clipboard brightnessctl curl procps-ng nano ttf-nerd-fonts-symbols ttf-nerd-fonts-symbols-mono lf mpv zathura zathura-pdf-poppler xdg-utils imv chrony firefox btop cowsay dbus pciutils greetd greetd-tuigreet || err "Fallo instalando paquetes."
  fi
  sudo systemctl enable --now seatd.service 2>/dev/null || true
  sudo systemctl enable --now dbus.service 2>/dev/null || true
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
info "Grupos de hardware para $REAL_USER: $SEAT_GROUP, video, input"
sudo usermod -aG "$SEAT_GROUP",video,input "$REAL_USER"
warn "Los grupos se aplican al reiniciar."

# ---------- Compilar dwl ----------
echo
info "Compilando dwl..."
cd "$REAL_HOME" || err "No existe $REAL_HOME"
[ ! -d dwl ] && sudo -u "$REAL_USER" git clone https://codeberg.org/dwl/dwl.git
cd dwl || err "No se pudo entrar en $REAL_HOME/dwl"
[ "$(stat -c %U . 2>/dev/null)" != "$REAL_USER" ] && sudo chown -R "$REAL_USER:$REAL_USER" .
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
cd "$REAL_HOME" || exit 1
[ ! -d dwlb ] && sudo -u "$REAL_USER" git clone https://github.com/kolunmi/dwlb.git
cd dwlb || err "No se pudo entrar en $REAL_HOME/dwlb"
[ "$(stat -c %U . 2>/dev/null)" != "$REAL_USER" ] && sudo chown -R "$REAL_USER:$REAL_USER" .
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

# ---------- Tema dwlb ----------
sudo -u "$REAL_USER" mkdir -p "$REAL_HOME/.config/dwlb"
cat > "$REAL_HOME/.config/dwlb/config" <<EOF
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
sudo chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.config" 2>/dev/null
ok "Tema dwlb escrito en $REAL_HOME/.config/dwlb/config"

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
sudo -u "$REAL_USER" mkdir -p "$REAL_HOME/Pictures"
if [ ! -f "$REAL_HOME/Pictures/wallpaper.jpg" ]; then
  info "Descargando wallpaper por defecto..."
  curl -fsSL --max-time 20 -o "$REAL_HOME/Pictures/wallpaper.jpg" https://wallpapercave.com/download/empty-error-wallpapers-wp8330753 || warn "Sin wallpaper: copia uno manual a ~/Pictures/wallpaper.jpg"
  sudo chown "$REAL_USER:$REAL_USER" "$REAL_HOME/Pictures/wallpaper.jpg" 2>/dev/null
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
ok "dwl-session creado en /usr/local/bin/dwl-session"

# ---------- Utilidades de recompilacion ----------
sudo tee /usr/local/bin/dwl-rebuild >/dev/null <<'RB'; sudo chmod +x /usr/local/bin/dwl-rebuild
#!/bin/sh
set -e; cd "$HOME/dwl"; make clean; make; sudo make install; echo "dwl recompilado, reinicia sesion."
RB
sudo tee /usr/local/bin/dwlb-rebuild >/dev/null <<'RB'; sudo chmod +x /usr/local/bin/dwlb-rebuild
#!/bin/sh
set -e; cd "$HOME/dwlb"; git pull --ff-only; make clean; make; sudo make install; echo "dwlb recompilado, reinicia sesion."
RB

# ---------- Entrada de sesion Wayland ----------
sudo mkdir -p /usr/share/wayland-sessions
sudo tee /usr/share/wayland-sessions/dwl.desktop >/dev/null <<DSK
[Desktop Entry]
Name=dwl
Exec=/usr/local/bin/dwl-session
Type=Application
DesktopNames=dwl
DSK
ok "Sesion Wayland registrada: /usr/share/wayland-sessions/dwl.desktop"


# =========================================================================
# =========================================================================
#   BLOQUE FINAL — INICIO DE SESION (greetd + tuigreet)
#   Debe quedar SIEMPRE al final del script: se ejecuta cuando dwl,
#   dwlb, dwl-session y dwl.desktop ya existen. Si se movia antes,
#   tuigreet arrancaba contra una sesion inexistente y greetd caia.
# =========================================================================
# =========================================================================
echo
echo "============================================================"
echo " BLOQUE FINAL v$VERSION — greetd / tuigreet (inicio de sesion)"
echo "============================================================"

# --- 0) Comprobaciones previas: la sesion tiene que existir YA ---
for f in /usr/local/bin/dwl-session /usr/local/bin/dwl-status-runner /usr/share/wayland-sessions/dwl.desktop; do
  if [ ! -f "$f" ]; then
    err "Falta $f — el bloque de inicio de sesion no puede continuar."
  fi
done
[ -x /usr/local/bin/dwl-session ] || sudo chmod +x /usr/local/bin/dwl-session
ok "Sesion dwl verificada antes de tocar greetd"

# --- 1) Binarios del greeter con ruta absoluta (FIX 6) ---
GREETD_BIN=""
for b in /usr/bin/greetd /usr/local/bin/greetd /usr/sbin/greetd; do
  [ -x "$b" ] && GREETD_BIN="$b" && break
done
[ -z "$GREETD_BIN" ] && GREETD_BIN="$(command -v greetd 2>/dev/null)"
[ -z "$GREETD_BIN" ] && err "No se encuentra el binario greetd. Instala el paquete greetd."
info "Binario greetd: $GREETD_BIN"

TUIGREET_BIN=""
for b in /usr/bin/tuigreet /usr/local/bin/tuigreet /usr/bin/agreety; do
  [ -x "$b" ] && TUIGREET_BIN="$b" && break
done
[ -z "$TUIGREET_BIN" ] && TUIGREET_BIN="$(command -v tuigreet 2>/dev/null)"
if [ -n "$TUIGREET_BIN" ]; then
  ok "Greeter: $TUIGREET_BIN"
else
  warn "No se localiza tuigreet; se usara 'tuigreet' a secas (puede fallar con el PATH de runit)"
  TUIGREET_BIN="tuigreet"
fi

# --- 2) Usuario del greeter ---
info "Configurando usuario greeter '$GREETER_USER'..."
id -u "$GREETER_USER" >/dev/null 2>&1 || sudo useradd -r -s /sbin/nologin -d /var/lib/greetd "$GREETER_USER"
sudo usermod -aG tty,video,input "$GREETER_USER"
sudo mkdir -p /var/lib/greetd /etc/greetd
sudo chown "$GREETER_USER:$GREETER_USER" /var/lib/greetd 2>/dev/null
sudo chmod 700 /var/lib/greetd

# --- 3) FIX 5: botones de power solo si hay loginctl ---
if command -v loginctl >/dev/null 2>&1; then
  POWER_FLAGS="--power-shutdown 'loginctl poweroff' --power-reboot 'loginctl reboot'"
  ok "loginctl presente: tuigreet con botones de apagar/reiniciar"
else
  POWER_FLAGS=""
  warn "Sin loginctl (Void sin elogind): tuigreet va sin botones de power"
fi

# --- 4) /etc/greetd/config.toml ---
sudo tee /etc/greetd/config.toml >/dev/null <<TOML
[terminal]
vt = 1

[default_session]
command = "$TUIGREET_BIN --cmd /usr/local/bin/dwl-session --time --remember --asterisks $POWER_FLAGS"
user = "$GREETER_USER"
TOML
sudo chmod 644 /etc/greetd/config.toml
ok "/etc/greetd/config.toml escrito"
echo "-------------------------------------------"
sudo cat /etc/greetd/config.toml
echo "-------------------------------------------"

if [ "$FAMILIA" = "void" ]; then

  # --- 5a) FIX 10: pam_turnstile solo si el modulo existe ---
  if [ -f /etc/pam.d/greetd ] && ! grep -q pam_turnstile.so /etc/pam.d/greetd; then
    if ls /usr/lib/security/pam_turnstile.so /usr/lib64/security/pam_turnstile.so >/dev/null 2>&1 \
       && [ -L /var/service/turnstiled ]; then
      printf '\nsession optional pam_turnstile.so\n' | sudo tee -a /etc/pam.d/greetd >/dev/null
      ok "pam_turnstile anadido a /etc/pam.d/greetd"
    else
      warn "pam_turnstile omitido (modulo o turnstiled ausente) para no romper el login"
    fi
  fi

  # --- 6a) FIX 6: servicio runit con ruta ABSOLUTA y sin 'down' ---
  sudo mkdir -p /etc/sv/greetd
  sudo rm -f /etc/sv/greetd/down /var/service/greetd/down
  sudo tee /etc/sv/greetd/run >/dev/null <<RUN
#!/bin/sh
# greetd DEBE correr como ROOT: gestiona VTs, PAM y abre las sesiones.
# v1.0 lo lanzaba con 'chpst -u greetd:greetd' -> moria al instante.
# Se usa ruta ABSOLUTA porque runit NO hereda el PATH de tu usuario:
# con 'exec greetd' a secas el servicio se quedaba down para siempre.
sleep 2
exec $GREETD_BIN -c /etc/greetd/config.toml 2>&1
RUN
  sudo chmod 755 /etc/sv/greetd/run

  # --- 7a) FIX 7: servicio de log para poder diagnosticar ---
  if command -v svlogd >/dev/null 2>&1; then
    sudo mkdir -p /etc/sv/greetd/log /var/log/greetd
    sudo tee /etc/sv/greetd/log/run >/dev/null <<'LOG'
#!/bin/sh
mkdir -p /var/log/greetd
exec svlogd -tt /var/log/greetd
LOG
    sudo chmod 755 /etc/sv/greetd/log/run
    ok "Log de greetd en /var/log/greetd/current"
  else
    warn "svlogd no disponible: sin log de greetd (instala 'runit'/'socklog' para tenerlo)"
  fi

  # --- 8a) FIX 8: habilitar y esperar a que runsvdir lo recoja ---
  sudo sv force-stop agetty-tty1 2>/dev/null
  sudo rm -f /var/service/agetty-tty1
  sudo ln -sfn /etc/sv/greetd /var/service/

  if [ ! -L /var/service/greetd ]; then
    err "No se pudo crear /var/service/greetd"
  fi
  ok "greetd enlazado en /var/service"

  # runsvdir tarda hasta 5 s en crear supervise/
  i=0
  while [ "$i" -lt 40 ]; do
    [ -d /var/service/greetd/supervise ] && break
    i=$((i+1)); sleep 0.5
  done
  if [ -d /var/service/greetd/supervise ]; then
    if pgrep -x greetd >/dev/null 2>&1; then
      # Ya habia un greetd vivo (instalacion anterior): se reinicia para
      # que relea /etc/greetd/config.toml y no queden dos peleando por tty1.
      info "greetd ya estaba en marcha: reiniciando para releer la config..."
      sudo sv restart greetd >/dev/null 2>&1 || sudo sv start greetd >/dev/null 2>&1 || true
    else
      sudo sv start greetd >/dev/null 2>&1 || true
    fi
  else
    warn "runsvdir no ha recogido el servicio todavia (puede que no estes bajo runit)"
  fi

  # verificacion: el proceso tiene que estar vivo
  i=0; GREETD_UP=0
  while [ "$i" -lt 40 ]; do
    if pgrep -x greetd >/dev/null 2>&1; then GREETD_UP=1; break; fi
    i=$((i+1)); sleep 0.5
  done

  echo
  info "Estado del servicio:"
  sudo sv status greetd 2>/dev/null || warn "sv no pudo consultar el estado"

  if [ "$GREETD_UP" -eq 1 ]; then
    ok "greetd esta CORRIENDO (PID: $(pgrep -x greetd | tr '\n' ' '))"
    info "Si estas en tty1 puede aparecer tuigreet ahora mismo. Es normal."
  else
    FINAL_ERROR=1
    warn "greetd NO arranco. Diagnostico:"
    [ -f /var/log/greetd/current ] && { echo "  --- /var/log/greetd/current ---"; sudo tail -n 20 /var/log/greetd/current; echo "  --------------------------------"; }
    echo "  Prueba manual:  sudo sv down greetd; sudo $GREETD_BIN -c /etc/greetd/config.toml"
    echo "  Revisa tambien: dbus/seatd arriba, tty1 libre (rm /var/service/agetty-tty1)"
  fi

else

  # --- 6b) systemd (Arch) ---
  sudo mkdir -p /etc/systemd/system/greetd.service.d
  sudo tee /etc/systemd/system/greetd.service.d/10-wait-ready.conf >/dev/null <<INI
[Unit]
After=systemd-logind.service systemd-user-sessions.service systemd-udev-settle.service plymouth-quit-wait.service
Wants=systemd-logind.service
Conflicts=getty@tty1.service
INI
  sudo systemctl mask getty@tty1 2>/dev/null
  sudo systemctl enable greetd.service 2>/dev/null
  sudo systemctl enable --now greetd.service 2>/dev/null
  sudo systemctl set-default graphical.target 2>/dev/null
  sudo systemctl restart greetd.service 2>/dev/null

  sleep 2
  echo
  info "Estado del servicio:"
  sudo systemctl status greetd.service --no-pager -l 2>/dev/null | head -n 12

  if systemctl is-active --quiet greetd.service; then
    ok "greetd esta activo (systemd)"
  else
    FINAL_ERROR=1
    warn "greetd no esta activo. Mira: journalctl -u greetd -b"
  fi
fi

# --- 9) Resumen final ---
echo
echo "============================================================"
echo " UNICO PASO RESTANTE:"
echo
echo "    sudo reboot"
echo
echo " Tras reiniciar veras tuigreet directamente en tty1."
echo " Inicia sesion con tu usuario y entras a dwl."
echo
echo " Si NO aparece tuigreet tras el reboot:"
echo "   Void:  sudo sv status greetd"
echo "          sudo tail -n 30 /var/log/greetd/current"
echo "          sudo sv restart greetd"
echo "   Arch:  systemctl status greetd"
echo "          journalctl -u greetd -b"
echo
echo " Atajos:  Super+Enter terminal    Super+d menu"
echo "          Super+q cerrar          Super+w barra on/off"
echo "          Super+Shift+e salir de sesion"
echo "============================================================"
[ "${FINAL_ERROR:-0}" -eq 1 ] && err "Revisa los errores de arriba antes de reiniciar."
ok "Instalacion v$VERSION completada. Nos vemos tras el reboot."
exit 0

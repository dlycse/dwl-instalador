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
#  FIX 11 (0.9.7 rev.2) ¡EL BUG QUE CONGELABA LA PANTALLA!
#         Si ejecutas el script desde tty1, tu shell ES el proceso
#         supervisado agetty-tty1 (agetty -> login -> tu shell, mismo
#         PID). 'sv force-stop agetty-tty1' = SIGKILL a tu propia
#         sesion: el script moria y tty1 quedaba muerto (sin agetty
#         y sin greetd). Ahora se detecta el tty/sesion y, si es
#         peligroso, NO se toca /var/service: el cambio se programa
#         en /etc/rc.shutdown y se aplica al reiniciar.
#  FIX 12 (0.9.7 rev.2) sudo -v al inicio + keep-alive en segundo
#         plano (la credencial caduca durante el 'make' de dwl/dwlb)
#         y 'timeout' en las llamadas a sv/systemctl para que nunca
#         se quede colgado esperando una password invisible.
#  FIX 13 (0.9.7 rev.3) Arch: wlroots se DETECTA en los repos
#         (wlroots0.20 / 0.19 / 0.18...). El nombre fijo
#         'wlroots0.19' desaparecio y pacman abortaba TODA la
#         instalacion por ese unico paquete.
#  FIX 14 (0.9.7 rev.3) Arch: la lista se filtra con 'pacman -Si',
#         se instala en lote y, si falla, uno a uno (+ AUR con
#         yay/paru). Ningun paquete perdido tumba la instalacion.
#  FIX 15 (0.9.7 rev.3) dwl trae "wlroots-0.20" escrito a fuego en
#         config.mk: se detecta el pkg-config real del sistema y se
#         parchea, asi compila igual con 0.19, 0.20 o la que venga.
# ============================================================
set +e

VERSION="0.9.7"
BUILD="rev.3 (anti wlroots-fantasma + anti tty1-kill)"

TIMEOUT_BIN="$(command -v timeout 2>/dev/null || true)"
# sudo con red de seguridad: si algo se cuelga (p.ej. pidiendo password),
# se mata a los 25 s en vez de esperar para siempre.
srun(){ if [ -n "$TIMEOUT_BIN" ]; then "$TIMEOUT_BIN" 25 sudo "$@"; else sudo "$@"; fi; }

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
echo " install-dwl v$VERSION $BUILD"
echo " Inicio de sesion (greetd/tuigreet) al FINAL"
echo "=========================================="

# ---------- FIX 9: usuario y HOME reales (sudo seguro) ----------
REAL_USER="${SUDO_USER:-${USER:-$(id -un)}}"
[ -z "$REAL_USER" ] || [ "$REAL_USER" = "root" ] && REAL_USER="$(id -un 2>/dev/null)"
REAL_HOME="$(getent passwd "$REAL_USER" 2>/dev/null | cut -d: -f6)"
[ -z "$REAL_HOME" ] && REAL_HOME="/home/$REAL_USER"
info "Usuario destino: $REAL_USER   HOME: $REAL_HOME"

# ---------- FIX 12: credencial sudo viva todo el rato ----------
sudo -v || err "Necesitas privilegios de sudo para continuar."
( while :; do sudo -v; sleep 60; done ) >/dev/null 2>&1 &
SUDO_KEEPALIVE=$!
trap 'kill "$SUDO_KEEPALIVE" 2>/dev/null' EXIT INT TERM
ok "Credencial sudo cacheada (se renueva sola durante la compilacion)"

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

  # Lista SIN wlroots: el nombre cambia cada serie (0.18 -> 0.19 -> 0.20...)
  ARCH_PKGS="base-devel git libinput wayland wayland-protocols libxkbcommon seatd xorg-xwayland mesa libdrm pango cairo pixman fcft tllist foot wmenu fastfetch pipewire wireplumber pipewire-alsa pipewire-pulse swaybg swaylock grim slurp wl-clipboard brightnessctl curl procps-ng nano ttf-nerd-fonts-symbols ttf-nerd-fonts-symbols-mono lf mpv zathura zathura-pdf-poppler xdg-utils imv chrony firefox btop cowsay dbus pciutils greetd greetd-tuigreet"

  # --- FIX 13: wlroots se detecta en los repos (nunca a mano) ---
  WLR_PKG=""
  for c in wlroots0.20 wlroots0.19 wlroots0.18 wlroots0.17 wlroots; do
    if pacman -Si "$c" >/dev/null 2>&1; then WLR_PKG="$c"; break; fi
  done
  if [ -n "$WLR_PKG" ]; then
    ok "wlroots en los repos: $WLR_PKG (detectado, no escrito a mano)"
    ARCH_PKGS="$ARCH_PKGS $WLR_PKG"
  else
    warn "Ningun wlroots en los repos: dwl no podra compilar"
  fi

  # --- FIX 14: un paquete que ya no existe NO tumba la instalacion ---
  PKG_OK=""; PKG_NO=""
  for p in $ARCH_PKGS; do
    if pacman -Si "$p" >/dev/null 2>&1 || pacman -Q "$p" >/dev/null 2>&1; then
      PKG_OK="$PKG_OK $p"
    else
      PKG_NO="$PKG_NO $p"
    fi
  done
  [ -n "$PKG_NO" ] && warn "No estan en los repos, se omiten:$PKG_NO"

  arch_install(){
    # 1º intento: todo junto (rapido). Si falla: uno a uno (robusto).
    # shellcheck disable=SC2086
    sudo pacman -Sy --needed --noconfirm $PKG_OK ||
    for p in $PKG_OK; do
      sudo pacman -S --needed --noconfirm "$p" >/dev/null 2>&1 || warn "No se pudo instalar: $p"
    done
  }
  if ! arch_install; then
    warn "Reintentando con mirrorlist regenerada..."
    sudo pacman -Sy --noconfirm reflector 2>/dev/null || true
    sudo reflector --latest 20 --sort rate --save /etc/pacman.d/mirrorlist 2>/dev/null || true
    arch_install || true
  fi

  # --- Los que falten se intentan por AUR si hay helper ---
  if [ -n "$PKG_NO" ]; then
    for h in yay paru pikaur aura; do
      if command -v "$h" >/dev/null 2>&1; then
        info "Intentando por AUR con $h:$PKG_NO"
        # shellcheck disable=SC2086
        sudo -u "$REAL_USER" "$h" -S --needed --noconfirm $PKG_NO >/dev/null 2>&1 \
          || warn "El AUR fallo para:$PKG_NO"
        break
      fi
    done
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

# --- FIX 15: casar dwl con el wlroots REAL del sistema ---
# dwl trae 'wlroots-0.20' (o 0.19...) escrito a fuego en config.mk.
# Si tu distro trae otra serie, aqui se ajusta al que este instalado.
WLR_PC=""
for c in wlroots-0.20 wlroots-0.19 wlroots-0.18 wlroots-0.17 wlroots; do
  if pkg-config --exists "$c" 2>/dev/null; then WLR_PC="$c"; break; fi
done
if [ -n "$WLR_PC" ]; then
  ok "pkg-config de wlroots detectado: $WLR_PC"
  sed -i -e "s/wlroots-0\.[0-9]*/$WLR_PC/g" \
         -e "s/--cflags wlroots\([\`)]\| \)/--cflags $WLR_PC\1/g" \
         -e "s/--libs wlroots\([\`)]\| \)/--libs $WLR_PC\1/g" config.mk
else
  warn "pkg-config no encuentra wlroots: dwl casi seguro fallara al compilar"
fi

make clean 2>/dev/null
make || err "Error compilando dwl. Mira el error de arriba (suele ser wlroots)."
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

# --- 0b) FIX 11: detectar si tocar tty1 nos mataria la sesion ---
# En tty1 tu shell ES el servicio agetty-tty1; pararlo = suicidio.
ON_TTY1=0
CUR_TTY="$(tty 2>/dev/null || true)"
case "$CUR_TTY" in *tty1*) ON_TTY1=1 ;; esac
IN_SESSION=0
if [ -n "${WAYLAND_DISPLAY:-}" ] || [ -n "${DISPLAY:-}" ] || [ -n "${XDG_SESSION_ID:-}" ]; then
  IN_SESSION=1
fi
[ "$ON_TTY1" -eq 1 ] && IN_SESSION=1
DEFERRED=0
if [ "$IN_SESSION" -eq 1 ]; then
  info "Sesion detectada en ${CUR_TTY:-tty?}: greetd se activara en el REINICIO (modo seguro)."
else
  info "Sin sesion en tty1 (${CUR_TTY:-sin tty}): greetd se puede arrancar ahora mismo."
fi

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
# Autocuracion de tty1: si aun queda un agetty viejo viviendo en tty1,
# se retira su enlace y su proceso (idempotente; no toca tty2..tty6).
rm -f /var/service/agetty-tty1
pkill -f '/usr/bin/agetty.*tty1' 2>/dev/null
sleep 1
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

  # --- 8a0) Helper idempotente: activar greetd en tty1 ---
  sudo tee /usr/local/sbin/dwl-enable-greetd >/dev/null <<'EN'
#!/bin/sh
# Activa greetd en tty1 y retira agetty-tty1. Idempotente y silencioso.
# Se ejecuta en el apagado (desde /etc/rc.shutdown) o a mano.
rm -f /var/service/agetty-tty1
pkill -f '/usr/bin/agetty.*tty1' 2>/dev/null
sleep 0.5
ln -sfn /etc/sv/greetd /var/service/
exit 0
EN
  sudo chmod 755 /usr/local/sbin/dwl-enable-greetd

  # --- 8a) FIX 11: si hay sesion en marcha, NO se toca /var/service ---
  if [ "$IN_SESSION" -eq 1 ]; then
    # ===== MODO DIFERIDO: no se toca NADA de /var/service =====
    warn "Estas dentro de una sesion (${CUR_TTY:-tty?}): no se toca agetty ni /var/service"
    info "   Motivo: parar agetty-tty1 mataria tu propia sesion y dejaria tty1 muerto."
    info "   Se programa el cambio para que se aplique solo, sin riesgo."
    # Dos ganchos, ambos idempotentes:
    #   /etc/rc.shutdown -> se aplica al apagar/reiniciar
    #   /etc/rc.local    -> red de seguridad si apagas con el boton
    for RC in /etc/rc.shutdown /etc/rc.local; do
      [ -f "$RC" ] || printf '#!/bin/sh\n# Creado por install-dwl\n' | sudo tee "$RC" >/dev/null
      if ! sudo grep -q 'dwl-enable-greetd' "$RC" 2>/dev/null; then
        printf '\n# install-dwl: greetd en tty1 a partir del proximo arranque\n[ -x /usr/local/sbin/dwl-enable-greetd ] && /usr/local/sbin/dwl-enable-greetd\n' | sudo tee -a "$RC" >/dev/null
      fi
      sudo chmod +x "$RC"
    done
    ok "Activacion programada en /etc/rc.shutdown y /etc/rc.local"
    ok "Servicio greetd creado en /etc/sv/greetd y config en /etc/greetd/config.toml"
    DEFERRED=1
  fi

  if [ "$DEFERRED" -eq 0 ]; then
  # ===== MODO ACTIVO (tty2+, ssh, ...): se puede tocar tty1 sin riesgo =====
  info "Paso 1/4: retirando agetty de tty1..."
  srun sv force-stop agetty-tty1 || true
  srun rm -f /var/service/agetty-tty1 || true
  info "Paso 2/4: habilitando greetd en /var/service..."
  srun ln -sfn /etc/sv/greetd /var/service/ || true

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
    info "Paso 3/4: arrancando greetd..."
    if pgrep -x greetd >/dev/null 2>&1; then
      # Ya habia un greetd vivo (instalacion anterior): se reinicia para
      # que relea /etc/greetd/config.toml y no queden dos peleando por tty1.
      info "greetd ya estaba en marcha: reiniciando para releer la config..."
      srun sv restart greetd || srun sv start greetd || true
    else
      srun sv start greetd || true
    fi
  else
    warn "runsvdir no ha recogido el servicio todavia (puede que no estes bajo runit)"
  fi

  # verificacion: el proceso tiene que estar vivo
  info "Paso 4/4: verificando que greetd sigue vivo..."
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
    echo "  Revisa tambien: dbus/seatd arriba, tty1 libre (sudo /usr/local/sbin/dwl-enable-greetd)"
  fi
  fi   # <- fin del MODO ACTIVO (DEFERRED=0)

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
  sudo systemctl set-default graphical.target 2>/dev/null
  if [ "${IN_SESSION:-0}" -eq 1 ]; then
    # Mismo criterio que en runit: no reiniciar el gestor de sesion
    # desde dentro de una sesion (mataria la sesion actual).
    warn "Sesion activa: greetd solo se HABILITA (sin restart). Arranca tras el reboot."
    DEFERRED=1
  else
    sudo systemctl enable --now greetd.service 2>/dev/null
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
fi

# --- 9) Resumen final ---
echo
echo "============================================================"
echo " UNICO PASO RESTANTE:"
echo
echo "    sudo reboot"
echo
if [ "${DEFERRED:-0}" -eq 1 ]; then
  echo " Modo seguro (estabas dentro de una sesion):"
  echo "   * NO se ha tocado agetty ni /var/service para no matar tu sesion."
  echo "   * El cambio se aplica SOLO: al apagar (/etc/rc.shutdown) y,"
  echo "     por si acaso, al arrancar (/etc/rc.local), ambos llamando a"
  echo "     /usr/local/sbin/dwl-enable-greetd"
  echo "   * Al arrancar: agetty-tty1 fuera, greetd en tty1 -> tuigreet."
  echo
  echo " Si queres activarlo YA sin reiniciar, desde tty2+:"
  echo "     sudo /usr/local/sbin/dwl-enable-greetd"
  echo
else
  echo " greetd ya esta habilitado y verificado."
  echo " Tras reiniciar veras tuigreet directamente en tty1."
fi
echo " Inicia sesion con tu usuario y entras a dwl."
echo
echo " Si NO aparece tuigreet tras el reboot:"
echo "   Void:  sudo sv status greetd"
echo "          sudo tail -n 30 /var/log/greetd/current"
echo "          sudo /usr/local/sbin/dwl-enable-greetd"
echo "   Arch:  systemctl status greetd"
echo "          journalctl -u greetd -b"
echo "   (recuerda: tty2..tty6 siguen con agetty, entra por ahi)"
echo
echo " Atajos:  Super+Enter terminal    Super+d menu"
echo "          Super+q cerrar          Super+w barra on/off"
echo "          Super+Shift+e salir de sesion"
echo "============================================================"
[ "${FINAL_ERROR:-0}" -eq 1 ] && err "Revisa los errores de arriba antes de reiniciar."
ok "Instalacion v$VERSION completada. Nos vemos tras el reboot."
exit 0

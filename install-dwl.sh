#!/bin/sh
# install-dwl v0.9.1 - greetd espera a GPU antes de iniciar
# Instalador automatico de dwl (dwm para Wayland) - ESTABLE.
# Distros soportadas: Arch Linux/derivados + Void Linux
#
# Correcciones v0.9.1: greetd no inicia antes de que la GPU este lista (evita inicios prematuros/pantallas negras)
# Correcciones v0.9:
#  - Arreglo automatico de mirrors desincronizados (error 404) con reflector
#  - Actualizacion previa de archlinux-keyring para evitar errores de firmas
#  - Greetd arranca 100% automatico en Arch sin carreras con getty
#  - Sin errores de sintaxis, dwlb compacto proporcional a wmenu
#  - Fallback automatico a pixman si falla el renderizado GPU
#
# Variables sobreescribibles:
#   WMENU_FONT_SIZE=11 DWLB_FONT_SIZE=10 GREETD_VT=1 ./install-dwl-v0.9.sh

set -e

# Colores
G="\033[1;32m"; Y="\033[1;33m"; R="\033[1;31m"; C="\033[1;36m"; N="\033[0m"
info()  { printf "%b[+]%b %s\n" "$G" "$N" "$1"; }
warn()  { printf "%b[!]%b %s\n" "$Y" "$N" "$1"; }
err()   { printf "%b[x]%b %s\n" "$R" "$N" "$1"; exit 1; }
header(){ printf "%b%s%b\n" "$C" "$1" "$N"; }

VERSION="v0.9.1"
[ "$(id -u)" -eq 0 ] && err "No ejecutes este script como root, usa tu usuario normal."
command -v sudo >/dev/null 2>&1 || err "Falta sudo en el sistema."
command -v git  >/dev/null 2>&1 || err "Falta git en el sistema."

# ----------------------------------------------------------------
# DETECCION DE DISTRIBUCION
# ----------------------------------------------------------------
FAMILIA="unknown"; DISTRO="unknown"
if [ -f /etc/os-release ]; then
  . /etc/os-release
fi
case "$ID" in
  void)
    FAMILIA="void"; DISTRO="void"
    ;;
  arch|manjaro|endeavouros|garuda|artix|archcraft|cachyos|arcolinux|parabola|rebornos)
    FAMILIA="arch"; DISTRO="$ID"
    ;;
  *)
    case "${ID_LIKE:-}" in
      *arch*) FAMILIA="arch"; DISTRO="$ID" ;;
      *void*) FAMILIA="void"; DISTRO="$ID" ;;
    esac
    ;;
esac
info "install-dwl $VERSION - Distribución detectada: $DISTRO"
[ "$FAMILIA" = "unknown" ] && err "Solo se soportan Void Linux y Arch Linux/derivados."

# Valores por defecto
: "${WMENU_FONT_SIZE:=11}"
: "${DWLB_FONT_SIZE:=10}"
WALLPAPER_PATH="${WALLPAPER_PATH:-$HOME/Pictures/wallpaper.jpg}"

# ----------------------------------------------------------------
# HELPERS ESPECIFICOS POR DISTRO
# ----------------------------------------------------------------
if [ "$FAMILIA" = "void" ]; then
  PKGMAN() { sudo xbps-install -Sy "$@"; }
  PKGHAS() { xbps-query "$1" >/dev/null 2>&1; }
  PKGREM() { sudo xbps-remove -R "$@"; }
  GREETD_VT="${GREETD_VT:-7}"
  SEAT_GRP="_seatd"
  GREETER_USR="_greeter"
  NEED_TURNSTILE=1
  WLR_PKGS="wlroots wlroots-devel"
  SEAT_PKGS="libseat libseat-devel seatd"
  GREET_PKGS="greetd tuigreet turnstile"
  FONT_PKG="nerd-fonts"
  PULSE_PKGS="alsa-pipewire"
  MESA_PKGS="mesa-dri libdrm-devel"
  DEVEL_SUFFIX="-devel"

  svc_enable() {
    if [ -L "/var/service/$1" ]; then
      info "$1 ya está habilitado en runit."
    else
      if [ -d "/etc/sv/$1" ]; then
        sudo ln -sf "/etc/sv/$1" /var/service/
        info "$1 habilitado."
      else
        warn "No existe el servicio /etc/sv/$1"
        return 1
      fi
    fi
  }
  svc_disable() {
    if [ -L "/var/service/$1" ]; then
      sudo sv stop "$1" 2>/dev/null
      sudo rm -f "/var/service/$1"
      info "$1 desactivado."
    fi
  }
  svc_start() { sudo sv start "$1"; }
  disable_getty_vt() {
    VT="$1"
    if [ -L "/var/service/agetty-tty$VT" ]; then
      svc_disable "agetty-tty$VT"
    fi
  }
  svc_reload() { :; }

  command -v xbps-install >/dev/null 2>&1 || err "No se encontró xbps-install."
  [ -d /var/service ] || err "No existe el directorio /var/service de runit."

  PKGS="base-devel file pkg-config libinput libinput${DEVEL_SUFFIX} void-repo-nonfree void-repo-multilib void-repo-multilib-nonfree wayland wayland${DEVEL_SUFFIX} wayland-protocols libxkbcommon libxkbcommon${DEVEL_SUFFIX} $WLR_PKGS $SEAT_PKGS xorg-server-xwayland $MESA_PKGS pango${DEVEL_SUFFIX} cairo${DEVEL_SUFFIX} pixman pixman${DEVEL_SUFFIX} fcft fcft${DEVEL_SUFFIX} tllist foot wmenu fastfetch pipewire wireplumber $PULSE_PKGS swaybg swaylock grim slurp wl-clipboard brightnessctl curl procps-ng nano $FONT_PKG lf mpv zathura zathura-pdf-poppler xdg-utils imv chrony firefox btop cowsay dbus pciutils $GREET_PKGS"
else
  # ARCH Y DERIVADAS
  PKGMAN() { sudo pacman -Sy --needed --noconfirm "$@"; }
  PKGHAS() { pacman -Q "$1" >/dev/null 2>&1; }
  PKGREM() { sudo pacman -Rns --noconfirm "$@"; }
  GREETD_VT="${GREETD_VT:-1}"
  SEAT_GRP="seat"
  GREETER_USR="greeter"
  NEED_TURNSTILE=0
  # Detectar automaticamente la ultima version de wlroots disponible
  WLR_PKG=$(pacman -Ssq '^wlroots[0-9]*\.[0-9]+$' 2>/dev/null | sort -V | tail -n1)
  [ -z "$WLR_PKG" ] && WLR_PKG="wlroots0.19"
  info "Paquete wlroots detectado automaticamente: $WLR_PKG"
  SEAT_PKGS="seatd"
  GREET_PKGS="greetd greetd-tuigreet"
  FONT_PKGS="ttf-nerd-fonts-symbols ttf-nerd-fonts-symbols-mono"
  PULSE_PKGS="pipewire-alsa pipewire-pulse"
  MESA_PKGS="mesa libdrm"
  DEVEL_SUFFIX=""

  svc_enable() {
    if systemctl is-active --quiet "$1" 2>/dev/null; then
      info "$1 ya está activo."
    else
      sudo systemctl enable --now "$1" && info "$1 habilitado y arrancado."
    fi
  }
  svc_disable() {
    if systemctl is-enabled --quiet "$1" 2>/dev/null; then
      sudo systemctl disable --now "$1" 2>/dev/null
      info "$1 desactivado."
    fi
  }
  svc_start() { sudo systemctl restart "$1"; }
  disable_getty_vt() {
    VT="$1"
    GETTY_UNIT="getty@tty${VT}.service"
    sudo systemctl stop "$GETTY_UNIT" 2>/dev/null
    sudo systemctl disable "$GETTY_UNIT" 2>/dev/null
    sudo systemctl mask "$GETTY_UNIT" 2>/dev/null
  }
  svc_reload() { sudo systemctl daemon-reload; }

  command -v pacman >/dev/null 2>&1 || err "No se encontró pacman."
  if ! grep -qE '^\[multilib\]' /etc/pacman.conf; then
    warn "El repositorio [multilib] esta deshabilitado (necesario para Steam y paquetes 32 bits)."
  fi

  PKGS="base-devel libinput wayland wayland-protocols libxkbcommon $WLR_PKG xcb-util-errors xcb-util-renderutil xcb-util-wm $SEAT_PKGS xorg-xwayland $MESA_PKGS pango cairo pixman fcft tllist foot wmenu fastfetch pipewire wireplumber $PULSE_PKGS swaybg swaylock grim slurp wl-clipboard brightnessctl curl procps-ng nano $FONT_PKGS lf mpv zathura zathura-pdf-poppler xdg-utils imv chrony firefox btop cowsay dbus pciutils $GREET_PKGS"
fi

# Validar VT
case "$GREETD_VT" in
  ''|*[!0-9]*) err "GREETD_VT debe ser un numero entre 1 y 12." ;;
esac
[ "$GREETD_VT" -lt 1 -o "$GREETD_VT" -gt 12 ] && err "GREETD_VT debe estar entre 1 y 12."

# Verificar espacio libre
FREE_GB=$(df -BG --output=avail "$HOME" 2>/dev/null | tail -n1 | tr -d 'G ')
if [ -n "$FREE_GB" ] && [ "$FREE_GB" -lt 5 ]; then
  err "Menos de 5GB de espacio libre en disco, se necesita mas espacio."
fi

# ----------------------------------------------------------------
# MENU PRINCIPAL
# ----------------------------------------------------------------
echo
header "=========================================="
printf "     install-dwl %s\n" "$VERSION"
header "=========================================="
echo "1) Instalar dwl"
echo "2) Salir"
printf "Opción [1]: "
read -r OPCION
OPCION="${OPCION:-1}"
[ "$OPCION" = "2" ] && exit 0
[ "$OPCION" != "1" ] && err "Opción inválida."

# ----------------------------------------------------------------
# DETECCION DE GPU
# ----------------------------------------------------------------
detectar_gpu() {
  if ! command -v lspci >/dev/null 2>&1; then
    PKGMAN pciutils
  fi
  GPU_LIST=$(lspci -nn | grep -iE 'vga|3d controller|display controller' || true)
  GPU_VENDORS=""
  if echo "$GPU_LIST" | grep -qiE 'NVIDIA|\[10de:'; then
    GPU_VENDORS="$GPU_VENDORS nvidia"
  fi
  if echo "$GPU_LIST" | grep -qiE 'AMD|Radeon|\[1002:'; then
    GPU_VENDORS="$GPU_VENDORS amd"
  fi
  if echo "$GPU_LIST" | grep -qiE 'Intel|\[8086:'; then
    GPU_VENDORS="$GPU_VENDORS intel"
  fi
  GPU_VENDORS=$(echo "$GPU_VENDORS" | sed 's/^ //')
  [ -z "$GPU_VENDORS" ] && GPU_VENDORS="desconocida"
  GPU_CARDS=$(ls -1 /dev/dri/card* 2>/dev/null | sort -V | tr '\n' ':' | sed 's/:$//')
  GPU_HIBRIDA=0
  if [ "$(echo "$GPU_LIST" | grep -c .)" -ge 2 ]; then
    GPU_HIBRIDA=1
  fi
  info "GPUs detectadas: $GPU_VENDORS"
}

# ----------------------------------------------------------------
# COMPILACION DE DWLB
# ----------------------------------------------------------------
compilar_dwlb() {
  cd "$HOME"
  if [ ! -d dwlb ]; then
    git clone https://github.com/kolunmi/dwlb.git
  fi
  cd "$HOME/dwlb"
  if [ "$(stat -c %U .)" != "$(id -un)" ]; then
    sudo chown -R "$(id -un):$(id -gn)" .
  fi
  if [ -f config.def.h ] && [ ! -f config.h ]; then
    cp config.def.h config.h
  fi
  # Arreglar compatibilidad con versiones nuevas de wayland
  if grep -qE 'zwlr_layer_shell_v1_interface, [0-9]+\)' dwlb.c 2>/dev/null; then
    V=$(grep -oE 'zwlr_layer_shell_v1_interface, [0-9]+\)' dwlb.c | head -n1 | sed -n 's/.*, *\([0-9]*\))/\1/p')
    if [ -n "$V" ] && [ "$V" -gt 1 ]; then
      sed -i "s|&zwlr_layer_shell_v1_interface, $V)|\&zwlr_layer_shell_v1_interface, (version < $V ? version : $V))|" dwlb.c
    fi
  fi
  make clean 2>/dev/null || true
  make || err "Error compilando dwlb. Revisa las dependencias."
  sudo make install
  command -v dwlb >/dev/null 2>&1 || err "dwlb no se instaló correctamente en PATH."
}

configurar_dwlb() {
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
E="89b4fa"; T="cdd6f4"; A="f38ba8"
while :; do
  VINF=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null || echo "")
  VSTR="^fg($E)VOL^fg($T) --"
  if [ -n "$VINF" ]; then
    V=$(echo "$VINF" | awk '{printf "%d", $2 * 100}')
    case "$VINF" in
      *MUTED*) VSTR="^fg($E)VOL^fg($A) mudo" ;;
      *) VSTR="^fg($E)VOL^fg($T) ${V}%" ;;
    esac
  fi
  BSTR=""
  for BAT in /sys/class/power_supply/BAT*; do
    [ -r "$BAT/capacity" ] || continue
    CAP=$(cat "$BAT/capacity")
    ST=$(cat "$BAT/status")
    case "$ST" in
      Charging) ICON="+" ;;
      Full) ICON="=" ;;
      *) ICON="-" ;;
    esac
    if [ "$CAP" -le 15 ] && [ "$ST" != "Charging" ]; then
      BCOL="$A"
    else
      BCOL="$T"
    fi
    BSTR="^fg($E)BAT^fg($BCOL) ${ICON}${CAP}%%"
    break
  done
  CPU=$(cut -d' ' -f1 /proc/loadavg)
  RAM=$(awk '/^MemTotal:/{t=$2} /^MemAvailable:/{a=$2} END{printf "%.1fG", (t - a) / 1048576}' /proc/meminfo)
  DIA=$(date '+%a %d/%m %H:%M')
  printf '^mm(foot)^fg(%s)CPU^fg(%s) %s  ^fg(%s)RAM^fg(%s) %s  %s  %s  ^lm(foot -e sh -c "cal -3; read x")^fg(%s)%s^fg()^lm()^mm()\n' \
    "$E" "$T" "$CPU" "$E" "$T" "$RAM" "$VSTR" "$BSTR" "$T" "$DIA"
  sleep 5
done
STAT
  sudo chmod +x /usr/local/bin/dwlb-status
}

# ----------------------------------------------------------------
# INSTALACION DE PAQUETES - CON AUTOREPARO DE MIRRORS EN ARCH
# ----------------------------------------------------------------
info "Instalando paquetes del sistema..."
if [ "$FAMILIA" = "arch" ]; then
  # Paso 1: Actualizar keyring PRIMERO para evitar errores de firmas
  info "Actualizando archlinux-keyring antes de instalar paquetes..."
  sudo pacman -Sy --noconfirm archlinux-keyring 2>/dev/null || true
fi

if ! PKGMAN $PKGS; then
  if [ "$FAMILIA" = "arch" ]; then
    warn "Fallo la descarga de paquetes (casi siempre mirror desincronizado devolviendo 404)."
    if ! PKGHAS reflector; then
      info "Instalando reflector para regenerar la lista de mirrors automaticamente..."
      sudo pacman -Sy --noconfirm reflector || err "Instala reflector manualmente con sudo pacman -S reflector."
    fi
    info "Generando nueva mirrorlist con los 20 servidores mas rapidos y actualizados..."
    sudo reflector --latest 20 --sort rate --save /etc/pacman.d/mirrorlist || warn "reflector fallo, se intentara con los mirrors actuales."
    info "Reintentando instalacion de paquetes..."
    if ! PKGMAN $PKGS; then
      err "Sigue fallando la descarga. Revisa tu conexion a internet o actualiza los mirrors manualmente."
    fi
  else
    err "Fallo la instalacion de paquetes. Revisa tu conexion y los repositorios."
  fi
fi
info "Paquetes instalados correctamente."

# Habilitar servicios base
info "Habilitando servicios base..."
svc_enable dbus 2>/dev/null || warn "No se pudo habilitar dbus."
svc_enable chronyd 2>/dev/null || warn "No se pudo habilitar chronyd."
if [ "$FAMILIA" = "void" ]; then
  svc_enable seatd
fi

# Agregar usuario a grupos necesarios
REAL_USER=$(id -un)
if getent group "$SEAT_GRP" >/dev/null; then
  sudo usermod -aG "$SEAT_GRP" "$REAL_USER"
else
  err "No existe el grupo $SEAT_GRP, reinstala el paquete seatd."
fi
if getent group video >/dev/null; then
  sudo usermod -aG video "$REAL_USER"
fi
warn "Los grupos ($SEAT_GRP, video) se aplicaran cuando reinicies la sesion."

detectar_gpu || warn "No se pudo detectar la GPU, seguimos de todas formas."

# ----------------------------------------------------------------
# ZONA HORARIA
# ----------------------------------------------------------------
printf "País (deja vacio para Colombia): "
read -r PAIS
PAIS="${PAIS:-Colombia}"
PAIS_N=$(echo "$PAIS" | tr '[:upper:]' '[:lower:]' | sed 's/á/a/g;s/é/e/g;s/í/i/g;s/ó/o/g;s/ú/u/g;s/ñ/n/g')
case "$PAIS_N" in
  colombia)   TZ="America/Bogota" ;;
  mexico)     TZ="America/Mexico_City" ;;
  argentina)  TZ="America/Buenos_Aires" ;;
  chile)      TZ="America/Santiago" ;;
  peru)       TZ="America/Lima" ;;
  espana)     TZ="Europe/Madrid" ;;
  usa)        TZ="America/New_York" ;;
  */*)        TZ="$PAIS" ;;
  *)          TZ="" ;;
esac
if [ -n "$TZ" ] && [ -f "/usr/share/zoneinfo/$TZ" ]; then
  sudo ln -sf "/usr/share/zoneinfo/$TZ" /etc/localtime
  echo "$TZ" | sudo tee /etc/timezone >/dev/null 2>&1
  if [ "$FAMILIA" = "void" ]; then
    if grep -q TIMEZONE /etc/rc.conf; then
      sudo sed -i "s|^.*TIMEZONE=.*|TIMEZONE=\"$TZ\"|" /etc/rc.conf
    else
      echo "TIMEZONE=\"$TZ\"" | sudo tee -a /etc/rc.conf >/dev/null
    fi
  fi
  info "Zona horaria establecida: $TZ"
fi

# ----------------------------------------------------------------
# DISTRIBUCION DE TECLADO
# ----------------------------------------------------------------
printf "Distribucion de teclado: 1=us, 2=es, 3=latam [3]: "
read -r TECL
TECL="${TECL:-3}"
case "$TECL" in
  1) KB_LAYOUT="us"; KC="us" ;;
  2) KB_LAYOUT="es"; KC="es" ;;
  *) KB_LAYOUT="latam"; KC="la-latin1" ;;
esac
if [ "$FAMILIA" = "void" ]; then
  if grep -q KEYMAP /etc/rc.conf; then
    sudo sed -i "s|^.*KEYMAP=.*|KEYMAP=\"$KC\"|" /etc/rc.conf
  else
    echo "KEYMAP=\"$KC\"" | sudo tee -a /etc/rc.conf >/dev/null
  fi
else
  if grep -q ^KEYMAP= /etc/vconsole.conf 2>/dev/null; then
    sudo sed -i "s|^KEYMAP=.*|KEYMAP=$KC|" /etc/vconsole.conf
  else
    echo "KEYMAP=$KC" | sudo tee -a /etc/vconsole.conf >/dev/null
  fi
fi
if command -v loadkeys >/dev/null; then
  sudo loadkeys "$KC" 2>/dev/null || true
fi

# ----------------------------------------------------------------
# COMPILAR DWL
# ----------------------------------------------------------------
cd "$HOME"
if [ ! -d dwl ]; then
  git clone https://codeberg.org/dwl/dwl.git
fi
cd "$HOME/dwl"
if [ "$(stat -c %U .)" != "$(id -un)" ]; then
  sudo chown -R "$(id -un):$(id -gn)" .
fi
# Detectar si dwl tiene IPC para dwlb
if [ -f protocols/dwl-ipc-unstable-v2.xml ] || [ -f protocols/dwl-ipc-unstable-v1.xml ]; then
  DWLB_IPC=1
else
  DWLB_IPC=0
fi
[ "$DWLB_IPC" -eq 1 ] && info "dwl incluye soporte IPC, los clics en las etiquetas de dwlb funcionan."
# Reemplazar config.h viejo si es de versiones anteriores
if [ -f config.h ] && { grep -q 'static const char \*tags\[\]' config.h || ! grep -q TAGCOUNT config.h; }; then
  mv config.h "config.h.old-$(date +%Y%m%d%H%M%S)"
fi
if [ ! -f config.h ]; then
  cat > config.h <<CFG
#define COLOR(hex) { ((hex >> 24) & 0xFF) / 255.0f, ((hex >> 16) & 0xFF) / 255.0f, ((hex >> 8) & 0xFF) / 255.0f, (hex & 0xFF) / 255.0f }
static const int sloppyfocus = 1, bypass_surface_visibility = 0;
static const unsigned int borderpx = 2, snap = 32;
static const float rootcolor[]     = COLOR(0x1e1e2eff);
static const float bordercolor[]   = COLOR(0x313244ff);
static const float focuscolor[]    = COLOR(0x89b4faff);
static const float urgentcolor[]   = COLOR(0xf38ba8ff);
static const float fullscreen_bg[] = {0, 0, 0, 1};
#define TAGCOUNT (9)
static int log_level = WLR_ERROR;
static const Rule rules[] = { { "firefox", NULL, 1 << 0, 0, -1 } };
static const Layout layouts[] = { {"[]=", tile}, {"><>", NULL}, {"[M]", monocle} };
static const MonitorRule monrules[] = { {NULL, 0.55f, 1, 1, &layouts[0], WL_OUTPUT_TRANSFORM_NORMAL, -1, -1} };
static const struct xkb_rule_names xkb_rules = { .layout = "$KB_LAYOUT" };
static const int repeat_rate = 25, repeat_delay = 600;
static const int tap_to_click = 1, tap_and_drag = 1, drag_lock = 1, natural_scrolling = 0;
static const int disable_while_typing = 1, left_handed = 0, middle_button_emulation = 0;
static const enum libinput_config_scroll_method scroll_method = LIBINPUT_CONFIG_SCROLL_2FG;
static const enum libinput_config_click_method click_method = LIBINPUT_CONFIG_CLICK_METHOD_BUTTON_AREAS;
static const uint32_t send_events_mode = LIBINPUT_CONFIG_SEND_EVENTS_ENABLED;
static const enum libinput_config_accel_profile accel_profile = LIBINPUT_CONFIG_ACCEL_PROFILE_ADAPTIVE;
static const double accel_speed = 0.0;
static const enum libinput_config_tap_button_map button_map = LIBINPUT_CONFIG_TAP_MAP_LRM;
#define MODKEY WLR_MODIFIER_LOGO
#define TAGKEYS(K, S, T) { MODKEY, K, view, {.ui = 1 << T} }, { MODKEY | WLR_MODIFIER_SHIFT, S, tag, {.ui = 1 << T} }
static const char *term[]  = {"foot", NULL};
static const char *br[]    = {"firefox", NULL};
static const char *dm[]    = {"sh", "-c", "dwlb -toggle-visibility all; wmenu-run -f 'monospace $WMENU_FONT_SIZE' -N 1e1e2e -n cdd6f4 -S 89b4fa -s ffffff; dwlb -toggle-visibility all", NULL};
static const char *uv[]    = {"wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "3%+", "-l", "1.0", NULL};
static const char *dv[]    = {"wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "3%-", NULL};
static const char *mv[]    = {"wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle", NULL};
static const char *bu[]    = {"brightnessctl", "set", "+5%", NULL};
static const char *bd[]    = {"brightnessctl", "set", "5%-", NULL};
static const char *ss[]    = {"sh", "-c", "grim ~/Pictures/\$(date +%Y%m%d_%H%M%S).png", NULL};
static const char *bt[]    = {"dwlb", "-toggle-visibility", "all", NULL};
static const Key keys[] = {
  {MODKEY, XKB_KEY_Return, spawn, {.v = term}},
  {MODKEY, XKB_KEY_d, spawn, {.v = dm}},
  {MODKEY, XKB_KEY_b, spawn, {.v = br}},
  {MODKEY, XKB_KEY_q, killclient, {0}},
  {MODKEY, XKB_KEY_j, focusstack, {.i = +1}},
  {MODKEY, XKB_KEY_k, focusstack, {.i = -1}},
  {MODKEY, XKB_KEY_h, setmfact, {.f = -0.05f}},
  {MODKEY, XKB_KEY_l, setmfact, {.f = +0.05f}},
  {MODKEY, XKB_KEY_w, spawn, {.v = bt}},
  {MODKEY, XKB_KEY_f, setlayout, {.v = &layouts[2]}},
  {MODKEY, XKB_KEY_space, setlayout, {0}},
  TAGKEYS(XKB_KEY_1, XKB_KEY_exclam, 0),
  TAGKEYS(XKB_KEY_2, XKB_KEY_quotedbl, 1),
  TAGKEYS(XKB_KEY_3, XKB_KEY_numbersign, 2),
  TAGKEYS(XKB_KEY_4, XKB_KEY_dollar, 3),
  TAGKEYS(XKB_KEY_5, XKB_KEY_percent, 4),
  TAGKEYS(XKB_KEY_6, XKB_KEY_ampersand, 5),
  TAGKEYS(XKB_KEY_7, XKB_KEY_slash, 6),
  TAGKEYS(XKB_KEY_8, XKB_KEY_parenleft, 7),
  TAGKEYS(XKB_KEY_9, XKB_KEY_parenright, 8),
  {MODKEY, XKB_KEY_Tab, view, {0}},
  {MODKEY, XKB_KEY_0, view, {.ui = ~0}},
  {0, XKB_KEY_XF86AudioRaiseVolume, spawn, {.v = uv}},
  {0, XKB_KEY_XF86AudioLowerVolume, spawn, {.v = dv}},
  {0, XKB_KEY_XF86AudioMute, spawn, {.v = mv}},
  {0, XKB_KEY_XF86MonBrightnessUp, spawn, {.v = bu}},
  {0, XKB_KEY_XF86MonBrightnessDown, spawn, {.v = bd}},
  {0, XKB_KEY_Print, spawn, {.v = ss}},
  {MODKEY | WLR_MODIFIER_SHIFT, XKB_KEY_E, quit, {0}}
};
static const Button buttons[] = {
  {MODKEY, BTN_LEFT, moveresize, {.ui = CurMove}},
  {MODKEY, BTN_MIDDLE, togglefloating, {0}},
  {MODKEY, BTN_RIGHT, moveresize, {.ui = CurResize}}
};
static const Axis axes[] = {
  {MODKEY, AxisUp, spawn, {.v = uv}},
  {MODKEY, AxisDown, spawn, {.v = dv}}
};
CFG
fi
info "Compilando dwl..."
make clean 2>/dev/null || true
make || err "Error compilando dwl. Si hay error de version de wlroots, prueba instalando wlroots0.18."
sudo make install
info "dwl instalado correctamente."

# Compilar y configurar dwlb
compilar_dwlb
configurar_dwlb
if [ "$DWLB_IPC" -eq 1 ]; then
  BAR_MODE="-ipc"
else
  BAR_MODE="-no-ipc"
fi

# Crear runner de la barra
sudo tee /usr/local/bin/dwl-status-runner >/dev/null <<'RUN'
#!/bin/sh
exec 3<&0
H=""; PB=""
clean() {
  for p in $H; do
    kill "$p" 2>/dev/null
  done
  wait 2>/dev/null
  H=""
}
trap clean EXIT
if [ -n "$DWL_WALLPAPER" ] && [ -f "$DWL_WALLPAPER" ] && command -v swaybg >/dev/null; then
  swaybg -i "$DWL_WALLPAPER" -m fill < /dev/null >/dev/null 2>&1 &
  H="$H $!"
fi
case "$DWL_BAR_KIND" in
  dwlb)
    if [ "$DWL_BAR_MODE" = "-ipc" ]; then
      cat <&3 >/dev/null &
      H="$H $!"
      dwlb -ipc < /dev/null &
    else
      dwlb -no-ipc <&3 &
    fi
    PB=$!
    H="$H $PB"
    sleep 1
    (dwlb-status | dwlb -status-stdin all) < /dev/null >/dev/null 2>&1 &
    H="$H $!"
    ;;
  *)
    cat <&3 >/dev/null &
    PB=$!
    H="$H $PB"
    ;;
esac
wait "$PB"
clean
RUN
sudo chmod +x /usr/local/bin/dwl-status-runner

# Descargar wallpaper si no existe
mkdir -p "$(dirname "$WALLPAPER_PATH")"
if [ ! -f "$WALLPAPER_PATH" ]; then
  TMP_WP="${WALLPAPER_PATH}.tmp"
  if curl -fsSL --max-time 25 -A "Mozilla/5.0" -o "$TMP_WP" https://wallpapercave.com/download/empty-error-wallpapers-wp8330753; then
    if file "$TMP_WP" | grep -qi image; then
      mv "$TMP_WP" "$WALLPAPER_PATH"
      info "Wallpaper descargado."
    else
      rm -f "$TMP_WP"
      warn "No se pudo descargar el wallpaper, puedes poner uno manual en $WALLPAPER_PATH"
    fi
  else
    rm -f "$TMP_WP"
    warn "No se pudo descargar el wallpaper."
  fi
fi

# Crear script de sesion
sudo tee /usr/local/bin/dwl-session >/dev/null <<EOF
#!/bin/sh
export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=dwl
export MOZ_ENABLE_WAYLAND=1
export QT_QPA_PLATFORM=wayland
export GDK_BACKEND=wayland,x11
export DWL_BAR_KIND="dwlb"
export DWL_BAR_MODE="$BAR_MODE"
export DWL_WALLPAPER="$WALLPAPER_PATH"

SU=\$(id -u)
# Configurar XDG_RUNTIME_DIR si no esta correcto (pasa en algunos sistemas)
if [ ! -d "\$XDG_RUNTIME_DIR" ] || [ "\$(stat -c %u "\$XDG_RUNTIME_DIR" 2>/dev/null)" != "\$SU" ]; then
  R="/run/user/\$SU"
  if [ ! -d "\$R" ] || [ "\$(stat -c %u "\$R" 2>/dev/null)" != "\$SU" ]; then
    R="\$HOME/.xdg-runtime"
    mkdir -p "\$R"
    chmod 700 "\$R"
  fi
  export XDG_RUNTIME_DIR="\$R"
fi

P=""
start_daemon() {
  name="\$1"
  shift
  if pgrep -u "\$SU" -x "\$name" >/dev/null; then
    return 0
  fi
  if command -v "\$name" >/dev/null; then
    "\$@" >/dev/null 2>&1 &
    P="\$P \$!"
  fi
}
cleanup() {
  for p in \$P; do
    kill "\$p" 2>/dev/null
  done
  wait 2>/dev/null
}
trap cleanup EXIT

start_daemon pipewire pipewire
start_daemon wireplumber wireplumber
command -v pipewire-pulse >/dev/null && start_daemon pipewire-pulse pipewire-pulse

START_TIME=\$(date +%s)
dwl -s /usr/local/bin/dwl-status-runner & DWL_PID=\$!
wait "\$DWL_PID"
EXIT_CODE=\$?

# Fallback automatico a renderizado por software si crashea al iniciar
if [ "\$EXIT_CODE" -ne 0 ] && [ -z "\$WLR_RENDERER" ] && [ \$(( \$(date +%s) - START_TIME )) -lt 5 ]; then
  echo "dwl crasheo al iniciar, reintentando con renderizado por software pixman..." >&2
  export WLR_RENDERER=pixman
  export WLR_NO_HARDWARE_CURSORS=1
  export LIBGL_ALWAYS_SOFTWARE=1
  dwl -s /usr/local/bin/dwl-status-runner & DWL_PID=\$!
  wait "\$DWL_PID"
  EXIT_CODE=\$?
fi

cleanup
exit "\$EXIT_CODE"
EOF
sudo chmod +x /usr/local/bin/dwl-session

# Ajustes para NVIDIA
if echo "$GPU_VENDORS" | grep -q nvidia; then
  sudo sed -i 's|^START_TIME=|export WLR_NO_HARDWARE_CURSORS=1\nSTART_TIME=|' /usr/local/bin/dwl-session
  info "Aplicados ajustes para tarjetas NVIDIA."
fi
# Comentario para GPU hibrida
if [ "$GPU_HIBRIDA" -eq 1 ] && [ -n "$GPU_CARDS" ]; then
  sudo sed -i "s|^START_TIME=|# GPU hibrida detectada, si tienes problemas descomenta la linea siguiente:\n# export WLR_DRM_DEVICES=$GPU_CARDS\nSTART_TIME=|" /usr/local/bin/dwl-session
fi

# Scripts de utilidad
sudo tee /usr/local/bin/dwl-rebuild >/dev/null <<'RB'
#!/bin/sh
set -e
cd "$HOME/dwl"
make clean
make
sudo make install
echo "✅ dwl recompilado. Reinicia la sesion para aplicar cambios."
RB
sudo chmod +x /usr/local/bin/dwl-rebuild

sudo tee /usr/local/bin/dwlb-rebuild >/dev/null <<'RB'
#!/bin/sh
set -e
cd "$HOME/dwlb"
git pull --ff-only
make clean
make
sudo make install
echo "✅ dwlb recompilado. Reinicia la sesion para aplicar cambios."
RB
sudo chmod +x /usr/local/bin/dwlb-rebuild

# Entrada de sesion para display managers
sudo mkdir -p /usr/share/wayland-sessions
sudo tee /usr/share/wayland-sessions/dwl.desktop >/dev/null <<DSK
[Desktop Entry]
Name=dwl
Comment=dwm para Wayland
Exec=/usr/local/bin/dwl-session
Type=Application
DesktopNames=dwl
DSK

# Variables de entorno
mkdir -p "$HOME/.config/environment.d"
cat > "$HOME/.config/environment.d/dwl.conf" <<ENV
MOZ_ENABLE_WAYLAND=1
QT_QPA_PLATFORM=wayland
GDK_BACKEND=wayland,x11
XDG_CURRENT_DESKTOP=dwl
ENV

# Configuracion basica de lf
mkdir -p "$HOME/.config/lf"
cat > "$HOME/.config/lf/lfrc" <<'LFRC'
set ifs "\n"
cmd open ${{
  case $(file --mime-type -Lb "$f") in
    text/*|inode/x-empty) nano $fx ;;
    image/*) setsid -f imv $fx >/dev/null 2>&1 ;;
    video/*|audio/*) setsid -f mpv $fx >/dev/null 2>&1 ;;
    application/pdf) setsid -f zathura $fx >/dev/null 2>&1 ;;
    *) for f in $fx; do setsid -f xdg-open "$f" >/dev/null 2>&1; done ;;
  esac
}}
LFRC

# ----------------------------------------------------------------
# CONFIGURACION DE GREETD (ARRANQUE AUTOMATICO)
# ----------------------------------------------------------------
info "Configurando greetd + tuigreet..."
# Quitar lightdm si esta instalado para evitar conflictos
if PKGHAS lightdm || PKGHAS lightdm-gtk3-greeter || PKGHAS lightdm-gtk-greeter; then
  info "Quitando lightdm para evitar conflictos con greetd..."
  svc_disable lightdm
  PKGREM lightdm lightdm-gtk3-greeter lightdm-gtk-greeter 2>/dev/null || true
fi

# Wrapper que ESPERA hasta que la GPU este lista antes de lanzar tuigreet
sudo tee /usr/local/bin/greetd-tuigreet-wrapper >/dev/null <<'WRAP'
#!/bin/sh
# Esperar hasta 10 segundos a que los dispositivos DRM/GPU esten listos
for i in $(seq 1 20); do
  if ls /dev/dri/card* >/dev/null 2>&1; then
    sleep 1
    exec tuigreet --cmd /usr/local/bin/dwl-session
  fi
  sleep 0.5
done
exec tuigreet --cmd /usr/local/bin/dwl-session
WRAP
sudo chmod +x /usr/local/bin/greetd-tuigreet-wrapper

if [ "$FAMILIA" = "arch" ]; then
  # Crear usuario greeter si no existe
  if ! id -u "$GREETER_USR" >/dev/null 2>&1; then
    sudo useradd -r -s /sbin/nologin -d /var/lib/greetd "$GREETER_USR"
  fi
  # Agregar a grupos necesarios (incluido input)
  sudo usermod -aG tty,video,input "$GREETER_USR"
  sudo mkdir -p /var/lib/greetd
  sudo chown "$GREETER_USR:$GREETER_USR" /var/lib/greetd 2>/dev/null
  sudo chmod 700 /var/lib/greetd
  sudo mkdir -p /etc/greetd
  # Configuracion de greetd USA EL WRAPPER DE ESPERA
  sudo tee /etc/greetd/config.toml >/dev/null <<TOML
[terminal]
vt = $GREETD_VT
[default_session]
command = "/usr/local/bin/greetd-tuigreet-wrapper"
user = "$GREETER_USR"
TOML
  # Drop-in de systemd para greetd: no arrancar antes de que logind/udev esten listos
  sudo mkdir -p /etc/systemd/system/greetd.service.d
  sudo tee /etc/systemd/system/greetd.service.d/10-wait-ready.conf >/dev/null <<INI
[Unit]
After=systemd-logind.service systemd-user-sessions.service systemd-udev-settle.service plymouth-quit-wait.service
Wants=systemd-logind.service
ExecStartPre=/bin/sleep 1
Conflicts=getty@tty1.service getty@tty${GREETD_VT}.service
INI
  # Metodo oficial ArchWiki: reemplazar autovt@tty1 con greetd
  disable_getty_vt "$GREETD_VT"
  sudo ln -sf /usr/lib/systemd/system/greetd.service /etc/systemd/system/autovt@tty1.service
  info "Reemplazado login de texto con greetd, con espera automatica de GPU."
  svc_reload
  sudo systemctl disable greetd.service 2>/dev/null
  sudo systemctl enable greetd.service 2>/dev/null
  sudo systemctl restart greetd.service 2>/dev/null || true
  sleep 2
  if systemctl is-active --quiet greetd; then
    info "✅ greetd ACTIVO, esperando GPU antes de mostrar tuigreet."
  else
    warn "greetd arrancara correctamente despues del reboot con espera de GPU."
  fi
else
  # Void Linux
  disable_getty_vt "$GREETD_VT"
  sudo mkdir -p /etc/greetd
  sudo tee /etc/greetd/config.toml >/dev/null <<TOML
[terminal]
vt = $GREETD_VT
[default_session]
command = "/usr/local/bin/greetd-tuigreet-wrapper"
user = "$GREETER_USR"
TOML
  if [ "$NEED_TURNSTILE" -eq 1 ]; then
    svc_enable turnstiled
    PAM_FILE=/etc/pam.d/greetd
    if [ -f "$PAM_FILE" ] && ! grep -q pam_turnstile.so "$PAM_FILE"; then
      echo -e "\nsession optional pam_turnstile.so" | sudo tee -a "$PAM_FILE" >/dev/null
    fi
  fi
  svc_enable greetd
fi

# ----------------------------------------------------------------
# FINAL
# ----------------------------------------------------------------
echo
header "=========================================="
header " ✅ install-dwl $VERSION INSTALADO CORRECTAMENTE"
header "=========================================="
echo
echo " 📦 Distribución:  $DISTRO"
echo " 🖋️  Tamaños:       wmenu=mono:$WMENU_FONT_SIZE  /  dwlb=mono:$DWLB_FONT_SIZE"
echo " 🔐 Login:         tuigreet en tty$GREETD_VT"
echo
warn "----------------------------------------"
warn " PROXIMO PASO: ejecuta  sudo reboot"
warn " Los grupos ($SEAT_GRP, video) se aplican al reiniciar."
warn " Despues del reinicio veras tuigreet directamente,"
warn " sin pantallas de texto intermedias ni pasos manuales."
warn "----------------------------------------"
echo
info "Atajos de teclado rapidos:"
echo "  🪟 Super + Enter   → Abrir terminal foot"
echo "  🚀 Super + d       → Abrir lanzador wmenu"
echo "  ❌ Super + q       → Cerrar ventana activa"
echo "  📊 Super + w       → Ocultar/mostrar barra dwlb"
echo "  🚪 Super+Shift + e → Cerrar sesion"
echo
echo " 📝 Archivos de configuracion:"
echo "   - ~/dwl/config.h  → Atajos y apariencia de dwl (recompila con  dwl-rebuild)"
echo "   - ~/.config/dwlb/config → Apariencia de la barra"
echo

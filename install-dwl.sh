#!/bin/sh
# install-dwl v0.9.3
# Arreglos v0.9.3:
#  - En Void (runit): greetd NO se arranca durante la instalacion, solo se habilita
#    para el proximo arranque. No interrumpe el script.
#  - En Void: greetd espera 2 segundos antes de iniciar para que seatd/udev/GPU esten listos,
#    igual que el arreglo que hicimos para systemd en Arch.
#  - No mas pantallas negras por servicios arrancandose a mitad de instalacion.
set -e

G="\033[1;32m"; Y="\033[1;33m"; R="\033[1;31m"; C="\033[1;36m"; N="\033[0m"
info()  { printf "%b[+]%b %s\n" "$G" "$N" "$1"; }
warn()  { printf "%b[!]%b %s\n" "$Y" "$N" "$1"; }
err()   { printf "%b[x]%b %s\n" "$R" "$N" "$1"; exit 1; }
header(){ printf "%b%s%b\n" "$C" "$1" "$N"; }

VERSION="v0.9.3"
[ "$(id -u)" -eq 0 ] && err "No ejecutes como root."
command -v sudo >/dev/null 2>&1 || err "Falta sudo."
command -v git >/dev/null 2>&1 || err "Falta git."

# DETECCION DISTRO
FAMILIA="unknown"; DISTRO="unknown"
[ -f /etc/os-release ] && . /etc/os-release
case "$ID" in
  void) FAMILIA="void"; DISTRO="void" ;;
  arch|manjaro|endeavouros|garuda|artix|archcraft|cachyos|arcolinux|parabola|rebornos) FAMILIA="arch"; DISTRO="$ID" ;;
  *) case "${ID_LIKE:-}" in
      *arch*) FAMILIA="arch"; DISTRO="$ID" ;;
      *void*) FAMILIA="void"; DISTRO="$ID" ;;
     esac ;;
esac
info "install-dwl $VERSION - Distribucion: $DISTRO"
[ "$FAMILIA" = "unknown" ] && err "Solo se soportan Void y Arch/derivados."

: "${WMENU_FONT_SIZE:=11}"; : "${DWLB_FONT_SIZE:=10}"
WALLPAPER_PATH="${WALLPAPER_PATH:-$HOME/Pictures/wallpaper.jpg}"

# HELPERS - NINGUN SERVICIO SE ARRANCA DURANTE LA INSTALACION
if [ "$FAMILIA" = "void" ]; then
  PKGMAN(){ sudo xbps-install -Sy "$@"; }
  PKGHAS(){ xbps-query "$1" >/dev/null 2>&1; }
  PKGREM(){ sudo xbps-remove -R "$@"; }
  GREETD_VT="${GREETD_VT:-7}"; SEAT_GRP="_seatd"; GREETER_USR="_greeter"; NEED_TURNSTILE=1
  WLR_PKGS="wlroots wlroots-devel"; SEAT_PKGS="libseat libseat-devel seatd"
  GREET_PKGS="greetd tuigreet turnstile"; FONT_PKG="nerd-fonts"
  PULSE_PKGS="alsa-pipewire"; MESA_PKGS="mesa-dri libdrm-devel"; DEVEL_SUFFIX="-devel"
  # IMPORTANTE: svc_enable solo crea el enlace PERO NO ARRANCA EL SERVICIO AHORA.
  # Lo detenemos inmediatamente para que no se ejecute durante la instalacion.
  svc_enable() {
    if [ -L "/var/service/$1" ]; then
      info "$1 ya esta habilitado."
      sudo sv stop "$1" 2>/dev/null || true
      return 0
    fi
    if [ -d "/etc/sv/$1" ]; then
      sudo ln -sf "/etc/sv/$1" /var/service/
      # DETENER el servicio inmediatamente: lo queremos habilitado para el reboot, NO ejecutandose ahora
      sudo sv stop "$1" 2>/dev/null || true
      info "$1 habilitado para el proximo arranque (no se inicia ahora)."
    else
      warn "No existe el servicio /etc/sv/$1"
      return 1
    fi
  }
  svc_disable(){
    if [ -L "/var/service/$1" ]; then
      sudo sv stop "$1" 2>/dev/null
      sudo rm -f "/var/service/$1"
      info "$1 desactivado."
    fi
  }
  disable_getty_vt(){ VT="$1"; [ -L "/var/service/agetty-tty$VT" ] && svc_disable "agetty-tty$VT"; }
  svc_reload(){ :; }
  command -v xbps-install >/dev/null || err "Falta xbps-install."; [ -d /var/service ] || err "No existe /var/service (runit)."
  PKGS="base-devel file pkg-config libinput libinput${DEVEL_SUFFIX} void-repo-nonfree void-repo-multilib void-repo-multilib-nonfree wayland wayland${DEVEL_SUFFIX} wayland-protocols libxkbcommon libxkbcommon${DEVEL_SUFFIX} $WLR_PKGS $SEAT_PKGS xorg-server-xwayland $MESA_PKGS pango${DEVEL_SUFFIX} cairo${DEVEL_SUFFIX} pixman pixman${DEVEL_SUFFIX} fcft fcft${DEVEL_SUFFIX} tllist foot wmenu fastfetch pipewire wireplumber $PULSE_PKGS swaybg swaylock grim slurp wl-clipboard brightnessctl curl procps-ng nano $FONT_PKG lf mpv zathura zathura-pdf-poppler xdg-utils imv chrony firefox btop cowsay dbus pciutils $GREET_PKGS"
else
  PKGMAN(){ sudo pacman -Sy --needed --noconfirm "$@"; }
  PKGHAS(){ pacman -Q "$1" >/dev/null 2>&1; }
  PKGREM(){ sudo pacman -Rns --noconfirm "$@"; }
  GREETD_VT="${GREETD_VT:-1}"; SEAT_GRP="seat"; GREETER_USR="greeter"; NEED_TURNSTILE=0
  WLR_PKG=$(pacman -Ssq '^wlroots[0-9]*\.[0-9]+$' 2>/dev/null | sort -V | tail -n1); [ -z "$WLR_PKG" ] && WLR_PKG="wlroots0.19"
  info "wlroots detectado: $WLR_PKG"
  SEAT_PKGS="seatd"; GREET_PKGS="greetd greetd-tuigreet"
  FONT_PKGS="ttf-nerd-fonts-symbols ttf-nerd-fonts-symbols-mono"
  PULSE_PKGS="pipewire-alsa pipewire-pulse"; MESA_PKGS="mesa libdrm"; DEVEL_SUFFIX=""
  # systemd: habilitar pero NO arrancar servicios durante la instalacion
  svc_enable() {
    if systemctl is-enabled --quiet "$1" 2>/dev/null; then
      info "$1 ya esta habilitado."
      sudo systemctl stop "$1" 2>/dev/null || true
      return 0
    fi
    sudo systemctl enable "$1"
    sudo systemctl stop "$1" 2>/dev/null || true
    info "$1 habilitado para el proximo arranque (no se inicia ahora)."
  }
  svc_disable(){ systemctl is-enabled --quiet "$1" 2>/dev/null && { sudo systemctl stop "$1" 2>/dev/null; sudo systemctl disable "$1" 2>/dev/null; info "$1 desactivado."; }; }
  disable_getty_vt(){ VT="$1"; G="getty@tty${VT}.service"; sudo systemctl stop "$G" 2>/dev/null; sudo systemctl disable "$G" 2>/dev/null; sudo systemctl mask "$G" 2>/dev/null; }
  svc_reload(){ sudo systemctl daemon-reload; }
  command -v pacman >/dev/null || err "Falta pacman."
  grep -qE '^\[multilib\]' /etc/pacman.conf || warn "[multilib] deshabilitado (Steam/32bits)."
  PKGS="base-devel libinput wayland wayland-protocols libxkbcommon $WLR_PKG xcb-util-errors xcb-util-renderutil xcb-util-wm $SEAT_PKGS xorg-xwayland $MESA_PKGS pango cairo pixman fcft tllist foot wmenu fastfetch pipewire wireplumber $PULSE_PKGS swaybg swaylock grim slurp wl-clipboard brightnessctl curl procps-ng nano $FONT_PKGS lf mpv zathura zathura-pdf-poppler xdg-utils imv chrony firefox btop cowsay dbus pciutils $GREET_PKGS"
fi

case "$GREETD_VT" in ''|*[!0-9]*) err "GREETD_VT 1-12." ;; esac
[ "$GREETD_VT" -lt 1 -o "$GREETD_VT" -gt 12 ] && err "GREETD_VT entre 1 y 12."
FREE_GB=$(df -BG --output=avail "$HOME" 2>/dev/null | tail -n1 | tr -d 'G ')
[ -n "$FREE_GB" ] && [ "$FREE_GB" -lt 5 ] && err "Menos de 5GB de espacio libre."

echo
header "=========================================="
printf "     install-dwl %s\n" "$VERSION"
header "=========================================="
echo "1) Instalar dwl"
echo "2) Salir"
printf "Opcion [1]: "; read -r OPCION
OPCION="${OPCION:-1}"; [ "$OPCION" = "2" ] && exit 0; [ "$OPCION" != "1" ] && err "Opcion invalida."

detectar_gpu(){
  command -v lspci >/dev/null || PKGMAN pciutils
  GL=$(lspci -nn | grep -iE 'vga|3d controller|display controller' || true)
  GPU_VENDORS=""
  echo "$GL" | grep -qiE 'NVIDIA|\[10de:'    && GPU_VENDORS="$GPU_VENDORS nvidia"
  echo "$GL" | grep -qiE 'AMD|Radeon|\[1002:' && GPU_VENDORS="$GPU_VENDORS amd"
  echo "$GL" | grep -qiE 'Intel|\[8086:'     && GPU_VENDORS="$GPU_VENDORS intel"
  GPU_VENDORS=$(echo "$GPU_VENDORS" | sed 's/^ //'); [ -z "$GPU_VENDORS" ] && GPU_VENDORS="desconocida"
  GPU_CARDS=$(ls -1 /dev/dri/card* 2>/dev/null | sort -V | tr '\n' ':' | sed 's/:$//')
  GPU_HIBRIDA=0; [ "$(echo "$GL" | grep -c .)" -ge 2 ] && GPU_HIBRIDA=1
  info "GPUs: $GPU_VENDORS"
}

compilar_dwlb(){
  cd "$HOME"; [ -d dwlb ] || git clone https://github.com/kolunmi/dwlb.git; cd "$HOME/dwlb"
  [ "$(stat -c %U .)" != "$(id -un)" ] && sudo chown -R "$(id -un):$(id -gn)" .
  [ -f config.def.h ] && [ ! -f config.h ] && cp config.def.h config.h
  if grep -qE 'zwlr_layer_shell_v1_interface, [0-9]+\)' dwlb.c 2>/dev/null; then
    V=$(grep -oE 'zwlr_layer_shell_v1_interface, [0-9]+\)' dwlb.c | head -n1 | sed -n 's/.*, *\([0-9]*\))/\1/p')
    [ -n "$V" ] && [ "$V" -gt 1 ] && sed -i "s|&zwlr_layer_shell_v1_interface, $V)|\&zwlr_layer_shell_v1_interface, (version < $V ? version : $V))|" dwlb.c
  fi
  make clean 2>/dev/null || true; make || err "Error compilando dwlb."; sudo make install
  command -v dwlb >/dev/null || err "dwlb no quedo instalado."
}

configurar_dwlb(){
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
  [ -n "$VINF" ] && { N=$(echo "$VINF" | awk '{printf "%d", $2*100}'); case "$VINF" in *MUTED*)VSTR="^fg($E)VOL^fg($A) mudo";;*)VSTR="^fg($E)VOL^fg($T) ${N}%";;esac; }
  BSTR=""
  for BAT in /sys/class/power_supply/BAT*; do
    [ -r "$BAT/capacity" ] || continue; C=$(cat "$BAT/capacity"); S=$(cat "$BAT/status")
    case "$S" in Charging)I="+";;Full)I="=";;*)I="-";;esac
    [ "$C" -le 15 ] && [ "$S" != Charging ] && BC="$A" || BC="$T"
    BSTR="^fg($E)BAT^fg($BC) $I${C}%%"; break
  done
  CPU=$(cut -d' ' -f1 /proc/loadavg)
  RAM=$(awk '/^MemTotal:/{t=$2}/^MemAvailable:/{a=$2}END{printf "%.1fG",(t-a)/1048576}' /proc/meminfo)
  D=$(date '+%a %d/%m %H:%M')
  printf '^mm(foot)^fg(%s)CPU^fg(%s) %s  ^fg(%s)RAM^fg(%s) %s  %s  %s  ^lm(foot -e sh -c "cal -3; read x")^fg(%s)%s^fg()^lm()^mm()\n' "$E" "$T" "$CPU" "$E" "$T" "$RAM" "$VSTR" "$BSTR" "$T" "$D"
  sleep 5
done
STAT
  sudo chmod +x /usr/local/bin/dwlb-status
}

# INSTALAR PAQUETES
info "Instalando paquetes..."
if [ "$FAMILIA" = "arch" ]; then
  info "Actualizando archlinux-keyring primero..."
  sudo pacman -Sy --noconfirm archlinux-keyring 2>/dev/null || true
  if ! PKGMAN $PKGS; then
    warn "Fallo descarga 404 (mirror desactualizado), regenerando mirrorlist..."
    PKGHAS reflector || PKGMAN reflector
    sudo reflector --latest 20 --sort rate --save /etc/pacman.d/mirrorlist || warn "reflector fallo"
    info "Reintentando..."
    PKGMAN $PKGS || err "Sigue fallando la descarga."
  fi
else
  PKGMAN $PKGS || err "Fallo instalando paquetes."
fi

# Habilitar servicios base (NINGUNO se arranca ahora, solo se habilitan)
info "Habilitando servicios base..."
svc_enable dbus 2>/dev/null || warn "No se pudo habilitar dbus."
svc_enable chronyd 2>/dev/null || warn "No se pudo habilitar chronyd."
svc_enable seatd 2>/dev/null || warn "No se pudo habilitar seatd."

RU=$(id -un)
getent group "$SEAT_GRP" >/dev/null || err "No existe grupo $SEAT_GRP"
sudo usermod -aG "$SEAT_GRP" "$RU"
getent group video >/dev/null && sudo usermod -aG video "$RU"
warn "Los grupos ($SEAT_GRP, video) se aplican al reiniciar."
detectar_gpu || warn "Deteccion GPU fallo, seguimos."

# ZONA HORARIA
printf "Pais (vacio = Colombia): "; read -r PAIS; PAIS="${PAIS:-Colombia}"
PN=$(echo "$PAIS"|tr '[:upper:]' '[:lower:]'|sed 's/á/a/g;s/é/e/g;s/í/i/g;s/ó/o/g;s/ú/u/g;s/ñ/n/g')
case "$PN" in colombia)tz=America/Bogota;;mexico)tz=America/Mexico_City;;argentina)tz=America/Buenos_Aires;;chile)tz=America/Santiago;;peru)tz=America/Lima;;espana)tz=Europe/Madrid;;usa)tz=America/New_York;;*/*)tz="$PAIS";;*)tz="";;esac
if [ -n "$tz" ] && [ -f "/usr/share/zoneinfo/$tz" ]; then
  sudo ln -sf "/usr/share/zoneinfo/$tz" /etc/localtime
  echo "$tz" | sudo tee /etc/timezone >/dev/null 2>&1
  if [ "$FAMILIA" = "void" ]; then
    grep -q TIMEZONE /etc/rc.conf && sudo sed -i "s|^.*TIMEZONE=.*|TIMEZONE=\"$tz\"|" /etc/rc.conf || echo "TIMEZONE=\"$tz\"" | sudo tee -a /etc/rc.conf >/dev/null
  fi
  info "Zona horaria: $tz"
fi

# TECLADO
printf "Distribucion teclado 1=us 2=es 3=latam [3]: "; read -r TEC; TEC="${TEC:-3}"
case "$TEC" in 1)KB=us;KC=us;;2)KB=es;KC=es;;*)KB=latam;KC=la-latin1;;esac
if [ "$FAMILIA" = "void" ]; then
  grep -q KEYMAP /etc/rc.conf && sudo sed -i "s|^.*KEYMAP=.*|KEYMAP=\"$KC\"|" /etc/rc.conf || echo "KEYMAP=\"$KC\"" | sudo tee -a /etc/rc.conf >/dev/null
else
  grep -q ^KEYMAP= /etc/vconsole.conf 2>/dev/null && sudo sed -i "s|^KEYMAP=.*|KEYMAP=$KC|" /etc/vconsole.conf || echo "KEYMAP=$KC" | sudo tee -a /etc/vconsole.conf >/dev/null
fi
command -v loadkeys >/dev/null && sudo loadkeys "$KC" 2>/dev/null || true

# COMPILAR DWL
cd "$HOME"; [ -d dwl ] || git clone https://codeberg.org/dwl/dwl.git; cd dwl
[ "$(stat -c %U .)" != "$(id -un)" ] && sudo chown -R "$(id -un):$(id -gn)" .
[ -f protocols/dwl-ipc-unstable-v2.xml ] || [ -f protocols/dwl-ipc-unstable-v1.xml ] && DWLB_IPC=1 || DWLB_IPC=0
[ "$DWLB_IPC" -eq 1 ] && info "Soporte IPC dwlb disponible."
if [ -f config.h ] && { grep -q 'static const char \*tags\[\]' config.h || ! grep -q TAGCOUNT config.h; }; then
  mv config.h "config.h.old-$(date +%Y%m%d%H%M%S)"
fi
if [ ! -f config.h ]; then
  cat > config.h <<CFG
#define COLOR(hex){((hex>>24)&0xFF)/255.0f,((hex>>16)&0xFF)/255.0f,((hex>>8)&0xFF)/255.0f,(hex&0xFF)/255.0f}
static const int sloppyfocus=1,bypass_surface_visibility=0;
static const unsigned int borderpx=2,snap=32;
static const float rootcolor[]=COLOR(0x1e1e2eff),bordercolor[]=COLOR(0x313244ff),focuscolor[]=COLOR(0x89b4faff),urgentcolor[]=COLOR(0xf38ba8ff),fullscreen_bg[]={0,0,0,1};
#define TAGCOUNT (9)
static int log_level=WLR_ERROR;
static const Rule rules[]={{"firefox",NULL,1<<0,0,-1}};
static const Layout layouts[]={{"[]=",tile},{"><>",NULL},{"[M]",monocle}};
static const MonitorRule monrules[]={{NULL,0.55f,1,1,&layouts[0],WL_OUTPUT_TRANSFORM_NORMAL,-1,-1}};
static const struct xkb_rule_names xkb_rules={.layout="$KB"};
static const int repeat_rate=25,repeat_delay=600;
static const int tap_to_click=1,tap_and_drag=1,drag_lock=1,natural_scrolling=0,disable_while_typing=1,left_handed=0,middle_button_emulation=0;
static const enum libinput_config_scroll_method scroll_method=LIBINPUT_CONFIG_SCROLL_2FG;
static const enum libinput_config_click_method click_method=LIBINPUT_CONFIG_CLICK_METHOD_BUTTON_AREAS;
static const uint32_t send_events_mode=LIBINPUT_CONFIG_SEND_EVENTS_ENABLED;
static const enum libinput_config_accel_profile accel_profile=LIBINPUT_CONFIG_ACCEL_PROFILE_ADAPTIVE;
static const double accel_speed=0.0;
static const enum libinput_config_tap_button_map button_map=LIBINPUT_CONFIG_TAP_MAP_LRM;
#define MODKEY WLR_MODIFIER_LOGO
#define TAGKEYS(K,S,T){MODKEY,K,view,{.ui=1<<T}},{MODKEY|WLR_MODIFIER_SHIFT,S,tag,{.ui=1<<T}}
static const char *term[]={"foot",NULL},*br[]={"firefox",NULL},*dm[]={"sh","-c","dwlb -toggle-visibility all; wmenu-run -f 'monospace $WMENU_FONT_SIZE' -N 1e1e2e -n cdd6f4 -S 89b4fa -s ffffff; dwlb -toggle-visibility all",NULL},*uv[]={"wpctl","set-volume","@DEFAULT_AUDIO_SINK@","3%+","-l","1.0",NULL},*dv[]={"wpctl","set-volume","@DEFAULT_AUDIO_SINK@","3%-",NULL},*mv[]={"wpctl","set-mute","@DEFAULT_AUDIO_SINK@","toggle",NULL},*bu[]={"brightnessctl","set","+5%",NULL},*bd[]={"brightnessctl","set","5%-",NULL},*ss[]={"sh","-c","grim ~/Pictures/\$(date +%Y%m%d_%H%M%S).png",NULL},*bt[]={"dwlb","-toggle-visibility","all",NULL};
static const Key keys[]={
{MODKEY,XKB_KEY_Return,spawn,{.v=term}},{MODKEY,XKB_KEY_d,spawn,{.v=dm}},{MODKEY,XKB_KEY_b,spawn,{.v=br}},{MODKEY,XKB_KEY_q,killclient,{0}},{MODKEY,XKB_KEY_j,focusstack,{.i=+1}},{MODKEY,XKB_KEY_k,focusstack,{.i=-1}},{MODKEY,XKB_KEY_h,setmfact,{.f=-0.05f}},{MODKEY,XKB_KEY_l,setmfact,{.f=+0.05f}},{MODKEY,XKB_KEY_w,spawn,{.v=bt}},{MODKEY,XKB_KEY_f,setlayout,{.v=&layouts[2]}},{MODKEY,XKB_KEY_space,setlayout,{0}},
TAGKEYS(XKB_KEY_1,XKB_KEY_exclam,0),TAGKEYS(XKB_KEY_2,XKB_KEY_quotedbl,1),TAGKEYS(XKB_KEY_3,XKB_KEY_numbersign,2),TAGKEYS(XKB_KEY_4,XKB_KEY_dollar,3),TAGKEYS(XKB_KEY_5,XKB_KEY_percent,4),TAGKEYS(XKB_KEY_6,XKB_KEY_ampersand,5),TAGKEYS(XKB_KEY_7,XKB_KEY_slash,6),TAGKEYS(XKB_KEY_8,XKB_KEY_parenleft,7),TAGKEYS(XKB_KEY_9,XKB_KEY_parenright,8),{MODKEY,XKB_KEY_Tab,view,{0}},{MODKEY,XKB_KEY_0,view,{.ui=~0}},
{0,XKB_KEY_XF86AudioRaiseVolume,spawn,{.v=uv}},{0,XKB_KEY_XF86AudioLowerVolume,spawn,{.v=dv}},{0,XKB_KEY_XF86AudioMute,spawn,{.v=mv}},{0,XKB_KEY_XF86MonBrightnessUp,spawn,{.v=bu}},{0,XKB_KEY_XF86MonBrightnessDown,spawn,{.v=bd}},{0,XKB_KEY_Print,spawn,{.v=ss}},{MODKEY|WLR_MODIFIER_SHIFT,XKB_KEY_E,quit,{0}}};
static const Button buttons[]={{MODKEY,BTN_LEFT,moveresize,{.ui=CurMove}},{MODKEY,BTN_MIDDLE,togglefloating,{0}},{MODKEY,BTN_RIGHT,moveresize,{.ui=CurResize}}};
static const Axis axes[]={{MODKEY,AxisUp,spawn,{.v=uv}},{MODKEY,AxisDown,spawn,{.v=dv}}};
CFG
fi
info "Compilando dwl..."; make clean 2>/dev/null || true; make || err "Error compilando dwl."; sudo make install

compilar_dwlb; configurar_dwlb
[ "$DWLB_IPC" -eq 1 ] && BM="-ipc" || BM="-no-ipc"

# RUNNER BARRA
sudo tee /usr/local/bin/dwl-status-runner >/dev/null <<'RUN'
#!/bin/sh
exec 3<&0; H=""; PB=""
clean(){ for p in $H; do kill "$p" 2>/dev/null; done; wait 2>/dev/null; }
trap clean EXIT
if [ -n "$DWL_WALLPAPER" ] && [ -f "$DWL_WALLPAPER" ] && command -v swaybg >/dev/null; then
  swaybg -i "$DWL_WALLPAPER" -m fill < /dev/null >/dev/null 2>&1 & H="$H $!"
fi
case "$DWL_BAR_KIND" in
 dwlb)
  if [ "$DWL_BAR_MODE" = "-ipc" ]; then cat <&3 >/dev/null & H="$H $!"; dwlb -ipc < /dev/null &
                               else dwlb -no-ipc <&3 & fi
  PB=$!; H="$H $PB"; sleep 1
  (dwlb-status | dwlb -status-stdin all) < /dev/null >/dev/null 2>&1 & H="$H $!" ;;
 *) cat <&3 >/dev/null & PB=$!; H="$H $PB" ;;
esac
wait "$PB"; clean
RUN
sudo chmod +x /usr/local/bin/dwl-status-runner

# WALLPAPER
mkdir -p "$(dirname "$WALLPAPER_PATH")"
if [ ! -f "$WALLPAPER_PATH" ]; then
  T="${WALLPAPER_PATH}.tmp"
  curl -fsSL --max-time 25 -A Mozilla/5.0 -o "$T" https://wallpapercave.com/download/empty-error-wallpapers-wp8330753 && file "$T" | grep -qi image && mv "$T" "$WALLPAPER_PATH" || { rm -f "$T"; warn "No se descargo wallpaper."; }
fi

# SESION DWL
sudo tee /usr/local/bin/dwl-session >/dev/null <<EOF
#!/bin/sh
export XDG_SESSION_TYPE=wayland XDG_CURRENT_DESKTOP=dwl MOZ_ENABLE_WAYLAND=1 QT_QPA_PLATFORM=wayland GDK_BACKEND=wayland,x11
export DWL_BAR_KIND="dwlb" DWL_BAR_MODE="$BM" DWL_WALLPAPER="$WALLPAPER_PATH"
SU=\$(id -u)
if [ ! -d "\$XDG_RUNTIME_DIR" ] || [ "\$(stat -c %u "\$XDG_RUNTIME_DIR" 2>/dev/null)" != "\$SU" ]; then
  R="/run/user/\$SU"
  if [ ! -d "\$R" ] || [ "\$(stat -c %u "\$R" 2>/dev/null)" != "\$SU" ]; then R="\$HOME/.xdg-runtime"; mkdir -p "\$R"; chmod 700 "\$R"; fi
  export XDG_RUNTIME_DIR="\$R"
fi
P=""
ud(){ n="\$1";shift; pgrep -u "\$SU" -x "\$n" >/dev/null && return 0; command -v "\$n" >/dev/null && { "\$@" >/dev/null 2>&1 & P="\$P \$!"; }; }
clean(){ for p in \$P; do kill "$p" 2>/dev/null; done; wait 2>/dev/null; }
trap clean EXIT
ud pipewire pipewire; ud wireplumber wireplumber; command -v pipewire-pulse >/dev/null && ud pipewire-pulse pipewire-pulse
IN=\$(date +%s)
dwl -s /usr/local/bin/dwl-status-runner & DP=\$!; wait "\$DP"; ST=\$?
if [ "\$ST" -ne 0 ] && [ -z "\$WLR_RENDERER" ] && [ \$((\$(date +%s) - IN)) -lt 5 ]; then
  echo "Reintento con pixman...">&2; export WLR_RENDERER=pixman WLR_NO_HARDWARE_CURSORS=1 LIBGL_ALWAYS_SOFTWARE=1
  dwl -s /usr/local/bin/dwl-status-runner & DP=\$!; wait "\$DP"; ST=\$?
fi
clean; exit "\$ST"
EOF
sudo chmod +x /usr/local/bin/dwl-session
echo "$GPU_VENDORS" | grep -q nvidia && sudo sed -i 's|^IN=|export WLR_NO_HARDWARE_CURSORS=1\nIN=|' /usr/local/bin/dwl-session
[ "$GPU_HIBRIDA" -eq 1 ] && [ -n "$GPU_CARDS" ] && sudo sed -i "s|^IN=|# export WLR_DRM_DEVICES=$GPU_CARDS\nIN=|" /usr/local/bin/dwl-session

# UTILIDADES
sudo tee /usr/local/bin/dwl-rebuild >/dev/null <<'RB'; sudo chmod +x /usr/local/bin/dwl-rebuild
#!/bin/sh;set -e;cd "$HOME/dwl";make clean;make;sudo make install;echo "✅ Listo, reinicia sesion."
RB
sudo tee /usr/local/bin/dwlb-rebuild >/dev/null <<'RB'; sudo chmod +x /usr/local/bin/dwlb-rebuild
#!/bin/sh;set -e;cd "$HOME/dwlb";git pull --ff-only;make clean;make;sudo make install;echo "✅ Listo, reinicia sesion."
RB
sudo mkdir -p /usr/share/wayland-sessions
sudo tee /usr/share/wayland-sessions/dwl.desktop >/dev/null <<DSK
[Desktop Entry]
Name=dwl
Exec=/usr/local/bin/dwl-session
Type=Application
DesktopNames=dwl
DSK
mkdir -p "$HOME/.config/environment.d"
cat > "$HOME/.config/environment.d/dwl.conf" <<ENV
MOZ_ENABLE_WAYLAND=1
QT_QPA_PLATFORM=wayland
GDK_BACKEND=wayland,x11
XDG_CURRENT_DESKTOP=dwl
ENV
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
# CONFIGURACION GREETD: NUNCA SE ARRANCA DURANTE INSTALACION
# ----------------------------------------------------------------
info "Configurando greetd..."
if PKGHAS lightdm || PKGHAS lightdm-gtk3-greeter || PKGHAS lightdm-gtk-greeter; then
  info "Quitando lightdm para evitar conflictos..."
  svc_disable lightdm; PKGREM lightdm lightdm-gtk3-greeter lightdm-gtk-greeter 2>/dev/null || true
fi

# Wrapper que espera a la GPU (funciona igual en Arch y Void)
sudo tee /usr/local/bin/greetd-tuigreet-wrapper >/dev/null <<'WRAP'
#!/bin/sh
# Esperar hasta que la GPU y dispositivos DRM esten listos antes de mostrar tuigreet
# Funciona tanto en systemd (Arch) como en runit (Void)
for i in $(seq 1 30); do
  if ls /dev/dri/card* >/dev/null 2>&1; then
    sleep 2
    exec tuigreet --cmd /usr/local/bin/dwl-session
  fi
  sleep 0.5
done
# Si pasaron 15 segundos y aun no hay GPU, intentar de todas formas
exec tuigreet --cmd /usr/local/bin/dwl-session
WRAP
sudo chmod +x /usr/local/bin/greetd-tuigreet-wrapper

if [ "$FAMILIA" = "arch" ]; then
  id -u "$GREETER_USR" >/dev/null 2>&1 || sudo useradd -r -s /sbin/nologin -d /var/lib/greetd "$GREETER_USR"
  sudo usermod -aG tty,video,input "$GREETER_USR"
  sudo mkdir -p /var/lib/greetd; sudo chown "$GREETER_USR:$GREETER_USR" /var/lib/greetd 2>/dev/null; sudo chmod 700 /var/lib/greetd
  sudo mkdir -p /etc/greetd
  sudo tee /etc/greetd/config.toml >/dev/null <<TOML
[terminal]
vt = $GREETD_VT
[default_session]
command = "/usr/local/bin/greetd-tuigreet-wrapper"
user = "$GREETER_USR"
TOML
  # Drop-in systemd
  sudo mkdir -p /etc/systemd/system/greetd.service.d
  sudo tee /etc/systemd/system/greetd.service.d/10-wait-ready.conf >/dev/null <<INI
[Unit]
After=systemd-logind.service systemd-user-sessions.service systemd-udev-settle.service plymouth-quit-wait.service
Wants=systemd-logind.service
ExecStartPre=/bin/sleep 2
Conflicts=getty@tty1.service getty@tty${GREETD_VT}.service
INI
  disable_getty_vt "$GREETD_VT"
  sudo ln -sf /usr/lib/systemd/system/greetd.service /etc/systemd/system/autovt@tty1.service
  sudo systemctl stop greetd.service 2>/dev/null || true
  svc_reload
  sudo systemctl disable greetd.service 2>/dev/null; sudo systemctl enable greetd.service >/dev/null
  info "✅ greetd configurado y listo para arrancar DESPUES de reboot."
else
  # Void / runit
  disable_getty_vt "$GREETD_VT"
  # Asegurarse que el usuario greeter exista en Void
  id -u "$GREETER_USR" >/dev/null 2>&1 || sudo useradd -r -s /sbin/nologin -d /var/lib/greetd "$GREETER_USR"
  sudo usermod -aG tty,video,input "$GREETER_USR"
  sudo mkdir -p /var/lib/greetd; sudo chown "$GREETER_USR:$GREETER_USR" /var/lib/greetd 2>/dev/null; sudo chmod 700 /var/lib/greetd
  # Modificar el run script de greetd para que arranque DESPUES de seatd
  # Añadir una dependencia: greetd necesita que seatd este corriendo
  if [ -f /etc/sv/greetd/run ]; then
    # Agregar espera de seatd al principio del run script
    if ! grep -q "seatd" /etc/sv/greetd/run; then
      sudo sed -i '2i # Esperar a que seatd este corriendo\nwhile ! sv status seatd | grep -q "^run: "; do sleep 0.5; done\nsleep 2' /etc/sv/greetd/run
    fi
  fi
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
    P=/etc/pam.d/greetd
    [ -f "$P" ] && ! grep -q pam_turnstile.so "$P" && echo -e "\nsession optional pam_turnstile.so" | sudo tee -a "$P" >/dev/null
  fi
  svc_enable greetd
  info "✅ greetd configurado en Void, arrancara despues de seatd en el reboot."
fi

echo
header "=========================================="
header " ✅ install-dwl $VERSION INSTALADO CORRECTAMENTE"
header "=========================================="
echo
echo " 📦 Distribucion:  $DISTRO"
echo " 🖋️  Tamaños:       wmenu=mono:$WMENU_FONT_SIZE  /  dwlb=mono:$DWLB_FONT_SIZE"
echo " 🔐 Login:         greetd+tuigreet con espera de GPU"
echo " ⚠️  NINGUN servicio se arranco durante la instalacion, no hay interrupciones."
echo
warn"----------------------------------------"
warn" 🚨 PROXIMO PASO:  ejecuta  sudo reboot"
warn"----------------------------------------"
warn" Los grupos ($SEAT_GRP, video) se aplican al reiniciar."
warn" En el arranque greetd esperara 2 segundos hasta que seatd y la GPU"
warn" esten 100% listos antes de mostrar tuigreet, sin inicios prematuros."
echo
info"Atajos: Super+Enter=foot | Super+d=wmenu | Super+q=cerrar | Super+w=toggle barra"

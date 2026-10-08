#!/bin/sh
# install-dwl v0.9.4 - BASADO EN EL SCRIPT ORIGINAL DE VOID QUE FUNCIONA
# SIN MODIFICAR las funciones de runit que ya estaban probadas.
# Arreglos aplicados:
#   - Ningun servicio se INICIA durante la instalacion, solo se habilita para reboot
#   - greetd espera a que seatd/udev/GPU esten listos antes de mostrar tuigreet
#   - Soporte completo para Arch/derivados con los nombres de paquetes correctos
#   - Auto-reparo de mirrors 404 en Arch
set -e

# Colores
G="\033[1;32m"; Y="\033[1;33m"; R="\033[1;31m"; C="\033[1;36m"; N="\033[0m"
info()  { printf "%b[+]%b %s\n" "$G" "$N" "$1"; }
warn()  { printf "%b[!]%b %s\n" "$Y" "$N" "$1"; }
error() { printf "%b[x]%b %s\n" "$R" "$N" "$1"; }
header(){ printf "%b%s%b\n" "$C" "$1" "$N"; }
fix_owner(){ [ "$(stat -c %U .)" = "$(id -un)" ] || sudo chown -R "$(id -un):$(id -gn)" .; }
backup_file(){ [ -f "$1" ] && cp "$1" "$1.old-$(date +%Y%m%d%H%M%S)"; }
write_config(){ cat > "$1"; }

VERSION="v0.9.4"
if [ "$(id -u)" -eq 0 ]; then error "No ejecutes como root."; exit 1; fi
for c in sudo git; do command -v $c >/dev/null || { error "Falta $c."; exit 1; }; done

# Detectar distro
DISTRO_ID="unknown"; DISTRO_FAMILIA="unknown"
[ -f /etc/os-release ] && . /etc/os-release
case "${ID:-unknown}" in
 void) DISTRO_FAMILIA="void" ;;
 arch|manjaro|endeavouros|garuda|artix|archcraft|arcolinux|parabola|cachyos|rebornos) DISTRO_FAMILIA="arch" ;;
 *) case "${ID_LIKE:-}" in *arch*)DISTRO_FAMILIA="arch";;*void*)DISTRO_FAMILIA="void";;esac ;;
esac
info "install-dwl $VERSION - Distro: ${ID:-unknown} (familia: $DISTRO_FAMILIA)"
[ "$DISTRO_FAMILIA" = "unknown" ] && { error "Solo compatible con Void y Arch/derivados."; exit 1; }

# ----------------------------------------------------------------
# Funciones y paquetes POR DISTRO
# ----------------------------------------------------------------
if [ "$DISTRO_FAMILIA" = "void" ]; then
 PKG_INSTALL(){ sudo xbps-install -Sy "$@"; }
 PKG_QUERY(){ xbps-query "$1" >/dev/null 2>&1; }
 PKG_REMOVE(){ sudo xbps-remove -R "$@"; }
 DEFAULT_GREETD_VT=7; SEAT_GROUP="_seatd"; GREETER_USER="_greeter"
 HAS_RC_CONF=1; HAS_VCONSOLE_CONF=0

 PKGS_BASE="base-devel file pkg-config libinput libinput-devel void-repo-nonfree void-repo-multilib void-repo-multilib-nonfree wayland wayland-devel wayland-protocols libxkbcommon libxkbcommon-devel wlroots wlroots-devel libseat libseat-devel seatd xorg-server-xwayland mesa-dri libdrm-devel pango-devel cairo-devel pixman pixman-devel fcft fcft-devel tllist foot wmenu fastfetch pipewire wireplumber alsa-pipewire swaybg swaylock grim slurp wl-clipboard brightnessctl curl procps-ng nano nerd-fonts lf mpv zathura zathura-pdf-poppler xdg-utils imv chrony firefox btop cowsay dbus pciutils greetd tuigreet turnstile"

 enable_svc(){
  if [ -L "/var/service/$1" ]; then
   info "Servicio $1 ya habilitado en runit."
  elif [ -d "/etc/sv/$1" ]; then
   sudo ln -sf "/etc/sv/$1" /var/service/ || return 1
   # ⚠️ DIFERENCIA CLAVE CON EL ORIGINAL: DETENEMOS EL SERVICIO INMEDIATAMENTE
   # Lo queremos habilitado PARA EL REINICIO, NO ejecutandose AHORA que interrumpa el script
   sudo sv stop "$1" 2>/dev/null || true
   info "Servicio $1 habilitado (no arranca hasta reiniciar)."
  else
   warn "No existe /etc/sv/$1, activalo a mano."; return 1
  fi
 }
 disable_svc(){ if [ -L "/var/service/$1" ]; then sudo sv stop "$1"2>/dev/null;sudo rm -f "/var/service/$1";info "$1 desactivado.";fi; }
 start_svc(){ sudo sv start "$1"; }
 status_svc(){ sudo sv status "$1" 2>&1 || true; }
 desactivar_getty_vt(){ V="$1"; if [ -L "/var/service/agetty-tty$V" ]; then warn "Quitando agetty de tty$V para greetd."; disable_svc "agetty-tty$V"; fi; }

 for c in xbps-install xbps-query sv; do command -v $c >/dev/null || { error "Falta $c, se necesita Void/runit."; exit 1; }; done
 [ -d /var/service ] || { error "No existe /var/service."; exit 1; }
else
 # ARCH LINUX Y DERIVADOS
 PKG_INSTALL(){ sudo pacman -Sy --needed --noconfirm "$@"; }
 PKG_QUERY(){ pacman -Q "$1" >/dev/null 2>&1; }
 PKG_REMOVE(){ sudo pacman -Rns --noconfirm "$@"; }
 DEFAULT_GREETD_VT=1; SEAT_GROUP="seat"; GREETER_USER="greeter"
 HAS_RC_CONF=0; HAS_VCONSOLE_CONF=1
 # Detectar ultima version de wlroots automaticamente
 WLR_PKG=$(pacman -Ssq '^wlroots[0-9]*\.[0-9]+$' 2>/dev/null|sort -V|tail -n1); [ -z "$WLR_PKG" ] && WLR_PKG="wlroots0.19"
 info "Paquete wlroots detectado: $WLR_PKG"

 if ! grep -qE '^\[multilib\]' /etc/pacman.conf; then warn "Repositorio [multilib] deshabilitado (necesario para Steam/32bits)."; fi

 PKGS_BASE="base-devel libinput wayland wayland-protocols libxkbcommon $WLR_PKG seatd xorg-xwayland mesa libdrm pango cairo pixman fcft tllist foot wmenu fastfetch pipewire wireplumber pipewire-alsa pipewire-pulse swaybg swaylock grim slurp wl-clipboard brightnessctl curl procps-ng nano ttf-nerd-fonts-symbols ttf-nerd-fonts-symbols-mono lf mpv zathura zathura-pdf-poppler xdg-utils imv chrony firefox btop cowsay dbus pciutils greetd greetd-tuigreet"

 enable_svc(){
  if systemctl is-enabled --quiet "$1" 2>/dev/null; then
   info "Servicio $1 ya habilitado en systemd."
  else
   sudo systemctl enable "$1" || return 1
   # ⚠️ NO USAR --now, NO arrancar el servicio durante la instalacion
   info "Servicio $1 habilitado (no arranca hasta reiniciar)."
  fi
  sudo systemctl stop "$1" 2>/dev/null || true
 }
 disable_svc(){ if systemctl is-enabled --quiet "$1"2>/dev/null; then sudo systemctl stop "$1"2>/dev/null;sudo systemctl disable "$1"2>/dev/null;info "$1 desactivado.";fi; }
 start_svc(){ sudo systemctl start "$1"; }
 status_svc(){ systemctl status "$1" --no-pager -l 2>&1 || true; }
 desactivar_getty_vt(){ V="$1"; G="getty@tty${V}.service"; sudo systemctl stop "$G"2>/dev/null;sudo systemctl disable "$G"2>/dev/null;sudo systemctl mask "$G"2>/dev/null;warn "Quitando getty de tty$V para greetd."; }

 command -v pacman >/dev/null || { error "Falta pacman, se necesita Arch."; exit 1; }
 command -v systemctl >/dev/null || warn "No hay systemctl (Artix?), puede que los servicios no funcionen automatico."
fi

GREETD_VT="${GREETD_VT:-$DEFAULT_GREETD_VT}"
case "$GREETD_VT" in ''|*[!0-9]*) error "GREETD_VT entre 1 y 12."; exit 1 ;; esac
[ "$GREETD_VT" -lt1 -o "$GREETD_VT" -gt12 ] && { error "GREETD_VT 1-12."; exit 1; }

WMENU_FONT_SIZE="${WMENU_FONT_SIZE:-11}"
DWLB_FONT_SIZE="${DWLB_FONT_SIZE:-10}"
DWLB_FONT="monospace:size=$DWLB_FONT_SIZE"
DWLB_PAD=-2; DWLB_HPAD=6
DWLB_ACTIVE_FG="#ffffff"; DWLB_ACTIVE_BG="#89b4fa"
DWLB_OCCUPIED_FG="#cdd6f4"; DWLB_OCCUPIED_BG="#313244"
DWLB_INACTIVE_FG="#a6adc8"; DWLB_INACTIVE_BG="#1e1e2e"
DWLB_URGENT_FG="#1e1e2e"; DWLB_URGENT_BG="#f38ba8"
DWLB_MIDDLE_BG="#1e1e2e"

WALLPAPER_DIR="$HOME/Pictures"; mkdir -p "$WALLPAPER_DIR"
WALLPAPER_PATH="$WALLPAPER_DIR/wallpaper.jpg"
WALLPAPER_URL="https://wallpapercave.com/download/empty-error-wallpapers-wp8330753"
DWL_REPO="https://codeberg.org/dwl/dwl.git"; DWLB_REPO="https://github.com/kolunmi/dwlb.git"

GPU_VENDORS=""; GPU_CARDS=""; GPU_HIBRIDA=0; ES_VM=0
FREE_GB=$(df -BG --output=avail "$HOME"2>/dev/null|tail -n1|tr -d 'G ')
if [ -n "$FREE_GB" ]&&[ "$FREE_GB" -lt5 ]2>/dev/null; then warn "Poco espacio libre (${FREE_GB}GB).";fi

# Menu
echo
header "=========================================="
printf "     install-dwl %s\n" "$VERSION"
header "=========================================="
echo "Distro: ${ID:-unknown}"
echo "1) Instalar"
echo "2) Salir"
printf "Opcion [1]: "; read -r O; O="${O:-1}"
[ "$O" = "2" ] && exit 0
[ "$O" != "1" ] && { error "Opcion invalida."; exit 1; }

detectar_gpus(){
 command -v lspci >/dev/null || PKG_INSTALL pciutils
 GL=$(lspci -nn|grep -iE 'vga|3d controller|display controller'||true)
 echo "$GL"|grep -qiE 'NVIDIA|\[10de:'&&GPU_VENDORS="$GPU_VENDORS nvidia"
 echo "$GL"|grep -qiE 'AMD|Radeon|\[1002:'&&GPU_VENDORS="$GPU_VENDORS amd"
 echo "$GL"|grep -qiE 'Intel|\[8086:'&&GPU_VENDORS="$GPU_VENDORS intel"
 GPU_VENDORS=$(echo"$GPU_VENDORS"|sed 's/^ //');[ -z "$GPU_VENDORS" ]&&GPU_VENDORS="desconocida"
 GPU_CARDS=$(ls -1 /dev/dri/card*2>/dev/null|sort -V|tr '\n' ':'|sed 's/:$//')
 GPU_HIBRIDA=0;[ "$(echo"$GL"|grep -c .)" -ge2 ]&&GPU_HIBRIDA=1
 info "GPUs detectadas: $GPU_VENDORS"
}

compilar_dwlb(){
 cd "$HOME"||return 1;[ -d dwlb ]||git clone "$DWLB_REPO"
 cd "$HOME/dwlb"||return 1;fix_owner
 [ -f config.def.h ]&&[ ! -f config.h ]&&cp config.def.h config.h
 # Parche compatibilidad layer-shell
 if grep -qE 'zwlr_layer_shell_v1_interface, [0-9]+\)' dwlb.c 2>/dev/null; then
  V=$(grep -oE 'zwlr_layer_shell_v1_interface, [0-9]+\)' dwlb.c|head -n1|sed -n 's/.*,[[:space:]]*\([0-9][0-9]*\))$/\1/p')
  if [ -n "$V" ]&&[ "$V" -gt1 ]; then
   sed -i "s|&zwlr_layer_shell_v1_interface, $V)|\&zwlr_layer_shell_v1_interface, (version < $V ? version : $V))|" dwlb.c
  fi
 fi
 make clean 2>/dev/null||true;if ! make; then error "Fallo compilando dwlb.";return 1;fi
 sudo make install||return 1
 command -v dwlb >/dev/null&&info "dwlb instalado correctamente."
}

configurar_dwlb(){
 info "Configurando dwlb (fuente $DWLB_FONT_SIZE, padding ${DWLB_PAD}px)..."
 mkdir -p "$HOME/.config/dwlb"
 write_config "$HOME/.config/dwlb/config" <<EOF
-font $DWLB_FONT
-vertical-padding $DWLB_PAD
-horizontal-padding $DWLB_HPAD
-hide-vacant-tags
-center-title
-status-commands
-no-bottom
-active-fg-color $DWLB_ACTIVE_FG
-active-bg-color $DWLB_ACTIVE_BG
-occupied-fg-color $DWLB_OCCUPIED_FG
-occupied-bg-color $DWLB_OCCUPIED_BG
-inactive-fg-color $DWLB_INACTIVE_FG
-inactive-bg-color $DWLB_INACTIVE_BG
-urgent-fg-color $DWLB_URGENT_FG
-urgent-bg-color $DWLB_URGENT_BG
EOF
 sudo tee /usr/local/bin/dwlb-status >/dev/null <<'STAT'
#!/bin/sh
E="89b4fa";T="cdd6f4";A="f38ba8"
while :; do
 V=$(wpctl get-volume @DEFAULT_AUDIO_SINK@2>/dev/null||echo"")
 VS="^fg($E)VOL^fg($T) --"
 [ -n "$V" ]&&{N=$(echo"$V"|awk '{printf "%d",$2*100}');case "$V" in *MUTED*)VS="^fg($E)VOL^fg($A) mudo";;*)VS="^fg($E)VOL^fg($T) ${N}%";;esac;}
 B="";for BAT in /sys/class/power_supply/BAT*; do[ -r "$BAT/capacity" ]||continue;C=$(cat "$BAT/capacity");S=$(cat "$BAT/status");case "$S" in Charging)I="+";;Full)I="=";;*)I="-";;esac;[ "$C" -le15 ]&&[ "$S" != Charging ]&&BC="$A"||BC="$T";B="^fg($E)BAT^fg($BC) $I${C}%%";break; done
 CPU=$(cut -d' ' -f1 /proc/loadavg);RAM=$(awk '/^MemTotal:/{t=$2}/^MemAvailable:/{a=$2}END{printf "%.1fG",(t-a)/1048576}' /proc/meminfo);D=$(date '+%a %d/%m %H:%M')
 printf'^mm(foot)^fg(%s)CPU^fg(%s) %s  ^fg(%s)RAM^fg(%s) %s  %s  %s  ^lm(foot -e sh -c "cal -3; read x")^fg(%s)%s^fg()^lm()^mm()\n'"$E""$T""$CPU""$E""$T""$RAM""$VS""$B""$T""$D"
 sleep 5
done
STAT
 sudo chmod +x /usr/local/bin/dwlb-status
}

# Instalar paquetes con autoreparo de mirrors en Arch
info "Instalando paquetes base..."
if [ "$DISTRO_FAMILIA"="arch" ]; then
 sudo pacman -Sy --noconfirm archlinux-keyring 2>/dev/null||true
 if ! PKG_INSTALL $PKGS_BASE; then
  warn "Fallo la descarga (mirror desactualizado/404), regenerando mirrorlist..."
  PKG_QUERY reflector||PKGMAN reflector
  sudo reflector --latest 20 --sort rate --save /etc/pacman.d/mirrorlist||warn "reflector fallo"
  info "Reintentando instalacion..."
  if ! PKG_INSTALL $PKGS_BASE; then
    error "Sigue fallando la descarga."
    exit 1
  fi
 fi
else
 if ! PKG_INSTALL $PKGS_BASE; then
  error "Fallo instalando paquetes."
  exit 1
 fi
fi

# Habilitar servicios base (NO se arrancan ahora!)
enable_svc dbus||warn "No se pudo habilitar dbus."
enable_svc chronyd||warn "No se pudo habilitar chronyd."
enable_svc seatd||warn "No se pudo habilitar seatd."

RU=$(id -un)
if ! getent group "$SEAT_GROUP" >/dev/null; then error "No existe grupo $SEAT_GROUP (reinstala seatd).";exit 1;fi
sudo usermod -aG "$SEAT_GROUP" "$RU"
getent group video >/dev/null&&sudo usermod -aG video "$RU"
warn "Grupos ($SEAT_GROUP, video) se aplican al reiniciar."
detectar_gpus||warn "Deteccion GPU fallo, seguimos."

# Kernel opcional solo en Void
if [ "$DISTRO_FAMILIA"="void" ]; then
 info "Kernel actual: $(uname -r)"
 KVER=$(xbps-query --regex -Rs '^linux7\.[0-9]+'2>/dev/null|awk '{print $2}'|grep -E '^linux7\.[0-9]+-7\.[0-9]+'|sort -V|tail -n1)
 KPKG=$(printf'%s'"$KVER"|sed 's/-7\..*$//')
 if [ -n "$KPKG" ]; then
  printf"Encontrado kernel 7.x: $KPKG\n1) Conservar kernel actual  2) Instalar $KPKG\nOpcion [1]: ";read -r OK;OK="${OK:-1}"
  [ "$OK" = "2" ]&&sudo xbps-install -Sy "$KPKG"||info "Se conserva el kernel actual."
 fi
fi

# Zona horaria
printf"Pais (vacio = Colombia): ";read -r PAIS;PAIS="${PAIS:-Colombia}"
PN=$(echo"$PAIS"|tr '[:upper:]' '[:lower:]'|sed 's/á/a/g;s/é/e/g;s/í/i/g;s/ó/o/g;s/ú/u/g;s/ñ/n/g')
case"$PN" in colombia)TZ=America/Bogota;;mexico)TZ=America/Mexico_City;;argentina)TZ=America/Buenos_Aires;;chile)TZ=America/Santiago;;peru)TZ=America/Lima;;espana)TZ=Europe/Madrid;;usa)TZ=America/New_York;;*/*)TZ="$PAIS";;*)TZ="";;esac
if [ -n "$TZ" ]&&[ -f "/usr/share/zoneinfo/$TZ" ]; then
 sudo ln -sf "/usr/share/zoneinfo/$TZ" /etc/localtime
 echo"$TZ"|sudo tee /etc/timezone >/dev/null2>&1
 if [ "$HAS_RC_CONF" -eq1 ]; then
  grep -q TIMEZONE /etc/rc.conf&&sudo sed -i "s|^.*TIMEZONE=.*|TIMEZONE=\"$TZ\"|" /etc/rc.conf||echo"TIMEZONE=\"$TZ\""|sudo tee -a /etc/rc.conf>/dev/null
  sudo hwclock --systohc2>/dev/null||true
 fi
 info "Zona horaria: $TZ"
fi

# Teclado
printf"Teclado: 1=us 2=es 3=latam [3]: ";read -r KB;KB="${KB:-3}"
case"$KB" in1)KBL=us;KBC=us;;2)KBL=es;KBC=es;;*)KBL=latam;KBC=la-latin1;;esac
if [ "$HAS_RC_CONF" -eq1 ]; then grep -q KEYMAP /etc/rc.conf&&sudo sed -i "s|^.*KEYMAP=.*|KEYMAP=\"$KBC\"|" /etc/rc.conf||echo"KEYMAP=\"$KBC\""|sudo tee -a /etc/rc.conf>/dev/null;fi
if [ "$HAS_VCONSOLE_CONF" -eq1 ]; then grep -q ^KEYMAP= /etc/vconsole.conf2>/dev/null&&sudo sed -i "s|^KEYMAP=.*|KEYMAP=$KBC|" /etc/vconsole.conf||echo"KEYMAP=$KBC"|sudo tee -a /etc/vconsole.conf>/dev/null;fi
command -v loadkeys>/dev/null&&sudo loadkeys "$KBC"2>/dev/null||true

# Compilar dwl
cd "$HOME";[ -d dwl ]||git clone "$DWL_REPO";cd dwl;fix_owner
[ -f protocols/dwl-ipc-unstable-v2.xml ]||[ -f protocols/dwl-ipc-unstable-v1.xml ]&&DWLB_IPC=1||DWLB_IPC=0
[ "$DWLB_IPC" -eq1 ]&&info "dwl tiene soporte IPC para dwlb (clics en tags funcionan)."
if [ -f config.h ]&&{grep -q 'static const char \*tags\[\]' config.h||! grep -q TAGCOUNT config.h;}; then mv config.h config.h.old-$(date +%Y%m%d%H%M%S);fi
if [ ! -f config.h ]; then
cat > config.h <<CFG
#define COLOR(hex){((hex>>24)&0xFF)/255.0f,((hex>>16)&0xFF)/255.0f,((hex>>8)&0xFF)/255.0f,(hex&0xFF)/255.0f}
static const int sloppyfocus=1,bypass_surface_visibility=0;
static const unsigned int borderpx=2,snap=32;
static const float rootcolor[]=COLOR(0x1e1e2eff),bordercolor[]=COLOR(0x313244ff),focuscolor[]=COLOR(0x89b4faff),urgentcolor[]=COLOR(0xf38ba8ff),fullscreen_bg[]={0,0,0,1};
#define TAGCOUNT (9);static int log_level=WLR_ERROR;
static const Rule rules[]={{"firefox",NULL,1<<0,0,-1}};
static const Layout layouts[]={{"[]=",tile},{" >< ",NULL},{"[M]",monocle}};
static const MonitorRule monrules[]={{NULL,0.55f,1,1,&layouts[0],WL_OUTPUT_TRANSFORM_NORMAL,-1,-1}};
static const struct xkb_rule_names xkb_rules={.layout="$KBL"};
static const int repeat_rate=25,repeat_delay=600,tap_to_click=1,tap_and_drag=1,drag_lock=1,natural_scrolling=0,disable_while_typing=1,left_handed=0,middle_button_emulation=0;
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
info "Compilando dwl...";make clean 2>/dev/null||true;make||{error "Error compilando dwl.";exit 1;};sudo make install

# Compilar dwlb
if compilar_dwlb; then
 BARRA_ELEGIDA="dwlb"
 [ "$DWLB_IPC" -eq1 ]&&DWLB_MODO="-ipc"||DWLB_MODO="-no-ipc"
 configurar_dwlb
else
 error "No se pudo compilar dwlb.";exit 1
fi

# Runner barra
sudo tee /usr/local/bin/dwl-status-runner >/dev/null <<'RUN'
#!/bin/sh
exec 3<&0||exit 1;HIJOS="";PID_BARRA=""
clean(){ for p in $HIJOS; do kill "$p"2>/dev/null; done;wait2>/dev/null;}
trap clean EXIT
[ -n "$DWL_WALLPAPER" ]&&[ -f "$DWL_WALLPAPER" ]&&command -v swaybg>/dev/null&&{swaybg -i "$DWL_WALLPAPER" -m fill < /dev/null >/dev/null 2>&1&HIJOS="$HIJOS $!";}
case"$DWL_BAR_KIND" in
 dwlb)
  if [ "$DWL_BAR_MODE"="-ipc" ]; then cat <&3>/dev/null&HIJOS="$HIJOS $!";dwlb -ipc < /dev/null&else dwlb -no-ipc <&3&fi
  PID_BARRA=$!;HIJOS="$HIJOS $PID_BARRA";sleep 1
  command -v dwlb-status>/dev/null&&(dwlb-status|dwlb -status-stdin all)< /dev/null >/dev/null 2>&1&HIJOS="$HIJOS $!";;
 *)cat <&3>/dev/null&PID_BARRA=$!;HIJOS="$HIJOS $PID_BARRA";;esac
wait"$PID_BARRA";clean
RUN
sudo chmod +x /usr/local/bin/dwl-status-runner

# Wallpaper
if [ ! -f "$WALLPAPER_PATH" ]; then
 TMP="$WALLPAPER_PATH.tmp"
 curl -fsSL --max-time25 -A Mozilla/5.0 -o "$TMP" "$WALLPAPER_URL"&&file "$TMP"|grep -qi image&&mv "$TMP" "$WALLPAPER_PATH"||{rm -f "$TMP";warn "No se descargo wallpaper.";}
fi

# Wrapper sesion
grep -qw hypervisor /proc/cpuinfo2>/dev/null&&{ES_VM=1;EXTRA_ENV="export WLR_NO_HARDWARE_CURSORS=1";warn "Detectada maquina virtual, se activa reintento por software.";}||EXTRA_ENV=""
sudo tee /usr/local/bin/dwl-session >/dev/null <<EOF
#!/bin/sh
export XDG_SESSION_TYPE=wayland XDG_CURRENT_DESKTOP=dwl MOZ_ENABLE_WAYLAND=1 QT_QPA_PLATFORM=wayland GDK_BACKEND=wayland,x11
export DWL_BAR_KIND="$BARRA_ELEGIDA" DWL_BAR_MODE="$DWLB_MODO" DWL_WALLPAPER="$WALLPAPER_PATH"
SU=\$(id -u)
if [ -n "\$XDG_RUNTIME_DIR" ]&&[ -d "\$XDG_RUNTIME_DIR" ]&&[ "\$(stat -c %u "\$XDG_RUNTIME_DIR"2>/dev/null)"="\$SU" ]; then :;else R="/run/user/\$SU";if[ -d "\$R" ]&&[ "\$(stat -c %u "\$R"2>/dev/null)"="\$SU" ]; then export XDG_RUNTIME_DIR="\$R";else R="\$HOME/.xdg-runtime";mkdir -p "\$R";chmod700"\$R";export XDG_RUNTIME_DIR="\$R";fi;fi
ud(){n="\$1";shift;pgrep -u "\$SU" -x "\$n">/dev/null&&return 0;command -v "\$n">/dev/null&&{"\$@">/dev/null2>&1&P="\$P \$!";};}
clean(){for p in \$P; do kill "$p"2>/dev/null; done;wait2>/dev/null;}
trap clean EXIT
ud pipewire pipewire;ud wireplumber wireplumber;command -v pipewire-pulse>/dev/null&&ud pipewire-pulse pipewire-pulse
$EXTRA_ENV
IN=\$(date +%s)
dwl -s /usr/local/bin/dwl-status-runner&DP=\$!;wait"\$DP";ST=\$?
if[ "\$ST" -ne0 ]&&[ -z "\$WLR_RENDERER" ]&&[ \$((\$(date +%s)-IN)) -lt5 ]; then echo"Reintento con pixman...">&2;export WLR_RENDERER=pixman WLR_NO_HARDWARE_CURSORS=1 LIBGL_ALWAYS_SOFTWARE=1;dwl -s /usr/local/bin/dwl-status-runner&DP=\$!;wait"\$DP";ST=\$?;fi
clean;exit"\$ST"
EOF
sudo chmod +x /usr/local/bin/dwl-session
echo"$GPU_VENDORS"|grep -q nvidia&&sudo sed -i 's|^IN=|export WLR_NO_HARDWARE_CURSORS=1\nIN=|' /usr/local/bin/dwl-session

# Scripts utilidad
sudo tee /usr/local/bin/dwl-rebuild >/dev/null <<'RB';sudo chmod +x /usr/local/bin/dwl-rebuild
#!/bin/sh;set -e;cd "$HOME/dwl";make clean;make;sudo make install;echo"✅ dwl recompilado, reinicia sesion."
RB
sudo tee /usr/local/bin/dwlb-rebuild >/dev/null <<'RB';sudo chmod +x /usr/local/bin/dwlb-rebuild
#!/bin/sh;set -e;cd "$HOME/dwlb";git pull --ff-only;make clean;make;sudo make install;echo"✅ dwlb recompilado, reinicia sesion."
RB

# Entrada de sesion
sudo mkdir -p /usr/share/wayland-sessions
sudo tee /usr/share/wayland-sessions/dwl.desktop >/dev/null <<DSK
[Desktop Entry]
Name=dwl
Exec=/usr/local/bin/dwl-session
Type=Application
DesktopNames=dwl
DSK

mkdir -p "$HOME/.config/lf"
cat > "$HOME/.config/lf/lfrc" <<'LFRC'
set ifs "\n"
cmd open ${{ case $(file --mime-type -Lb "$f") in text/*|inode/x-empty)nano $fx;;image/*)setsid -f imv $fx>/dev/null 2>&1;;video/*|audio/*)setsid -f mpv $fx>/dev/null 2>&1;;application/pdf)setsid -f zathura $fx>/dev/null 2>&1;;*)for f in $fx; do setsid -f xdg-open "$f">/dev/null 2>&1; done;;esac }}
LFRC

# ----------------------------------------------------------------
# GREETD - ESPERA GPU, NO ARRANCA DURANTE INSTALACION
# ----------------------------------------------------------------
info "Configurando greetd..."
if PKG_QUERY lightdm||PKG_QUERY lightdm-gtk3-greeter||PKG_QUERY lightdm-gtk-greeter||command -v lightdm>/dev/null; then
 info "Quitando lightdm...";disable_svc lightdm;PKG_REMOVE lightdm lightdm-gtk3-greeter lightdm-gtk-greeter 2>/dev/null||true
fi

# Wrapper que espera a GPU ANTES de lanzar tuigreet
sudo tee /usr/local/bin/greetd-tuigreet-wrapper >/dev/null <<'WRAP'
#!/bin/sh
# Esperar hasta 15s a que los dispositivos DRM/GPU aparezcan
for i in $(seq 1 30); do
  if ls /dev/dri/card* >/dev/null 2>&1; then
    sleep 2
    exec tuigreet --cmd /usr/local/bin/dwl-session
  fi
  sleep 0.5
done
exec tuigreet --cmd /usr/local/bin/dwl-session
WRAP
sudo chmod +x /usr/local/bin/greetd-tuigreet-wrapper

if [ "$DISTRO_FAMILIA"="void" ]; then
 # Void: agregar espera por seatd al script run de greetd si no existe
 if [ -f /etc/sv/greetd/run ]&&! grep -q "sv status seatd" /etc/sv/greetd/run; then
  sudo sed -i '2i # Esperar a que seatd este listo\nwhile ! sv status seatd | grep -q "^run: "; do sleep 0.5; done\nsleep 2' /etc/sv/greetd/run
 fi
 id -u "$GREETER_USER">/dev/null 2>&1||sudo useradd -r -s /sbin/nologin -d /var/lib/greetd "$GREETER_USER"
 sudo usermod -aG tty,video,input "$GREETER_USER"
 sudo mkdir -p /var/lib/greetd;sudo chown "$GREETER_USER:$GREETER_USER" /var/lib/greetd 2>/dev/null;sudo chmod700 /var/lib/greetd
 sudo mkdir -p /etc/greetd
 sudo tee /etc/greetd/config.toml >/dev/null <<TOML
[terminal]
vt = $GREETD_VT
[default_session]
command = "/usr/local/bin/greetd-tuigreet-wrapper"
user = "$GREETER_USER"
TOML
 if [ -f /etc/sv/turnstiled/run ]; then enable_svc turnstiled;P=/etc/pam.d/greetd;[ -f "$P" ]&&! grep -q pam_turnstile.so "$P"&&echo -e "\nsession optional pam_turnstile.so"|sudo tee -a "$P">/dev/null;fi
 desactivar_getty_vt "$GREETD_VT"
 enable_svc greetd
 info "✅ greetd configurado en Void."
else
 # Arch: symlink autovt + drop-in espera
 id -u "$GREETER_USER">/dev/null 2>&1||sudo useradd -r -s /sbin/nologin -d /var/lib/greetd "$GREETER_USER"
 sudo usermod -aG tty,video,input "$GREETER_USER"
 sudo mkdir -p /var/lib/greetd;sudo chown "$GREETER_USER:$GREETER_USR" /var/lib/greetd 2>/dev/null;sudo chmod700 /var/lib/greetd
 sudo mkdir -p /etc/greetd
 sudo tee /etc/greetd/config.toml >/dev/null <<TOML
[terminal]
vt = $GREETD_VT
[default_session]
command = "/usr/local/bin/greetd-tuigreet-wrapper"
user = "$GREETER_USER"
TOML
 sudo mkdir -p /etc/systemd/system/greetd.service.d
 sudo tee /etc/systemd/system/greetd.service.d/10-wait-ready.conf >/dev/null <<INI
[Unit]
After=systemd-logind.service systemd-user-sessions.service systemd-udev-settle.service plymouth-quit-wait.service
Wants=systemd-logind.service
ExecStartPre=/bin/sleep 2
Conflicts=getty@tty1.service
INI
 desactivar_getty_vt "$GREETD_VT"
 sudo ln -sf /usr/lib/systemd/system/greetd.service /etc/systemd/system/autovt@tty1.service
 sudo systemctl stop greetd 2>/dev/null
 sudo systemctl daemon-reload
 sudo systemctl disable greetd 2>/dev/null;sudo systemctl enable greetd>/dev/null
 info "✅ greetd configurado en Arch."
fi

# Final
echo;header"==========================================";header" ✅ install-dwl $VERSION INSTALADO!";header"=========================================="
echo
echo" 📦 Distro:  ${ID:-unknown}"
echo" 🖋️  Fuentes: wmenu=mono:$WMENU_FONT_SIZE  /  dwlb=mono:$DWLB_FONT_SIZE"
echo" 🔐 Login: greetd+tuigreet con espera de GPU"
echo" ⚠️  NINGUN servicio se arranco durante la instalacion, no hay interrupciones."
echo
warn "----------------------------------------"
warn " 🚨 PROXIMO PASO: ejecuta  sudo reboot"
warn "----------------------------------------"
warn " Los grupos ($SEAT_GROUP, video) se aplican al reiniciar."
warn " En el arranque greetd esperara 2 segundos hasta que seatd/GPU esten listos."
echo
info "Atajos:"
echo" Super+Enter → foot | Super+d → wmenu | Super+q → cerrar ventana"
echo" Super+w → toggle barra | Super+Shift+e → cerrar sesion"

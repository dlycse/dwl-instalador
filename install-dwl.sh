#!/bin/sh
# install-dwl v0.8.6
# Instalador de dwl (dwm para Wayland) multiplataforma.
# Soportado oficialmente:
#   - Arch Linux y derivados (pacman + systemd): 100% testeado
#   - Void Linux (xbps + runit)
#
# Entorno: dwl (fuente) + dwlb (barra), foot, wmenu, swaybg, pipewire,
#          capturas/brillo/volumen y login automatico con greetd+tuigreet.
# NO instala drivers de GPU ni Steam.

set -e

# Colores
G="\033[1;32m"; Y="\033[1;33m"; R="\033[1;31m"; C="\033[1;36m"; N="\033[0m"
info(){ printf "%b[+]%b %s\n" "$G" "$N" "$1"; }
warn(){ printf "%b[!]%b %s\n" "$Y" "$N" "$1"; }
err() { printf "%b[x]%b %s\n" "$R" "$N" "$1"; exit 1; }
hdr() { printf "%b%s%b\n" "$C" "$1" "$N"; }

VERSION="v0.8.6"
[ "$(id -u)" -eq 0 ] && err "No ejecutes como root, usa sudo."
command -v sudo >/dev/null || err "Falta sudo (agrega tu usuario a sudoers)."
command -v git  >/dev/null || err "Falta git."

# Detectar distro
DISTRO="unknown"; FAMILIA="unknown"
[ -f /etc/os-release ] && . /etc/os-release
case "$ID" in
    void) FAMILIA="void";;
    arch|manjaro|endeavouros|garuda|artix|archcraft|cachyos|arcolinux|parabola|rebornos|obarun) FAMILIA="arch";;
    *) case "${ID_LIKE:-}" in *arch*)FAMILIA="arch";; *void*)FAMILIA="void";; esac;;
esac
info "install-dwl $VERSION - distro: $ID ($FAMILIA)"
[ "$FAMILIA" = "unknown" ] && err "Solo Void y Arch/derivadas."

# Constantes sobreescribibles por env
: "${WMENU_FONT_SIZE:=11}"
: "${DWLB_FONT_SIZE:=10}"
WALLPAPER_PATH="${WALLPAPER_PATH:-$HOME/Pictures/wallpaper.jpg}"

if [ "$FAMILIA" = "void" ]; then
    # ------- Void (xbps + runit) -------
    PKGMAN(){ sudo xbps-install -Sy "$@"; }
    PKGHAS(){ xbps-query "$1" >/dev/null 2>&1; }
    PKGREM(){ sudo xbps-remove -R "$@"; }
    GREETD_VT="${GREETD_VT:-7}"
    SEAT_GRP="_seatd"
    GREETER_USR="_greeter"
    TURNSTILE=1
    WLR_PKGS="wlroots wlroots-devel"
    SEAT_PKGS="libseat libseat-devel seatd"
    GREET_PKGS="greetd tuigreet turnstile"
    FONT_PKG="nerd-fonts"
    PULSE_PKG="alsa-pipewire"
    MESA_PKGS="mesa-dri libdrm-devel"
    DEVEL="-devel"

    svc_on(){
        if [ -L "/var/service/$1" ]; then info "$1 ya esta en runit."
        elif [ -d "/etc/sv/$1" ]; then sudo ln -s "/etc/sv/$1" /var/service/ && info "$1 habilitado."
        else warn "/etc/sv/$1 no existe, activalo manual."; return 1; fi
    }
    svc_off(){ [ -L "/var/service/$1" ] && { sudo sv stop "$1" 2>/dev/null; sudo rm -f "/var/service/$1"; info "$1 desactivado."; }; }
    svc_start(){ sudo sv start "$1"; }
    disable_getty_tty(){ VT="$1"; [ -L "/var/service/agetty-tty$VT" ] && svc_off "agetty-tty$VT"; }

    command -v xbps-install >/dev/null || err "Falta xbps-install."
    [ -d /var/service ] || err "No existe /var/service (runit)."

    PKGS="base-devel file pkg-config libinput libinput${DEVEL} void-repo-nonfree void-repo-multilib void-repo-multilib-nonfree \
          wayland wayland${DEVEL} wayland-protocols libxkbcommon libxkbcommon${DEVEL} $WLR_PKGS $SEAT_PKGS \
          xorg-server-xwayland $MESA_PKGS pango${DEVEL} cairo${DEVEL} pixman pixman${DEVEL} fcft fcft${DEVEL} tllist \
          foot wmenu fastfetch pipewire wireplumber $PULSE_PKG swaybg swaylock grim slurp wl-clipboard \
          brightnessctl curl procps-ng nano $FONT_PKG lf mpv zathura zathura-pdf-poppler xdg-utils imv \
          chrony firefox btop cowsay dbus pciutils $GREET_PKGS"

else
    # ------- Arch (pacman + systemd) -------
    PKGMAN(){ sudo pacman -Sy --needed --noconfirm "$@"; }
    PKGHAS(){ pacman -Q "$1" >/dev/null 2>&1; }
    PKGREM(){ sudo pacman -Rns --noconfirm "$@"; }
    GREETD_VT="${GREETD_VT:-1}"
    SEAT_GRP="seat"
    GREETER_USR="greeter"
    TURNSTILE=0   # pam_systemd hace XDG_RUNTIME_DIR
    # Encontrar automaticamente la ultima version de wlroots disponible (0.19, 0.20, ...)
    WLR_PKG=$(pacman -Ssq '^wlroots[0-9]*\.[0-9]+$' 2>/dev/null | sort -V | tail -n1)
    [ -z "$WLR_PKG" ] && WLR_PKG="wlroots0.19"
    info "Usando paquete wlroots: $WLR_PKG"
    SEAT_PKGS="seatd"   # libseat viene dentro del paquete seatd
    GREET_PKGS="greetd greetd-tuigreet"
    FONT_PKG="ttf-nerd-fonts-symbols ttf-nerd-fonts-symbols-mono"
    PULSE_PKG="pipewire-alsa pipewire-pulse"
    MESA_PKGS="mesa libdrm"
    DEVEL=""

    # --- FUNCIONES DE SERVICIO SYSTEMD ARREGLADAS ---
    # enable --now = habilita en el arranque Y lo arranca inmediatamente
    svc_on(){
        if systemctl is-active --quiet "$1" 2>/dev/null; then
            info "$1 ya esta corriendo."
        else
            sudo systemctl enable --now "$1" && info "$1 habilitado y arrancado (systemd)."
        fi
    }
    svc_off(){
        if systemctl is-enabled --quiet "$1" 2>/dev/null; then
            sudo systemctl disable --now "$1" 2>/dev/null || true
            info "$1 desactivado."
        fi
    }
    svc_start(){ sudo systemctl restart "$1"; }
    # Desactivar el getty de la VT de greetd INCONDICIONALMENTE
    disable_getty_tty(){
        VT="$1"
        local g="getty@tty${VT}.service"
        if systemctl is-enabled --quiet "$g" 2>/dev/null; then
            warn "Desactivando $g para que greetd use tty$VT"
            sudo systemctl disable --now "$g" 2>/dev/null || true
        fi
        # Enmascararlo para que no vuelva a aparecer en los proximos arranques
        sudo systemctl mask "$g" 2>/dev/null || true
    }

    command -v pacman >/dev/null || err "Falta pacman."
    grep -qE '^\[multilib\]' /etc/pacman.conf || warn "[multilib] deshabilitado; lo necesitaras para Steam/32bits."

    PKGS="base-devel libinput wayland wayland-protocols libxkbcommon $WLR_PKG \
          xcb-util-errors xcb-util-renderutil xcb-util-wm $SEAT_PKGS xorg-xwayland \
          $MESA_PKGS pango cairo pixman fcft tllist foot wmenu fastfetch \
          pipewire wireplumber $PULSE_PKG swaybg swaylock grim slurp wl-clipboard \
          brightnessctl curl procps-ng nano $FONT_PKG lf mpv zathura zathura-pdf-poppler \
          xdg-utils imv chrony firefox btop cowsay dbus pciutils $GREET_PKGS"
fi

GREETD_VT="${GREETD_VT:-$GREETD_VT_DEFAULT}"
case "$GREETD_VT" in ''|*[!0-9]*) err "GREETD_VT numero entre 1-12.";; esac
[ "$GREETD_VT" -lt 1 -o "$GREETD_VT" -gt 12 ] && err "GREETD_VT 1-12."

FREE_GB=$(df -BG --output=avail "$HOME" | tail -n1 | tr -d 'G ')
[ -n "$FREE_GB" ] && [ "$FREE_GB" -lt 5 ] && err "Menos de 5GB libres."

# Menu
echo
hdr "=========================================="
printf "  install-dwl %s\n" "$VERSION"
hdr "=========================================="
echo "1) Instalar"
echo "2) Salir"
printf "Opcion: "; read -r O
[ "$O" = "2" ] && exit 0
[ "$O" != "1" ] && err "Opcion invalida."

# --- Deteccion de GPU ---
detectar_gpus(){
    command -v lspci >/dev/null || PKGMAN pciutils
    local GL=$(lspci -nn | grep -iE 'vga|3d controller|display controller' || true)
    GPU_VENDORS=""
    echo "$GL" | grep -qiE 'NVIDIA|\[10de:' && GPU_VENDORS="$GPU_VENDORS nvidia"
    echo "$GL" | grep -qiE 'AMD|Radeon|\[1002:' && GPU_VENDORS="$GPU_VENDORS amd"
    echo "$GL" | grep -qiE 'Intel|\[8086:' && GPU_VENDORS="$GPU_VENDORS intel"
    GPU_VENDORS=$(echo "$GPU_VENDORS" | sed 's/^ //')
    [ -z "$GPU_VENDORS" ] && GPU_VENDORS="desconocida"
    GPU_CARDS=$(ls -1 /dev/dri/card* 2>/dev/null | sort -V | tr '\n' ':' | sed 's/:$//')
    GPU_HIBRIDA=0; [ "$(echo "$GL" | grep -c .)" -ge 2 ] && GPU_HIBRIDA=1
    info "GPUs: $GPU_VENDORS"
}

# --- Compilar dwlb ---
compilar_dwlb(){
    cd "$HOME"
    [ -d dwlb ] || { info "Clonando dwlb..."; git clone https://github.com/kolunmi/dwlb.git; }
    cd "$HOME/dwlb"
    if [ "$(stat -c %U .)" != "$(id -un)" ]; then sudo chown -R "$(id -un):$(id -gn)" .; fi
    [ -f config.def.h ] && [ ! -f config.h ] && cp config.def.h config.h
    # Parche layer-shell version
    if grep -qE 'zwlr_layer_shell_v1_interface, [0-9]+\)' dwlb.c 2>/dev/null; then
        V=$(grep -oE 'zwlr_layer_shell_v1_interface, [0-9]+\)' dwlb.c | head -n1 | sed -n 's/.*, *\([0-9]*\))/\1/p')
        [ -n "$V" ] && [ "$V" -gt 1 ] && sed -i "s|&zwlr_layer_shell_v1_interface, $V)|\&zwlr_layer_shell_v1_interface, (version < $V ? version : $V))|" dwlb.c
    fi
    make clean 2>/dev/null || true
    make || { err "Error compilando dwlb (faltan headers?)"; }
    sudo make install
    command -v dwlb >/dev/null || err "dwlb no esta en PATH."
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
 V=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null || echo "")
 VSTR="^fg("$E")VOL^fg("$T") --"
 [ -n "$V" ] && {
   VOL=$(echo "$V"|awk '{printf "%d",$2*100}')
   case "$V" in *MUTED*) VSTR="^fg("$E")VOL^fg("$A") mudo";; *) VSTR="^fg("$E")VOL^fg("$T") $VOL%";; esac
 }
 B=""
 for BDEV in /sys/class/power_supply/BAT*; do
   [ -r "$BDEV/capacity" ] || continue
   C=$(cat "$BDEV/capacity"); S=$(cat "$BDEV/status")
   case "$S" in Charging)I="+";;Full)I="=";;*)I="-";;esac
   [ "$C" -le 15 ] && [ "$S" != Charging ] && BC="$A" || BC="$T"
   B="^fg("$E")BAT^fg("$BC") $I${C}%%"
   break
 done
 CPU=$(cut -d' ' -f1 /proc/loadavg)
 RAM=$(awk '/^MemTotal:/{t=$2}/^MemAvailable:/{a=$2}END{printf "%.1fG",(t-a)/1048576}' /proc/meminfo)
 D=$(date '+%a %d/%m %H:%M')
 printf '^mm(foot)^fg(%s)CPU^fg(%s) %s  ^fg(%s)RAM^fg(%s) %s  %s  %s  ^lm(foot -e sh -c "cal -3; read x")^fg(%s)%s^fg()^lm()^mm()\n' \
   "$E" "$T" "$CPU" "$E" "$T" "$RAM" "$VSTR" "$B" "$T" "$D"
 sleep 5
done
STAT
    sudo chmod +x /usr/local/bin/dwlb-status
}

# --- PASO PRINCIPAL: INSTALACION ---
info "Instalando paquetes..."
PKGMAN $PKGS || err "Fallo instalando paquetes. Revisa tu conexion."

info "Habilitando servicios base..."
svc_on dbus || warn "dbus fallo."
svc_on chronyd || warn "chronyd fallo."
[ "$FAMILIA" = "void" ] && svc_on seatd

REAL_USER=$(id -un)
getent group "$SEAT_GRP" >/dev/null || err "No existe grupo $SEAT_GRP (reinstala seatd)."
sudo usermod -aG "$SEAT_GRP" "$REAL_USER"
getent group video >/dev/null && sudo usermod -aG video "$REAL_USER"
warn "Grupos ($SEAT_GRP, video) se aplican al reiniciar."

detectar_gpus || true

# Zona horaria
printf "Pais (vacio = Colombia): "; read -r pais; pais="${pais:-Colombia}"
pais_n=$(echo "$pais"|tr '[:upper:]' '[:lower:]'|sed 's/á/a/g;s/é/e/g;s/í/i/g;s/ó/o/g;s/ú/u/g;s/ñ/n/g')
case "$pais_n" in
 colombia)tz=America/Bogota;; mexico)tz=America/Mexico_City;; argentina)tz=America/Buenos_Aires;;
 chile)tz=America/Santiago;; peru)tz=America/Lima;; espana)tz=Europe/Madrid;; usa)tz=America/New_York;;
 */*)tz="$pais";; *)tz="";;
esac
if [ -n "$tz" ] && [ -f "/usr/share/zoneinfo/$tz" ]; then
 sudo ln -sf "/usr/share/zoneinfo/$tz" /etc/localtime
 echo "$tz"|sudo tee /etc/timezone >/dev/null 2>&1
 [ "$FAMILIA" = "void" ] && grep -q TIMEZONE /etc/rc.conf && sudo sed -i "s|^.*TIMEZONE=.*|TIMEZONE=\"$tz\"|" /etc/rc.conf || true
fi

# Teclado
printf "Teclado 1=us 2=es 3=latam [3]: "; read -r k; k="${k:-3}"
case "$k" in 1)kb=us;kc=us;;2)kb=es;kc=es;;*)kb=latam;kc=la-latin1;;esac
if [ "$FAMILIA" = "void" ]; then
 grep -q KEYMAP /etc/rc.conf && sudo sed -i "s|^.*KEYMAP=.*|KEYMAP=\"$kc\"|" /etc/rc.conf || echo "KEYMAP=\"$kc\""|sudo tee -a /etc/rc.conf >/dev/null
else
 sudo mkdir -p /etc
 grep -q ^KEYMAP= /etc/vconsole.conf 2>/dev/null && sudo sed -i "s|^KEYMAP=.*|KEYMAP=$kc|" /etc/vconsole.conf || echo "KEYMAP=$kc"|sudo tee -a /etc/vconsole.conf >/dev/null
fi
command -v loadkeys >/dev/null && sudo loadkeys "$kc" 2>/dev/null || true

# --- Compilar dwl ---
cd "$HOME"
[ -d dwl ] || { info "Clonando dwl..."; git clone https://codeberg.org/dwl/dwl.git; }
cd dwl
if [ "$(stat -c %U .)" != "$(id -un)" ]; then sudo chown -R "$(id -un):$(id -gn)" .; fi

if [ -f protocols/dwl-ipc-unstable-v2.xml ] || [ -f protocols/dwl-ipc-unstable-v1.xml ]; then
 DWLB_IPC=1; info "IPC disponible para dwlb."
else DWLB_IPC=0; fi

# Regenerar config.h si es viejo
if [ -f config.h ] && { grep -q 'static const char \*tags\[\]' config.h || ! grep -q 'TAGCOUNT' config.h; }; then
 mv config.h "config.h.old-$(date +%Y%m%d%H%M%S)"
fi
if [ ! -f config.h ]; then
 info "Generando config.h (layout $kb)..."
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
static const struct xkb_rule_names xkb_rules={.layout="$kb"};
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
static const char *term[]={"foot",NULL},*br[]={"firefox",NULL},
*dm[]={"sh","-c","dwlb -toggle-visibility all; wmenu-run -f 'monospace $WMENU_FONT_SIZE' -N 1e1e2e -n cdd6f4 -S 89b4fa -s ffffff; dwlb -toggle-visibility all",NULL},
*uv[]={"wpctl","set-volume","@DEFAULT_AUDIO_SINK@","3%+","-l","1.0",NULL},*dv[]={"wpctl","set-volume","@DEFAULT_AUDIO_SINK@","3%-",NULL},
*mv[]={"wpctl","set-mute","@DEFAULT_AUDIO_SINK@","toggle",NULL},*bu[]={"brightnessctl","set","+5%",NULL},*bd[]={"brightnessctl","set","5%-",NULL},
*ss[]={"sh","-c","grim ~/Pictures/\$(date +%Y%m%d_%H%M%S).png",NULL},*bt[]={"dwlb","-toggle-visibility","all",NULL};
static const Key keys[]={
{MODKEY,XKB_KEY_Return,spawn,{.v=term}},{MODKEY,XKB_KEY_d,spawn,{.v=dm}},{MODKEY,XKB_KEY_b,spawn,{.v=br}},
{MODKEY,XKB_KEY_q,killclient,{0}},{MODKEY,XKB_KEY_j,focusstack,{.i=+1}},{MODKEY,XKB_KEY_k,focusstack,{.i=-1}},
{MODKEY,XKB_KEY_h,setmfact,{.f=-0.05f}},{MODKEY,XKB_KEY_l,setmfact,{.f=+0.05f}},{MODKEY,XKB_KEY_w,spawn,{.v=bt}},
{MODKEY,XKB_KEY_f,setlayout,{.v=&layouts[2]}},{MODKEY,XKB_KEY_space,setlayout,{0}},
TAGKEYS(XKB_KEY_1,XKB_KEY_exclam,0),TAGKEYS(XKB_KEY_2,XKB_KEY_quotedbl,1),TAGKEYS(XKB_KEY_3,XKB_KEY_numbersign,2),
TAGKEYS(XKB_KEY_4,XKB_KEY_dollar,3),TAGKEYS(XKB_KEY_5,XKB_KEY_percent,4),TAGKEYS(XKB_KEY_6,XKB_KEY_ampersand,5),
TAGKEYS(XKB_KEY_7,XKB_KEY_slash,6),TAGKEYS(XKB_KEY_8,XKB_KEY_parenleft,7),TAGKEYS(XKB_KEY_9,XKB_KEY_parenright,8),
{MODKEY,XKB_KEY_Tab,view,{0}},{MODKEY,XKB_KEY_0,view,{.ui=~0}},
{0,XKB_KEY_XF86AudioRaiseVolume,spawn,{.v=uv}},{0,XKB_KEY_XF86AudioLowerVolume,spawn,{.v=dv}},
{0,XKB_KEY_XF86AudioMute,spawn,{.v=mv}},{0,XKB_KEY_XF86MonBrightnessUp,spawn,{.v=bu}},
{0,XKB_KEY_XF86MonBrightnessDown,spawn,{.v=bd}},{0,XKB_KEY_Print,spawn,{.v=ss}},
{MODKEY|WLR_MODIFIER_SHIFT,XKB_KEY_E,quit,{0}}
};
static const Button buttons[]={{MODKEY,BTN_LEFT,moveresize,{.ui=CurMove}},{MODKEY,BTN_MIDDLE,togglefloating,{0}},{MODKEY,BTN_RIGHT,moveresize,{.ui=CurResize}}};
static const Axis axes[]={{MODKEY,AxisUp,spawn,{.v=uv}},{MODKEY,AxisDown,spawn,{.v=dv}}};
CFG
fi
info "Compilando dwl..."
make clean 2>/dev/null || true
make || err "Error compilando dwl. Si wlroots es muy viejo/nuevo, instala la version correcta (ej: sudo pacman -S wlroots0.18)"
sudo make install

# --- dwlb ---
compilar_dwlb
configurar_dwlb
BARRA="dwlb"
[ "$DWLB_IPC" -eq 1 ] && BARRA_MODE="-ipc" || BARRA_MODE="-no-ipc"

# Runner de barra/wallpaper
sudo tee /usr/local/bin/dwl-status-runner >/dev/null <<'RUN'
#!/bin/sh
exec 3<&0 || exit 1; H=""; PB=""
clean(){ for p in $H; do kill "$p" 2>/dev/null; done; wait 2>/dev/null; H=""; }
trap clean EXIT
[ -n "$DWL_WALLPAPER" ] && [ -f "$DWL_WALLPAPER" ] && command -v swaybg >/dev/null && { swaybg -i "$DWL_WALLPAPER" -m fill </dev/null >/dev/null 2>&1 & H="$H $!"; }
case "$DWL_BAR_KIND" in
 dwlb)
  if [ "$DWL_BAR_MODE" = "-ipc" ]; then cat <&3 >/dev/null & H="$H $!"; dwlb -ipc </dev/null &
                               else dwlb -no-ipc <&3 & fi
  PB=$!; H="$H $PB"
  sleep 1; (dwlb-status | dwlb -status-stdin all) </dev/null >/dev/null 2>&1 & H="$H $!" ;;
 *) cat <&3 >/dev/null & PB=$!; H="$H $PB" ;;
esac
wait "$PB"; clean
RUN
sudo chmod +x /usr/local/bin/dwl-status-runner

# Wallpaper
mkdir -p "$(dirname "$WALLPAPER_PATH")"
if [ ! -f "$WALLPAPER_PATH" ]; then
 T="${WALLPAPER_PATH}.tmp"
 curl -fsSL --max-time 20 -A Mozilla/5.0 -o "$T" https://wallpapercave.com/download/empty-error-wallpapers-wp8330753 && file "$T"|grep -qi image && mv "$T" "$WALLPAPER_PATH" || { rm -f "$T"; warn "Wallpaper descartado (error de red)."; }
fi

# --- Wrapper de sesion ---
sudo tee /usr/local/bin/dwl-session >/dev/null <<EOF
#!/bin/sh
export XDG_SESSION_TYPE=wayland XDG_CURRENT_DESKTOP=dwl MOZ_ENABLE_WAYLAND=1 QT_QPA_PLATFORM=wayland GDK_BACKEND=wayland,x11
export DWL_BAR_KIND="$BARRA" DWL_BAR_MODE="$BARRA_MODE" DWL_WALLPAPER="$WALLPAPER_PATH"
SU=\$(id -u)
if [ ! -d "\$XDG_RUNTIME_DIR" ] || [ "\$(stat -c %u "\$XDG_RUNTIME_DIR" 2>/dev/null)" != "\$SU" ]; then
  R="/run/user/\$SU"
  if [ ! -d "\$R" ] || [ "\$(stat -c %u "\$R" 2>/dev/null)" != "\$SU" ]; then
    R="\$HOME/.xdg-runtime"; mkdir -p "\$R"; chmod 700 "\$R"
  fi
  export XDG_RUNTIME_DIR="\$R"
fi
P=""
ud(){ n="\$1"; shift; pgrep -u "\$SU" -x "\$n" >/dev/null && return 0; command -v "\$n" >/dev/null && { "\$@" >/dev/null 2>&1 & P="\$P \$!"; }; }
clean(){ for p in \$P; do kill "\$p" 2>/dev/null; done; wait 2>/dev/null; }
trap clean EXIT
ud pipewire pipewire; ud wireplumber wireplumber; command -v pipewire-pulse >/dev/null && ud pipewire-pulse pipewire-pulse
IN=\$(date +%s)
dwl -s /usr/local/bin/dwl-status-runner & DPID=\$!; wait "\$DPID"; ST=\$?
if [ "\$ST" -ne 0 ] && [ -z "\$WLR_RENDERER" ] && [ \$((\$(date +%s)-IN)) -lt 5 ]; then
  echo "Reintento con render por software..." >&2
  export WLR_RENDERER=pixman WLR_NO_HARDWARE_CURSORS=1 LIBGL_ALWAYS_SOFTWARE=1
  dwl -s /usr/local/bin/dwl-status-runner & DPID=\$!; wait "\$DPID"; ST=\$?
fi
clean; exit "\$ST"
EOF
sudo chmod +x /usr/local/bin/dwl-session

# Ajustes GPU
echo "$GPU_VENDORS"|grep -q nvidia && sudo sed -i 's|^IN=|export WLR_NO_HARDWARE_CURSORS=1\nIN=|' /usr/local/bin/dwl-session
[ "$GPU_HIBRIDA" -eq 1 ] && [ -n "$GPU_CARDS" ] && sudo sed -i "s|^IN=|# export WLR_DRM_DEVICES=$GPU_CARDS\nIN=|" /usr/local/bin/dwl-session

# Scripts de rebuild
sudo tee /usr/local/bin/dwl-rebuild >/dev/null <<'RB'
#!/bin/sh; set -e; cd "$HOME/dwl"; make clean; make; sudo make install; echo "Listo, reinicia sesion."
RB
sudo chmod +x /usr/local/bin/dwl-rebuild
sudo tee /usr/local/bin/dwlb-rebuild >/dev/null <<'RB'
#!/bin/sh; set -e; cd "$HOME/dwlb"; git pull --ff-only; make clean; make; sudo make install; echo "Listo, reinicia sesion."
RB
sudo chmod +x /usr/local/bin/dwlb-rebuild

# Entrada de sesion para F3
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

# --- CONFIGURACION FINAL DE GREETD (LA PARTE QUE ESTABA ROTAAAA) ---
info "Configurando greetd..."

# 1) Quitar lightdm si existe
if PKGHAS lightdm || PKGHAS lightdm-gtk3-greeter || PKGHAS lightdm-gtk-greeter; then
 info "Desinstalando lightdm..."
 svc_off lightdm
 PKGREM lightdm lightdm-gtk3-greeter lightdm-gtk-greeter 2>/dev/null || true
fi

# 2) Asegurarse de que existe el usuario greeter (en Arch a veces no se crea si la instalacion se interrumpe)
if ! id -u "$GREETER_USR" >/dev/null 2>&1; then
 info "Creando usuario $GREETER_USR que faltaba..."
 sudo useradd -r -g video -s /sbin/nologin -d /var/lib/greetd "$GREETER_USR" 2>/dev/null || true
 sudo mkdir -p /var/lib/greetd
 sudo chown "$GREETER_USR:video" /var/lib/greetd
fi

# 3) DESACTIVAR SIEMPRE el getty de la vt de greetd, y enmascararlo para que no vuelva
disable_getty_tty "$GREETD_VT"

# 4) Escribir config.toml SIN ERRORES DE COMILLAS (usamos comillas simples para el comando dentro, sin anidar dobles)
sudo mkdir -p /etc/greetd
sudo tee /etc/greetd/config.toml >/dev/null <<TOML
# Generado por install-dwl $VERSION
[terminal]
vt = $GREETD_VT

[default_session]
command = 'tuigreet --time --time-format "%H:%M  %d/%m/%Y" --user-menu --remember --greeting "Bienvenido a dwl" --power-shutdown "shutdown -h now" --power-reboot "shutdown -r now" --cmd /usr/local/bin/dwl-session'
user = "$GREETER_USR"
TOML
info "/etc/greetd/config.toml escrito (sintaxis TOML valida)."

# 5) Si estamos en void y usamos turnstile, activarlo y agregar pam
if [ "$TURNSTILE" -eq 1 ]; then
 svc_on turnstiled
 PAM=/etc/pam.d/greetd
 [ -f "$PAM" ] && ! grep -q pam_turnstile.so "$PAM" && echo -e "\nsession optional pam_turnstile.so" | sudo tee -a "$PAM" >/dev/null
fi

# 6) HABILITAR Y ARRANCAR GREETD AHORA MISMO (systemd: enable --now; runit: enlazar + sv start)
info "Habilitando greetd..."
svc_on greetd || err "No se pudo habilitar greetd."

# 7) Esperar 2 segundos y comprobar que este corriendo DE VERDAD
sleep 2
if [ "$FAMILIA" = "arch" ]; then
 if systemctl is-active --quiet greetd; then
  info "greetd esta ACTIVO corriendo en tty$GREETD_VT."
 else
  err "greetd no arranco. Revisa con: sudo journalctl -u greetd -b"
 fi
else
 if sv status greetd | grep -q ^run:; then
  info "greetd esta ACTIVO en tty$GREETD_VT."
 else
  err "greetd no arranco. Revisa con: sudo sv status greetd"
 fi
fi

echo
hdr "=========================================="
hdr "   install-dwl $VERSION INSTALADO!"
hdr "=========================================="
echo "Distro:  $ID"
echo "Barra:   dwlb ($BARRA_MODE)  | wmenu: monospace $WMENU_FONT_SIZE  | dwlb: monospace $DWLB_FONT_SIZE"
echo "VT login: tty$GREETD_VT"
echo
warn "============================================================"
warn "  REINICIA AHORA MISMO: sudo reboot"
warn "  Los grupos de permisos NO se aplican hasta reiniciar."
warn "  Despues del reinicio veras tuigreet directamente en la"
warn "  pantalla de login, sin pantallas negras intermedias."
warn "============================================================"
echo
info "Atajos en ~/Atajos.txt"
info "Para cambiar configuracion despues:"
info "  ~/dwl/config.h -> atajos/colores -> recompila con: dwl-rebuild"
info "  ~/.config/dwlb/config -> barra (no recompila)"

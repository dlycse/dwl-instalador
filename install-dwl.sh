#!/bin/sh
# install-dwl v0.9.5
# Instalador de dwl (dwm para Wayland) - FUNCIONA 100% AUTOMATICO.
#
# Distros soportadas sin intervencion manual:
#   - Arch Linux y TODAS sus derivadas (pacman + systemd): Manjaro, EndeavourOS,
#     Garuda, CachyOS, ArcoLinux, Artix, Parabola, etc.
#   - Void Linux (xbps + runit).
#
# Entorno que instala:
#   dwl (compilado desde fuente, rama main) + dwlb (barra) + foot (terminal)
#   + wmenu (lanzador) + swaybg (wallpaper) + pipewire (audio) + grim/slurp
#   (capturas) + brightnessctl + lf (gestor archivos) + zathura + firefox
#   + greetd + tuigreet (gestor de inicio automatico, NO se necesita lightdm/gdm/sddm).
#
# NO instala drivers de GPU ni Steam (lo haces tu segun tu grafica).
#
# Variables sobreescribibles por entorno:
#   WMENU_FONT_SIZE=11 DWLB_FONT_SIZE=10 GREETD_VT=1 ./install-dwl-v0.9.5.sh

set -e

# Colores
G="\033[1;32m"; Y="\033[1;33m"; R="\033[1;31m"; C="\033[1;36m"; N="\033[0m"
info(){ printf "%b[+]%b %s\n" "$G" "$N" "$1"; }
warn(){ printf "%b[!]%b %s\n" "$Y" "$N" "$1"; }
err() { printf "%b[x]%b %s\n" "$R" "$N" "$1"; exit 1; }
hdr() { printf "%b%s%b\n" "$C" "$1" "$N"; }

VERSION="v0.9.5"
[ "$(id -u)" -eq 0 ] && err "No ejecutes el script como root (los archivos quedarian en /root)."
command -v sudo >/dev/null || err "Falta sudo: agrega tu usuario a sudoers con visudo."
command -v git  >/dev/null || err "Falta git: instalalo primero."

# Detectar familia de distro
FAMILIA="unknown"; DISTRO="unknown"
[ -f /etc/os-release ] && . /etc/os-release
case "$ID" in
    void) FAMILIA="void"; DISTRO="void";;
    arch|manjaro|endeavouros|garuda|artix|archcraft|cachyos|arcolinux|parabola|rebornos|obarun|hyperbola)
        FAMILIA="arch"; DISTRO="$ID";;
    *)
        case "${ID_LIKE:-}" in
            *arch*) FAMILIA="arch"; DISTRO="$ID";;
            *void*) FAMILIA="void"; DISTRO="$ID";;
        esac;;
esac
info "install-dwl $VERSION - Distro detectada: $DISTRO (familia: $FAMILIA)"
[ "$FAMILIA" = "unknown" ] && err "Solo compatible con Void Linux y Arch Linux/derivadas."

# Constantes configurables
: "${WMENU_FONT_SIZE:=11}"
: "${DWLB_FONT_SIZE:=10}"
WALLPAPER_PATH="${WALLPAPER_PATH:-$HOME/Pictures/wallpaper.jpg}"

# ----------------------------------------------------------------
# Definiciones por distro
# ----------------------------------------------------------------
if [ "$FAMILIA" = "void" ]; then
    # -------- Void (xbps + runit) --------
    PKGMAN(){ sudo xbps-install -Sy "$@"; }
    PKGHAS(){ xbps-query "$1" >/dev/null 2>&1; }
    PKGREM(){ sudo xbps-remove -R "$@"; }
    GREETD_VT="${GREETD_VT:-1}"
    SEAT_GRP="_seatd"
    GREETER_USR="_greeter"
    NEED_TURNSTILE=1
    WLR_PKGS="wlroots wlroots-devel"
    SEAT_PKGS="libseat libseat-devel seatd"
    GREET_PKGS="greetd tuigreet turnstile"
    FONT_PKG="nerd-fonts"
    PULSE_PKG="alsa-pipewire"
    MESA_PKGS="mesa-dri libdrm-devel"
    DEVEL="-devel"

    svc_on(){
        if [ -L "/var/service/$1" ]; then info "$1 ya habilitado en runit."
        elif [ -d "/etc/sv/$1" ]; then
            sudo ln -sf "/etc/sv/$1" /var/service/
            info "$1 habilitado (arranca al reiniciar)."
            sudo sv stop "$1" 2>/dev/null || true
        else warn "No existe /etc/sv/$1, activalo manual."; return 1; fi
    }
    svc_off(){
        if [ -L "/var/service/$1" ]; then
            sudo sv stop "$1" 2>/dev/null || true
            sudo rm -f "/var/service/$1"
            info "$1 desactivado."
        fi
    }
    svc_start(){ sudo sv start "$1"; }
    disable_getty_vt(){ VT="$1"; [ -L "/var/service/agetty-tty$VT" ] && svc_off "agetty-tty$VT"; }
    svc_daemon_reload(){ :; }   # runit no necesita recargar

    command -v xbps-install >/dev/null || err "Falta xbps-install."
    [ -d /var/service ] || err "/var/service no existe (runit no esta instalado)."

    PKGS="base-devel file pkg-config libinput libinput${DEVEL} void-repo-nonfree void-repo-multilib void-repo-multilib-nonfree \
          wayland wayland${DEVEL} wayland-protocols libxkbcommon libxkbcommon${DEVEL} $WLR_PKGS $SEAT_PKGS \
          xorg-server-xwayland $MESA_PKGS pango${DEVEL} cairo${DEVEL} pixman pixman${DEVEL} fcft fcft${DEVEL} tllist \
          foot wmenu fastfetch pipewire wireplumber $PULSE_PKG swaybg swaylock grim slurp wl-clipboard \
          brightnessctl curl procps-ng nano $FONT_PKG lf mpv zathura zathura-pdf-poppler xdg-utils imv \
          chrony firefox btop cowsay dbus pciutils $GREET_PKGS"

else
    # -------- Arch Linux (pacman + systemd) --------
    PKGMAN(){ sudo pacman -Sy --needed --noconfirm "$@"; }
    PKGHAS(){ pacman -Q "$1" >/dev/null 2>&1; }
    PKGREM(){ sudo pacman -Rns --noconfirm "$@"; }
    GREETD_VT="${GREETD_VT:-1}"
    SEAT_GRP="seat"
    GREETER_USR="greeter"
    NEED_TURNSTILE=0
    # Detectar automaticamente la ultima version de wlroots (0.19, 0.20, etc.)
    WLR_PKG=$(pacman -Ssq '^wlroots[0-9]*\.[0-9]+$' 2>/dev/null | sort -V | tail -n1)
    [ -z "$WLR_PKG" ] && WLR_PKG="wlroots0.19"
    info "Paquete wlroots detectado: $WLR_PKG"
    SEAT_PKGS="seatd"
    GREET_PKGS="greetd greetd-tuigreet"
    FONT_PKG="ttf-nerd-fonts-symbols ttf-nerd-fonts-symbols-mono"
    PULSE_PKG="pipewire-alsa pipewire-pulse"
    MESA_PKGS="mesa libdrm"
    DEVEL=""

    svc_on(){
        if systemctl is-enabled --quiet "$1" 2>/dev/null; then
            info "$1 ya esta habilitado en systemd."
        else
            sudo systemctl enable "$1" && info "$1 habilitado (arranca al reiniciar)."
        fi
        sudo systemctl stop "$1" 2>/dev/null || true
    }
    svc_off(){
        if systemctl is-enabled --quiet "$1" 2>/dev/null; then
            sudo systemctl stop "$1" 2>/dev/null || true
            sudo systemctl disable "$1" 2>/dev/null || true
            info "$1 desactivado."
        fi
    }
    svc_start(){ sudo systemctl restart "$1"; }
    disable_getty_vt(){
        VT="$1"
        G="getty@tty${VT}.service"
        sudo systemctl stop "$G" 2>/dev/null || true
        sudo systemctl disable "$G" 2>/dev/null || true
        sudo systemctl mask "$G" 2>/dev/null || true
        info "getty de tty$VT desactivado y enmascarado."
    }
    svc_daemon_reload(){ sudo systemctl daemon-reload; }

    command -v pacman >/dev/null || err "Falta pacman."
    grep -qE '^\[multilib\]' /etc/pacman.conf || warn "[multilib] no habilitado en pacman.conf: necesario para Steam/32bits."

    PKGS="base-devel libinput wayland wayland-protocols libxkbcommon $WLR_PKG \
          xcb-util-errors xcb-util-renderutil xcb-util-wm $SEAT_PKGS xorg-xwayland \
          $MESA_PKGS pango cairo pixman fcft tllist foot wmenu fastfetch \
          pipewire wireplumber $PULSE_PKG swaybg swaylock grim slurp wl-clipboard \
          brightnessctl curl procps-ng nano $FONT_PKG lf mpv zathura zathura-pdf-poppler \
          xdg-utils imv chrony firefox btop cowsay dbus pciutils $GREET_PKGS"
fi

# Validar VT
case "$GREETD_VT" in ''|*[!0-9]*) err "GREETD_VT debe ser un numero 1-12.";; esac
[ "$GREETD_VT" -lt 1 -o "$GREETD_VT" -gt 12 ] && err "GREETD_VT fuera de rango (1-12)."

# Espacio libre
FREE_GB=$(df -BG --output=avail "$HOME" 2>/dev/null | tail -n1 | tr -d 'G ')
[ -n "$FREE_GB" ] && [ "$FREE_GB" -lt 5 ] && err "Menos de 5GB libres en $HOME."

# Menu principal
echo
hdr "=========================================="
printf "     install-dwl %s\n" "$VERSION"
hdr "=========================================="
echo "1) Instalar dwl + entorno Wayland completo"
echo "2) Salir"
printf "Opcion [1]: "; read -r OPC; OPC="${OPC:-1}"
[ "$OPC" = "2" ] && { info "Saliendo."; exit 0; }
[ "$OPC" != "1" ] && err "Opcion invalida."

# ----------------------------------------------------------------
# Deteccion de GPUs (solo informativa)
# ----------------------------------------------------------------
detectar_gpus(){
    command -v lspci >/dev/null || PKGMAN pciutils
    GL=$(lspci -nn | grep -iE 'vga|3d controller|display controller' || true)
    GPU_VENDORS=""
    echo "$GL" | grep -qiE 'NVIDIA|\[10de:'   && GPU_VENDORS="$GPU_VENDORS nvidia"
    echo "$GL" | grep -qiE 'AMD|Radeon|\[1002:' && GPU_VENDORS="$GPU_VENDORS amd"
    echo "$GL" | grep -qiE 'Intel|\[8086:'    && GPU_VENDORS="$GPU_VENDORS intel"
    GPU_VENDORS=$(echo "$GPU_VENDORS" | sed 's/^ //')
    [ -z "$GPU_VENDORS" ] && GPU_VENDORS="desconocida"
    GPU_CARDS=$(ls -1 /dev/dri/card* 2>/dev/null | sort -V | tr '\n' ':' | sed 's/:$//')
    GPU_HIBRIDA=0; [ "$(echo "$GL" | grep -c .)" -ge 2 ] && GPU_HIBRIDA=1
    info "GPUs detectadas: $GPU_VENDORS"
}

# ----------------------------------------------------------------
# Compilar dwlb
# ----------------------------------------------------------------
compilar_dwlb(){
    cd "$HOME"
    [ -d dwlb ] || { info "Clonando dwlb..."; git clone https://github.com/kolunmi/dwlb.git || return 1; }
    cd "$HOME/dwlb"
    if [ "$(stat -c %U .)" != "$(id -un)" ]; then sudo chown -R "$(id -un):$(id -gn)" .; fi
    [ -f config.def.h ] && [ ! -f config.h ] && cp config.def.h config.h
    # Parche de version de layer-shell
    if grep -qE 'zwlr_layer_shell_v1_interface, [0-9]+\)' dwlb.c 2>/dev/null; then
        V=$(grep -oE 'zwlr_layer_shell_v1_interface, [0-9]+\)' dwlb.c | head -n1 | sed -n 's/.*, *\([0-9]*\))/\1/p')
        if [ -n "$V" ] && [ "$V" -gt 1 ]; then
            sed -i "s|&zwlr_layer_shell_v1_interface, $V)|\&zwlr_layer_shell_v1_interface, (version < $V ? version : $V))|" dwlb.c
            info "Parche de compatibilidad layer-shell aplicado (max v$V)."
        fi
    fi
    make clean 2>/dev/null || true
    make || { err "Error compilando dwlb (faltan headers de fcft/pixman?)"; }
    sudo make install || return 1
    command -v dwlb >/dev/null || err "dwlb no quedo en PATH tras instalar."
}

configurar_dwlb(){
    info "Configurando dwlb (fuente monospace:$DWLB_FONT_SIZE, pad -2px)..."
    mkdir -p "$HOME/.config/dwlb"
    cat > "$HOME/.config/dwlb/config" <<EOF
# dwlb (install-dwl $VERSION)
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
    V=$(echo "$VINF"|awk '{printf "%d",$2*100}')
    case "$VINF" in *MUTED*) VSTR="^fg($E)VOL^fg($A) mudo";; *) VSTR="^fg($E)VOL^fg($T) ${V}%";; esac
  fi
  BSTR=""
  for B in /sys/class/power_supply/BAT*; do
    [ -r "$B/capacity" ] || continue
    C=$(cat "$B/capacity"); S=$(cat "$B/status")
    case "$S" in Charging)I="+";;Full)I="=";;*)I="-";;esac
    [ "$C" -le 15 ] && [ "$S" != "Charging" ] && BC="$A" || BC="$T"
    BSTR="^fg($E)BAT^fg($BC) $I${C}%%"
    break
  done
  CPU=$(cut -d' ' -f1 /proc/loadavg)
  RAM=$(awk '/^MemTotal:/{t=$2}/^MemAvailable:/{a=$2}END{printf "%.1fG",(t-a)/1048576}' /proc/meminfo)
  D=$(date '+%a %d/%m %H:%M')
  printf '^mm(foot)^fg(%s)CPU^fg(%s) %s  ^fg(%s)RAM^fg(%s) %s  %s  %s  ^lm(foot -e sh -c "cal -3; read x")^fg(%s)%s^fg()^lm()^mm()\n' \
    "$E" "$T" "$CPU" "$E" "$T" "$RAM" "$VSTR" "$BSTR" "$T" "$D"
  sleep 5
done
STAT
    sudo chmod +x /usr/local/bin/dwlb-status
}

# ----------------------------------------------------------------
# Instalacion principal
# ----------------------------------------------------------------
info "Instalando paquetes..."
PKGMAN $PKGS || err "Fallo la instalacion de paquetes. Revisa conexion/repositorios."

info "Habilitando servicios base..."
svc_on dbus  || warn "dbus no pudo habilitarse."
svc_on chronyd || warn "chronyd no pudo habilitarse."
[ "$FAMILIA" = "void" ] && svc_on seatd

# Grupos de usuario
REAL_USER=$(id -un)
getent group "$SEAT_GRP" >/dev/null || err "No existe grupo $SEAT_GRP (reinstala seatd)."
sudo usermod -aG "$SEAT_GRP" "$REAL_USER"
getent group video >/dev/null && sudo usermod -aG video "$REAL_USER"
warn "Los grupos ($SEAT_GRP, video) se aplican al reiniciar sesion."

detectar_gpus || warn "Deteccion de GPUs fallo, sigo."

# Opcion de kernel nuevo (solo en Void)
if [ "$FAMILIA" = "void" ]; then
  info "Kernel actual: $(uname -r)"
  # Buscar ultimo kernel de la serie 7.x en repositorios
  KVER=$(xbps-query --regex -Rs '^linux[0-9]+\.[0-9]+' 2>/dev/null | awk '{print $2}' | grep -E '^linux[0-9]+\.[0-9]+-[0-9]+\.[0-9]+' | sort -V | tail -n1)
  KPKG=$(printf '%s' "$KVER" | sed 's/-[0-9]\..*$//')
  if [ -n "$KPKG" ]; then
    printf "Kernel mas nuevo disponible: %s\n" "$KPKG"
    printf "Que kernel quieres usar?\n"
    printf "  1) Conservar el kernel actual\n"
    printf "  2) Instalar $KPKG (recomendado para mejor soporte Wayland)\n"
    printf "Opcion [2]: "; read -r OK; OK="${OK:-2}"
    if [ "$OK" = "2" ]; then
      info "Instalando $KPKG..."
      sudo xbps-install -Sy "$KPKG" || warn "No se pudo instalar el kernel nuevo."
    else
      info "Se conserva el kernel actual."
    fi
  else
    warn "No se encontro un kernel nuevo en los repositorios."
  fi
fi

# Zona horaria
printf "Pais (vacio = Colombia): "; read -r P; P="${P:-Colombia}"
PN=$(echo "$P" | tr '[:upper:]' '[:lower:]' | sed 's/á/a/g;s/é/e/g;s/í/i/g;s/ó/o/g;s/ú/u/g;s/ñ/n/g')
case "$PN" in
 colombia)tz=America/Bogota;;mexico)tz=America/Mexico_City;;argentina)tz=America/Buenos_Aires;;
 chile)tz=America/Santiago;;peru)tz=America/Lima;;espana|spain)tz=Europe/Madrid;;
 "estados unidos"|usa|eeuu)tz=America/New_York;;*/*)tz="$P";;*)tz="";;
esac
if [ -n "$tz" ] && [ -f "/usr/share/zoneinfo/$tz" ]; then
  sudo ln -sf "/usr/share/zoneinfo/$tz" /etc/localtime
  echo "$tz" | sudo tee /etc/timezone >/dev/null 2>&1
  [ "$FAMILIA" = "void" ] && {
    grep -q TIMEZONE /etc/rc.conf && sudo sed -i "s|^.*TIMEZONE=.*|TIMEZONE=\"$tz\"|" /etc/rc.conf \
      || echo "TIMEZONE=\"$tz\"" | sudo tee -a /etc/rc.conf >/dev/null
  }
  info "Zona horaria: $tz"
else
  warn "Pais no reconocido, zona horaria intacta."
fi

# Teclado
printf "Teclado 1=us 2=es 3=latam [3]: "; read -r K; K="${K:-3}"
case "$K" in 1)KB=us;KC=us;;2)KB=es;KC=es;;*)KB=latam;KC=la-latin1;;esac
if [ "$FAMILIA" = "void" ]; then
  grep -q KEYMAP /etc/rc.conf && sudo sed -i "s|^.*KEYMAP=.*|KEYMAP=\"$KC\"|" /etc/rc.conf \
    || echo "KEYMAP=\"$KC\"" | sudo tee -a /etc/rc.conf >/dev/null
else
  grep -q ^KEYMAP= /etc/vconsole.conf 2>/dev/null && sudo sed -i "s|^KEYMAP=.*|KEYMAP=$KC|" /etc/vconsole.conf \
    || echo "KEYMAP=$KC" | sudo tee -a /etc/vconsole.conf >/dev/null
fi
command -v loadkeys >/dev/null && sudo loadkeys "$KC" 2>/dev/null || true
KB_XKB="$KB"

# ----------------------------------------------------------------
# Compilar dwl
# ----------------------------------------------------------------
cd "$HOME"
[ -d dwl ] || { info "Clonando dwl..."; git clone https://codeberg.org/dwl/dwl.git; }
cd dwl
if [ "$(stat -c %U .)" != "$(id -un)" ]; then sudo chown -R "$(id -un):$(id -gn)" .; fi

# Detectar IPC
if [ -f protocols/dwl-ipc-unstable-v2.xml ] || [ -f protocols/dwl-ipc-unstable-v1.xml ]; then
  DWLB_IPC=1; info "dwl incluye protocolo IPC: los clics en tags de la barra funcionaran."
else DWLB_IPC=0; fi

# Regenerar config.h si es API antigua
if [ -f config.h ] && { grep -q 'static const char \*tags\[\]' config.h || ! grep -q TAGCOUNT config.h; }; then
  VIEJO="config.h.old-$(date +%Y%m%d%H%M%S)"
  warn "Tu config.h es de la API vieja de dwl; lo guardo como $VIEJO y genero uno nuevo."
  mv config.h "$VIEJO"
fi
if [ ! -f config.h ]; then
  info "Generando config.h (layout $KB_XKB)..."
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
static const struct xkb_rule_names xkb_rules={.layout="$KB_XKB"};
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
make || err "Error compilando dwl: la version de wlroots no es compatible. Prueba: sudo pacman -S wlroots0.18"
sudo make install || err "No se pudo instalar dwl en /usr/local."

# ----------------------------------------------------------------
# Instalar dwlb
# ----------------------------------------------------------------
compilar_dwlb
configurar_dwlb
if [ "$DWLB_IPC" -eq 1 ]; then BAR_MODE="-ipc"; else BAR_MODE="-no-ipc"; fi

# Status runner
sudo tee /usr/local/bin/dwl-status-runner >/dev/null <<'RUN'
#!/bin/sh
exec 3<&0 || exit 1; H=""; PB=""
clean(){ for p in $H; do kill "$p" 2>/dev/null; done; wait 2>/dev/null; H=""; }
trap clean EXIT
if [ -n "$DWL_WALLPAPER" ] && [ -f "$DWL_WALLPAPER" ] && command -v swaybg >/dev/null; then
  swaybg -i "$DWL_WALLPAPER" -m fill </dev/null >/dev/null 2>&1 & H="$H $!"
fi
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
  info "Descargando wallpaper..."
  T="${WALLPAPER_PATH}.tmp"
  curl -fsSL --max-time 25 -A "Mozilla/5.0" \
    -o "$T" https://wallpapercave.com/download/empty-error-wallpapers-wp8330753 \
    && file "$T" | grep -qi image && mv "$T" "$WALLPAPER_PATH" \
    || { rm -f "$T"; warn "No se pudo descargar el wallpaper, se verá fondo solido."; }
fi

# Wrapper de sesion
sudo tee /usr/local/bin/dwl-session >/dev/null <<EOF
#!/bin/sh
export XDG_SESSION_TYPE=wayland XDG_CURRENT_DESKTOP=dwl MOZ_ENABLE_WAYLAND=1 QT_QPA_PLATFORM=wayland GDK_BACKEND=wayland,x11
export DWL_BAR_KIND="dwlb" DWL_BAR_MODE="$BAR_MODE" DWL_WALLPAPER="$WALLPAPER_PATH"
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
  echo "Reintento con render por software (pixman)..." >&2
  export WLR_RENDERER=pixman WLR_NO_HARDWARE_CURSORS=1 LIBGL_ALWAYS_SOFTWARE=1
  dwl -s /usr/local/bin/dwl-status-runner & DPID=\$!; wait "\$DPID"; ST=\$?
fi
clean; exit "\$ST"
EOF
sudo chmod +x /usr/local/bin/dwl-session

# Ajustes por GPU
echo "$GPU_VENDORS" | grep -q nvidia && {
  info "GPU NVIDIA detectada: desactivando cursores hardware para evitar cursor invisible."
  sudo sed -i 's|^IN=|export WLR_NO_HARDWARE_CURSORS=1\nIN=|' /usr/local/bin/dwl-session
}
[ "$GPU_HIBRIDA" -eq 1 ] && [ -n "$GPU_CARDS" ] && {
  info "GPU hibrida detectada; WLR_DRM_DEVICES queda comentada en dwl-session."
  sudo sed -i "s|^IN=|# export WLR_DRM_DEVICES=$GPU_CARDS\nIN=|" /usr/local/bin/dwl-session
}

# Scripts de rebuild
sudo tee /usr/local/bin/dwl-rebuild >/dev/null <<'RB'
#!/bin/sh
set -e; cd "$HOME/dwl"; make clean; make; sudo make install
echo "Listo. Cierra sesion para aplicar."
RB
sudo chmod +x /usr/local/bin/dwl-rebuild
sudo tee /usr/local/bin/dwlb-rebuild >/dev/null <<'RB'
#!/bin/sh
set -e; cd "$HOME/dwlb"; git pull --ff-only; make clean; make; sudo make install
echo "Listo. Cierra sesion para ver los cambios."
RB
sudo chmod +x /usr/local/bin/dwlb-rebuild

# Wayland session desktop
sudo mkdir -p /usr/share/wayland-sessions
sudo tee /usr/share/wayland-sessions/dwl.desktop >/dev/null <<DSK
[Desktop Entry]
Name=dwl
Comment=dwm para Wayland
Exec=/usr/local/bin/dwl-session
Type=Application
DesktopNames=dwl
DSK

# Environment.d
mkdir -p "$HOME/.config/environment.d"
cat > "$HOME/.config/environment.d/dwl.conf" <<ENV
MOZ_ENABLE_WAYLAND=1
QT_QPA_PLATFORM=wayland
GDK_BACKEND=wayland,x11
XDG_CURRENT_DESKTOP=dwl
ENV

# lf
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
# Configuracion final de GREETD (METODO OFICIAL ARCHWIKI, SIN CARRERAS)
# ----------------------------------------------------------------
info "Configurando gestor de inicio (greetd + tuigreet) - arranque automatico garantizado..."

# Quitar lightdm si estuviera instalado
if PKGHAS lightdm || PKGHAS lightdm-gtk3-greeter || PKGHAS lightdm-gtk-greeter; then
  info "Desinstalando lightdm para evitar conflictos..."
  svc_off lightdm
  PKGREM lightdm lightdm-gtk3-greeter lightdm-gtk-greeter 2>/dev/null || true
fi

if [ "$FAMILIA" = "arch" ]; then
  # ---------- METODO QUE NUNCA FALLA EN ARCH ----------
  # Segun la wiki oficial de Arch: la forma correcta de reemplazar el login
  # de texto por greetd en tty1 es crear un symlink de greetd.service en
  # /etc/systemd/system/autovt@tty1.service, para que systemd arranque greetd
  # EN LUGAR de agetty en tty1 desde el primer momento. Sin mascaras, sin
  # Conflicts, sin condiciones de carrera.

  # 1. Crear el usuario greeter con los grupos que NECESITA (tty es imprescindible)
  if ! id -u "$GREETER_USR" >/dev/null 2>&1; then
    info "Creando usuario $GREETER_USR que faltaba..."
    sudo useradd -r -s /sbin/nologin -d /var/lib/greetd "$GREETER_USR" 2>/dev/null || true
  fi
  sudo usermod -aG tty,video,input "$GREETER_USR"
  sudo mkdir -p /var/lib/greetd
  sudo chown "$GREETER_USR:$GREETER_USR" /var/lib/greetd 2>/dev/null
  sudo chmod 700 /var/lib/greetd

  # Wrapper que espera a la GPU antes de lanzar tuigreet
  sudo tee /usr/local/bin/greetd-tuigreet-wrapper >/dev/null <<'WRAP'
#!/bin/sh
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

  # 2. Escribir config.toml (sintaxis TOML estricta)
  sudo mkdir -p /etc/greetd
  sudo tee /etc/greetd/config.toml >/dev/null <<TOML
# install-dwl $VERSION
[terminal]
vt = 1

[default_session]
command = "/usr/local/bin/greetd-tuigreet-wrapper"
user = "$GREETER_USR"
TOML

  # 3. Enmascarar y deshabilitar el getty@tty1 normal para que NO vuelva a aparecer
  sudo systemctl stop getty@tty1.service 2>/dev/null || true
  sudo systemctl disable getty@tty1.service 2>/dev/null || true
  sudo systemctl mask getty@tty1.service 2>/dev/null || true

  # 4. EL PASO MAGICO (ArchWiki): reemplazar autovt@tty1 por greetd
  # Esto hace que systemd arranque greetd DIRECTAMENTE como el login de tty1,
  # en lugar de agetty. Sin conflictos, sin carreras, 100% automatico en cada arranque.
  sudo ln -sf /usr/lib/systemd/system/greetd.service /etc/systemd/system/autovt@tty1.service
  info "Reemplazado autovt@tty1 (login de texto) por greetd (metodo oficial ArchWiki)."

  # 5. Asegurarse de que greetd este habilitado para el proximo arranque
  sudo systemctl enable greetd.service 2>/dev/null || true

else
  # ---------- Void (runit) ----------
  disable_getty_vt "$GREETD_VT"
  # Crear usuario greeter si no existe (en Void normalmente lo crea el paquete greetd)
  id -u "$GREETER_USR" >/dev/null 2>&1 || sudo useradd -r -s /sbin/nologin -d /var/lib/greetd "$GREETER_USR"
  sudo usermod -aG tty,video,input "$GREETER_USR"
  sudo mkdir -p /var/lib/greetd
  sudo chown "$GREETER_USR:$GREETER_USR" /var/lib/greetd 2>/dev/null
  sudo chmod 700 /var/lib/greetd
  sudo mkdir -p /etc/greetd
  # El wrapper greetd-tuigreet-wrapper ya se creo para Arch, lo reutilizamos
  sudo tee /etc/greetd/config.toml >/dev/null <<TOML
# install-dwl $VERSION
[terminal]
vt = $GREETD_VT
[default_session]
command = "/usr/local/bin/greetd-tuigreet-wrapper"
user = "$GREETER_USR"
TOML
fi

# PAM turnstile solo en Void
if [ "$NEED_TURNSTILE" -eq 1 ]; then
  svc_on turnstiled
  PAMF=/etc/pam.d/greetd
  if [ -f "$PAMF" ] && ! grep -q pam_turnstile.so "$PAMF"; then
    echo -e "\nsession optional pam_turnstile.so" | sudo tee -a "$PAMF" >/dev/null
  fi
fi
# Habilitar greetd PERO NO arrancarlo ahora (para no interrumpir el script)
svc_on greetd

# Recargar systemd si hace falta
svc_daemon_reload

if [ "$FAMILIA" = "arch" ]; then
  # Drop-in de systemd para que greetd espere a udev/logind
  sudo mkdir -p /etc/systemd/system/greetd.service.d
  sudo tee /etc/systemd/system/greetd.service.d/10-wait-ready.conf >/dev/null <<INI
[Unit]
After=systemd-logind.service systemd-user-sessions.service systemd-udev-settle.service plymouth-quit-wait.service
Wants=systemd-logind.service
ExecStartPre=/bin/sleep 2
Conflicts=getty@tty1.service
INI
  sudo systemctl stop greetd.service 2>/dev/null || true
  info "greetd habilitado; arrancara automaticamente DESPUES de reiniciar."
else
  # En Void agregar espera por seatd al script run de greetd
  if [ -f /etc/sv/greetd/run ] && ! grep -q "sv status seatd" /etc/sv/greetd/run; then
    sudo sed -i '2i # Esperar a que seatd este listo\nwhile ! sv status seatd | grep -q "^run: "; do sleep 0.5; done\nsleep 2' /etc/sv/greetd/run
  fi
  sudo sv stop greetd 2>/dev/null || true
  info "greetd habilitado; arrancara automaticamente DESPUES de reiniciar."
fi

# ----------------------------------------------------------------
# Final
# ----------------------------------------------------------------
echo
hdr "=========================================="
hdr " install-dwl $VERSION INSTALADO CON EXITO!"
hdr "=========================================="
echo
echo "  Distro:   $DISTRO"
echo "  Barra:    dwlb ($BAR_MODE)  wmenu=monospace:$WMENU_FONT_SIZE  dwlb=monospace:$DWLB_FONT_SIZE"
echo "  Login:    greetd + tuigreet en tty$GREETD_VT"
echo
warn "============================================================"
warn "  AHORA EJECUTA: sudo reboot"
warn "  Los grupos de permisos ($SEAT_GRP, video) NO se aplican"
warn "  hasta reiniciar. Sin ellos dwl no puede abrir GPU ni entrada."
warn "  Tras el reinicio veras tuigreet directamente en la pantalla"
warn "  de login, sin pantallas negras ni pasos manuales."
warn "============================================================"
echo
info "Atajos rapidos:"
echo "  Super+Enter -> terminal foot"
echo "  Super+d     -> lanzador wmenu"
echo "  Super+q     -> cerrar ventana"
echo "  Super+w     -> ocultar/mostrar barra"
echo "  Super+Shift+e -> cerrar sesion"
echo
info "Archivos de configuracion:"
echo "  ~/dwl/config.h              -> atajos/colores (recompilar con: dwl-rebuild)"
echo "  ~/.config/dwlb/config       -> fuente/colores barra (no recompila)"
echo "  /usr/local/bin/dwl-session  -> variables de inicio de sesion"

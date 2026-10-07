#!/bin/sh
# install-dwl v0.8.5
# Instalador de dwl (dwm para Wayland) multiplataforma.
#
# Distros soportadas:
#   - Void Linux (xbps + runit)
#   - Arch Linux y derivadas: Manjaro, EndeavourOS, Garuda, Artix, Archcraft, CachyOS, ArcoLinux, Parabola.
#
# Entorno que instala:
#   dwl (compilado desde fuente, rama main) + dwlb (barra), foot, wmenu, swaybg,
#   pipewire/wireplumber, captura de pantalla, control de brillo/volumen y
#   arranque con greetd + tuigreet (desinstala/desactiva lightdm si existia).
#
# NO instala drivers de GPU ni Steam: lo haces tu segun tu hardware.
#
# Variables de entorno que puedes sobreescribir antes de ejecutar:
#   DWLB_FONT_SIZE=10 WMENU_FONT_SIZE=11 GREETD_VT=1 ./install-dwl.sh
#

set -e

# ----------------------------------------------------------------
# Colores
# ----------------------------------------------------------------
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
CYAN="\033[1;36m"
RESET="\033[0m"
info()  { printf "%b[+]%b %s\n" "$GREEN" "$RESET" "$1"; }
warn()  { printf "%b[!]%b %s\n" "$YELLOW" "$RESET" "$1"; }
error() { printf "%b[x]%b %s\n" "$RED" "$RESET" "$1"; }
hdr()   { printf "%b%s%b\n" "$CYAN" "$1" "$RESET"; }

VERSION="v0.8.5"

# ----------------------------------------------------------------
# Funciones auxiliares
# ----------------------------------------------------------------
write_config() {
    if [ -f "$1" ]; then
        warn "$1 ya existe: se conserva. Nueva copia en $1.nuevo"
        cat > "$1.nuevo" || return 1
    else
        cat > "$1" || return 1
    fi
}
fix_owner() {
    if [ "$(stat -c %U .)" != "$(id -un)" ] || [ -n "$(find . ! -user "$(id -un)" -print -quit)" ]; then
        info "Devolviendo la propiedad de $(pwd) a $(id -un)..."
        sudo chown -R "$(id -un):$(id -gn)" . || return 1
    fi
}
backup_file() {
    if [ -f "$1" ]; then
        BP="$1.bak-$(date +%Y%m%d%H%M%S)"
        sudo cp -a "$1" "$BP" && info "Backup: $BP" || return 1
    fi
}

# ----------------------------------------------------------------
# Comprobaciones iniciales
# ----------------------------------------------------------------
[ "$(id -u)" -eq 0 ] && { error "No ejecutes como root."; exit 1; }
command -v sudo >/dev/null 2>&1 || { error "Falta sudo (agrega tu usuario a sudoers)."; exit 1; }
command -v git  >/dev/null 2>&1 || { error "Falta git. Instalalo primero."; exit 1; }

# Detectar distro
DISTRO_ID="unknown"; DISTRO_FAMILIA="unknown"
[ -f /etc/os-release ] && . /etc/os-release
case "$ID" in
    void) DISTRO_FAMILIA="void" ;;
    arch|manjaro|endeavouros|garuda|artix|archcraft|cachyos|arcolinux|hyperbola|parabola|rebornos|obarun)
        DISTRO_FAMILIA="arch" ;;
    *)
        case "${ID_LIKE:-}" in
            *arch*) DISTRO_FAMILIA="arch" ;;
            *void*) DISTRO_FAMILIA="void" ;;
        esac ;;
esac
info "install-dwl $VERSION - Distro detectada: $ID (familia: $DISTRO_FAMILIA)"
[ "$DISTRO_FAMILIA" = "unknown" ] && { error "Distro no soportada. Solo Void y Arch/derivadas."; exit 1; }

# ----------------------------------------------------------------
# Constantes configurables (sobreescribibles por env)
# ----------------------------------------------------------------
DWL_REPO="${DWL_REPO:-https://codeberg.org/dwl/dwl.git}"
DWLB_REPO="${DWLB_REPO:-https://github.com/kolunmi/dwlb.git}"
WALLPAPER_DIR="$HOME/Pictures"
WALLPAPER_PATH="${WALLPAPER_PATH:-$WALLPAPER_DIR/wallpaper.jpg}"
WALLPAPER_URL="${WALLPAPER_URL:-https://wallpapercave.com/download/empty-error-wallpapers-wp8330753}"

# Tamaños de fuente alineados
WMENU_FONT_SIZE="${WMENU_FONT_SIZE:-11}"
DWLB_FONT_SIZE="${DWLB_FONT_SIZE:-10}"
DWLB_FONT="${DWLB_FONT:-monospace:size=$DWLB_FONT_SIZE}"
DWLB_PAD="${DWLB_PAD:--2}"
DWLB_HPAD="${DWLB_HPAD:-6}"

# Colores (Catppuccin Mocha por defecto)
DWLB_ACTIVE_FG="${DWLB_ACTIVE_FG:-#ffffff}"
DWLB_ACTIVE_BG="${DWLB_ACTIVE_BG:-#89b4fa}"
DWLB_OCCUPIED_FG="${DWLB_OCCUPIED_FG:-#cdd6f4}"
DWLB_OCCUPIED_BG="${DWLB_OCCUPIED_BG:-#313244}"
DWLB_INACTIVE_FG="${DWLB_INACTIVE_FG:-#a6adc8}"
DWLB_INACTIVE_BG="${DWLB_INACTIVE_BG:-#1e1e2e}"
DWLB_URGENT_FG="${DWLB_URGENT_FG:-#1e1e2e}"
DWLB_URGENT_BG="${DWLB_URGENT_BG:-#f38ba8}"

# ----------------------------------------------------------------
# Definir funciones y paquetes SEGUN DISTRO
# ----------------------------------------------------------------
if [ "$DISTRO_FAMILIA" = "void" ]; then
    # -------- Void Linux (xbps + runit) --------
    PKG_INSTALL() { sudo xbps-install -Sy "$@"; }
    PKG_QUERY()   { xbps-query "$1" >/dev/null 2>&1; }
    PKG_REMOVE()  { sudo xbps-remove -R "$@"; }
    DEFAULT_GREETD_VT=7
    SEAT_GROUP="_seatd"
    GREETER_USER="_greeter"
    HAS_RC_CONF=1
    HAS_VCONSOLE=0
    USES_SYSTEMD=0
    NEED_TURNSTILE=1
    WLR_PKG="wlroots"
    WLR_DEV_PKG="wlroots-devel"
    SEAT_PKG="libseat libseat-devel seatd"
    FONT_PKG="nerd-fonts"
    GREETER_PKGS="greetd tuigreet turnstile"
    PULSE_PKG="alsa-pipewire"
    MESA_PKG="mesa-dri libdrm-devel"
    DEVEL_SUFFIX="-devel"

    PKGS_BASE="base-devel file pkg-config \
        libinput libinput-devel void-repo-nonfree void-repo-multilib void-repo-multilib-nonfree \
        wayland wayland-devel wayland-protocols libxkbcommon libxkbcommon-devel \
        $WLR_PKG $WLR_DEV_PKG $SEAT_PKG \
        xorg-server-xwayland $MESA_PKG pango-devel cairo-devel pixman pixman-devel fcft fcft-devel tllist \
        foot wmenu fastfetch pipewire wireplumber $PULSE_PKG \
        swaybg swaylock grim slurp wl-clipboard brightnessctl curl procps-ng \
        nano $FONT_PKG lf mpv zathura zathura-pdf-poppler xdg-utils imv \
        chrony firefox btop cowsay dbus pciutils $GREETER_PKGS"

    enable_svc() {
        if [ -L "/var/service/$1" ]; then
            [ -d "/etc/sv/$1" ] && info "Servicio $1 ya habilitado." || { error "Enlace roto en /var/service/$1"; return 1; }
        elif [ -d "/etc/sv/$1" ]; then
            sudo ln -s "/etc/sv/$1" /var/service/ && info "Servicio $1 habilitado (runit)."
        else
            warn "/etc/sv/$1 no existe; activalo a mano."; return 1
        fi
    }
    disable_svc() {
        if [ -L "/var/service/$1" ]; then
            sudo sv stop "$1" 2>/dev/null || true
            sudo rm -f "/var/service/$1"
            info "Servicio $1 desactivado."
        fi
    }
    start_svc()   { sudo sv start "$1"; }
    disable_getty(){ VT="$1"; [ -L "/var/service/agetty-tty$VT" ] && disable_svc "agetty-tty$VT"; }

    for cmd in xbps-install xbps-query sv; do
        command -v "$cmd" >/dev/null || { error "Falta $cmd (runit/xbps no estan instalados?)."; exit 1; }
    done
    [ -d /var/service ] || { error "No existe /var/service."; exit 1; }

elif [ "$DISTRO_FAMILIA" = "arch" ]; then
    # -------- Arch Linux (pacman + systemd) --------
    PKG_INSTALL() { sudo pacman -Sy --needed --noconfirm "$@"; }
    PKG_QUERY()   { pacman -Q "$1" >/dev/null 2>&1; }
    PKG_REMOVE()  { sudo pacman -Rns --noconfirm "$@"; }
    DEFAULT_GREETD_VT=1
    SEAT_GROUP="seat"
    GREETER_USER="greeter"
    HAS_RC_CONF=0
    HAS_VCONSOLE=1
    USES_SYSTEMD=1
    NEED_TURNSTILE=0   # pam_systemd ya hace XDG_RUNTIME_DIR
    # Detectar automaticamente la version mas nueva de wlroots disponible en los repos
    # para no hardcodear wlroots0.19 y romperlo cuando salga 0.20+.
    WLR_PKG=$(pacman -Ssq '^wlroots[0-9]*\.[0-9]+$' 2>/dev/null | sort -V | tail -n1)
    [ -z "$WLR_PKG" ] && WLR_PKG="wlroots0.19"
    info "Paquete wlroots detectado en repos: $WLR_PKG"
    SEAT_PKG="seatd"    # libseat viene DENTRO de seatd en Arch, no es un paquete separado
    FONT_PKG="ttf-nerd-fonts-symbols ttf-nerd-fonts-symbols-mono"
    GREETER_PKGS="greetd greetd-tuigreet"
    PULSE_PKG="pipewire-alsa pipewire-pulse"
    MESA_PKG="mesa libdrm"
    DEVEL_SUFFIX=""     # En Arch los headers vienen en el mismo paquete

    PKGS_BASE="base-devel libinput wayland wayland-protocols libxkbcommon \
        $WLR_PKG xcb-util-errors xcb-util-renderutil xcb-util-wm $SEAT_PKG \
        xorg-xwayland $MESA_PKG pango cairo pixman fcft tllist \
        foot wmenu fastfetch pipewire wireplumber $PULSE_PKG \
        swaybg swaylock grim slurp wl-clipboard brightnessctl curl procps-ng \
        nano $FONT_PKG lf mpv zathura zathura-pdf-poppler xdg-utils imv \
        chrony firefox btop cowsay dbus pciutils $GREETER_PKGS"

    if ! grep -qE '^\[multilib\]' /etc/pacman.conf; then
        warn "[multilib] no esta habilitado en /etc/pacman.conf. Lo necesitaras para Steam/32 bits."
    fi

    enable_svc() {
        if systemctl is-enabled --quiet "$1" 2>/dev/null; then
            info "Servicio $1 ya habilitado (systemd)."
        else
            sudo systemctl enable "$1" && info "Servicio $1 habilitado (systemd)."
        fi
    }
    disable_svc() {
        systemctl is-enabled --quiet "$1" 2>/dev/null && { sudo systemctl disable --now "$1" 2>/dev/null; info "Servicio $1 desactivado."; }
    }
    start_svc()   { sudo systemctl start "$1"; }
    disable_getty(){ VT="$1"; local g="getty@tty${VT}.service"; systemctl is-enabled --quiet "$g" 2>/dev/null && { warn "Desactivando $g para que greetd use tty$VT"; sudo systemctl disable --now "$g" 2>/dev/null || true; }; }

    command -v pacman >/dev/null || { error "Falta pacman."; exit 1; }
fi

GREETD_VT="${GREETD_VT:-$DEFAULT_GREETD_VT}"
case "$GREETD_VT" in
    ''|*[!0-9]*) error "GREETD_VT debe ser un numero entre 1 y 12."; exit 1 ;;
esac
[ "$GREETD_VT" -lt 1 ] || [ "$GREETD_VT" -gt 12 ] && { error "GREETD_VT entre 1 y 12."; exit 1; }

# Espacio libre
FREE_GB=$(df -BG --output=avail "$HOME" 2>/dev/null | tail -n1 | tr -d 'G ')
if [ -n "$FREE_GB" ] && [ "$FREE_GB" -lt 5 ] 2>/dev/null; then
    error "Menos de 5GB libres en $HOME, cancela."; exit 1
elif [ -n "$FREE_GB" ] && [ "$FREE_GB" -lt 20 ] 2>/dev/null; then
    warn "Solo ${FREE_GB}GB libres (recomendado >=20GB). Continuar? [y/N] "
    read -r c; case "$c" in y|Y) ;; *) exit 1;; esac
fi

# ----------------------------------------------------------------
# Menú principal
# ----------------------------------------------------------------
echo "=========================================="
printf "  install-dwl %s\n" "$VERSION"
echo "=========================================="
echo "Distro:      $DISTRO_ID"
echo "Barra:       dwlb"
echo "Login:       greetd + tuigreet"
echo "(lightdm se desactivara/desinstalara si existe)"
echo "(drivers GPU/Steam NO se instalan automaticamente)"
echo ""
echo " 1) Instalar dwl + entorno Wayland"
echo " 2) Salir"
printf "Opcion [1-2]: "
read -r OPCION
case "$OPCION" in 1) ;; 2) info "Saliendo."; exit 0 ;; *) error "Opcion invalida."; exit 1;; esac

# ----------------------------------------------------------------
# Deteccion de GPU
# ----------------------------------------------------------------
detectar_gpus() {
    command -v lspci >/dev/null || { info "Instalando pciutils..."; PKG_INSTALL pciutils || return 1; }
    GL=$(lspci -nn | grep -iE 'vga|3d controller|display controller' || true)
    GPU_VENDORS=""
    echo "$GL" | grep -qiE 'NVIDIA|\[10de:'   && GPU_VENDORS="$GPU_VENDORS nvidia"
    echo "$GL" | grep -qiE 'AMD|Radeon|\[1002:'&& GPU_VENDORS="$GPU_VENDORS amd"
    echo "$GL" | grep -qiE 'Intel|\[8086:'    && GPU_VENDORS="$GPU_VENDORS intel"
    GPU_VENDORS=$(echo "$GPU_VENDORS" | sed 's/^ //')
    [ -z "$GPU_VENDORS" ] && GPU_VENDORS="desconocida"
    GPU_CARDS=$(ls -1 /dev/dri/card* 2>/dev/null | sort -V | tr '\n' ':' | sed 's/:$//')
    GPU_HIBRIDA=0; [ "$(echo "$GL" | grep -c .)" -ge 2 ] && GPU_HIBRIDA=1
    info "GPUs detectadas:"; echo "$GL" | sed 's/^/    /'
    info "Fabricantes: $GPU_VENDORS"
    [ -n "$GPU_CARDS" ] && info "Nodos DRM: $GPU_CARDS"
    return 0
}

# ----------------------------------------------------------------
# Compilar dwlb
# ----------------------------------------------------------------
compilar_dwlb() {
    cd "$HOME"
    [ -d dwlb ] || { info "Clonando dwlb..."; git clone "$DWLB_REPO" || return 1; }
    cd "$HOME/dwlb"; fix_owner
    [ -f config.def.h ] && [ ! -f config.h ] && cp config.def.h config.h
    # Parche de version de layer-shell por si acaso
    if grep -qE 'zwlr_layer_shell_v1_interface, [0-9]+\)' dwlb.c 2>/dev/null; then
        V=$(grep -oE 'zwlr_layer_shell_v1_interface, [0-9]+\)' dwlb.c | head -n1 | sed -n 's/.*, *\([0-9]*\))/\1/p')
        if [ -n "$V" ] && [ "$V" -gt 1 ]; then
            sed -i "s|&zwlr_layer_shell_v1_interface, $V)|\&zwlr_layer_shell_v1_interface, (version < $V ? version : $V))|" dwlb.c
        fi
    fi
    make clean 2>/dev/null || true
    make || { error "Error compilando dwlb."; return 1; }
    sudo make install || return 1
    [ -f dwlb.1 ] && [ ! -f /usr/local/share/man/man1/dwlb.1 ] && { sudo mkdir -p /usr/local/share/man/man1; sudo cp dwlb.1 /usr/local/share/man/man1/dwlb.1; }
    command -v dwlb >/dev/null || { error "dwlb no esta en el PATH."; return 1; }
    return 0
}

# ----------------------------------------------------------------
# Configurar dwlb
# ----------------------------------------------------------------
configurar_dwlb() {
    info "Configurando dwlb (fuente $DWLB_FONT_SIZE, pad ${DWLB_PAD}px)..."
    mkdir -p "$HOME/.config/dwlb"
    write_config "$HOME/.config/dwlb/config" <<EOF
# dwlb config (install-dwl $VERSION)
-font $DWLB_FONT
-vertical-padding $DWLB_PAD
-horizontal-padding $DWLB_HPAD
-hide-vacant-tags
-center-title
-status-commands
-no-bottom
-no-hidden
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
E="89b4fa"; T="cdd6f4"; A="f38ba8"
vol(){ command -v wpctl >/dev/null || return 0; I=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null)||return 0
      V=$(echo "$I"|awk '{printf "%d",$2*100}')
      case "$I" in *MUTED*) printf '^fg(%s)VOL^fg(%s) mudo  ' "$E" "$A";; *) printf '^fg(%s)VOL^fg(%s) %s%%  ' "$E" "$T" "$V";; esac; }
bat(){ for B in /sys/class/power_supply/BAT*; do [ -r "$B/capacity" ]||continue; C=$(cat "$B/capacity"); S=$(cat "$B/status")
      case "$S" in Charging)i="+";;Full)i="=";;*)i="-";;esac; [ "$C" -le 15 ]&&[ "$S" != Charging ]&&c="$A"||c="$T"
      printf '^fg(%s)BAT^fg(%s) %s%s%%  ' "$E" "$c" "$i" "$C"; break; done; }
cpu(){ [ -r /proc/loadavg ]&&printf '^fg(%s)CPU^fg(%s) %s  ' "$E" "$T" "$(cut -d' ' -f1 /proc/loadavg)"; }
ram(){ [ -r /proc/meminfo ]&&awk -v e="$E" -v t="$T" '/^MemTotal:/{to=$2}/^MemAvailable:/{d=$2}END{if(to)printf "^fg(%s)RAM^fg(%s) %.1fG  ",e,t,(to-d)/1048576}' /proc/meminfo; }
fecha(){ printf '^lm(foot -e sh -c "cal -3; read x")^mm(foot)^fg(%s)%s^fg()^mm()^lm()' "$T" "$(date '+%a %d/%m %H:%M')"; }
while :; do printf '^mm(foot)%s%s%s%s%s^mm()\n' "$(cpu)$(ram)$(vol)$(bat)$(fecha)"; sleep 5; done
STAT
    sudo chmod +x /usr/local/bin/dwlb-status
}

# ----------------------------------------------------------------
# Configurar greetd
# ----------------------------------------------------------------
configurar_greetd() {
    # Quitar lightdm si esta
    for pkg in lightdm lightdm-gtk3-greeter lightdm-gtk-greeter; do
        if PKG_QUERY "$pkg"; then
            info "Desinstalando lightdm..."; disable_svc lightdm; PKG_REMOVE lightdm lightdm-gtk3-greeter lightdm-gtk-greeter 2>/dev/null||true; break
        fi
    done

    SESSION_CMD="/usr/local/bin/dwl-session"
    sudo mkdir -p /etc/greetd
    backup_file /etc/greetd/config.toml
    sudo tee /etc/greetd/config.toml <<EOF
# Generado por install-dwl $VERSION
[terminal]
vt = $GREETD_VT
[default_session]
command = "tuigreet --time --time-format '%H:%M  %d/%m/%Y' --user-menu --remember --greeting 'Bienvenido a dwl' --power-shutdown 'shutdown -h now' --power-reboot 'shutdown -r now' --cmd $SESSION_CMD"
user = "$GREETER_USER"
EOF
    info "/etc/greetd/config.toml escrito."

    if [ "$NEED_TURNSTILE" -eq 1 ]; then
        info "Habilitando turnstiled para XDG_RUNTIME_DIR..."
        enable_svc turnstiled || warn "No se pudo habilitar turnstiled."
        PAM=/etc/pam.d/greetd
        if [ -f "$PAM" ] && ! grep -q pam_turnstile.so "$PAM" 2>/dev/null; then
            backup_file "$PAM"
            printf '\nsession optional pam_turnstile.so\n' | sudo tee -a "$PAM" >/dev/null
        fi
    else
        info "pam_systemd ya gestiona XDG_RUNTIME_DIR; turnstile no es necesario."
    fi

    disable_getty "$GREETD_VT"
}

iniciar_greetd() {
    [ -x /usr/local/bin/dwl-session ] || { error "No existe dwl-session."; return 1; }
    enable_svc greetd || { error "No pude habilitar greetd."; return 1; }
    info "Arrancando greetd..."
    start_svc greetd || { error "No se pudo iniciar greetd."; return 1; }
    info "greetd corriendo en tty$GREETD_VT."
}

detectar_hardware() {
    ES_VM=0
    grep -qw hypervisor /proc/cpuinfo 2>/dev/null && {
        ES_VM=1; VM=$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo "desconocida")
        warn "Maquina virtual detectada ($VM). Si falla el renderizado se reintentara con pixman.";
    }
    info "Fuente wmenu: monospace $WMENU_FONT_SIZE  |  dwlb: monospace $DWLB_FONT_SIZE"
    EXTRA_ENV=""
    [ "$ES_VM" -eq 1 ] && EXTRA_ENV="export WLR_NO_HARDWARE_CURSORS=1"
}

# ----------------------------------------------------------------
# Instalacion base
# ----------------------------------------------------------------
instalar_base() {
    info "Kernel: $(uname -r)"

    # Pregunta por kernel nuevo solo en Void
    if [ "$DISTRO_FAMILIA" = "void" ]; then
        NEWK=$(xbps-query --regex -Rs '^linux7\.[0-9]+' 2>/dev/null | awk '{print $2}' | sort -V | tail -n1)
        if [ -n "$NEWK" ]; then
            NEWK_NAME=$(echo "$NEWK" | sed 's/-7\..*$//')
            info "Kernel 7.x disponible: $NEWK_NAME"
            printf "  1) Conservar kernel actual (por defecto)\n  2) Instalar $NEWK_NAME junto al actual\nOpcion: "
            read -r ok; ok="${ok:-1}"
            [ "$ok" = "2" ] && { PKG_INSTALL "$NEWK_NAME" || warn "No se pudo instalar."; }
        fi
    fi

    info "Instalando paquetes..."
    PKG_INSTALL $PKGS_BASE || { error "Fallo la instalacion de paquetes. Revisa tu conexion o repositorios."; return 1; }

    info "Habilitando servicios base..."
    enable_svc dbus || warn "Fallo dbus."
    enable_svc chronyd || warn "Fallo chronyd."
    [ "$DISTRO_FAMILIA" = "void" ] && enable_svc seatd

    REAL_USER=$(id -un)
    getent group "$SEAT_GROUP" >/dev/null || { error "No existe el grupo $SEAT_GROUP. Reinstala seatd."; return 1; }
    sudo usermod -aG "$SEAT_GROUP" "$REAL_USER" || { error "No pude agregar $REAL_USER al grupo $SEAT_GROUP."; return 1; }
    getent group video >/dev/null && sudo usermod -aG video "$REAL_USER"
    warn "Los grupos nuevos ($SEAT_GROUP, video) solo se aplican tras reiniciar sesion."

    detectar_hardware
    detectar_gpus || warn "Deteccion de GPU fallida, sigo."

    # Zona horaria
    info "Configurando zona horaria..."
    printf "Pais (vacio = Colombia): "; read -r pais; pais="${pais:-Colombia}"
    pais_n=$(echo "$pais" | tr '[:upper:]' '[:lower:]' | sed 's/á/a/g;s/é/e/g;s/í/i/g;s/ó/o/g;s/ú/u/g;s/ñ/n/g')
    case "$pais_n" in
        colombia)tz=America/Bogota;; mexico)tz=America/Mexico_City;; argentina)tz=America/Buenos_Aires;;
        chile)tz=America/Santiago;; peru)tz=America/Lima;; espana|spain)tz=Europe/Madrid;;
        "estados unidos"|usa)tz=America/New_York;; */*)tz="$pais";; *)tz="";;
    esac
    if [ -n "$tz" ] && [ -f "/usr/share/zoneinfo/$tz" ]; then
        sudo ln -sf "/usr/share/zoneinfo/$tz" /etc/localtime
        echo "$tz" | sudo tee /etc/timezone >/dev/null 2>&1
        [ "$HAS_RC_CONF" -eq 1 ] && {
            grep -q TIMEZONE /etc/rc.conf && sudo sed -i "s|^.*TIMEZONE=.*|TIMEZONE=\"$tz\"|" /etc/rc.conf || echo "TIMEZONE=\"$tz\"" | sudo tee -a /etc/rc.conf >/dev/null;
        }
        info "Zona horaria: $tz"
    else
        warn "Pais no reconocido, se deja la hora como esta."
    fi

    # Teclado
    info "Teclado: 1=us, 2=es, 3=latam (defecto 3)"
    printf "Opcion: "; read -r k; k="${k:-3}"
    case "$k" in 1)kb=us;kc=us;;2)kb=es;kc=es;;3)kb=latam;kc=la-latin1;;esac
    if [ "$HAS_RC_CONF" -eq 1 ]; then
        grep -q KEYMAP /etc/rc.conf && sudo sed -i "s|^.*KEYMAP=.*|KEYMAP=\"$kc\"|" /etc/rc.conf || echo "KEYMAP=\"$kc\"" | sudo tee -a /etc/rc.conf >/dev/null;
    fi
    if [ "$HAS_VCONSOLE" -eq 1 ]; then
        backup_file /etc/vconsole.conf
        grep -q ^KEYMAP= /etc/vconsole.conf && sudo sed -i "s|^KEYMAP=.*|KEYMAP=$kc|" /etc/vconsole.conf || echo "KEYMAP=$kc" | sudo tee -a /etc/vconsole.conf >/dev/null;
    fi
    command -v loadkeys >/dev/null && sudo loadkeys "$kc" 2>/dev/null || true
    KB_XKB="$kb"

    # Compilar dwl
    cd "$HOME"
    [ -d dwl ] || { info "Clonando dwl..."; git clone "$DWL_REPO"; }
    cd dwl; fix_owner
    if [ -f protocols/dwl-ipc-unstable-v2.xml ] || [ -f protocols/dwl-ipc-unstable-v1.xml ]; then
        DWLB_IPC=1; info "dwl incluye IPC: dwlb usara -ipc (clics en tags funcionales)."
    else
        DWLB_IPC=0; info "dwl sin IPC: dwlb usara -no-ipc."
    fi
    # Regenerar config.h si es API antigua
    if [ -f config.h ] && { grep -q 'static const char \*tags\[\]' config.h || ! grep -q 'TAGCOUNT' config.h || ! grep -q 'axes\[\]' config.h; }; then
        VIEJO=config.h.old-$(date +%Y%m%d%H%M%S)
        warn "Tu config.h es de la API vieja; lo guardo como $VIEJO y genero uno nuevo."
        mv config.h "$VIEJO"
    fi
    if [ -f config.h ]; then
        warn "Se conserva tu config.h existente. Si no compila borralo y vuelve a ejecutar."
    else
        info "Generando config.h (layout $KB_XKB)..."
        cat > config.h <<EOF
/* dwl config.h (install-dwl $VERSION) */
#define COLOR(hex) { ((hex>>24)&0xFF)/255.0f,((hex>>16)&0xFF)/255.0f,((hex>>8)&0xFF)/255.0f,(hex&0xFF)/255.0f }
static const int sloppyfocus=1,bypass_surface_visibility=0;
static const unsigned int borderpx=2,snap=32;
static const float rootcolor[]=COLOR(0x1e1e2eff),bordercolor[]=COLOR(0x313244ff),focuscolor[]=COLOR(0x89b4faff),urgentcolor[]=COLOR(0xf38ba8ff),fullscreen_bg[]={0,0,0,1};
#define TAGCOUNT (9)
static int log_level=WLR_ERROR;
static const Rule rules[]={{"Gimp",NULL,0,1,-1},{"firefox",NULL,1<<0,0,-1}};
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
static const char *term[]={"foot",NULL},*browser[]={"firefox",NULL},
*dmenu[]={"sh","-c","dwlb -toggle-visibility all; wmenu-run -f 'monospace $WMENU_FONT_SIZE' -N 1e1e2e -n cdd6f4 -S 89b4fa -s ffffff; dwlb -toggle-visibility all",NULL},
*upvol[]={"wpctl","set-volume","@DEFAULT_AUDIO_SINK@","3%+","-l","1.0",NULL},*downvol[]={"wpctl","set-volume","@DEFAULT_AUDIO_SINK@","3%-",NULL},
*mutevol[]={"wpctl","set-mute","@DEFAULT_AUDIO_SINK@","toggle",NULL},*brup[]={"brightnessctl","set","+5%",NULL},*brdown[]={"brightnessctl","set","5%-",NULL},
*ss[]={"sh","-c","grim ~/Pictures/\$(date +%Y%m%d_%H%M%S).png",NULL},
*bart[]={"dwlb","-toggle-visibility","all",NULL};
static const Key keys[]={
{MODKEY,XKB_KEY_Return,spawn,{.v=term}},{MODKEY,XKB_KEY_d,spawn,{.v=dmenu}},{MODKEY,XKB_KEY_b,spawn,{.v=browser}},
{MODKEY,XKB_KEY_q,killclient,{0}},{MODKEY,XKB_KEY_j,focusstack,{.i=+1}},{MODKEY,XKB_KEY_k,focusstack,{.i=-1}},
{MODKEY,XKB_KEY_h,setmfact,{.f=-0.05f}},{MODKEY,XKB_KEY_l,setmfact,{.f=+0.05f}},{MODKEY,XKB_KEY_w,spawn,{.v=bart}},
{MODKEY,XKB_KEY_f,setlayout,{.v=&layouts[2]}},{MODKEY,XKB_KEY_space,setlayout,{0}},
TAGKEYS(XKB_KEY_1,XKB_KEY_exclam,0),TAGKEYS(XKB_KEY_2,XKB_KEY_quotedbl,1),TAGKEYS(XKB_KEY_3,XKB_KEY_numbersign,2),
TAGKEYS(XKB_KEY_4,XKB_KEY_dollar,3),TAGKEYS(XKB_KEY_5,XKB_KEY_percent,4),TAGKEYS(XKB_KEY_6,XKB_KEY_ampersand,5),
TAGKEYS(XKB_KEY_7,XKB_KEY_slash,6),TAGKEYS(XKB_KEY_8,XKB_KEY_parenleft,7),TAGKEYS(XKB_KEY_9,XKB_KEY_parenright,8),
{MODKEY,XKB_KEY_Tab,view,{0}},{MODKEY,XKB_KEY_0,view,{.ui=~0}},
{0,XKB_KEY_XF86AudioRaiseVolume,spawn,{.v=upvol}},{0,XKB_KEY_XF86AudioLowerVolume,spawn,{.v=downvol}},
{0,XKB_KEY_XF86AudioMute,spawn,{.v=mutevol}},{0,XKB_KEY_XF86MonBrightnessUp,spawn,{.v=brup}},
{0,XKB_KEY_XF86MonBrightnessDown,spawn,{.v=brdown}},{0,XKB_KEY_Print,spawn,{.v=ss}},
{MODKEY|WLR_MODIFIER_SHIFT,XKB_KEY_E,quit,{0}}
};
static const Button buttons[]={{MODKEY,BTN_LEFT,moveresize,{.ui=CurMove}},{MODKEY,BTN_MIDDLE,togglefloating,{0}},{MODKEY,BTN_RIGHT,moveresize,{.ui=CurResize}}};
static const Axis axes[]={{MODKEY,AxisUp,spawn,{.v=upvol}},{MODKEY,AxisDown,spawn,{.v=downvol}}};
EOF
    fi
    info "Compilando dwl..."
    make clean 2>/dev/null || true
    if ! make; then
        error "Error compilando dwl. Si el error menciona version de wlroots, instala la version que necesites"
        error "  Arch: sudo pacman -S wlroots0.18   (o wlroots0.19 / wlroots0.17)"
        error "  Void: sudo xbps-install -S wlroots-devel"
        return 1
    fi
    sudo make install

    # Compilar dwlb
    BARRA=""; DWLB_MODO="-no-ipc"
    if compilar_dwlb; then BARRA="dwlb"; configurar_dwlb; fi
    [ "$BARRA" = "dwlb" ] && [ "$DWLB_IPC" -eq 1 ] && DWLB_MODO="-ipc"

    # Status runner
    sudo tee /usr/local/bin/dwl-status-runner >/dev/null <<'RUN'
#!/bin/sh
exec 3<&0 || exit 1; H=""; PB=""
clean(){ for p in $H; do kill "$p" 2>/dev/null; done; for p in $H; do wait "$p" 2>/dev/null; done; H=""; }
trap clean EXIT; trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM
[ -n "$DWL_WALLPAPER" ] && [ -f "$DWL_WALLPAPER" ] && command -v swaybg >/dev/null && { swaybg -i "$DWL_WALLPAPER" -m fill </dev/null >/dev/null 2>&1 & H="$H $!"; }
case "$DWL_BAR_KIND" in
 dwlb)
  if [ "$DWL_BAR_MODE" = "-ipc" ]; then cat <&3 >/dev/null & H="$H $!"; dwlb -ipc </dev/null &
                               else dwlb -no-ipc <&3 & fi
  PB=$!; H="$H $PB"
  command -v dwlb-status >/dev/null && { sleep 1; (dwlb-status | dwlb -status-stdin all) </dev/null >/dev/null 2>&1 & H="$H $!"; } ;;
 *) cat <&3 >/dev/null & PB=$!; H="$H $PB" ;;
esac
wait "$PB"; E=$?; clean; exit $E
RUN
    sudo chmod +x /usr/local/bin/dwl-status-runner

    # Wallpaper
    mkdir -p "$WALLPAPER_DIR"
    if [ ! -f "$WALLPAPER_PATH" ]; then
        info "Descargando wallpaper..."
        T="$WALLPAPER_PATH.tmp"
        if curl -fsSL --max-time 20 -A "Mozilla/5.0" -e https://wallpapercave.com/ -o "$T" "$WALLPAPER_URL" && file "$T" | grep -qi image; then
            mv "$T" "$WALLPAPER_PATH"
        else
            warn "No se pudo descargar wallpaper (se verá fondo solido)."; rm -f "$T"
        fi
    fi

    # lf config
    mkdir -p "$HOME/.config/lf"
    write_config "$HOME/.config/lf/lfrc" <<'LFRC'
set ifs "\n"
cmd open ${{
 case $(file --mime-type -Lb "$f") in
  text/*|application/json|inode/x-empty) nano $fx ;;
  image/*) setsid -f imv $fx >/dev/null 2>&1 ;;
  video/*|audio/*) setsid -f mpv $fx >/dev/null 2>&1 ;;
  application/pdf) setsid -f zathura $fx >/dev/null 2>&1 ;;
  *) for f in $fx; do setsid -f xdg-open "$f" >/dev/null 2>&1; done ;;
 esac
}}
LFRC

    # Wrapper de sesion
    sudo tee /usr/local/bin/dwl-session >/dev/null <<EOF
#!/bin/sh
# dwl-session (install-dwl $VERSION)
export XDG_SESSION_TYPE=wayland XDG_CURRENT_DESKTOP=dwl XDG_SESSION_DESKTOP=dwl
export MOZ_ENABLE_WAYLAND=1 QT_QPA_PLATFORM=wayland GDK_BACKEND=wayland,x11
export DWL_BAR_KIND="$BARRA" DWL_BAR_MODE="$DWLB_MODO" DWL_WALLPAPER="$WALLPAPER_PATH"
SU=\$(id -u)
[ -d "\$XDG_RUNTIME_DIR" ] && [ "\$(stat -c %u "\$XDG_RUNTIME_DIR" 2>/dev/null)" = "\$SU" ] && chmod 700 "\$XDG_RUNTIME_DIR" 2>/dev/null || {
  R="/run/user/\$SU"
  [ ! -d "\$R" ] || [ "\$(stat -c %u "\$R" 2>/dev/null)" != "\$SU" ] && { R="\$HOME/.xdg-runtime"; mkdir -p "\$R"; chmod 700 "\$R"; }
  export XDG_RUNTIME_DIR="\$R"
}
DP=""; DWL_PID=""
ud(){ n="\$1"; shift; pgrep -u "\$SU" -x "\$n" >/dev/null && return 0; command -v "\$n" >/dev/null && { "\$@" >/dev/null 2>&1 & DP="\$DP \$!"; }; }
clean(){ for p in \$DP; do kill "\$p" 2>/dev/null; done; for p in \$DP; do wait "\$p" 2>/dev/null; done; DP=""; }
end(){ [ -n "\$DWL_PID" ] && kill "\$DWL_PID" 2>/dev/null; exit "\$1"; }
trap clean EXIT; trap 'end 129' HUP; trap 'end 130' INT; trap 'end 143' TERM
ud pipewire pipewire; ud wireplumber wireplumber; command -v pipewire-pulse >/dev/null && ud pipewire-pulse pipewire-pulse
$EXTRA_ENV
IN=\$(date +%s)
dwl -s /usr/local/bin/dwl-status-runner & DWL_PID=\$!
wait "\$DWL_PID"; ST=\$?; DWL_PID=""
if [ "\$ST" -ne 0 ] && [ -z "\$WLR_RENDERER" ] && [ \$((\$(date +%s)-IN)) -lt 5 ]; then
 echo "Reintentando con render por software (pixman)..." >&2
 export WLR_RENDERER=pixman WLR_NO_HARDWARE_CURSORS=1 LIBGL_ALWAYS_SOFTWARE=1
 dwl -s /usr/local/bin/dwl-status-runner & DWL_PID=\$!; wait "\$DWL_PID"; ST=\$?; DWL_PID=""
fi
clean; exit "\$ST"
EOF
    sudo chmod +x /usr/local/bin/dwl-session

    # Ajustes por GPU detectada
    echo "$GPU_VENDORS" | grep -q nvidia && {
        info "GPU NVIDIA: desactivando cursores hardware."
        sudo sed -i 's|^IN=|export WLR_NO_HARDWARE_CURSORS=1\nIN=|' /usr/local/bin/dwl-session
    }
    [ "$GPU_HIBRIDA" -eq 1 ] && [ -n "$GPU_CARDS" ] && {
        info "GPU hibrida detectada; dejo WLR_DRM_DEVICES como comentario en el wrapper."
        sudo sed -i "s|^IN=|# Hibrida: descomenta para forzar GPU:\n# export WLR_DRM_DEVICES=$GPU_CARDS\nIN=|" /usr/local/bin/dwl-session
    }

    # Scripts de rebuild
    sudo tee /usr/local/bin/dwl-rebuild >/dev/null <<'RB'
#!/bin/sh
set -e; cd "$HOME/dwl"; make clean; make; sudo make install; echo "Listo. Reinicia la sesion."
RB
    sudo chmod +x /usr/local/bin/dwl-rebuild
    sudo tee /usr/local/bin/dwlb-rebuild >/dev/null <<'RB2'
#!/bin/sh
set -e; cd "$HOME/dwlb"; git pull --ff-only; make clean; make; sudo make install; echo "Listo. Reinicia la sesion."
RB2
    sudo chmod +x /usr/local/bin/dwlb-rebuild

    # Entrada de sesion para el menu F3
    sudo mkdir -p /usr/share/wayland-sessions
    sudo tee /usr/share/wayland-sessions/dwl.desktop >/dev/null <<DESK
[Desktop Entry]
Name=dwl
Comment=dwm para Wayland
Exec=/usr/local/bin/dwl-session
Type=Application
DesktopNames=dwl
DESK

    # Entorno de usuario (systemd environment.d para que todas las apps hereden las vars)
    mkdir -p "$HOME/.config/environment.d"
    write_config "$HOME/.config/environment.d/dwl.conf" <<ENV
# Variables de entorno para dwl (install-dwl $VERSION)
MOZ_ENABLE_WAYLAND=1
QT_QPA_PLATFORM=wayland
GDK_BACKEND=wayland,x11
XDG_CURRENT_DESKTOP=dwl
ENV

    # Chuleta de atajos
    write_config "$HOME/Atajos.txt" <<ATAJOS
==================== ATAJOS DWL ($VERSION) ====================
Super+Enter .......... terminal (foot)
Super+d .............. lanzador (wmenu)
Super+b .............. firefox
Super+q .............. cerrar ventana
Super+j/k ............ cambiar ventana enfocada
Super+h/l ............ cambiar tamaño del area maestra
Super+w .............. ocultar/mostrar barra dwlb
Super+f .............. monocle (pantalla completa sin ocultar barra)
Super+(1-9) .......... ir al tag N
Super+Shift+(1-9) .... mandar ventana al tag N
Super+Shift+e ........ cerrar sesion
Ctrl+Alt+F1..F12 ..... cambiar de tty (consola de emergencia)
ATAJOS

    info "Instalacion base completada."
}

# ----------------------------------------------------------------
# Lanzar todo
# ----------------------------------------------------------------
instalar_base
configurar_greetd
iniciar_greetd

echo
hdr "=========================================="
hdr " install-dwl $VERSION instalado!"
hdr "=========================================="
echo "Distro:  $DISTRO_ID"
echo "Barra:   ${BARRA:-sin barra} ($DWLB_MODO)"
echo "Tamaños: wmenu=$WMENU_FONT_SIZE / dwlb=$DWLB_FONT_SIZE"
echo "VT:      tty$GREETD_VT"
echo
echo "Archivos clave:"
echo "  ~/dwl/config.h              -> atajos/colores (dwl-rebuild)"
echo "  ~/.config/dwlb/config       -> barra (NO necesita recompilar)"
echo "  /usr/local/bin/dwl-session  -> wrapper de arranque"
echo "  ~/Atajos.txt                -> chuleta"
echo
warn "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
warn " REINICIA AHORA con: sudo reboot"
warn " Los grupos de permisos no se aplican hasta reiniciar."
warn " Sin ellos dwl no puede abrir la GPU ni teclado/raton."
warn "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
echo
info "Referencia de drivers:"
if [ "$DISTRO_FAMILIA" = "arch" ]; then
    echo "  NVIDIA .. sudo pacman -S nvidia nvidia-utils lib32-nvidia-utils"
    echo "            agrega nvidia_drm.modeset=1 a los parametros del kernel"
    echo "  AMD ..... sudo pacman -S mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon"
    echo "  Intel ... sudo pacman -S mesa lib32-mesa vulkan-intel intel-media-driver"
    echo "  Steam ... sudo pacman -S steam (necesita [multilib])"
else
    echo "  NVIDIA .. sudo xbps-install -S nvidia nvidia-libs-32bit"
    echo "  AMD ..... sudo xbps-install -S mesa-dri mesa-vulkan-radeon linux-firmware-amd"
    echo "  Intel ... sudo xbps-install -S mesa-dri mesa-vulkan-intel intel-video-accel"
    echo "  Steam ... activa repos nonfree/multilib, luego sudo xbps-install -S steam"
fi

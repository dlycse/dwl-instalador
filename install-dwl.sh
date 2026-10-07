#!/bin/sh
# install-dwl-v0.8
# Instalador de dwl (dwm para Wayland).
# Soporta:
#   - Void Linux (xbps + runit, modo original)
#   - Arch Linux y derivadas: Manjaro, EndeavourOS, Garuda, Artix, Archcraft, etc.
#
# Entorno que instala: dwl (compilado desde fuente) + dwlb, foot, wmenu,
# swaybg, pipewire y arranque con greetd + tuigreet (unico gestor de inicio;
# lightdm se desactiva y desinstala si existe).
#
# Este script NO instala drivers de GPU ni Steam. Eso lo instalas tu mismo
# con el gestor de paquetes de tu distro cuando lo necesites.
#

set -e

# ----------------------------------------------------------------
# Colores y mensajes
# ----------------------------------------------------------------
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
RESET="\033[0m"

info()  { printf "%b[+]%b %s\n" "$GREEN" "$RESET" "$1"; }
warn()  { printf "%b[!]%b %s\n" "$YELLOW" "$RESET" "$1"; }
error() { printf "%b[x]%b %s\n" "$RED" "$RESET" "$1"; }

write_config() {
    if [ -f "$1" ]; then
        warn "$1 ya existe: se conserva tu version. La nueva quedo en $1.nuevo"
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
        BACKUP_PATH="$1.bak-$(date +%Y%m%d%H%M%S)"
        sudo cp -a "$1" "$BACKUP_PATH" || return 1
        info "Copia de seguridad: $BACKUP_PATH"
    fi
}

# ----------------------------------------------------------------
# 0. Comprobaciones previas COMUNES
# ----------------------------------------------------------------
if [ "$(id -u)" -eq 0 ]; then
    error "No ejecutes este script como root: los archivos quedarian en /root."
    exit 1
fi

if ! command -v sudo >/dev/null 2>&1; then
    error "Falta 'sudo'. Instalalo y agrega tu usuario a sudoers (visudo) antes de continuar."
    exit 1
fi

if ! command -v git >/dev/null 2>&1; then
    error "Falta 'git'. Instalalo antes de continuar."
    exit 1
fi

# ----------------------------------------------------------------
# 0b. Detectar distro
# ----------------------------------------------------------------
DISTRO_ID="unknown"
DISTRO_FAMILIA="unknown"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO_ID="${ID:-unknown}"
    ID_LIKE="${ID_LIKE:-}"
fi

case "$DISTRO_ID" in
    void) DISTRO_FAMILIA="void" ;;
    arch|manjaro|endeavouros|garuda|artix|archcraft|arcolinux|hyperbola|parabola|cachyos|rebornos|obarun)
        DISTRO_FAMILIA="arch" ;;
    *)
        case "$ID_LIKE" in
            *arch*) DISTRO_FAMILIA="arch" ;;
            *void*) DISTRO_FAMILIA="void" ;;
            *)      DISTRO_FAMILIA="unknown" ;;
        esac ;;
esac

info "Distro detectada: $DISTRO_ID (familia: $DISTRO_FAMILIA)"

if [ "$DISTRO_FAMILIA" = "unknown" ]; then
    error "Este script solo es compatible con Void Linux y Arch Linux/derivadas."
    error "Distro detectada: $DISTRO_ID"
    exit 1
fi

# ----------------------------------------------------------------
# 0c. Definir funciones y paquetes SEGUN LA DISTRO
# ----------------------------------------------------------------
if [ "$DISTRO_FAMILIA" = "void" ]; then
    PKG_INSTALL() { sudo xbps-install -Sy "$@"; }
    PKG_QUERY()   { xbps-query "$1" >/dev/null 2>&1; }
    PKG_REMOVE()  { sudo xbps-remove -R "$@"; }
    PKG_UPDATE()  { sudo xbps-install -Su; }
    DEFAULT_GREETD_VT=7
    SEAT_GROUP="_seatd"
    GREETER_USER="_greeter"
    HAS_RC_CONF=1
    HAS_VCONSOLE_CONF=0
    USES_SYSTEMD_LOGIND=0
    NEEDS_SEATD_DAEMON=1
    NEEDS_TURNSTILE=1

    PKGS_BASE="base-devel file pkg-config \
        libinput libinput-devel void-repo-nonfree void-repo-multilib void-repo-multilib-nonfree \
        wayland wayland-devel wayland-protocols \
        libxkbcommon libxkbcommon-devel \
        wlroots wlroots-devel \
        libseat libseat-devel seatd \
        xorg-server-xwayland \
        mesa-dri libdrm-devel \
        pango-devel cairo-devel \
        pixman pixman-devel fcft fcft-devel tllist \
        foot wmenu fastfetch \
        pipewire wireplumber alsa-pipewire \
        swaybg swaylock grim slurp wl-clipboard \
        brightnessctl curl procps-ng \
        nano nerd-fonts lf mpv zathura zathura-pdf-poppler xdg-utils imv \
        chrony firefox btop cowsay dbus pciutils greetd tuigreet turnstile"

    enable_svc() {
        if [ -L "/var/service/$1" ]; then
            if [ ! -d "/etc/sv/$1" ]; then
                error "Existe el enlace /var/service/$1, pero falta el servicio /etc/sv/$1."
                return 1
            fi
            info "El servicio $1 ya esta habilitado en runit."
        elif [ -d "/etc/sv/$1" ]; then
            sudo ln -s "/etc/sv/$1" /var/service/ || return 1
            info "Servicio $1 habilitado en runit."
        else
            warn "No encontre /etc/sv/$1. Activalo a mano."
            return 1
        fi
    }
    disable_svc() {
        if [ -L "/var/service/$1" ]; then
            sudo sv stop "$1" 2>/dev/null || true
            sudo rm -f "/var/service/$1"
            info "Servicio $1 desactivado."
        fi
    }
    start_svc()  { sudo sv start "$1"; }
    status_svc() { sudo sv status "$1" 2>&1 || true; }
    desactivar_getty_vt() {
        VT="$1"
        [ -L "/var/service/agetty-tty$VT" ] && disable_svc "agetty-tty$VT"
    }

    for CMD in xbps-install xbps-query sv; do
        command -v "$CMD" >/dev/null 2>&1 || { error "Falta '$CMD'."; exit 1; }
    done
    [ -d /var/service ] || { error "No existe /var/service (runit)."; exit 1; }

elif [ "$DISTRO_FAMILIA" = "arch" ]; then
    PKG_INSTALL() { sudo pacman -Sy --needed --noconfirm "$@"; }
    PKG_QUERY()   { pacman -Q "$1" >/dev/null 2>&1; }
    PKG_REMOVE()  { sudo pacman -Rns --noconfirm "$@"; }
    DEFAULT_GREETD_VT=1
    SEAT_GROUP="seat"
    GREETER_USER="greeter"
    HAS_RC_CONF=0
    HAS_VCONSOLE_CONF=1
    # systemd-logind ya crea XDG_RUNTIME_DIR y gestiona el seat;
    # turnstile es una herramienta de Void y NO EXISTE en Arch.
    USES_SYSTEMD_LOGIND=1
    NEEDS_SEATD_DAEMON=0
    NEEDS_TURNSTILE=0

    if ! command -v pacman >/dev/null 2>&1; then
        error "Falta 'pacman'."; exit 1
    fi

    if ! grep -qE '^\[multilib\]' /etc/pacman.conf; then
        warn "El repositorio [multilib] no esta habilitado en /etc/pacman.conf."
        warn "Lo necesitaras para Steam y librerias de 32 bits. El script sigue,"
        warn "pero para instalar Steam luego tendras que activarlo."
    fi

    # --- Paquetes de Arch ---
    # Notas importantes:
    #  * wlroots en Arch esta versionado (wlroots0.17, wlroots0.18, wlroots0.19, wlroots).
    #    dwl de la rama main sigue wlroots git (el "wlroots" sin numero), pero
    #    el paquete oficial 'wlroots' de extra se actualiza con cada release.
    #    Instalamos wlroots (el mas nuevo) y sus headers de desarrollo.
    #  * No existe paquete separado 'libseat': lo provee 'seatd'.
    #  * tuigreet se llama 'greetd-tuigreet' en extra.
    #  * turnstile es un paquete propio de Void; en Arch pam_systemd se encarga
    #    de XDG_RUNTIME_DIR, asi que NO se instala ni se toca pam.d/greetd.
    #  * Los *-devel de Void se llaman igual que el paquete en Arch.
    #  * seatd es una libreria para gestionar el seat; con systemd-logind el
    #    daemon seatd no es estrictamente necesario, pero la libreria si.
    PKGS_BASE="base-devel \
        libinput wayland wayland-protocols \
        libxkbcommon wlroots libseat xcb-util-errors xcb-util-renderutil xcb-util-wm \
        xorg-xwayland mesa libdrm \
        pango cairo pixman fcft tllist \
        foot wmenu fastfetch \
        pipewire wireplumber pipewire-alsa pipewire-pulse \
        swaybg swaylock grim slurp wl-clipboard \
        brightnessctl curl procps-ng \
        nano ttf-nerd-fonts-symbols ttf-nerd-fonts-symbols-mono \
        lf mpv zathura zathura-pdf-poppler xdg-utils imv \
        chrony firefox btop cowsay dbus pciutils \
        greetd greetd-tuigreet seatd"

    enable_svc() {
        if systemctl is-enabled --quiet "$1" 2>/dev/null; then
            info "El servicio $1 ya esta habilitado en systemd."
        else
            sudo systemctl enable "$1" || return 1
            info "Servicio $1 habilitado en systemd."
        fi
    }
    disable_svc() {
        if systemctl is-enabled --quiet "$1" 2>/dev/null; then
            sudo systemctl disable --now "$1" 2>/dev/null || true
            info "Servicio $1 desactivado."
        fi
    }
    start_svc()  { sudo systemctl start "$1"; }
    status_svc() { systemctl status "$1" --no-pager -l 2>&1 || true; }
    desactivar_getty_vt() {
        VT="$1"
        local gsvc="getty@tty${VT}.service"
        if systemctl is-enabled --quiet "$gsvc" 2>/dev/null; then
            warn "Desactivando getty en tty$VT para que greetd pueda usarla."
            sudo systemctl disable --now "$gsvc" 2>/dev/null || true
        fi
    }
fi

# ----------------------------------------------------------------
# 0d. Variables generales
# ----------------------------------------------------------------
GREETD_VT="${GREETD_VT:-$DEFAULT_GREETD_VT}"
case "$GREETD_VT" in
    ''|*[!0-9]*) error "GREETD_VT debe ser un numero entre 1 y 12."; exit 1 ;;
esac
if [ "$GREETD_VT" -lt 1 ] || [ "$GREETD_VT" -gt 12 ]; then
    error "GREETD_VT debe estar entre 1 y 12 (recibido: $GREETD_VT)."; exit 1
fi

DWL_REPO="https://codeberg.org/dwl/dwl.git"
DWLB_REPO="https://github.com/kolunmi/dwlb.git"
WALLPAPER_DIR="$HOME/Pictures"
WALLPAPER_PATH="$WALLPAPER_DIR/wallpaper.jpg"
WALLPAPER_URL="https://wallpapercave.com/download/empty-error-wallpapers-wp8330753"

# Tamaños de fuente: wmenu 11, dwlb 10 (uno menos para que la barra quede
# compacta y a la misma altura visual). Se pueden sobreescribir por env.
WMENU_FONT_SIZE="${WMENU_FONT_SIZE:-11}"
DWLB_FONT_SIZE="${DWLB_FONT_SIZE:-10}"

DWLB_FONT="${DWLB_FONT:-monospace:size=$DWLB_FONT_SIZE}"
DWLB_PAD="${DWLB_PAD:--2}"
DWLB_HPAD="${DWLB_HPAD:-6}"
DWLB_ACTIVE_FG="#ffffff"
DWLB_ACTIVE_BG="#89b4fa"
DWLB_OCCUPIED_FG="#cdd6f4"
DWLB_OCCUPIED_BG="#313244"
DWLB_INACTIVE_FG="#a6adc8"
DWLB_INACTIVE_BG="#1e1e2e"
DWLB_URGENT_FG="#1e1e2e"
DWLB_URGENT_BG="#f38ba8"
DWLB_MIDDLE_BG="#1e1e2e"

GPU_VENDORS=""
GPU_CARDS=""
GPU_HIBRIDA=0

FREE_GB=$(df -BG --output=avail "$HOME" 2>/dev/null | tail -n1 | tr -d 'G ' )
if [ -n "$FREE_GB" ] && [ "$FREE_GB" -lt 20 ] 2>/dev/null; then
    warn "Solo detecto ${FREE_GB}GB libres en $HOME. Se recomiendan al menos 20GB."
    printf "Continuar de todas formas? [y/N] "
    read -r CONTINUAR_DISCO
    case "$CONTINUAR_DISCO" in
        y|Y) ;;
        *) error "Cancelado."; exit 1 ;;
    esac
fi

# ==================================================================
# MENU
# ==================================================================
echo "=========================================="
echo "    Instalador dwl v0.8"
echo "=========================================="
echo "Distro objetivo: $DISTRO_ID"
echo "Barra: dwlb | Gestor de inicio: greetd + tuigreet"
echo "(lightdm se desactivara/desinstalara si existe)"
echo "(drivers de GPU y Steam: los instalas tu aparte)"
echo
echo "1) Instalar dwl + dwlb, foot, wmenu, swaybg, greetd"
echo "2) Salir"
printf "Opcion [1-2]: "
read -r OPCION
case "$OPCION" in
    1) ;;
    2) info "Saliendo..."; exit 0 ;;
    *) error "Opcion no valida."; exit 1 ;;
esac

# ==================================================================
# detectar_gpus
# ==================================================================
detectar_gpus() {
    if ! command -v lspci >/dev/null 2>&1; then
        info "Instalando pciutils..."
        PKG_INSTALL pciutils || return 1
    fi
    GPU_LISTA=$(lspci -nn | grep -iE 'vga|3d controller|display controller' || true)
    GPU_VENDORS=""
    printf '%s' "$GPU_LISTA" | grep -qiE '\[10de:'      && GPU_VENDORS="$GPU_VENDORS nvidia"
    printf '%s' "$GPU_LISTA" | grep -qiE '\[1002:|AMD'  && GPU_VENDORS="$GPU_VENDORS amd"
    printf '%s' "$GPU_LISTA" | grep -qiE '\[8086:|Intel'&& GPU_VENDORS="$GPU_VENDORS intel"
    GPU_VENDORS=$(printf '%s' "$GPU_VENDORS" | sed 's/^ //')
    GPU_NUM=$(printf '%s\n' "$GPU_LISTA" | grep -c . || true)
    GPU_CARDS=$(ls -1 /dev/dri/card* 2>/dev/null | sort -V | tr '\n' ':' | sed 's/:$//')
    [ -n "$GPU_VENDORS" ] || GPU_VENDORS="desconocida"
    GPU_HIBRIDA=0; [ "$GPU_NUM" -ge 2 ] && GPU_HIBRIDA=1
    info "GPUs detectadas ($GPU_NUM):"
    printf '%s\n' "$GPU_LISTA" | sed 's/^/    /'
    info "Fabricantes: $GPU_VENDORS"
    [ -n "$GPU_CARDS" ] && info "Nodos DRM: $GPU_CARDS"
    return 0
}

# ==================================================================
# compilar_dwlb
# ==================================================================
compilar_dwlb() {
    cd "$HOME" || return 1
    if [ ! -d dwlb ]; then
        info "Clonando dwlb desde $DWLB_REPO ..."
        git clone "$DWLB_REPO" || return 1
    fi
    cd "$HOME/dwlb" || return 1
    fix_owner || return 1
    if [ -f config.def.h ] && [ ! -f config.h ]; then
        cp config.def.h config.h
        info "Creado ~/dwlb/config.h a partir de config.def.h."
    fi
    if grep -qE 'zwlr_layer_shell_v1_interface, [0-9]+\)' dwlb.c 2>/dev/null; then
        DWLB_LS_VER=$(grep -oE 'zwlr_layer_shell_v1_interface, [0-9]+\)' dwlb.c | head -n1 | \
            sed -n 's/.*,[[:space:]]*\([0-9][0-9]*\))$/\1/p')
        case "$DWLB_LS_VER" in ''|*[!0-9]*) DWLB_LS_VER="" ;; esac
        if [ -n "$DWLB_LS_VER" ] && [ "$DWLB_LS_VER" -gt 1 ]; then
            sed -i "s|&zwlr_layer_shell_v1_interface, $DWLB_LS_VER)|\&zwlr_layer_shell_v1_interface, (version < $DWLB_LS_VER ? version : $DWLB_LS_VER))|" dwlb.c \
                || warn "No pude aplicar el parche layer-shell."
            info "Parche layer-shell aplicado a dwlb (max version $DWLB_LS_VER)."
        fi
    fi
    make clean 2>/dev/null || true
    if ! make; then
        error "Fallo la compilacion de dwlb. Revisa las dependencias (-devel/-headers)."
        return 1
    fi
    sudo make install || return 1
    if [ -f dwlb.1 ]; then
        if ! command -v man >/dev/null 2>&1; then :;
        elif [ ! -f /usr/local/share/man/man1/dwlb.1 ]; then
            sudo mkdir -p /usr/local/share/man/man1
            sudo cp dwlb.1 /usr/local/share/man/man1/dwlb.1
            info "Manual instalado: man 1 dwlb"
        fi
    fi
    command -v dwlb >/dev/null 2>&1 || { error "dwlb no quedo en el PATH."; return 1; }
    return 0
}

# ==================================================================
# configurar_dwlb
# ==================================================================
configurar_dwlb() {
    info "Escribiendo la configuracion de dwlb (fuente $DWLB_FONT_SIZE, padding ${DWLB_PAD}px)..."
    mkdir -p "$HOME/.config/dwlb"
    write_config "$HOME/.config/dwlb/config" <<EOF
# Configuracion de dwlb (https://github.com/kolunmi/dwlb)
-font $DWLB_FONT
-vertical-padding $DWLB_PAD
-horizontal-padding $DWLB_HPAD
-hide-vacant-tags
-center-title
-status-commands
-no-bottom
-no-hidden

# Colores (Catppuccin Mocha)
-active-fg-color $DWLB_ACTIVE_FG
-active-bg-color $DWLB_ACTIVE_BG
-occupied-fg-color $DWLB_OCCUPIED_FG
-occupied-bg-color $DWLB_OCCUPIED_BG
-inactive-fg-color $DWLB_INACTIVE_FG
-inactive-bg-color $DWLB_INACTIVE_BG
-urgent-fg-color $DWLB_URGENT_FG
-urgent-bg-color $DWLB_URGENT_BG
EOF

    info "Instalando 'dwlb-status'..."
    sudo tee /usr/local/bin/dwlb-status >/dev/null <<'EOF'
#!/bin/sh
COLOR_ETIQ="89b4fa"; COLOR_TXT="cdd6f4"; COLOR_ALERTA="f38ba8"
bloque_volumen() {
    command -v wpctl >/dev/null 2>&1 || return 0
    INFO=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null) || return 0
    VOL=$(printf '%s' "$INFO" | awk '{printf "%d", $2 * 100}')
    case "$INFO" in
        *MUTED*) printf '^fg(%s)VOL^fg(%s) mudo' "$COLOR_ETIQ" "$COLOR_ALERTA" ;;
        *)       printf '^fg(%s)VOL^fg(%s) %s%%' "$COLOR_ETIQ" "$COLOR_TXT" "$VOL" ;;
    esac
    printf '  '
}
bloque_bateria() {
    for BAT in /sys/class/power_supply/BAT*; do
        [ -r "$BAT/capacity" ] || continue
        CAP=$(cat "$BAT/capacity"); EST=$(cat "$BAT/status" 2>/dev/null || echo Unknown)
        case "$EST" in Charging) ICONO="+" ;; Full) ICONO="=" ;; *) ICONO="-" ;; esac
        [ "$CAP" -le 15 ] && [ "$EST" != "Charging" ] && COLOR="$COLOR_ALERTA" || COLOR="$COLOR_TXT"
        printf '^fg(%s)BAT^fg(%s) %s%s%%  ' "$COLOR_ETIQ" "$COLOR" "$ICONO" "$CAP"; break
    done
}
bloque_cpu() { [ -r /proc/loadavg ] && printf '^fg(%s)CPU^fg(%s) %s  ' "$COLOR_ETIQ" "$COLOR_TXT" "$(cut -d' ' -f1 /proc/loadavg)"; }
bloque_ram() {
    [ -r /proc/meminfo ] || return 0
    awk -v e="$COLOR_ETIQ" -v t="$COLOR_TXT" '
        /^MemTotal:/{total=$2} /^MemAvailable:/{disp=$2}
        END{if(total)printf "^fg(%s)RAM^fg(%s) %.1fG  ",e,t,(total-disp)/1048576}' /proc/meminfo
}
bloque_fecha() {
    printf '^lm(foot -e sh -c "cal -3; read x")^mm(foot)^fg(%s)%s^fg()^mm()^lm()' \
        "$COLOR_TXT" "$(date '+%a %d/%m  %H:%M')"
}
while :; do
    printf '^mm(foot)%s%s%s%s%s^mm()\n' \
        "$(bloque_cpu)" "$(bloque_ram)" "$(bloque_volumen)" \
        "$(bloque_bateria)" "$(bloque_fecha)"
    sleep 5
done
EOF
    sudo chmod +x /usr/local/bin/dwlb-status
}

# ==================================================================
# configurar_greetd
# ==================================================================
configurar_greetd() {
    # Quitar lightdm si existe
    for PKG in lightdm lightdm-gtk3-greeter lightdm-gtk-greeter; do
        if PKG_QUERY "$PKG"; then
            info "Encontre lightdm instalado: lo quito."
            disable_svc lightdm
            PKG_REMOVE lightdm lightdm-gtk3-greeter lightdm-gtk-greeter 2>/dev/null || true
            break
        fi
    done

    # En Arch greetd/greetd-tuigreet ya van en PKGS_BASE (instalados en instalar_base).
    # En Void se instalan alli tambien, asi que no hace falta instalarlos aqui.

    SESSION_CMD="/usr/local/bin/dwl-session"
    info "Comando de sesion: $SESSION_CMD"

    sudo mkdir -p /etc/greetd
    backup_file /etc/greetd/config.toml
    sudo tee /etc/greetd/config.toml >/dev/null <<EOF
# Generado por install-dwl-v0.8.sh
[terminal]
vt = $GREETD_VT
[default_session]
command = "tuigreet --time --time-format '%H:%M  %d/%m/%Y' --user-menu --remember --greeting 'Bienvenido a dwl' --power-shutdown 'shutdown -h now' --power-reboot 'shutdown -r now' --cmd $SESSION_CMD"
user = "$GREETER_USER"
EOF
    info "Escrito /etc/greetd/config.toml"

    if [ "$NEEDS_TURNSTILE" -eq 1 ]; then
        info "Configurando turnstile (prepara XDG_RUNTIME_DIR mediante PAM)..."
        enable_svc turnstiled || warn "turnstiled no esta disponible."
        PAM_FILE="/etc/pam.d/greetd"
        if [ -f /usr/lib/security/pam_turnstile.so ] || [ -f /usr/lib64/security/pam_turnstile.so ]; then
            if [ -f "$PAM_FILE" ] && ! grep -q 'pam_turnstile.so' "$PAM_FILE"; then
                backup_file "$PAM_FILE"
                printf '\nsession\toptional\tpam_turnstile.so\n' | sudo tee -a "$PAM_FILE" >/dev/null
                info "Anadido pam_turnstile.so a $PAM_FILE"
            fi
        else
            warn "No encontre pam_turnstile.so; se omite."
        fi
    else
        info "En esta distro pam_systemd ya configura XDG_RUNTIME_DIR; se omite turnstile."
    fi

    desactivar_getty_vt "$GREETD_VT"
}

# ==================================================================
# iniciar_greetd
# ==================================================================
iniciar_greetd() {
    [ -x /usr/local/bin/dwl-session ] || { error "No existe /usr/local/bin/dwl-session."; return 1; }
    enable_svc greetd || { error "No pude habilitar greetd."; return 1; }
    info "Arrancando greetd..."
    start_svc greetd || { error "No se pudo iniciar greetd."; return 1; }
    ESTADO=$(status_svc greetd)
    case "$ESTADO" in
        *run:*|*active*running*) info "greetd activo en tty$GREETD_VT." ;;
        *) warn "Estado de greetd: $ESTADO" ;;
    esac
}

# ==================================================================
# detectar_hardware
# ==================================================================
detectar_hardware() {
    ES_VM=0
    if grep -qw hypervisor /proc/cpuinfo 2>/dev/null; then
        ES_VM=1
        VM_NOMBRE=$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo "desconocida")
        warn "Maquina virtual detectada ($VM_NOMBRE)."
    fi
    info "Fuente wmenu: monospace $WMENU_FONT_SIZE"
    info "Fuente dwlb:  monospace $DWLB_FONT_SIZE"
    EXTRA_ENV=""
    [ "$ES_VM" -eq 1 ] && EXTRA_ENV="export WLR_NO_HARDWARE_CURSORS=1"
}

# ==================================================================
# instalar_base
# ==================================================================
instalar_base() {

    info "Kernel en uso: $(uname -r)"
    if [ "$DISTRO_FAMILIA" = "void" ]; then
        info "Buscando kernel 7.x en los repos..."
        KERNEL_7_PKGVER=$(xbps-query --regex -Rs '^linux7\.[0-9]+' 2>/dev/null | awk '{print $2}' \
            | grep -E '^linux7\.[0-9]+-7\.[0-9]+' | sort -V | tail -n1)
        KERNEL_7_PKG=$(printf '%s' "$KERNEL_7_PKGVER" | sed 's/-7\..*$//')
        if [ -z "$KERNEL_7_PKG" ]; then
            warn "No se encontro kernel 7.x; se conserva el actual."
        else
            info "Kernel 7.x disponible: $KERNEL_7_PKG"
            printf "  1) Conservar el kernel actual\n  2) Instalar %s\nOpcion [1]: " "$KERNEL_7_PKG"
            read -r OPCION_KERNEL; OPCION_KERNEL="${OPCION_KERNEL:-1}"
            case "$OPCION_KERNEL" in
                2) PKG_INSTALL "$KERNEL_7_PKG" && info "$KERNEL_7_PKG instalado." || warn "No se pudo instalar." ;;
                *) info "Se conserva el kernel actual." ;;
            esac
        fi
    fi

    info "Instalando paquetes base..."
    if ! PKG_INSTALL $PKGS_BASE; then
        error "La instalacion de paquetes fallo."
        return 1
    fi

    info "Habilitando servicios..."
    enable_svc dbus || warn "No se pudo habilitar dbus."
    enable_svc chronyd || warn "No se pudo habilitar chronyd."
    [ "$NEEDS_SEATD_DAEMON" -eq 1 ] && enable_svc seatd

    REAL_USER=$(id -un)
    info "Configurando grupos para $REAL_USER..."
    if ! getent group "$SEAT_GROUP" >/dev/null 2>&1; then
        error "No existe el grupo '$SEAT_GROUP' (seatd)."; return 1
    fi
    sudo usermod -aG "$SEAT_GROUP" "$REAL_USER" || { error "No pude agregar $REAL_USER al grupo $SEAT_GROUP."; return 1; }
    if getent group video >/dev/null 2>&1; then
        sudo usermod -aG video "$REAL_USER" && info "$REAL_USER agregado a 'video'" \
            || warn "No se pudo agregar a video."
    fi
    warn "Los grupos nuevos solo se aplican tras reiniciar/cerrar sesion."

    detectar_hardware
    detectar_gpus || warn "No pude detectar GPUs; sigo sin sus avisos."

    # --- Zona horaria ---
    info "Zona horaria."
    printf "Pais (ej: Colombia, Mexico, Espana). Vacio = Colombia: "
    read -r PAIS_INPUT; PAIS_INPUT="${PAIS_INPUT:-Colombia}"
    PAIS_NORM=$(printf '%s' "$PAIS_INPUT" | tr '[:upper:]' '[:lower:]' | \
        sed 's/á/a/g;s/é/e/g;s/í/i/g;s/ó/o/g;s/ú/u/g;s/ñ/n/g')
    case "$PAIS_NORM" in
        colombia)Tz=America/Bogota;; mexico)Tz=America/Mexico_City;;
        argentina)Tz=America/Buenos_Aires;; chile)Tz=America/Santiago;;
        peru)Tz=America/Lima;; ecuador)Tz=America/Guayaquil;; venezuela)Tz=America/Caracas;;
        bolivia)Tz=America/La_Paz;; paraguay)Tz=America/Asuncion;; uruguay)Tz=America/Montevideo;;
        panama)Tz=America/Panama;; "costa rica")Tz=America/Costa_Rica;;
        espana|spain)Tz=Europe/Madrid;; "estados unidos"|usa|eeuu)Tz=America/New_York;;
        */*)Tz="$PAIS_INPUT";; *)Tz="";;
    esac
    if [ -n "$Tz" ] && [ -f "/usr/share/zoneinfo/$Tz" ]; then
        info "Zona horaria: $Tz"
        sudo ln -sf "/usr/share/zoneinfo/$Tz" /etc/localtime || warn "No pude enlazar /etc/localtime."
        printf '%s\n' "$Tz" | sudo tee /etc/timezone >/dev/null 2>&1 || true
        if [ "$HAS_RC_CONF" -eq 1 ]; then
            sudo hwclock --systohc 2>/dev/null || true
            if grep -qE '^[#[:space:]]*TIMEZONE=' /etc/rc.conf; then
                sudo sed -i "s|^[#[:space:]]*TIMEZONE=.*|TIMEZONE=\"$Tz\"|" /etc/rc.conf
            else
                printf 'TIMEZONE="%s"\n' "$Tz" | sudo tee -a /etc/rc.conf >/dev/null
            fi
        fi
    else
        warn "No reconozco '$PAIS_INPUT'; se deja la zona horaria como esta."
    fi

    # --- Teclado ---
    info "Teclado."
    while true; do
        printf " 1) us  2) es  3) latam [3]: "
        read -r K; K="${K:-3}"
        case "$K" in
            1) KB_XKB=us; KB_CONSOLA=us; break;;
            2) KB_XKB=es; KB_CONSOLA=es; break;;
            3) KB_XKB=latam; KB_CONSOLA=la-latin1; break;;
            *) warn "Elige 1, 2 o 3.";;
        esac
    done
    if [ -n "$KB_CONSOLA" ]; then
        if [ "$HAS_RC_CONF" -eq 1 ]; then
            if grep -qE '^[#[:space:]]*KEYMAP=' /etc/rc.conf; then
                sudo sed -i "s|^[#[:space:]]*KEYMAP=.*|KEYMAP=\"$KB_CONSOLA\"|" /etc/rc.conf
            else printf 'KEYMAP="%s"\n' "$KB_CONSOLA" | sudo tee -a /etc/rc.conf >/dev/null; fi
        fi
        if [ "$HAS_VCONSOLE_CONF" -eq 1 ]; then
            backup_file /etc/vconsole.conf
            if grep -qE '^KEYMAP=' /etc/vconsole.conf; then
                sudo sed -i "s|^KEYMAP=.*|KEYMAP=$KB_CONSOLA|" /etc/vconsole.conf
            else printf 'KEYMAP=%s\n' "$KB_CONSOLA" | sudo tee -a /etc/vconsole.conf >/dev/null; fi
        fi
        command -v loadkeys >/dev/null 2>&1 && sudo loadkeys "$KB_CONSOLA" 2>/dev/null || true
    fi

    # --- Clonar/compilar dwl ---
    cd "$HOME"
    [ -d dwl ] || { info "Clonando dwl..."; git clone "$DWL_REPO"; }
    cd dwl; fix_owner

    if [ -f protocols/dwl-ipc-unstable-v2.xml ] || [ -f protocols/dwl-ipc-unstable-v1.xml ]; then
        DWLB_IPC=1; info "dwl incluye IPC: dwlb usara -ipc (clics en tags funcionales)."
    else
        DWLB_IPC=0; info "dwl sin parche IPC: dwlb usara -no-ipc."
    fi

    # Apartar config.h de API antigua
    if [ -f config.h ] && { grep -q 'static const char \*tags\[\]' config.h || \
                            ! grep -q 'TAGCOUNT' config.h || ! grep -q 'log_level' config.h || \
                            ! grep -q 'axes\[\]' config.h; }; then
        VIEJO="config.h.antiguo-$(date +%Y%m%d%H%M%S)"
        warn "Tu config.h usa la API antigua; lo guardo como ~/dwl/$VIEJO."
        mv config.h "$VIEJO"
    fi

    if [ -f config.h ]; then
        warn "config.h ya existe y es compatible: se conserva."
    else
        info "Escribiendo config.h (layout '$KB_XKB')..."
        cat > config.h <<EOF
/* dwl config.h - generado por install-dwl-v0.8.sh */
#define COLOR(hex) { ((hex>>24)&0xFF)/255.0f, ((hex>>16)&0xFF)/255.0f, ((hex>>8)&0xFF)/255.0f, (hex&0xFF)/255.0f }
static const int sloppyfocus=1, bypass_surface_visibility=0;
static const unsigned int borderpx=2, snap=32;
static const float rootcolor[]=COLOR(0x1e1e2eff), bordercolor[]=COLOR(0x313244ff),
                   focuscolor[]=COLOR(0x89b4faff), urgentcolor[]=COLOR(0xf38ba8ff),
                   fullscreen_bg[]={0.0f,0.0f,0.0f,1.0f};
#define TAGCOUNT (9)
static int log_level = WLR_ERROR;
static const Rule rules[]={ {"Gimp",NULL,0,1,-1}, {"firefox",NULL,1<<0,0,-1} };
static const Layout layouts[]={ {"[]=",tile}, {"><>",NULL}, {"[M]",monocle} };
static const MonitorRule monrules[]={ {NULL,0.55f,1,1,&layouts[0],WL_OUTPUT_TRANSFORM_NORMAL,-1,-1} };
static const struct xkb_rule_names xkb_rules={.layout="$KB_XKB"};
static const int repeat_rate=25, repeat_delay=600;
static const int tap_to_click=1, tap_and_drag=1, drag_lock=1, natural_scrolling=0,
    disable_while_typing=1, left_handed=0, middle_button_emulation=0;
static const enum libinput_config_scroll_method scroll_method=LIBINPUT_CONFIG_SCROLL_2FG;
static const enum libinput_config_click_method click_method=LIBINPUT_CONFIG_CLICK_METHOD_BUTTON_AREAS;
static const uint32_t send_events_mode=LIBINPUT_CONFIG_SEND_EVENTS_ENABLED;
static const enum libinput_config_accel_profile accel_profile=LIBINPUT_CONFIG_ACCEL_PROFILE_ADAPTIVE;
static const double accel_speed=0.0;
static const enum libinput_config_tap_button_map button_map=LIBINPUT_CONFIG_TAP_MAP_LRM;
#define MODKEY WLR_MODIFIER_LOGO
#define TAGKEYS(K,S,T) { MODKEY,K,view,{.ui=1<<T} }, { MODKEY|WLR_MODIFIER_CTRL,K,toggleview,{.ui=1<<T} }, \
    { MODKEY|WLR_MODIFIER_SHIFT,S,tag,{.ui=1<<T} }, { MODKEY|WLR_MODIFIER_CTRL|WLR_MODIFIER_SHIFT,S,toggletag,{.ui=1<<T} }
static const char *termcmd[]={"foot",NULL}, *browsercmd[]={"firefox",NULL},
    *dmenucmd[]={"sh","-c","dwlb -toggle-visibility all; wmenu-run -f 'monospace $WMENU_FONT_SIZE' -N 1e1e2e -n cdd6f4 -S 89b4fa -s ffffff; dwlb -toggle-visibility all",NULL},
    *lfcmd[]={"foot","-e","lf",NULL},
    *upvol[]={"wpctl","set-volume","@DEFAULT_AUDIO_SINK@","3%+","-l","1.0",NULL},
    *downvol[]={"wpctl","set-volume","@DEFAULT_AUDIO_SINK@","3%-",NULL},
    *mutevol[]={"wpctl","set-mute","@DEFAULT_AUDIO_SINK@","toggle",NULL},
    *brup[]={"brightnessctl","set","+5%",NULL}, *brdown[]={"brightnessctl","set","5%-",NULL},
    *screenshot[]={"sh","-c","grim ~/Pictures/\$(date +'%Y-%m-%d_%H-%M-%S').png",NULL},
    *bartoggle[]={"dwlb","-toggle-visibility","all",NULL}, *barmove[]={"dwlb","-toggle-location","all",NULL};
static const Key keys[]={
 {MODKEY,XKB_KEY_d,spawn,{.v=dmenucmd}},{MODKEY,XKB_KEY_Return,spawn,{.v=termcmd}},
 {MODKEY,XKB_KEY_t,spawn,{.v=termcmd}},{MODKEY,XKB_KEY_b,spawn,{.v=browsercmd}},
 {MODKEY,XKB_KEY_r,spawn,{.v=lfcmd}},
 {MODKEY,XKB_KEY_q,killclient,{0}},
 {MODKEY,XKB_KEY_j,focusstack,{.i=+1}},{MODKEY,XKB_KEY_Down,focusstack,{.i=+1}},
 {MODKEY,XKB_KEY_k,focusstack,{.i=-1}},{MODKEY,XKB_KEY_Up,focusstack,{.i=-1}},
 {MODKEY,XKB_KEY_h,setmfact,{.f=-0.05f}},{MODKEY,XKB_KEY_l,setmfact,{.f=+0.05f}},
 {MODKEY,XKB_KEY_i,incnmaster,{.i=+1}},{MODKEY|WLR_MODIFIER_SHIFT,XKB_KEY_T,togglefloating,{0}},
 {MODKEY,XKB_KEY_w,spawn,{.v=bartoggle}},{MODKEY|WLR_MODIFIER_SHIFT,XKB_KEY_W,spawn,{.v=barmove}},
 {MODKEY|WLR_MODIFIER_SHIFT,XKB_KEY_Return,zoom,{0}},
 {MODKEY,XKB_KEY_f,setlayout,{.v=&layouts[2]}},{MODKEY,XKB_KEY_space,setlayout,{0}},
 {MODKEY|WLR_MODIFIER_SHIFT,XKB_KEY_F,togglefullscreen,{0}},
 TAGKEYS(XKB_KEY_1,XKB_KEY_exclam,0),TAGKEYS(XKB_KEY_2,XKB_KEY_quotedbl,1),
 TAGKEYS(XKB_KEY_3,XKB_KEY_numbersign,2),TAGKEYS(XKB_KEY_4,XKB_KEY_dollar,3),
 TAGKEYS(XKB_KEY_5,XKB_KEY_percent,4),TAGKEYS(XKB_KEY_6,XKB_KEY_ampersand,5),
 TAGKEYS(XKB_KEY_7,XKB_KEY_slash,6),TAGKEYS(XKB_KEY_8,XKB_KEY_parenleft,7),
 TAGKEYS(XKB_KEY_9,XKB_KEY_parenright,8),
 {MODKEY,XKB_KEY_Tab,view,{0}},{MODKEY,XKB_KEY_0,view,{.ui=~0}},
 {MODKEY,XKB_KEY_comma,focusmon,{.i=WLR_DIRECTION_LEFT}},
 {MODKEY,XKB_KEY_period,focusmon,{.i=WLR_DIRECTION_RIGHT}},
 {MODKEY|WLR_MODIFIER_SHIFT,XKB_KEY_less,tagmon,{.i=WLR_DIRECTION_LEFT}},
 {MODKEY|WLR_MODIFIER_SHIFT,XKB_KEY_greater,tagmon,{.i=WLR_DIRECTION_RIGHT}},
 {MODKEY|WLR_MODIFIER_SHIFT,XKB_KEY_semicolon,tagmon,{.i=WLR_DIRECTION_LEFT}},
 {MODKEY|WLR_MODIFIER_SHIFT,XKB_KEY_colon,tagmon,{.i=WLR_DIRECTION_RIGHT}},
 {0,XKB_KEY_XF86AudioRaiseVolume,spawn,{.v=upvol}},
 {0,XKB_KEY_XF86AudioLowerVolume,spawn,{.v=downvol}},
 {0,XKB_KEY_XF86AudioMute,spawn,{.v=mutevol}},
 {0,XKB_KEY_XF86MonBrightnessUp,spawn,{.v=brup}},
 {0,XKB_KEY_XF86MonBrightnessDown,spawn,{.v=brdown}},
 {0,XKB_KEY_Print,spawn,{.v=screenshot}},
 {MODKEY|WLR_MODIFIER_SHIFT,XKB_KEY_E,quit,{0}},
 {WLR_MODIFIER_CTRL|WLR_MODIFIER_ALT,XKB_KEY_BackSpace,quit,{0}},
#define CHVT(n) { WLR_MODIFIER_CTRL|WLR_MODIFIER_ALT,XKB_KEY_F##n,chvt,{.ui=n} }
 CHVT(1),CHVT(2),CHVT(3),CHVT(4),CHVT(5),CHVT(6),CHVT(7),CHVT(8),CHVT(9),CHVT(10),CHVT(11),CHVT(12)
};
static const Button buttons[]={
 {MODKEY,BTN_LEFT,moveresize,{.ui=CurMove}},
 {MODKEY,BTN_MIDDLE,togglefloating,{0}},
 {MODKEY,BTN_RIGHT,moveresize,{.ui=CurResize}},
};
static const Axis axes[]={
 {MODKEY,AxisUp,spawn,{.v=upvol}},{MODKEY,AxisDown,spawn,{.v=downvol}},
};
EOF
    fi

    info "Compilando dwl..."
    make clean 2>/dev/null || true
    if ! make; then
        error "Fallo al compilar dwl. Si el error menciona que wlroots es demasiado viejo,"
        error "necesitas la version que dwl espera. En Arch puedes probar con:"
        error "  sudo pacman -S wlroots0.19   (o wlroots0.18)"
        error "y luego volver a ejecutar 'make' en ~/dwl."
        return 1
    fi
    sudo make install

    BARRA_ELEGIDA=""
    if compilar_dwlb; then
        BARRA_ELEGIDA="dwlb"; configurar_dwlb
    else
        error "dwlb no compilo; la sesion arrancara sin barra."
    fi

    if [ "$BARRA_ELEGIDA" = "dwlb" ] && [ "${DWLB_IPC:-0}" -eq 1 ]; then
        DWLB_MODO="-ipc"
    else
        DWLB_MODO="-no-ipc"
    fi
    BARRA_CMD="dwl -s /usr/local/bin/dwl-status-runner"

    # dwl-status-runner
    sudo tee /usr/local/bin/dwl-status-runner >/dev/null <<'EOF'
#!/bin/sh
exec 3<&0 || exit 1; HIJOS=""; PID_BARRA=""
limpiar(){ for p in $HIJOS; do kill "$p" 2>/dev/null; done; for p in $HIJOS; do wait "$p" 2>/dev/null; done; HIJOS=""; }
trap limpiar EXIT; trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM
[ -n "$DWL_WALLPAPER" ] && [ -f "$DWL_WALLPAPER" ] && command -v swaybg >/dev/null && { swaybg -i "$DWL_WALLPAPER" -m fill </dev/null >/dev/null 2>&1 & HIJOS="$HIJOS $!"; }
case "$DWL_BAR_KIND" in
 dwlb)
  if [ "$DWL_BAR_MODE" = "-ipc" ]; then cat <&3 >/dev/null & HIJOS="$HIJOS $!"; dwlb -ipc </dev/null &
                                 else dwlb -no-ipc <&3 & fi
  PID_BARRA=$!; HIJOS="$HIJOS $PID_BARRA"
  command -v dwlb-status >/dev/null && { sleep 1; (dwlb-status | dwlb -status-stdin all) </dev/null >/dev/null 2>&1 & HIJOS="$HIJOS $!"; } ;;
 *) cat <&3 >/dev/null & PID_BARRA=$!; HIJOS="$HIJOS $PID_BARRA" ;;
esac
wait "$PID_BARRA"; E=$?; limpiar; trap - EXIT HUP INT TERM; exit $E
EOF
    sudo chmod +x /usr/local/bin/dwl-status-runner

    # lf
    info "Configurando lf..."
    mkdir -p "$HOME/.config/lf"
    write_config "$HOME/.config/lf/lfrc" <<'EOF'
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
EOF

    # Wallpaper
    mkdir -p "$WALLPAPER_DIR"
    if [ ! -f "$WALLPAPER_PATH" ]; then
        info "Descargando wallpaper..."
        TMP="$WALLPAPER_PATH.tmp"
        if curl -fsSL --max-time 30 -A "Mozilla/5.0" -e "https://wallpapercave.com/" -o "$TMP" "$WALLPAPER_URL" \
            && file "$TMP" | grep -qi image; then
            mv "$TMP" "$WALLPAPER_PATH"
        else
            warn "No se pudo descargar wallpaper; se omite."; rm -f "$TMP"
        fi
    fi

    # dwl-session wrapper
    info "Creando dwl-session..."
    sudo tee /usr/local/bin/dwl-session >/dev/null <<EOF
#!/bin/sh
export XDG_SESSION_TYPE=wayland XDG_CURRENT_DESKTOP=dwl XDG_SESSION_DESKTOP=dwl
export MOZ_ENABLE_WAYLAND=1 QT_QPA_PLATFORM=wayland GDK_BACKEND=wayland,x11
export DWL_BAR_KIND="$BARRA_ELEGIDA" DWL_BAR_MODE="$DWLB_MODO" DWL_WALLPAPER="$WALLPAPER_PATH"

SESSION_UID=\$(id -u)
if [ -n "\$XDG_RUNTIME_DIR" ] && [ -d "\$XDG_RUNTIME_DIR" ] && [ "\$(stat -c %u "\$XDG_RUNTIME_DIR" 2>/dev/null)" = "\$SESSION_UID" ]; then
    chmod 0700 "\$XDG_RUNTIME_DIR" 2>/dev/null || true
else
    RUNDIR="/run/user/\$SESSION_UID"
    if [ ! -d "\$RUNDIR" ] || [ "\$(stat -c %u "\$RUNDIR" 2>/dev/null)" != "\$SESSION_UID" ]; then
        RUNDIR="\$HOME/.xdg-runtime"; mkdir -p "\$RUNDIR" && chmod 0700 "\$RUNDIR"
    fi
    export XDG_RUNTIME_DIR="\$RUNDIR"
fi

if [ ! -S /run/seatd.sock ] && [ ! -S "\$XDG_RUNTIME_DIR/seatd.sock" ]; then
    # Con logind el socket no hace falta, pero esperamos un poco por si acaso
    i=0; while [ "\$i" -lt 5 ] && [ ! -S /run/seatd.sock ]; do i=\$((i+1)); sleep 1; done
fi

DAEMONS=""; DWL_PID=""
start_user_daemon(){
 n="\$1"; shift; pgrep -u "\$SESSION_UID" -x "\$n" >/dev/null 2>&1 && return 0
 command -v "\$n" >/dev/null 2>&1 || return 0
 "\$@" >/dev/null 2>&1 & DAEMONS="\$DAEMONS \$!"
}
clean_daemons(){ for p in \$DAEMONS; do kill "\$p" 2>/dev/null; done; for p in \$DAEMONS; do wait "\$p" 2>/dev/null; done; DAEMONS=""; }
end_session(){ [ -n "\$DWL_PID" ] && kill "\$DWL_PID" 2>/dev/null; exit "\$1"; }
trap clean_daemons EXIT; trap 'end_session 129' HUP; trap 'end_session 130' INT; trap 'end_session 143' TERM

start_user_daemon pipewire pipewire
start_user_daemon wireplumber wireplumber
command -v pipewire-pulse >/dev/null 2>&1 && start_user_daemon pipewire-pulse pipewire-pulse

$EXTRA_ENV
INICIO=\$(date +%s); $BARRA_CMD & DWL_PID=\$!; wait "\$DWL_PID"; ST=\$?; DWL_PID=""
if [ "\$ST" -ne 0 ] && [ -z "\$WLR_RENDERER" ] && [ \$((\$(date +%s)-INICIO)) -lt 5 ]; then
    echo "dwl-session: reintento con WLR_RENDERER=pixman" >&2
    export WLR_RENDERER=pixman WLR_NO_HARDWARE_CURSORS=1 LIBGL_ALWAYS_SOFTWARE=1
    $BARRA_CMD & DWL_PID=\$!; wait "\$DWL_PID"; ST=\$?; DWL_PID=""
fi
clean_daemons; trap - EXIT HUP INT TERM; exit "\$ST"
EOF
    sudo chmod +x /usr/local/bin/dwl-session

    if printf '%s' "$GPU_VENDORS" | grep -q nvidia; then
        info "GPU NVIDIA: anadiendo WLR_NO_HARDWARE_CURSORS=1."
        sudo sed -i 's|^INICIO=|export WLR_NO_HARDWARE_CURSORS=1\nINICIO=|' /usr/local/bin/dwl-session
    fi
    if [ "$GPU_HIBRIDA" -eq 1 ] && [ -n "$GPU_CARDS" ]; then
        sudo sed -i "s|^INICIO=|# HIBRIDA: descomenta si arranca en negro:\\n# export WLR_DRM_DEVICES=$GPU_CARDS\\nINICIO=|" /usr/local/bin/dwl-session
    fi

    # rebuild scripts
    sudo tee /usr/local/bin/dwl-rebuild >/dev/null <<'EOF'
#!/bin/sh
set -e; cd "$HOME/dwl"; make clean; make; sudo make install
echo "Listo. Cierra sesion para aplicar."
EOF
    sudo chmod +x /usr/local/bin/dwl-rebuild
    sudo tee /usr/local/bin/dwlb-rebuild >/dev/null <<'EOF'
#!/bin/sh
set -e; cd "$HOME/dwlb"
git pull --ff-only || echo "Aviso: no se pudo actualizar por git."
make clean; make; sudo make install
echo "Listo. Reinicia la sesion."
EOF
    sudo chmod +x /usr/local/bin/dwlb-rebuild

    # wayland-sessions desktop entry
    sudo mkdir -p /usr/share/wayland-sessions
    sudo tee /usr/share/wayland-sessions/dwl.desktop >/dev/null <<EOF
[Desktop Entry]
Name=dwl
Comment=dwm para Wayland
Exec=/usr/local/bin/dwl-session
Type=Application
DesktopNames=dwl
EOF

    # Atajos
    info "Creando ~/Atajos.txt..."
    write_config "$HOME/Atajos.txt" <<'EOF'
=========== ATAJOS PRINCIPALES dwl + dwlb ===========
Super+Enter ............ terminal (foot)
Super+d ................ lanzador (wmenu)
Super+q ................ cerrar ventana
Super+Shift+e .......... cerrar sesion
Super+w ................ ocultar/mostrar barra
Super+Shift+w .......... mover barra arriba/abajo
Super+(1-9) ............ ir a tag
Super+Shift+(1-9) ...... mandar ventana a tag
EOF

    info "Instalacion base completada."
}

# ==================================================================
# EJECUCION
# ==================================================================
instalar_base
configurar_greetd
iniciar_greetd

info "=========================================="
info " Instalacion completada con exito!"
info "=========================================="
info "Distro: $DISTRO_ID"
info "Barra: ${BARRA_ELEGIDA:-ninguna} ($DWLB_MODO)  |  wmenu: monospace $WMENU_FONT_SIZE  |  dwlb: monospace $DWLB_FONT_SIZE"
info "  ~/dwl/config.h ........... atajos (dwl-rebuild)"
info "  ~/.config/dwlb/config .... fuente/colores barra (sin compilar)"
info "  ~/Atajos.txt ............. chuleta: nano ~/Atajos.txt"
warn "REINICIA antes de entrar a dwl. Los grupos nuevos ('$SEAT_GROUP', video)"
warn "solo se aplican al volver a iniciar sesion. Comando: sudo reboot"
info ""
if [ "$DISTRO_FAMILIA" = "arch" ]; then
info "Drivers (referencia):"
info "  NVIDIA .... sudo pacman -S nvidia nvidia-utils lib32-nvidia-utils"
info "              y agrega nvidia_drm.modeset=1 a los parametros del kernel"
info "  AMD ....... sudo pacman -S mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon"
info "  Intel ..... sudo pacman -S mesa lib32-mesa vulkan-intel intel-media-driver"
info "  Steam ..... sudo pacman -S steam (necesita [multilib] habilitado)"
else
info "Drivers (referencia Void):"
info "  NVIDIA .... sudo xbps-install -S nvidia nvidia-libs-32bit"
info "  AMD ....... sudo xbps-install -S mesa-dri mesa-vulkan-radeon linux-firmware-amd"
info "  Intel ..... sudo xbps-install -S mesa-dri mesa-vulkan-intel intel-video-accel"
info "  Steam ..... activa repos nonfree/multilib, luego: sudo xbps-install -S steam"
fi

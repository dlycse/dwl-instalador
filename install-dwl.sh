#!/bin/sh
# install-dwl-v0.8.5
# Instalador de dwl (dwm para Wayland).
# Soporta:
#   - Void Linux (xbps + runit, modo original)
#   - Arch Linux y derivadas: Manjaro, EndeavourOS, Garuda, etc. (pacman + systemd)
#
# Entorno que instala: dwl + dwlb, foot, wmenu, swaybg, pipewire y arranque con
# greetd + tuigreet (unico gestor de inicio; lightdm se desactiva y desinstala si existe).
#
# Este script NO instala drivers de GPU ni Steam. Eso lo instalas tu mismo
# con el gestor de paquetes de tu distro cuando lo necesites (nonfree/multilib).
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
# 0. Comprobaciones previas QUE SON COMUNES A TODAS LAS DISTROS
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
# 0b. Detectar distro PRIMERO, antes de exigir comandos especificos
# ----------------------------------------------------------------
DISTRO_ID="unknown"
DISTRO_FAMILIA="unknown"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO_ID="${ID:-unknown}"
    ID_LIKE="${ID_LIKE:-}"
fi

# Normalizar familia de distro
case "$DISTRO_ID" in
    void)
        DISTRO_FAMILIA="void"
        ;;
    arch|manjaro|endeavouros|garuda|artix|archcraft|arcolinux|hyperbola|parabola)
        DISTRO_FAMILIA="arch"
        ;;
    *)
        # Mirar ID_LIKE por si es un derivado
        case "$ID_LIKE" in
            *arch*) DISTRO_FAMILIA="arch" ;;
            *void*) DISTRO_FAMILIA="void" ;;
            *)      DISTRO_FAMILIA="unknown" ;;
        esac
        ;;
esac

info "Distro detectada: $DISTRO_ID (familia: $DISTRO_FAMILIA)"

if [ "$DISTRO_FAMILIA" = "unknown" ]; then
    error "Este script solo es compatible con Void Linux y Arch Linux/derivadas."
    error "Distro detectada: $DISTRO_ID"
    exit 1
fi

# ----------------------------------------------------------------
# 0c. Definir variables y funciones ESPECIFICAS DE CADA DISTRO
# ----------------------------------------------------------------
if [ "$DISTRO_FAMILIA" = "void" ]; then
    # --- Void Linux (xbps + runit) ---
    PKG_INSTALL() { sudo xbps-install -Sy "$@"; }
    PKG_QUERY() { xbps-query "$1" >/dev/null 2>&1; }
    PKG_REMOVE() { sudo xbps-remove -R "$@"; }
    PKG_UPDATE() { sudo xbps-install -Su; }
    DEFAULT_GREETD_VT=7
    SEAT_GROUP="_seatd"
    GREETER_USER="_greeter"
    HAS_RC_CONF=1
    HAS_VCONSOLE_CONF=0

    # Paquetes
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
        chrony firefox btop cowsay dbus pciutils"

    # Funciones de servicios (runit)
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
            warn "No encontre /etc/sv/$1. Activalo a mano con: sudo ln -s /etc/sv/$1 /var/service/"
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
    start_svc() {
        sudo sv start "$1"
    }
    status_svc() {
        sudo sv status "$1" 2>&1 || true
    }
    desactivar_getty_vt() {
        VT="$1"
        if [ -L "/var/service/agetty-tty$VT" ]; then
            warn "Habia un agetty en tty$VT; lo quito para que greetd pueda usarla."
            disable_svc "agetty-tty$VT"
        fi
    }

    # Comprobaciones especificas de Void
    for CMD in xbps-install xbps-query sv; do
        if ! command -v "$CMD" >/dev/null 2>&1; then
            error "Falta '$CMD'. Este instalador requiere XBPS y runit de Void Linux."
            exit 1
        fi
    done
    if [ ! -d /var/service ]; then
        error "No existe /var/service. Comprueba que Void Linux y runit esten instalados correctamente."
        exit 1
    fi

elif [ "$DISTRO_FAMILIA" = "arch" ]; then
    # --- Arch Linux y derivadas (pacman + systemd) ---
    PKG_INSTALL() { sudo pacman -Sy --needed --noconfirm "$@"; }
    PKG_QUERY() { pacman -Qs "^$1$" >/dev/null 2>&1; }
    PKG_REMOVE() { sudo pacman -Rns --noconfirm "$@"; }
    PKG_UPDATE() { sudo pacman -Su --noconfirm; }
    DEFAULT_GREETD_VT=1
    SEAT_GROUP="seat"
    GREETER_USER="greeter"
    HAS_RC_CONF=0
    HAS_VCONSOLE_CONF=1

    # Verificar que multilib este habilitado (para 32 bits / Steam)
    if ! grep -qE '^\[multilib\]' /etc/pacman.conf; then
        warn "El repositorio [multilib] NO esta habilitado en /etc/pacman.conf."
        warn "Lo necesitaras si quieres instalar Steam o juegos de 32 bits."
        warn "Habilitalo descomentando las lineas [multilib] y Include, luego ejecuta sudo pacman -Sy."
    fi

    # Paquetes (Arch no separa headers en *-devel)
    PKGS_BASE="base-devel \
        libinput wayland wayland-protocols \
        libxkbcommon wlroots libseat seatd \
        xorg-xwayland mesa libdrm \
        pango cairo pixman fcft tllist \
        foot wmenu fastfetch \
        pipewire wireplumber pipewire-alsa \
        swaybg swaylock grim slurp wl-clipboard \
        brightnessctl curl procps-ng \
        nano ttf-nerd-fonts-symbols ttf-nerd-fonts-symbols-mono lf mpv zathura zathura-pdf-poppler xdg-utils imv \
        chrony firefox btop cowsay dbus pciutils greetd tuigreet turnstile"

    # Funciones de servicios (systemd)
    enable_svc() {
        if systemctl is-enabled --quiet "$1" 2>/dev/null; then
            info "El servicio $1 ya esta habilitado en systemd."
        else
            sudo systemctl enable --now "$1" || return 1
            info "Servicio $1 habilitado en systemd."
        fi
    }
    disable_svc() {
        if systemctl is-enabled --quiet "$1" 2>/dev/null; then
            sudo systemctl disable --now "$1" 2>/dev/null || true
            info "Servicio $1 desactivado."
        fi
    }
    start_svc() {
        sudo systemctl start "$1"
    }
    status_svc() {
        systemctl status "$1" --no-pager -l 2>&1 || true
    }
    desactivar_getty_vt() {
        VT="$1"
        GETTY_SVC="getty@tty${VT}.service"
        if systemctl is-enabled --quiet "$GETTY_SVC" 2>/dev/null; then
            warn "Habia un getty en tty$VT; lo desactivo para que greetd pueda usarla."
            sudo systemctl disable --now "$GETTY_SVC" 2>/dev/null || true
        fi
    }

    # Comprobaciones especificas de Arch
    if ! command -v pacman >/dev/null 2>&1; then
        error "Falta 'pacman'. Este instalador requiere un sistema basado en Arch Linux."
        exit 1
    fi
    if ! command -v systemctl >/dev/null 2>&1; then
        warn "No se encontro systemctl (usas Artix/OpenRC?). El script intentara seguir,"
        warn "pero es posible que la gestion de servicios no funcione automaticamente."
    fi
fi

# ----------------------------------------------------------------
# 0d. Variables de configuracion generales
# ----------------------------------------------------------------
GREETD_VT="${GREETD_VT:-$DEFAULT_GREETD_VT}"
case "$GREETD_VT" in
    ''|*[!0-9]*) error "GREETD_VT debe ser un numero entero entre 1 y 12."; exit 1 ;;
esac
if [ "$GREETD_VT" -lt 1 ] || [ "$GREETD_VT" -gt 12 ]; then
    error "GREETD_VT debe estar entre 1 y 12 (recibido: $GREETD_VT)."
    exit 1
fi

DWL_REPO="https://codeberg.org/dwl/dwl.git"
DWLB_REPO="https://github.com/kolunmi/dwlb.git"
WALLPAPER_DIR="$HOME/Pictures"
WALLPAPER_PATH="$WALLPAPER_DIR/wallpaper.jpg"
WALLPAPER_URL="https://wallpapercave.com/download/empty-error-wallpapers-wp8330753"

# --- Tamaños de fuente: wmenu se ve bien en 11, dwlb uno menos para que la
# barra quede compacta y a la misma altura visual que el lanzador.
WMENU_FONT_SIZE="${WMENU_FONT_SIZE:-11}"
DWLB_FONT_SIZE="${DWLB_FONT_SIZE:-10}"

# Apariencia de dwlb (paleta Catppuccin Mocha, igual que config.h de dwl)
DWLB_FONT="${DWLB_FONT:-monospace:size=$DWLB_FONT_SIZE}"
DWLB_PAD="${DWLB_PAD:--2}"        # padding vertical negativo = barra mas delgada
DWLB_HPAD="${DWLB_HPAD:-6}"       # padding horizontal para que el texto no quede pegado al borde
DWLB_ACTIVE_FG="#ffffff"
DWLB_ACTIVE_BG="#89b4fa"
DWLB_OCCUPIED_FG="#cdd6f4"
DWLB_OCCUPIED_BG="#313244"
DWLB_INACTIVE_FG="#a6adc8"
DWLB_INACTIVE_BG="#1e1e2e"
DWLB_URGENT_FG="#1e1e2e"
DWLB_URGENT_BG="#f38ba8"
DWLB_MIDDLE_BG="#1e1e2e"

# Deteccion de GPU: las rellena detectar_gpus().
GPU_VENDORS=""
GPU_CARDS=""
GPU_HIBRIDA=0

# Comprobacion de espacio libre
FREE_GB=$(df -BG --output=avail "$HOME" 2>/dev/null | tail -n1 | tr -d 'G ' )
if [ -n "$FREE_GB" ] && [ "$FREE_GB" -lt 20 ] 2>/dev/null; then
    warn "Solo detecto ${FREE_GB}GB libres en $HOME. Se recomiendan al menos 20GB."
    printf "Continuar de todas formas? [y/N] "
    read -r CONTINUAR_DISCO
    case "$CONTINUAR_DISCO" in
        y|Y) ;;
        *) error "Cancelado por el usuario."; exit 1 ;;
    esac
fi

# ==================================================================
# MENU DE SELECCION
# ==================================================================
echo "=========================================="
echo "    Instalador dwl v0.8"
echo "=========================================="
echo "Distro objetivo: $DISTRO_ID"
echo "Barra: dwlb (https://github.com/kolunmi/dwlb)"
echo "Gestor de inicio: greetd + tuigreet"
echo "(si tenias lightdm, se desactivara y desinstalara)"
echo "(los drivers de GPU y Steam no se tocan: los instalas tu aparte)"
echo
echo "1) Instalar dwl + dwlb, foot, wmenu, swaybg y el arranque con greetd"
echo "2) Salir"
printf "Opcion [1-2]: "
read -r OPCION

case "$OPCION" in
    1) ;;
    2) info "Saliendo..."; exit 0 ;;
    *) error "Opcion no valida."; exit 1 ;;
esac

# ==================================================================
# FUNCION: detectar TODAS las GPUs (incluidas las hibridas / Optimus)
# Es SOLO informativa: aqui no se instala ningun driver.
# ==================================================================
detectar_gpus() {
    if ! command -v lspci >/dev/null 2>&1; then
        info "Instalando pciutils para detectar las GPU..."
        PKG_INSTALL pciutils || return 1
    fi
    if ! command -v lspci >/dev/null 2>&1; then
        error "pciutils se instalo, pero lspci sigue sin estar disponible."
        return 1
    fi

    GPU_LISTA=$(lspci -nn | grep -iE 'vga|3d controller|display controller' || true)
    GPU_VENDORS=""

    if printf '%s' "$GPU_LISTA" | grep -qiE '\[10de:[[:xdigit:]]{4}\]|(^|[^[:alnum:]])NVIDIA([^[:alnum:]]|$)'; then
        GPU_VENDORS="$GPU_VENDORS nvidia"
    fi
    if printf '%s' "$GPU_LISTA" | grep -qiE '\[1002:[[:xdigit:]]{4}\]|(^|[^[:alnum:]])(AMD|Radeon|ATI)([^[:alnum:]]|$)'; then
        GPU_VENDORS="$GPU_VENDORS amd"
    fi
    if printf '%s' "$GPU_LISTA" | grep -qiE '\[8086:[[:xdigit:]]{4}\]|(^|[^[:alnum:]])Intel([^[:alnum:]]|$)'; then
        GPU_VENDORS="$GPU_VENDORS intel"
    fi
    GPU_VENDORS=$(printf '%s' "$GPU_VENDORS" | sed 's/^ //')

    GPU_NUM=$(printf '%s\n' "$GPU_LISTA" | grep -c . || true)
    GPU_CARDS=$(ls -1 /dev/dri/card* 2>/dev/null | sort -V | tr '\n' ':' | sed 's/:$//')

    [ -n "$GPU_VENDORS" ] || GPU_VENDORS="desconocida"

    if [ "$GPU_NUM" -ge 2 ]; then
        GPU_HIBRIDA=1
    else
        GPU_HIBRIDA=0
    fi

    info "GPUs detectadas ($GPU_NUM):"
    printf '%s\n' "$GPU_LISTA" | sed 's/^/    /'
    info "Fabricantes: $GPU_VENDORS"
    if [ "$GPU_HIBRIDA" -eq 1 ]; then
        info "Equipo con varias GPU (hibrida / Optimus). Si dwl arrancara en la"
        info "GPU equivocada, el wrapper dwl-session deja WLR_DRM_DEVICES ya"
        info "escrita como comentario: basta con descomentar esa linea."
    fi
    [ -n "$GPU_CARDS" ] && info "Nodos DRM: $GPU_CARDS"
    return 0
}

# ==================================================================
# FUNCION: barra dwlb (repositorio de kolunmi)
# ==================================================================
compilar_dwlb() {
    cd "$HOME" || return 1
    if [ -d dwlb ]; then
        info "Ya existe ~/dwlb: se reutiliza el clon existente."
    else
        info "Clonando dwlb desde $DWLB_REPO ..."
        git clone "$DWLB_REPO" || return 1
    fi
    cd "$HOME/dwlb" || return 1
    fix_owner || return 1

    if [ -f config.def.h ] && [ ! -f config.h ]; then
        cp config.def.h config.h
        info "Creado ~/dwlb/config.h a partir de config.def.h."
    fi

    # Parche de compatibilidad layer-shell
    if grep -qE 'zwlr_layer_shell_v1_interface, [0-9]+\)' dwlb.c 2>/dev/null; then
        DWLB_LS_VER=$(grep -oE 'zwlr_layer_shell_v1_interface, [0-9]+\)' dwlb.c | head -n1 | \
            sed -n 's/.*,[[:space:]]*\([0-9][0-9]*\))$/\1/p')
        case "$DWLB_LS_VER" in
            ''|*[!0-9]*) DWLB_LS_VER="" ;;
        esac
        if [ -n "$DWLB_LS_VER" ] && [ "$DWLB_LS_VER" -gt 1 ]; then
            sed -i "s|&zwlr_layer_shell_v1_interface, $DWLB_LS_VER)|\&zwlr_layer_shell_v1_interface, (version < $DWLB_LS_VER ? version : $DWLB_LS_VER))|" dwlb.c || \
                warn "No pude aplicar el parche layer-shell a dwlb; sigo igualmente."
            info "Parche layer-shell aplicado a dwlb (pide como mucho la version $DWLB_LS_VER)."
        fi
    fi

    make clean 2>/dev/null || true
    if ! make; then
        error "Fallo la compilacion de dwlb. Revisa que las dependencias de desarrollo esten instaladas."
        return 1
    fi
    sudo make install || return 1

    if [ -f dwlb.1 ] && ! command -v man >/dev/null 2>&1; then
        :
    elif [ -f dwlb.1 ] && [ ! -f /usr/local/share/man/man1/dwlb.1 ]; then
        sudo mkdir -p /usr/local/share/man/man1
        sudo cp dwlb.1 /usr/local/share/man/man1/dwlb.1
        info "Manual instalado: consulta 'man 1 dwlb'."
    fi

    command -v dwlb >/dev/null 2>&1 || {
        error "dwlb no quedo en el PATH tras 'make install'."
        return 1
    }
    return 0
}

# ==================================================================
# FUNCION: configuracion de dwlb (~/.config/dwlb/config + estado)
# ==================================================================
configurar_dwlb() {
    info "Escribiendo la configuracion de dwlb (fuente $DWLB_FONT_SIZE, padding ${DWLB_PAD}px)..."
    mkdir -p "$HOME/.config/dwlb"

    write_config "$HOME/.config/dwlb/config" <<EOF
# Configuracion de dwlb  (https://github.com/kolunmi/dwlb)
# Generada por install-dwl-v0.8.sh
# Una opcion por linea, tal cual se pasarian en la linea de comandos.
# Referencia completa: man 1 dwlb

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

# HiDPI: descomenta si tu monitor usa escalado 2x
# -scale 2
EOF

    info "Instalando 'dwlb-status' (texto de estado de la barra)..."
    sudo tee /usr/local/bin/dwlb-status >/dev/null <<'EOF'
#!/bin/sh
COLOR_ETIQ="89b4fa"
COLOR_TXT="cdd6f4"
COLOR_ALERTA="f38ba8"

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
        CAP=$(cat "$BAT/capacity")
        EST=$(cat "$BAT/status" 2>/dev/null || echo Unknown)
        case "$EST" in
            Charging) ICONO="+" ;;
            Full)     ICONO="=" ;;
            *)        ICONO="-" ;;
        esac
        if [ "$CAP" -le 15 ] && [ "$EST" != "Charging" ]; then
            COLOR="$COLOR_ALERTA"
        else
            COLOR="$COLOR_TXT"
        fi
        printf '^fg(%s)BAT^fg(%s) %s%s%%  ' "$COLOR_ETIQ" "$COLOR" "$ICONO" "$CAP"
        break
    done
}

bloque_cpu() {
    [ -r /proc/loadavg ] || return 0
    printf '^fg(%s)CPU^fg(%s) %s  ' "$COLOR_ETIQ" "$COLOR_TXT" "$(cut -d' ' -f1 /proc/loadavg)"
}

bloque_ram() {
    [ -r /proc/meminfo ] || return 0
    awk -v e="$COLOR_ETIQ" -v t="$COLOR_TXT" '
        /^MemTotal:/     { total=$2 }
        /^MemAvailable:/ { disp=$2 }
        END { if (total) printf "^fg(%s)RAM^fg(%s) %.1fG  ", e, t, (total-disp)/1048576 }
    ' /proc/meminfo
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
# FUNCION: greetd + tuigreet
# ==================================================================
configurar_greetd() {

    if [ -d /etc/sv/lightdm ] || PKG_QUERY lightdm || PKG_QUERY lightdm-gtk-greeter || command -v lightdm >/dev/null 2>&1; then
        info "Encontre lightdm instalado: lo quito (da errores y no se usa con greetd)."
        disable_svc lightdm
        PAQUETES_LIGHTDM=""
        for PKG in lightdm lightdm-gtk3-greeter lightdm-gtk-greeter; do
            if PKG_QUERY "$PKG"; then
                PAQUETES_LIGHTDM="$PAQUETES_LIGHTDM $PKG"
            fi
        done
        if [ -n "$PAQUETES_LIGHTDM" ]; then
            PKG_REMOVE $PAQUETES_LIGHTDM || \
                warn "No se pudo desinstalar lightdm. Hazlo a mano."
        fi
    fi

    # En Arch greetd/tuigreet/turnstile ya van en la lista de paquetes base
    if [ "$DISTRO_FAMILIA" = "void" ]; then
        info "Instalando greetd, tuigreet y turnstile..."
        PKG_INSTALL greetd tuigreet turnstile
    fi

    SESSION_CMD="/usr/local/bin/dwl-session"
    info "Comando de la sesion: $SESSION_CMD"

    sudo mkdir -p /etc/greetd
    backup_file /etc/greetd/config.toml

    sudo tee /etc/greetd/config.toml >/dev/null <<EOF
# Generado por install-dwl-v0.8.sh
# Documentacion: man 1 tuigreet

[terminal]
vt = $GREETD_VT

[default_session]
command = "tuigreet --time --time-format '%H:%M  %d/%m/%Y' --user-menu --remember --greeting 'Bienvenido a dwl' --power-shutdown 'shutdown -h now' --power-reboot 'shutdown -r now' --cmd $SESSION_CMD"
user = "$GREETER_USER"
EOF
    info "Escrito /etc/greetd/config.toml"

    info "Configurando turnstile (prepara XDG_RUNTIME_DIR mediante PAM)..."
    enable_svc turnstiled || warn "turnstiled no esta disponible; dwl-session usara su directorio privado de respaldo."

    PAM_FILE="/etc/pam.d/greetd"
    if [ -f /usr/lib/security/pam_turnstile.so ] || [ -f /usr/lib64/security/pam_turnstile.so ]; then
        if [ ! -f "$PAM_FILE" ]; then
            warn "No existe $PAM_FILE (el paquete greetd deberia haberlo creado)."
            warn "No puedo activar pam_turnstile automaticamente; revisa la instalacion de greetd."
        elif grep -q 'pam_turnstile.so' "$PAM_FILE"; then
            info "pam_turnstile ya estaba en $PAM_FILE."
        else
            backup_file "$PAM_FILE"
            printf '\n# Anadido por install-dwl-v0.8.sh para turnstile (XDG_RUNTIME_DIR)\nsession\toptional\tpam_turnstile.so\n' | \
                sudo tee -a "$PAM_FILE" >/dev/null
            info "Anadido 'session optional pam_turnstile.so' a $PAM_FILE"
            warn "Si algo falla al iniciar sesion, restaura la copia .bak-* de $PAM_FILE."
        fi
    else
        warn "No encontre pam_turnstile.so: se omite la parte de PAM."
        warn "Sin el, XDG_RUNTIME_DIR puede quedar vacio (el wrapper dwl-session tiene un plan B)."
    fi

    desactivar_getty_vt "$GREETD_VT"

    if [ "$DISTRO_FAMILIA" = "void" ] && [ ! -d /etc/sv/greetd ]; then
        error "El paquete greetd no creo /etc/sv/greetd; no habilito un servicio incompleto."
        return 1
    fi
    if [ "$DISTRO_FAMILIA" = "arch" ] && ! systemctl list-unit-files | grep -q greetd.service; then
        error "El paquete greetd no incluyo greetd.service; no habilito un servicio incompleto."
        return 1
    fi
}

# ==================================================================
# FUNCION: arrancar greetd (LO ULTIMO que hace el script)
# ==================================================================
iniciar_greetd() {
    if [ ! -x /usr/local/bin/dwl-session ]; then
        error "No existe /usr/local/bin/dwl-session: no arranco greetd."
        return 1
    fi

    if ! enable_svc greetd; then
        error "No pude habilitar el servicio greetd."
        return 1
    fi

    info "Todo instalado: arrancando greetd..."
    if ! start_svc greetd; then
        error "No se pudo iniciar greetd. Revisa su estado con: sudo sv status greetd  (Void) o systemctl status greetd (Arch)"
        return 1
    fi

    ESTADO_GREETD=$(status_svc greetd)
    case "$ESTADO_GREETD" in
        *run:*|*active*running*) info "greetd activo: tienes tuigreet en la tty$GREETD_VT." ;;
        *)     warn "No se puede confirmar que greetd este activo: $ESTADO_GREETD" ;;
    esac
}
# ==================================================================
# FUNCION: detectar hardware (VM y fuente del lanzador)
# ==================================================================
detectar_hardware() {
    ES_VM=0
    if grep -qw hypervisor /proc/cpuinfo 2>/dev/null; then
        ES_VM=1
        VM_NOMBRE=$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo "desconocida")
        warn "Maquina virtual detectada ($VM_NOMBRE)."
        warn "Si dwl no arranca con 'couldn't create renderer', activa la aceleracion 3D"
        warn "en la VM. Aun sin ella, el wrapper reintenta solo con render por software."
    fi

    info "Fuente del lanzador wmenu: monospace $WMENU_FONT_SIZE"
    info "Fuente de la barra dwlb:    monospace $DWLB_FONT_SIZE"

    EXTRA_ENV=""
    if [ "$ES_VM" -eq 1 ]; then
        EXTRA_ENV="export WLR_NO_HARDWARE_CURSORS=1"
    fi
}
# ==================================================================
# FUNCION: instalacion de dwl
# ==================================================================
instalar_base() {

    # --------------------------------------------------------
    # 0. Kernel: solo preguntar en Void; Arch ya trae kernel actualizado
    # --------------------------------------------------------
    info "Kernel actualmente en uso: $(uname -r)"
    if [ "$DISTRO_FAMILIA" = "void" ]; then
        info "Buscando un paquete de kernel de la serie 7.x en los repositorios..."
        KERNEL_7_PKGVER=$(xbps-query --regex -Rs '^linux7\.[0-9]+' 2>/dev/null | \
            awk '{print $2}' | \
            grep -E '^linux7\.[0-9]+-7\.[0-9]+([._][0-9]+)*$' | \
            sort -V | tail -n1)
        KERNEL_7_PKG=$(printf '%s' "$KERNEL_7_PKGVER" | sed 's/-7\..*$//')

        if [ -z "$KERNEL_7_PKG" ]; then
            warn "No encontre un paquete linux7.x en XBPS; se conserva el kernel actual."
        else
            info "Kernel 7.x disponible: $KERNEL_7_PKG ($KERNEL_7_PKGVER)"
            printf "Que kernel quieres usar?\n"
            printf "  1) Conservar el kernel que trae Void (opcion predeterminada)\n"
            printf "  2) Instalar $KERNEL_7_PKG junto al kernel actual\n"
            printf "Opcion [1]: "
            read -r OPCION_KERNEL
            OPCION_KERNEL="${OPCION_KERNEL:-1}"
            case "$OPCION_KERNEL" in
                1)
                    info "Se conserva el kernel actual de Void."
                    ;;
                2)
                    info "Instalando $KERNEL_7_PKG sin quitar el kernel actual..."
                    if sudo xbps-install -Sy "$KERNEL_7_PKG"; then
                        info "$KERNEL_7_PKG instalado junto al kernel actual."
                        warn "Despues de reiniciar, revisa el menu del gestor de arranque para elegirlo."
                    else
                        warn "No se pudo instalar $KERNEL_7_PKG; se conserva el kernel actual."
                    fi
                    ;;
                *)
                    error "Opcion de kernel no valida; usa 1 o 2."
                    return 1
                    ;;
            esac
        fi
    else
        info "En Arch Linux el kernel se actualiza automaticamente con el sistema, se omite la seleccion."
    fi

    # --------------------------------------------------------
    # 1. Paquetes
    # --------------------------------------------------------
    info "Instalando dependencias de dwl y del entorno Wayland..."
    if ! PKG_INSTALL $PKGS_BASE; then
        error "La instalacion de paquetes fallo. Revisa tu conexion/repos e intenta de nuevo."
        return 1
    fi

    info "Habilitando servicios (dbus, chronyd, seatd)..."
    enable_svc dbus || warn "No se pudo habilitar dbus."
    enable_svc chronyd || warn "No se pudo habilitar chronyd; la hora seguira con el reloj configurado."

    REAL_USER=$(id -un)

    # --------------------------------------------------------
    # 2. Grupos de usuario
    # --------------------------------------------------------
    info "Configurando grupos de permisos para el usuario $REAL_USER..."

    if ! getent group "$SEAT_GROUP" >/dev/null 2>&1; then
        error "No existe el grupo '$SEAT_GROUP' (grupo de seatd)."
        warn "Reinstala/verifica seatd con el gestor de paquetes."
        return 1
    fi

    if ! sudo usermod -aG "$SEAT_GROUP" "$REAL_USER"; then
        error "No pude anadir a $REAL_USER al grupo '$SEAT_GROUP'."
        warn "Hazlo a mano: sudo usermod -aG $SEAT_GROUP $REAL_USER"
        return 1
    fi

    if getent group video >/dev/null 2>&1; then
        if sudo usermod -aG video "$REAL_USER"; then
            info "Usuario $REAL_USER agregado al grupo 'video'."
        else
            warn "No pude anadir a $REAL_USER al grupo video."
            warn "Hazlo a mano: sudo usermod -aG video $REAL_USER"
        fi
    else
        warn "No existe el grupo video; revisa la instalacion base del sistema."
    fi

    if groups "$REAL_USER" 2>/dev/null | tr ' ' '\n' | grep -qx "$SEAT_GROUP"; then
        info "Usuario $REAL_USER agregado al grupo '$SEAT_GROUP'."
    else
        warn "No pude confirmar que $REAL_USER este en '$SEAT_GROUP'."
        warn "Si dwl no arranca: sudo usermod -aG $SEAT_GROUP $REAL_USER"
    fi

    enable_svc seatd || return 1
    warn "Los grupos nuevos solo se aplican despues de cerrar sesion y volver a entrar (o reiniciar)."

    # --------------------------------------------------------
    # 3. Deteccion de GPUs
    # --------------------------------------------------------
    detectar_hardware
    detectar_gpus || warn "No pude detectar las GPU; seguire sin sus avisos (el resto no cambia)."

    # --------------------------------------------------------
    # 4. Zona horaria
    # --------------------------------------------------------
    info "Configuracion de zona horaria."
    printf "Escribe tu pais (ej: Colombia, Mexico, Argentina, Espana).\nDeja vacio para usar Colombia por defecto: "
    read -r PAIS_INPUT
    PAIS_INPUT="${PAIS_INPUT:-Colombia}"

    PAIS_NORM=$(printf '%s' "$PAIS_INPUT" | tr '[:upper:]' '[:lower:]' | \
        sed 's/á/a/g; s/é/e/g; s/í/i/g; s/ó/o/g; s/ú/u/g; s/ñ/n/g')

    TZ_INPUT=""
    case "$PAIS_NORM" in
        colombia)                          TZ_INPUT="America/Bogota" ;;
        mexico)                            TZ_INPUT="America/Mexico_City" ;;
        argentina)                         TZ_INPUT="America/Buenos_Aires" ;;
        chile)                             TZ_INPUT="America/Santiago" ;;
        peru)                              TZ_INPUT="America/Lima" ;;
        ecuador)                           TZ_INPUT="America/Guayaquil" ;;
        venezuela)                         TZ_INPUT="America/Caracas" ;;
        bolivia)                           TZ_INPUT="America/La_Paz" ;;
        paraguay)                          TZ_INPUT="America/Asuncion" ;;
        uruguay)                           TZ_INPUT="America/Montevideo" ;;
        panama)                            TZ_INPUT="America/Panama" ;;
        "costa rica")                      TZ_INPUT="America/Costa_Rica" ;;
        guatemala)                         TZ_INPUT="America/Guatemala" ;;
        honduras)                          TZ_INPUT="America/Tegucigalpa" ;;
        "el salvador")                     TZ_INPUT="America/El_Salvador" ;;
        nicaragua)                         TZ_INPUT="America/Managua" ;;
        "republica dominicana")            TZ_INPUT="America/Santo_Domingo" ;;
        cuba)                              TZ_INPUT="America/Havana" ;;
        "puerto rico")                     TZ_INPUT="America/Puerto_Rico" ;;
        brasil|brazil)                     TZ_INPUT="America/Sao_Paulo" ;;
        "estados unidos"|usa|eeuu)         TZ_INPUT="America/New_York" ;;
        canada)                            TZ_INPUT="America/Toronto" ;;
        espana|spain)                      TZ_INPUT="Europe/Madrid" ;;
        francia|france)                    TZ_INPUT="Europe/Paris" ;;
        alemania|germany)                  TZ_INPUT="Europe/Berlin" ;;
        italia|italy)                      TZ_INPUT="Europe/Rome" ;;
        "reino unido"|uk|"united kingdom") TZ_INPUT="Europe/London" ;;
        */*)                               TZ_INPUT="$PAIS_INPUT" ;;
        *)                                 TZ_INPUT="" ;;
    esac

    case "$TZ_INPUT" in
        *[!A-Za-z0-9_+/-]*|/*|../*|*/../*|*/..)
            warn "La zona horaria indicada contiene caracteres/rutas no permitidos."
            TZ_INPUT=""
            ;;
    esac

    if [ -n "$TZ_INPUT" ] && [ -f "/usr/share/zoneinfo/$TZ_INPUT" ]; then
        info "Pais: $PAIS_INPUT -> Zona horaria: $TZ_INPUT"
        sudo ln -sf "/usr/share/zoneinfo/$TZ_INPUT" /etc/localtime || warn "No pude enlazar /etc/localtime."
        # Escribir /etc/timezone (comun en Debian/Arch)
        printf '%s\n' "$TZ_INPUT" | sudo tee /etc/timezone >/dev/null 2>&1 || true
        if [ "$DISTRO_FAMILIA" = "void" ]; then
            sudo hwclock --systohc 2>/dev/null || warn "No se pudo sincronizar el reloj de hardware (se ignora)."
            if grep -qE '^[#[:space:]]*TIMEZONE=' /etc/rc.conf 2>/dev/null; then
                sudo sed -i "s|^[#[:space:]]*TIMEZONE=.*|TIMEZONE=\"$TZ_INPUT\"|" /etc/rc.conf || warn "No pude actualizar TIMEZONE en /etc/rc.conf."
            else
                printf 'TIMEZONE="%s"\n' "$TZ_INPUT" | sudo tee -a /etc/rc.conf >/dev/null || warn "No pude escribir TIMEZONE en /etc/rc.conf."
            fi
        fi
    else
        warn "No reconoci '$PAIS_INPUT' como pais. Se deja la zona horaria sin cambios."
    fi

    # --------------------------------------------------------
    # 5. Teclado
    # --------------------------------------------------------
    info "Configuracion de teclado."
    KB_XKB=""
    KB_CONSOLA=""
    while true; do
        printf "Selecciona la distribucion de teclado:\n"
        printf "  1) Ingles (us)\n"
        printf "  2) Espanol de Espana (es)\n"
        printf "  3) Latinoamericano (latam)\n"
        printf "Opcion [3]: "
        read -r OPCION_TECLADO
        OPCION_TECLADO="${OPCION_TECLADO:-3}"
        case "$OPCION_TECLADO" in
            1) KB_XKB="us";    KB_CONSOLA="us";        break ;;
            2) KB_XKB="es";    KB_CONSOLA="es";        break ;;
            3) KB_XKB="latam"; KB_CONSOLA="la-latin1"; break ;;
            *) warn "Opcion no valida, elige 1, 2 o 3." ;;
        esac
    done

    if [ -n "$KB_CONSOLA" ]; then
        if [ "$HAS_RC_CONF" -eq 1 ]; then
            if grep -qE '^[#[:space:]]*KEYMAP=' /etc/rc.conf 2>/dev/null; then
                sudo sed -i "s|^[#[:space:]]*KEYMAP=.*|KEYMAP=\"$KB_CONSOLA\"|" /etc/rc.conf || warn "No pude actualizar KEYMAP en /etc/rc.conf."
            else
                printf 'KEYMAP="%s"\n' "$KB_CONSOLA" | sudo tee -a /etc/rc.conf >/dev/null || warn "No pude escribir KEYMAP en /etc/rc.conf."
            fi
        fi
        if [ "$HAS_VCONSOLE_CONF" -eq 1 ]; then
            backup_file /etc/vconsole.conf
            if grep -qE '^KEYMAP=' /etc/vconsole.conf 2>/dev/null; then
                sudo sed -i "s|^KEYMAP=.*|KEYMAP=$KB_CONSOLA|" /etc/vconsole.conf || warn "No pude actualizar KEYMAP en /etc/vconsole.conf."
            else
                printf 'KEYMAP=%s\n' "$KB_CONSOLA" | sudo tee -a /etc/vconsole.conf >/dev/null || warn "No pude escribir KEYMAP en /etc/vconsole.conf."
            fi
        fi
        command -v loadkeys >/dev/null 2>&1 && sudo loadkeys "$KB_CONSOLA" 2>/dev/null || true
    fi

    # --------------------------------------------------------
    # 6. Clonar y compilar dwl
    # --------------------------------------------------------
    cd "$HOME"
    if [ ! -d dwl ]; then
        info "Clonando dwl..."
        git clone "$DWL_REPO"
    fi
    cd dwl
    fix_owner

    if [ -f protocols/dwl-ipc-unstable-v2.xml ] || [ -f protocols/dwl-ipc-unstable-v1.xml ]; then
        DWLB_IPC=1
        info "dwl incluye el protocolo IPC: dwlb usara -ipc (clic en los tags funcional)."
    else
        DWLB_IPC=0
        info "dwl sin parche IPC: dwlb leera el estado por stdin (-no-ipc)."
    fi

    if [ -f config.h ] && { grep -q 'static const char \*tags\[\]' config.h || \
                            ! grep -q 'TAGCOUNT' config.h || \
                            ! grep -q 'log_level' config.h || \
                            ! grep -q 'axes\[\]' config.h; }; then
        CONFIG_VIEJO="config.h.antiguo-$(date +%Y%m%d%H%M%S)"
        warn "Tu ~/dwl/config.h usa la API ANTIGUA de dwl (falta TAGCOUNT/log_level/axes)."
        warn "Es justo lo que provoca los errores 'TAGCOUNT undeclared' al compilar."
        mv config.h "$CONFIG_VIEJO"
        warn "Lo guarde como ~/dwl/$CONFIG_VIEJO y escribo uno nuevo compatible."
    fi

    if [ -f config.h ]; then
        warn "config.h ya existe y es compatible: se conserva tu version."
        warn "Si quieres regenerarlo, borra ~/dwl/config.h y vuelve a ejecutar."
    else
        info "Escribiendo config.h personalizado (atajos, volumen, brillo, screenshot, barra)..."

        cat > config.h <<EOF
/* Configuracion de dwl generada por install-dwl-v0.8.sh */
#define COLOR(hex)    { ((hex >> 24) & 0xFF) / 255.0f, \\
                        ((hex >> 16) & 0xFF) / 255.0f, \\
                        ((hex >> 8) & 0xFF) / 255.0f, \\
                        (hex & 0xFF) / 255.0f }

static const int sloppyfocus               = 1;
static const int bypass_surface_visibility = 0;
static const unsigned int borderpx         = 2;
static const unsigned int snap             = 32;
static const float rootcolor[]             = COLOR(0x1e1e2eff);
static const float bordercolor[]           = COLOR(0x313244ff);
static const float focuscolor[]            = COLOR(0x89b4faff);
static const float urgentcolor[]           = COLOR(0xf38ba8ff);
static const float fullscreen_bg[]         = {0.0f, 0.0f, 0.0f, 1.0f};

#define TAGCOUNT (9)
static int log_level = WLR_ERROR;

static const Rule rules[] = {
    { "Gimp",     NULL,       0,            1,           -1 },
    { "firefox",  NULL,       1 << 0,       0,           -1 },
};

static const Layout layouts[] = {
    { "[]=",      tile },
    { "><>",      NULL },
    { "[M]",      monocle },
};

static const MonitorRule monrules[] = {
    { NULL,       0.55f, 1,      1,    &layouts[0], WL_OUTPUT_TRANSFORM_NORMAL,  -1,  -1 },
};

static const struct xkb_rule_names xkb_rules = {
    .rules = NULL, .model = NULL, .layout = "$KB_XKB", .variant = NULL, .options = NULL,
};

static const int repeat_rate = 25;
static const int repeat_delay = 600;

static const int tap_to_click = 1;
static const int tap_and_drag = 1;
static const int drag_lock = 1;
static const int natural_scrolling = 0;
static const int disable_while_typing = 1;
static const int left_handed = 0;
static const int middle_button_emulation = 0;
static const enum libinput_config_scroll_method scroll_method = LIBINPUT_CONFIG_SCROLL_2FG;
static const enum libinput_config_click_method click_method = LIBINPUT_CONFIG_CLICK_METHOD_BUTTON_AREAS;
static const uint32_t send_events_mode = LIBINPUT_CONFIG_SEND_EVENTS_ENABLED;
static const enum libinput_config_accel_profile accel_profile = LIBINPUT_CONFIG_ACCEL_PROFILE_ADAPTIVE;
static const double accel_speed = 0.0;
static const enum libinput_config_tap_button_map button_map = LIBINPUT_CONFIG_TAP_MAP_LRM;

#define MODKEY WLR_MODIFIER_LOGO

#define TAGKEYS(KEY,SKEY,TAG) \\
    { MODKEY,                    KEY,            view,            {.ui = 1 << TAG} }, \\
    { MODKEY|WLR_MODIFIER_CTRL,  KEY,            toggleview,      {.ui = 1 << TAG} }, \\
    { MODKEY|WLR_MODIFIER_SHIFT, SKEY,           tag,             {.ui = 1 << TAG} }, \\
    { MODKEY|WLR_MODIFIER_CTRL|WLR_MODIFIER_SHIFT,SKEY,toggletag, {.ui = 1 << TAG} }

#define SHCMD(cmd) { .v = (const char*[]){ "/bin/sh", "-c", cmd, NULL } }

static const char *termcmd[]    = { "foot", NULL };
static const char *browsercmd[] = { "firefox", NULL };
static const char *dmenucmd[]   = { "sh", "-c", "dwlb -toggle-visibility all; wmenu-run -f 'monospace $WMENU_FONT_SIZE' -N 1e1e2e -n cdd6f4 -S 89b4fa -s ffffff; dwlb -toggle-visibility all", NULL };
static const char *lfcmd[]      = { "foot", "-e", "lf", NULL };
static const char *upvol[]      = { "wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "3%+", "-l", "1.0", NULL };
static const char *downvol[]    = { "wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "3%-", NULL };
static const char *mutevol[]    = { "wpctl", "set-mute",   "@DEFAULT_AUDIO_SINK@", "toggle", NULL };
static const char *brup[]       = { "brightnessctl", "set", "+5%", NULL };
static const char *brdown[]     = { "brightnessctl", "set", "5%-", NULL };
static const char *screenshot[] = { "sh", "-c", "grim ~/Pictures/\$(date +'%Y-%m-%d_%H-%M-%S').png", NULL };
static const char *bartoggle[]  = { "dwlb", "-toggle-visibility", "all", NULL };
static const char *barmove[]    = { "dwlb", "-toggle-location", "all", NULL };

static const Key keys[] = {
    { MODKEY,                    XKB_KEY_d,                     spawn,            {.v = dmenucmd } },
    { MODKEY,                    XKB_KEY_Return,                spawn,            {.v = termcmd } },
    { MODKEY,                    XKB_KEY_t,                     spawn,            {.v = termcmd } },
    { MODKEY,                    XKB_KEY_b,                     spawn,            {.v = browsercmd } },
    { MODKEY,                    XKB_KEY_r,                     spawn,            {.v = lfcmd } },

    { MODKEY,                    XKB_KEY_q,                     killclient,       {0} },
    { MODKEY,                    XKB_KEY_j,                     focusstack,       {.i = +1 } },
    { MODKEY,                    XKB_KEY_Down,                  focusstack,       {.i = +1 } },
    { MODKEY,                    XKB_KEY_k,                     focusstack,       {.i = -1 } },
    { MODKEY,                    XKB_KEY_Up,                    focusstack,       {.i = -1 } },
    { MODKEY,                    XKB_KEY_h,                     setmfact,         {.f = -0.05f} },
    { MODKEY,                    XKB_KEY_l,                     setmfact,         {.f = +0.05f} },
    { MODKEY,                    XKB_KEY_i,                     incnmaster,       {.i = +1 } },
    { MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_T,                     togglefloating,   {0} },
    { MODKEY,                    XKB_KEY_w,                     spawn,            {.v = bartoggle } },
    { MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_W,                     spawn,            {.v = barmove } },
    { MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_Return,                zoom,             {0} },

    { MODKEY,                    XKB_KEY_f,                     setlayout,        {.v = &layouts[2]} },
    { MODKEY,                    XKB_KEY_space,                 setlayout,        {0} },
    { MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_F,                     togglefullscreen, {0} },

    TAGKEYS(          XKB_KEY_1, XKB_KEY_exclam,                     0),
    TAGKEYS(          XKB_KEY_2, XKB_KEY_quotedbl,                   1),
    TAGKEYS(          XKB_KEY_3, XKB_KEY_numbersign,                 2),
    TAGKEYS(          XKB_KEY_4, XKB_KEY_dollar,                     3),
    TAGKEYS(          XKB_KEY_5, XKB_KEY_percent,                    4),
    TAGKEYS(          XKB_KEY_6, XKB_KEY_ampersand,                  5),
    TAGKEYS(          XKB_KEY_7, XKB_KEY_slash,                      6),
    TAGKEYS(          XKB_KEY_8, XKB_KEY_parenleft,                  7),
    TAGKEYS(          XKB_KEY_9, XKB_KEY_parenright,                 8),
    { MODKEY,                    XKB_KEY_Tab,                   view,             {0} },
    { MODKEY,                    XKB_KEY_0,                     view,             {.ui = ~0} },

    { MODKEY,                    XKB_KEY_comma,                 focusmon,         {.i = WLR_DIRECTION_LEFT} },
    { MODKEY,                    XKB_KEY_period,                focusmon,         {.i = WLR_DIRECTION_RIGHT} },
    { MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_less,                  tagmon,           {.i = WLR_DIRECTION_LEFT} },
    { MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_greater,               tagmon,           {.i = WLR_DIRECTION_RIGHT} },
    { MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_semicolon,             tagmon,           {.i = WLR_DIRECTION_LEFT} },
    { MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_colon,                 tagmon,           {.i = WLR_DIRECTION_RIGHT} },

    { 0,                         XKB_KEY_XF86AudioRaiseVolume,  spawn,            {.v = upvol } },
    { 0,                         XKB_KEY_XF86AudioLowerVolume,  spawn,            {.v = downvol } },
    { 0,                         XKB_KEY_XF86AudioMute,         spawn,            {.v = mutevol } },
    { 0,                         XKB_KEY_XF86MonBrightnessUp,   spawn,            {.v = brup } },
    { 0,                         XKB_KEY_XF86MonBrightnessDown, spawn,            {.v = brdown } },
    { 0,                         XKB_KEY_Print,                 spawn,            {.v = screenshot } },

    { MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_E,                     quit,             {0} },
    { WLR_MODIFIER_CTRL|WLR_MODIFIER_ALT, XKB_KEY_BackSpace,    quit,             {0} },

#define CHVT(n) { WLR_MODIFIER_CTRL|WLR_MODIFIER_ALT,XKB_KEY_F##n, chvt, {.ui = (n)} }
    CHVT(1), CHVT(2), CHVT(3), CHVT(4),  CHVT(5),  CHVT(6),
    CHVT(7), CHVT(8), CHVT(9), CHVT(10), CHVT(11), CHVT(12),
};

static const Button buttons[] = {
    { MODKEY, BTN_LEFT,   moveresize,     {.ui = CurMove} },
    { MODKEY, BTN_MIDDLE, togglefloating, {0} },
    { MODKEY, BTN_RIGHT,  moveresize,     {.ui = CurResize} },
};

static const Axis axes[] = {
    { MODKEY, AxisUp,   spawn, {.v = upvol} },
    { MODKEY, AxisDown, spawn, {.v = downvol} },
};
EOF
        info "config.h escrito con layout '$KB_XKB'."
    fi

    info "Compilando dwl..."
    make clean 2>/dev/null || true
    make
    sudo make install

    # --------------------------------------------------------
    # 7. Barra dwlb
    # --------------------------------------------------------
    BARRA_ELEGIDA=""
    if compilar_dwlb; then
        BARRA_ELEGIDA="dwlb"
        configurar_dwlb
    else
        error "dwlb no compilo. La sesion arrancara sin barra."
    fi

    if [ "$BARRA_ELEGIDA" = "dwlb" ] && [ "${DWLB_IPC:-0}" -eq 1 ]; then
        DWLB_MODO="-ipc"
    else
        DWLB_MODO="-no-ipc"
    fi

    BARRA_CMD="dwl -s /usr/local/bin/dwl-status-runner"
    case "$BARRA_ELEGIDA" in
        dwlb) info "Barra: dwlb ($DWLB_MODO); el supervisor gestiona stdin, el estado y el wallpaper." ;;
        *)    warn "No hay barra instalada; el supervisor consumira el estado de dwl sin dibujar una barra." ;;
    esac

    info "Instalando el supervisor de barra y wallpaper..."
    sudo tee /usr/local/bin/dwl-status-runner >/dev/null <<'EOF'
#!/bin/sh
exec 3<&0 || exit 1
HIJOS=""
PID_BARRA=""

limpiar_hijos() {
    for PID_HIJO in $HIJOS; do
        kill "$PID_HIJO" 2>/dev/null || true
    done
    for PID_HIJO in $HIJOS; do
        wait "$PID_HIJO" 2>/dev/null || true
    done
    HIJOS=""
}

trap limpiar_hijos EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

if [ -n "$DWL_WALLPAPER" ] && [ -f "$DWL_WALLPAPER" ] && command -v swaybg >/dev/null 2>&1; then
    swaybg -i "$DWL_WALLPAPER" -m fill </dev/null >/dev/null 2>&1 &
    HIJOS="$HIJOS $!"
fi

case "$DWL_BAR_KIND" in
    dwlb)
        if [ "$DWL_BAR_MODE" = "-ipc" ]; then
            cat <&3 >/dev/null &
            HIJOS="$HIJOS $!"
            dwlb -ipc </dev/null &
        else
            dwlb -no-ipc <&3 &
        fi
        PID_BARRA=$!
        HIJOS="$HIJOS $PID_BARRA"

        if command -v dwlb-status >/dev/null 2>&1; then
            sleep 1
            ( dwlb-status | dwlb -status-stdin all ) </dev/null >/dev/null 2>&1 &
            HIJOS="$HIJOS $!"
        fi
        ;;
    *)
        cat <&3 >/dev/null &
        PID_BARRA=$!
        HIJOS="$HIJOS $PID_BARRA"
        ;;
esac

wait "$PID_BARRA"
ESTADO_BARRA=$?
limpiar_hijos
trap - EXIT HUP INT TERM
exit "$ESTADO_BARRA"
EOF
    sudo chmod +x /usr/local/bin/dwl-status-runner

    # --------------------------------------------------------
    # 8. lf
    # --------------------------------------------------------
    info "Configurando lf..."
    mkdir -p "$HOME/.config/lf"
    write_config "$HOME/.config/lf/lfrc" <<'EOF'
set ifs "\n"

cmd open ${{
    case $(file --mime-type -Lb "$f") in
        text/*|application/json|inode/x-empty)
            nano $fx ;;
        image/*)
            setsid -f imv $fx >/dev/null 2>&1 ;;
        video/*|audio/*)
            setsid -f mpv $fx >/dev/null 2>&1 ;;
        application/pdf)
            setsid -f zathura $fx >/dev/null 2>&1 ;;
        *)
            for f in $fx; do setsid -f xdg-open "$f" >/dev/null 2>&1; done ;;
    esac
}}
EOF

    # --------------------------------------------------------
    # 9. Wallpaper
    # --------------------------------------------------------
    mkdir -p "$WALLPAPER_DIR"
    if [ ! -f "$WALLPAPER_PATH" ]; then
        info "Descargando wallpaper..."
        WALLPAPER_TMP="$WALLPAPER_PATH.tmp"
        if curl -fsSL --max-time 30 -A "Mozilla/5.0" \
            -e "https://wallpapercave.com/" -o "$WALLPAPER_TMP" "$WALLPAPER_URL" \
            && file "$WALLPAPER_TMP" | grep -qi image; then
            mv "$WALLPAPER_TMP" "$WALLPAPER_PATH"
        else
            warn "No se pudo descargar un wallpaper valido; se omite."
            rm -f "$WALLPAPER_TMP"
        fi
    fi

    # --------------------------------------------------------
    # 10. Wrapper de sesion
    # --------------------------------------------------------
    info "Creando el wrapper de sesion..."
    sudo tee /usr/local/bin/dwl-session >/dev/null <<EOF
#!/bin/sh
export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=dwl
export XDG_SESSION_DESKTOP=dwl
export MOZ_ENABLE_WAYLAND=1
export QT_QPA_PLATFORM=wayland
export GDK_BACKEND=wayland,x11
export DWL_BAR_KIND="$BARRA_ELEGIDA"
export DWL_BAR_MODE="$DWLB_MODO"
export DWL_WALLPAPER="$WALLPAPER_PATH"

SESSION_UID=\$(id -u)
RUNDIR_OWNER=""
if [ -n "\$XDG_RUNTIME_DIR" ] && [ -d "\$XDG_RUNTIME_DIR" ]; then
    RUNDIR_OWNER=\$(stat -c %u "\$XDG_RUNTIME_DIR" 2>/dev/null || true)
fi
if [ "\$RUNDIR_OWNER" != "\$SESSION_UID" ]; then
    RUNDIR="/run/user/\$SESSION_UID"
    RUNDIR_OWNER=\$(stat -c %u "\$RUNDIR" 2>/dev/null || true)
    if [ ! -d "\$RUNDIR" ] || [ "\$RUNDIR_OWNER" != "\$SESSION_UID" ]; then
        RUNDIR="\$HOME/.xdg-runtime"
        if ! mkdir -p "\$RUNDIR" 2>/dev/null; then
            printf 'dwl-session: no pude crear XDG_RUNTIME_DIR\n' >&2
            exit 1
        fi
        if ! chmod 0700 "\$RUNDIR" 2>/dev/null; then
            printf 'dwl-session: no pude proteger XDG_RUNTIME_DIR con modo 0700\n' >&2
            exit 1
        fi
    fi
    export XDG_RUNTIME_DIR="\$RUNDIR"
else
    chmod 0700 "\$XDG_RUNTIME_DIR" 2>/dev/null || true
fi

if [ ! -S /run/seatd.sock ]; then
    i=0
    while [ "\$i" -lt 10 ] && [ ! -S /run/seatd.sock ]; do
        i=\$((i + 1))
        sleep 1
    done
    if [ ! -S /run/seatd.sock ]; then
        printf 'dwl-session: aviso, /run/seatd.sock no aparece. Revisa el servicio seatd.\n' >&2
    fi
fi

SESSION_DAEMON_PIDS=""
DWL_PID=""
iniciar_daemon_usuario() {
    DAEMON_NAME=\$1
    shift
    if pgrep -u "\$SESSION_UID" -x "\$DAEMON_NAME" >/dev/null 2>&1; then
        return 0
    fi
    if ! command -v "\$DAEMON_NAME" >/dev/null 2>&1; then
        printf 'dwl-session: no se encontro %s; se omite.\n' "\$DAEMON_NAME" >&2
        return 0
    fi
    "\$@" >/dev/null 2>&1 &
    SESSION_DAEMON_PIDS="\$SESSION_DAEMON_PIDS \$!"
}
limpiar_daemons_usuario() {
    for PID_DAEMON in \$SESSION_DAEMON_PIDS; do
        kill "\$PID_DAEMON" 2>/dev/null || true
    done
    for PID_DAEMON in \$SESSION_DAEMON_PIDS; do
        wait "\$PID_DAEMON" 2>/dev/null || true
    done
    SESSION_DAEMON_PIDS=""
}
terminar_sesion() {
    if [ -n "\$DWL_PID" ]; then
        kill "\$DWL_PID" 2>/dev/null || true
    fi
    exit "\$1"
}
trap limpiar_daemons_usuario EXIT
trap 'terminar_sesion 129' HUP
trap 'terminar_sesion 130' INT
trap 'terminar_sesion 143' TERM

iniciar_daemon_usuario pipewire pipewire
iniciar_daemon_usuario wireplumber wireplumber
iniciar_daemon_usuario pipewire-pulse pipewire-pulse

$EXTRA_ENV
INICIO=\$(date +%s)
$BARRA_CMD &
DWL_PID=\$!
wait "\$DWL_PID"
DWL_STATUS=\$?
DWL_PID=""

if [ "\$DWL_STATUS" -ne 0 ] && [ -z "\$WLR_RENDERER" ] && [ \$(( \$(date +%s) - INICIO )) -lt 5 ]; then
    printf 'dwl-session: dwl fallo al arrancar; reintento con WLR_RENDERER=pixman\n' >&2
    export WLR_RENDERER=pixman
    export WLR_NO_HARDWARE_CURSORS=1
    export LIBGL_ALWAYS_SOFTWARE=1
    $BARRA_CMD &
    DWL_PID=\$!
    wait "\$DWL_PID"
    DWL_STATUS=\$?
    DWL_PID=""
fi
limpiar_daemons_usuario
trap - EXIT HUP INT TERM
exit "\$DWL_STATUS"
EOF
    sudo chmod +x /usr/local/bin/dwl-session

    if printf '%s' "$GPU_VENDORS" | grep -q nvidia; then
        info "GPU NVIDIA: anadiendo WLR_NO_HARDWARE_CURSORS=1 al wrapper."
        sudo sed -i 's|^dwl |export WLR_NO_HARDWARE_CURSORS=1\ndwl |' /usr/local/bin/dwl-session
    fi

    if [ "$GPU_HIBRIDA" -eq 1 ] && [ -n "$GPU_CARDS" ]; then
        sudo sed -i "s|^dwl |# HIBRIDA: si arranca en pantalla negra, descomenta la linea siguiente:\n# export WLR_DRM_DEVICES=$GPU_CARDS\ndwl |" /usr/local/bin/dwl-session
    fi

    info "Instalando los comandos 'dwl-rebuild' y 'dwlb-rebuild'..."
    sudo tee /usr/local/bin/dwl-rebuild >/dev/null <<'EOF'
#!/bin/sh
set -e
cd "$HOME/dwl"
make clean
make
sudo make install
echo "Listo. Cierra sesion y vuelve a entrar para aplicar los cambios de dwl."
EOF
    sudo chmod +x /usr/local/bin/dwl-rebuild

    sudo tee /usr/local/bin/dwlb-rebuild >/dev/null <<'EOF'
#!/bin/sh
set -e
cd "$HOME/dwlb"
git pull --ff-only || echo "Aviso: no se pudo actualizar desde git; compilo lo que hay."
make clean
make
sudo make install
echo "Listo. Reinicia la sesion de dwl para ver la barra nueva."
EOF
    sudo chmod +x /usr/local/bin/dwlb-rebuild

    # --------------------------------------------------------
    # 11. Sesion Wayland
    # --------------------------------------------------------
    info "Registrando la sesion dwl en /usr/share/wayland-sessions..."
    sudo mkdir -p /usr/share/wayland-sessions
    sudo tee /usr/share/wayland-sessions/dwl.desktop >/dev/null <<EOF
[Desktop Entry]
Name=dwl
Comment=dwm para Wayland
Exec=/usr/local/bin/dwl-session
Type=Application
DesktopNames=dwl
EOF

    # --------------------------------------------------------
    # 12. Chuleta de atajos
    # --------------------------------------------------------
    info "Creando la chuleta de atajos ~/Atajos.txt..."
    write_config "$HOME/Atajos.txt" <<'ATAJOS_EOF'

==============================================================================
 ATAJOS DE TECLADO - dwl + dwlb
==============================================================================
  Super+Enter.................. abrir una terminal (foot)
  Super+d...................... lanzador de programas (wmenu)
  Super+q...................... cerrar la ventana actual
  Super+r...................... gestor de archivos (lf)
  Super+b...................... navegador (Firefox)
  Super+Shift+e................ cerrar sesion (volver al login)
  Ctrl+Alt+F1.................. consola de emergencia si algo se congela
  Super+w...................... ocultar/mostrar barra
  Super+Shift+w................ mover barra arriba/abajo
==============================================================================
ATAJOS_EOF

    info "Instalacion de dwl completada."
}

# ==================================================================
# EJECUCION
# ==================================================================
instalar_base
configurar_greetd
iniciar_greetd

info "=========================================="
info " Instalacion de DWL completada con exito!"
info "=========================================="
info "Distro: $DISTRO_ID"
info "En la pantalla de tuigreet escribe tu usuario y contrasena."
info "  F2  = cambiar el comando de la sesion"
info "  F3  = elegir otra sesion"
info "  F12 = apagar / reiniciar"
info ""
info "Barra instalada: ${BARRA_ELEGIDA:-ninguna}  (modo ${DWLB_MODO:-n/a})"
info "  Fuente barra:   monospace $DWLB_FONT_SIZE"
info "  Fuente wmenu:   monospace $WMENU_FONT_SIZE"
info "  Repositorio: https://github.com/kolunmi/dwlb"
info "  Manual:      man 1 dwlb"
info ""
info "Archivos clave:"
info "  ~/dwl/config.h                Atajos (dwl-rebuild para aplicar)"
info "  ~/Atajos.txt                  Chuleta: nano ~/Atajos.txt"
info "  ~/.config/dwlb/config         Fuente/colores de la barra (sin compilar)"
info ""
warn "IMPORTANTE: reinicia antes de usar dwl. Los grupos nuevos solo se aplican"
warn "al volver a iniciar sesion, y sin ellos dwl no puede abrir la GPU ni los"
warn "dispositivos de entrada. Comando sugerido: sudo reboot"
info ""
info "Referencia de drivers de GPU:"
if [ "$DISTRO_FAMILIA" = "void" ]; then
info "  NVIDIA........ sudo xbps-install -S nvidia nvidia-libs-32bit"
info "                 y ademas: options nvidia-drm modeset=1 (en /etc/modprobe.d/)"
info "  AMD........... sudo xbps-install -S mesa-dri mesa-vulkan-radeon linux-firmware-amd"
info "  Intel......... sudo xbps-install -S mesa-dri mesa-vulkan-intel intel-video-accel"
info "  Steam......... activa antes void-repo-nonfree, void-repo-multilib y"
info "                 void-repo-multilib-nonfree; luego: sudo xbps-install -S steam"
else
info "  NVIDIA........ sudo pacman -S nvidia nvidia-utils lib32-nvidia-utils"
info "                 y anade 'nvidia_drm.modeset=1' a los parametros del kernel en grub"
info "  AMD........... sudo pacman -S mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon libva-mesa-driver"
info "  Intel......... sudo pacman -S mesa lib32-mesa vulkan-intel lib32-vulkan-intel intel-media-driver"
info "  Steam......... sudo pacman -S steam (asegurate de tener [multilib] habilitado en pacman.conf)"
fi

#!/bin/sh
# install-dwl-v0.8.0.sh v0.8.0
# Instalador de dwl (dwm para Wayland) para VOID LINUX.
#
# Modos:
#   1) Basico:   dwl + barra externa, foot, wmenu, swaybg, pipewire
#   2) Completo: basico + Steam, drivers de GPU (incluido hibridas/Optimus)
# Kernel: ofrece el paquete linux7.x mas reciente solo si XBPS lo encuentra;
# por defecto conserva el kernel actual y, si se elige, instala 7.x en paralelo.
#
# GESTOR DE INICIO: greetd + tuigreet (unico). lightdm se elimino por completo.
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

# ----------------------------------------------------------------
# 0. Comprobaciones previas
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
    error "Falta 'git'. Instalalo antes de continuar con:"
    error "  sudo xbps-install -S git"
    exit 1
fi

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

DISTRO_ID="unknown"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO_ID="${ID:-unknown}"
fi
info "Distro detectada: $DISTRO_ID"

if [ "$DISTRO_ID" != "void" ]; then
    error "Este script es SOLO PARA VOID LINUX. No se ejecutara en '$DISTRO_ID'."
    exit 1
fi

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

# ----------------------------------------------------------------
# 0c. Variables de configuracion
# ----------------------------------------------------------------
DWL_REPO="https://codeberg.org/dwl/dwl.git"
DWLBAR_REPO="https://github.com/MadcowOG/dwl-bar.git"
WALLPAPER_DIR="$HOME/Pictures"
WALLPAPER_PATH="$WALLPAPER_DIR/wallpaper.jpg"
WALLPAPER_URL="https://wallpapercave.com/download/empty-error-wallpapers-wp8330753"

# VT de greetd (Void parchea greetd para usar la 7: las tty 1-6 tienen agetty)
GREETD_VT="${GREETD_VT:-7}"
case "$GREETD_VT" in
    ''|*[!0-9]*) error "GREETD_VT debe ser un numero entero entre 1 y 12."; exit 1 ;;
esac
if [ "$GREETD_VT" -lt 1 ] || [ "$GREETD_VT" -gt 12 ]; then
    error "GREETD_VT debe estar entre 1 y 12 (recibido: $GREETD_VT)."
    exit 1
fi
# Usuario del sistema que ejecuta el greeter en Void (lo crea el paquete greetd)
GREETER_USER="_greeter"
# Barra a usar: dwl-bar (por defecto) o waybar
BARRA="${BARRA:-dwl-bar}"

# ==================================================================
# MENU DE SELECCION
# ==================================================================
echo "=========================================="
echo "    Instalador dwl (Void Linux) v0.8.0"
echo "=========================================="
echo "Gestor de inicio: greetd + tuigreet"
echo "(si tenias lightdm, se desactivara y desinstalara)"
echo
echo "1) Instalacion BASICA (dwl + barra, foot, wmenu, swaybg)"
echo "2) Instalacion COMPLETA (basica + Steam y drivers de GPU)"
echo "3) Salir"
printf "Opcion [1-3]: "
read -r OPCION

case "$OPCION" in
    1|2) ;;
    3) info "Saliendo..."; exit 0 ;;
    *) error "Opcion no valida."; exit 1 ;;
esac

# ==================================================================
# FUNCION: detectar TODAS las GPUs (incluidas las hibridas / Optimus)
# ==================================================================
# Antes solo se miraba la primera linea del lspci, asi que en un portatil con
# Intel + NVIDIA se instalaban unicamente los drivers de Intel y la NVIDIA
# quedaba muerta. Aqui se recogen todos los vendors presentes.
detectar_gpus() {
    if ! command -v lspci >/dev/null 2>&1; then
        info "Instalando pciutils para detectar las GPU..."
        sudo xbps-install -Sy pciutils || return 1
    fi
    if ! command -v lspci >/dev/null 2>&1; then
        error "pciutils se instalo, pero lspci sigue sin estar disponible."
        return 1
    fi

    GPU_LISTA=$(lspci -nn | grep -iE 'vga|3d controller|display controller' || true)
    GPU_VENDORS=""

    # Se prefieren los identificadores PCI (10de NVIDIA, 1002 AMD, 8086 Intel).
    # El respaldo textual usa limites de caracteres: evita que 'ati' coincida
    # dentro de 'Corporation' y que el fabricante dependa del idioma de lspci.
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

    GPU_HAS_NVIDIA=0
    GPU_HAS_INTEL_AMD=0
    case " $GPU_VENDORS " in *" nvidia "*) GPU_HAS_NVIDIA=1 ;; esac
    case " $GPU_VENDORS " in *" intel "*|*" amd "*) GPU_HAS_INTEL_AMD=1 ;; esac
    if [ "$GPU_HIBRIDA" -eq 1 ] && [ "$GPU_HAS_NVIDIA" -eq 1 ] && [ "$GPU_HAS_INTEL_AMD" -eq 1 ]; then
        GPU_HIBRIDA_NVIDIA=1
    else
        GPU_HIBRIDA_NVIDIA=0
    fi

    info "GPUs detectadas ($GPU_NUM):"
    printf '%s\n' "$GPU_LISTA" | sed 's/^/    /'
    info "Fabricantes: $GPU_VENDORS"
    [ "$GPU_HIBRIDA" -eq 1 ] && info "Equipo con varias GPU detectado: se instalan los drivers de cada fabricante."
    [ "$GPU_HIBRIDA_NVIDIA" -eq 1 ] && info "Hibrida Intel/AMD + NVIDIA: se habilita PRIME bajo demanda."
    [ -n "$GPU_CARDS" ] && info "Nodos DRM: $GPU_CARDS"
    return 0
}

# ==================================================================
# FUNCION: drivers de GPU (todos los vendors, con sus 32 bits)
# ==================================================================
instalar_drivers_gpu() {
    info "Instalando drivers de GPU para: $GPU_VENDORS"

    for VENDOR in $GPU_VENDORS; do
        case "$VENDOR" in
            nvidia)
                warn "GPU NVIDIA: en Wayland el driver propietario funciona mucho mejor"
                warn "que antes, pero puede dar guerra (cursor invisible, apps que no arrancan)."
                sudo xbps-install -Sy nvidia nvidia-libs-32bit
                echo "options nvidia-drm modeset=1" | sudo tee /etc/modprobe.d/nvidia-drm-modeset.conf >/dev/null
                info "nvidia-drm modeset=1 configurado (imprescindible para Wayland)."
                ;;
            amd)
                sudo xbps-install -Sy mesa-dri mesa-vulkan-radeon mesa-dri-32bit \
                    mesa-vulkan-radeon-32bit linux-firmware-amd vulkan-loader
                ;;
            intel)
                sudo xbps-install -Sy mesa-dri mesa-vulkan-intel mesa-dri-32bit \
                    mesa-vulkan-intel-32bit intel-video-accel vulkan-loader
                ;;
            desconocida)
                warn "No identifique la GPU. Instalo los drivers libres (mesa) por si acaso."
                sudo xbps-install -Sy mesa-dri mesa-dri-32bit vulkan-loader || true
                ;;
        esac
    done

    # --- Equipos hibridos con NVIDIA (Intel/AMD + NVIDIA = PRIME) ----------
    if [ "$GPU_HIBRIDA_NVIDIA" -eq 1 ]; then
        info "Configurando arranque en GPU dedicada bajo demanda (PRIME)..."

        # Void NO tiene el paquete nvidia-prime, asi que creamos prime-run.
        # Son las mismas variables que usa el prime-run de Arch.
        info "Creando /usr/local/bin/prime-run (Void no trae nvidia-prime)..."
        sudo tee /usr/local/bin/prime-run >/dev/null <<'EOF'
#!/bin/sh
# prime-run: ejecuta una aplicacion usando la GPU NVIDIA en equipos hibridos.
#   prime-run steam
#   prime-run mpv video.mkv
# Creado por install-dwl-v0.8.0.sh porque Void no empaqueta nvidia-prime.
export __NV_PRIME_RENDER_OFFLOAD=1
export __NV_PRIME_RENDER_OFFLOAD_PROVIDER=NVIDIA-G0
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export __VK_LAYER_NV_optimus=NVIDIA_only
exec "$@"
EOF
        sudo chmod +x /usr/local/bin/prime-run

        warn "En hibridas, si dwl arranca en pantalla negra es que wlroots escogio la"
        warn "GPU equivocada. Fija las GPUs en /usr/local/bin/dwl-session con:"
        warn "  export WLR_DRM_DEVICES=$GPU_CARDS"
        warn "(ya quedaron anotadas como comentario dentro del wrapper)."
    fi
}

# ==================================================================
# FUNCION: barra externa (dwl-bar con Waybar como respaldo)
# ==================================================================
# dwl -s <cmd> arranca <cmd> cuando el compositor ya esta listo y le envia el
# estado (tags, titulo, layout) por su entrada estandar.
compilar_dwl_bar() {
    cd "$HOME" || return 1
    [ -d dwl-bar ] || git clone "$DWLBAR_REPO" || return 1
    cd "$HOME/dwl-bar" || return 1
    fix_owner || return 1

    # --- Parche de compatibilidad layer-shell --------------------------
    # dwl-bar pide SIEMPRE la version 4 de zwlr_layer_shell_v1, pero la que
    # anuncia dwl depende de wlroots (0.18 -> 3, 0.19/0.20 -> 5). Si anuncia
    # menos de 4 el bind falla y la barra no aparece:
    #   "invalid version for global zwlr_layer_shell_v1: have 3, wanted 4"
    # (issue #14 de dwl-bar). Lo de las v4/v5 solo anade "keyboard interactivity
    # on demand", que dwl-bar no usa, asi que bajar a la version anunciada es
    # seguro.
    if grep -q 'zwlr_layer_shell_v1_interface, 4)' src/main.c; then
        if ! sed -i 's|&zwlr_layer_shell_v1_interface, 4)|\&zwlr_layer_shell_v1_interface, (version < 4 ? version : 4))|' src/main.c; then
            error "No pude aplicar el parche layer-shell a dwl-bar."
            return 1
        fi
        if grep -q 'zwlr_layer_shell_v1_interface, 4)' src/main.c; then
            error "La linea layer-shell de dwl-bar sigue sin parchear."
            return 1
        fi
        info "Parche layer-shell aplicado a dwl-bar (usa la version que anuncie dwl)."
    fi

    make clean 2>/dev/null || true
    make || return 1
    sudo make install || return 1
    return 0
}

instalar_waybar() {
    info "Instalando Waybar desde los repositorios de Void..."
    sudo xbps-install -Sy Waybar || return 1

    mkdir -p "$HOME/.config/waybar" || return 1
    write_config "$HOME/.config/waybar/config" <<'EOF' || return 1
{
    "layer": "top",
    "position": "top",
    "height": 28,
    "spacing": 4,
    "modules-left": ["clock"],
    "modules-center": [],
    "modules-right": ["cpu", "memory", "pulseaudio", "network", "battery"],
    "clock": {
        "format": "{:%H:%M  %d/%m/%Y}",
        "tooltip-format": "{:%A, %d de %B de %Y}"
    },
    "cpu": {
        "format": "CPU {usage}%",
        "interval": 2
    },
    "memory": {
        "format": "RAM {}%",
        "interval": 5
    },
    "pulseaudio": {
        "format": "VOL {volume}%",
        "format-muted": "MUTE"
    },
    "network": {
        "format-wifi": "{essid}",
        "format-ethernet": "ETH",
        "format-disconnected": "SIN RED"
    },
    "battery": {
        "format": "BAT {capacity}%",
        "format-charging": "BAT {capacity}% +"
    }
}
EOF

    write_config "$HOME/.config/waybar/style.css" <<'EOF' || return 1
* {
    font-family: monospace;
    font-size: 13px;
    border: none;
    border-radius: 0;
}

window#waybar {
    background-color: #1a1b26;
    color: #c0caf5;
}

#clock, #cpu, #memory, #pulseaudio, #network, #battery {
    padding: 0 10px;
    background-color: #24283b;
    margin: 2px 1px;
}

#battery.charging {
    color: #9ece6a;
}

#battery.critical:not(.charging) {
    color: #f7768e;
}
EOF
    info "Config de Waybar escrita en ~/.config/waybar/"
    return 0
}

# ==================================================================
# FUNCION: greetd + tuigreet
# ==================================================================
configurar_greetd() {

    # --- 0. Fuera lightdm (daba errores y no encaja con Wayland) ---------
    if [ -d /etc/sv/lightdm ] || command -v lightdm >/dev/null 2>&1; then
        info "Encontre lightdm instalado: lo quito (da errores y no se usa con greetd)."
        disable_svc lightdm
        PAQUETES_LIGHTDM=""
        for PKG in lightdm lightdm-gtk3-greeter; do
            if xbps-query "$PKG" >/dev/null 2>&1; then
                PAQUETES_LIGHTDM="$PAQUETES_LIGHTDM $PKG"
            fi
        done
        if [ -n "$PAQUETES_LIGHTDM" ]; then
            sudo xbps-remove -R $PAQUETES_LIGHTDM || \
                warn "No se pudo desinstalar lightdm. Hazlo a mano: sudo xbps-remove -R$PAQUETES_LIGHTDM"
        fi
    fi

    info "Instalando greetd, tuigreet y turnstile..."
    sudo xbps-install -Sy greetd tuigreet turnstile

    # --- 1. Comando de la sesion ----------------------------------------
    SESSION_CMD="/usr/local/bin/dwl-session"
    info "Comando de la sesion: $SESSION_CMD"

    # --- 2. /etc/greetd/config.toml -------------------------------------
    # Dos detalles de Void que te rompen el invento si los copias de Arch:
    #   * el usuario del greeter es '_greeter' (con guion bajo)
    #   * greetd ejecuta el comando con 'sh -c', asi que las comillas simples
    #     de dentro del TOML funcionan como en cualquier terminal.
    sudo mkdir -p /etc/greetd
    backup_file /etc/greetd/config.toml

    sudo tee /etc/greetd/config.toml >/dev/null <<EOF
# Generado por install-dwl-v0.8.0.sh (v0.8.0)
# Documentacion: man 1 tuigreet   ·   https://github.com/tuigreet/tuigreet

[terminal]
# VT donde se muestra tuigreet. Void trae agetty en las tty 1-6,
# asi que la 7 es la correcta. Cambiala a 1 si desactivas agetty-tty1.
vt = $GREETD_VT

[default_session]

command = "tuigreet --time --time-format '%H:%M  %d/%m/%Y' --user-menu --remember --greeting 'Bienvenido a dwl' --power-shutdown 'shutdown -h now' --power-reboot 'shutdown -r now' --cmd $SESSION_CMD"

# En Void el paquete greetd crea el usuario '_greeter' (grupo video).
user = "$GREETER_USER"
EOF
    info "Escrito /etc/greetd/config.toml"

    # --- 3. turnstile: XDG_RUNTIME_DIR ----------------------------------
    # greetd NO crea /run/user/$UID; turnstile lo prepara mediante PAM.
    # Sin el, pipewire y el socket de Wayland fallan.
    # En Void, greetd tiene un archivo PAM propio en /etc/pam.d/greetd, que
    # instala el paquete greetd SIN pam_turnstile.so (solo trae
    # 'auth/account/session include system-local-login'), asi que hay que
    # anadirlo a mano tras instalar el paquete turnstile.
    info "Configurando turnstile (prepara XDG_RUNTIME_DIR mediante PAM)..."
    enable_svc turnstiled || warn "turnstiled no esta disponible; dwl-session usara su directorio privado de respaldo."

    PAM_FILE="/etc/pam.d/greetd"
    if [ -f /usr/lib/security/pam_turnstile.so ]; then
        if [ ! -f "$PAM_FILE" ]; then
            warn "No existe $PAM_FILE (el paquete greetd deberia haberlo creado)."
            warn "No puedo activar pam_turnstile automaticamente; revisa la instalacion de greetd."
        elif grep -q 'pam_turnstile.so' "$PAM_FILE"; then
            info "pam_turnstile ya estaba en $PAM_FILE."
        else
            backup_file "$PAM_FILE"
            # Se agrega al final del archivo: el stack de greetd ya contiene
            # una sesion; el modulo optional no altera el resultado de login.
            printf '\n# Anadido por install-dwl-v0.8.0.sh para turnstile (XDG_RUNTIME_DIR)\nsession\toptional\tpam_turnstile.so\n' | \
                sudo tee -a "$PAM_FILE" >/dev/null
            info "Anadido 'session optional pam_turnstile.so' a $PAM_FILE"
            warn "Si algo falla al iniciar sesion, restaura la copia .bak-* de $PAM_FILE."
        fi
    else
        warn "No encontre pam_turnstile.so: se omite la parte de PAM."
        warn "Sin el, XDG_RUNTIME_DIR puede quedar vacio (el wrapper dwl-session tiene un plan B)."
    fi

    # --- 4. Servicios ---------------------------------------------------
    if [ -L "/var/service/agetty-tty$GREETD_VT" ]; then
        warn "Habia un agetty en tty$GREETD_VT; lo quito para que greetd pueda usarla."
        disable_svc "agetty-tty$GREETD_VT"
    fi

    # greetd se enlaza en runit, pero NO se arranca aquí.
    # Se arranca al final del script, en iniciar_greetd().
    if [ ! -d /etc/sv/greetd ]; then
        error "El paquete greetd no creo /etc/sv/greetd; no habilito un servicio incompleto."
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
    if [ ! -d /etc/sv/greetd ]; then
        error "No existe /etc/sv/greetd: no puedo iniciar greetd con runit."
        return 1
    fi

    if [ ! -L /var/service/greetd ]; then
        enable_svc greetd || return 1
    fi


    info "Todo instalado: arrancando greetd..."
    if ! sudo sv start greetd; then
        error "runit no pudo iniciar greetd. Revisa con: sudo sv status greetd"
        return 1
    fi

    ESTADO_GREETD=$(sudo sv status greetd 2>&1 || true)
    case "$ESTADO_GREETD" in
        run:*) info "greetd activo: tienes tuigreet en la tty$GREETD_VT." ;;
        *)     warn "runit no confirma que greetd esté activo: $ESTADO_GREETD" ;;
    esac
}

# ==================================================================
# FUNCION: instalacion basica de dwl
# ==================================================================
instalar_base() {

    # --------------------------------------------------------
    # 0. Kernel 7.x opcional: no reemplaza ni elimina el kernel actual
    # --------------------------------------------------------
    info "Kernel actualmente en uso: $(uname -r)"
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

    # --------------------------------------------------------
    # 1. Paquetes
    # --------------------------------------------------------
    # No se instala el servidor Xorg completo: con lightdm hacia falta porque
    # greeter se dibujaba sobre X11, pero tuigreet se dibuja en la consola.
    # Basta con xorg-server-xwayland para las apps de X11 (Steam, juegos).
    # Si lo quieres: sudo xbps-install -Sy xorg-server
    info "Instalando dependencias de dwl y del entorno Wayland..."
    if ! sudo xbps-install -Sy \
        base-devel file pkg-config \
        libinput libinput-devel \
        wayland wayland-devel wayland-protocols \
        libxkbcommon libxkbcommon-devel \
        wlroots wlroots-devel \
        libseat libseat-devel seatd \
        xorg-server-xwayland \
        mesa-dri libdrm-devel \
        pango-devel cairo-devel \
        foot wmenu \
        pipewire wireplumber alsa-pipewire \
        swaybg swaylock grim slurp wl-clipboard \
        brightnessctl curl procps-ng \
        nano nerd-fonts lf mpv zathura zathura-pdf-poppler xdg-utils imv \
        chrony firefox btop cowsay dbus; then
        error "xbps-install fallo instalando las dependencias base. Revisa tu conexion/repos e intenta de nuevo."
        return 1
    fi

    info "Habilitando servicios (dbus, chronyd, seatd)..."
    enable_svc dbus || return 1
    enable_svc chronyd || warn "No se pudo habilitar chronyd; la hora seguira con el reloj configurado."

    REAL_USER=$(id -un)

    # --------------------------------------------------------
    # 2. Grupo de seatd: en Void es _seatd, NO seat
    # --------------------------------------------------------
    # El paquete crea ese grupo y el servicio arranca con
    #   exec /usr/bin/seatd -g _seatd
    # asi que /run/seatd.sock pertenece a '_seatd'. Sin ese grupo, libseat no
    # puede abrir el seat y dwl muere al arrancar.
    info "Configurando el grupo de seat para el usuario $REAL_USER..."

    if getent group _seatd >/dev/null 2>&1; then
        SEAT_GROUP="_seatd"
    else
        error "No existe el grupo _seatd que crea el paquete seatd de Void. No agregare el grupo incorrecto 'seat'."
        warn "Reinstala/verifica seatd con: sudo xbps-install -f seatd"
        return 1
    fi

    if ! sudo usermod -aG "$SEAT_GROUP" "$REAL_USER"; then
        error "No pude anadir a $REAL_USER al grupo '$SEAT_GROUP'."
        warn "Hazlo a mano: sudo usermod -aG $SEAT_GROUP $REAL_USER"
        return 1
    fi

    # El grupo video tambien se usa para acceso directo a dispositivos DRM y
    # aceleracion; se agrega en ambos modos, no solo si Steam esta disponible.
    if getent group video >/dev/null 2>&1; then
        if sudo usermod -aG video "$REAL_USER"; then
            info "Usuario $REAL_USER agregado al grupo 'video'."
        else
            warn "No pude anadir a $REAL_USER al grupo video."
            warn "Hazlo a mano: sudo usermod -aG video $REAL_USER"
        fi
    else
        warn "No existe el grupo video; revisa la instalacion base de Void."
    fi

    if groups "$REAL_USER" 2>/dev/null | tr ' ' '\n' | grep -qx "$SEAT_GROUP"; then
        info "Usuario $REAL_USER agregado al grupo '$SEAT_GROUP'."
    else
        warn "No pude confirmar que $REAL_USER este en '$SEAT_GROUP'."
        warn "Si dwl no arranca: sudo usermod -aG $SEAT_GROUP $REAL_USER"
    fi

    enable_svc seatd || return 1
    warn "El grupo '$SEAT_GROUP' solo se aplica despues de cerrar sesion y volver a entrar (o reiniciar)."

    # --------------------------------------------------------
    # 3. Deteccion de GPUs (antes de escribir el wrapper)
    # --------------------------------------------------------
    detectar_gpus

    # --------------------------------------------------------
    # 4. Zona horaria
    # --------------------------------------------------------
    info "Configuracion de zona horaria."
    printf "Escribe tu pais (ej: Colombia, Mexico, Argentina, España).\nDeja vacio para usar Colombia por defecto: "
    read -r PAIS_INPUT
    PAIS_INPUT="${PAIS_INPUT:-Colombia}"

    PAIS_NORM=$(printf '%s' "$PAIS_INPUT" | tr '[:upper:]' '[:lower:]' | \
        sed 's/á/a/g; s/é/e/g; s/í/i/g; s/ó/o/g; s/ú/u/g; s/ñ/n/g')

    TZ_INPUT=""
    case "$PAIS_NORM" in
        colombia)                          TZ_INPUT="America/Bogota" ;;
        mexico)                            TZ_INPUT="America/Mexico_City" ;;
        argentina)                         TZ_INPUT="America/Argentina/Buenos_Aires" ;;
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
        sudo hwclock --systohc || warn "No se pudo sincronizar el reloj de hardware (se ignora)."
        if grep -qE '^[#[:space:]]*TIMEZONE=' /etc/rc.conf 2>/dev/null; then
            sudo sed -i "s|^[#[:space:]]*TIMEZONE=.*|TIMEZONE=\"$TZ_INPUT\"|" /etc/rc.conf || warn "No pude actualizar TIMEZONE en /etc/rc.conf."
        else
            printf 'TIMEZONE="%s"\n' "$TZ_INPUT" | sudo tee -a /etc/rc.conf >/dev/null || warn "No pude escribir TIMEZONE en /etc/rc.conf."
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
        printf "  2) Español de España (es)\n"
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
        if grep -qE '^[#[:space:]]*KEYMAP=' /etc/rc.conf 2>/dev/null; then
            sudo sed -i "s|^[#[:space:]]*KEYMAP=.*|KEYMAP=\"$KB_CONSOLA\"|" /etc/rc.conf || warn "No pude actualizar KEYMAP en /etc/rc.conf."
        else
            printf 'KEYMAP="%s"\n' "$KB_CONSOLA" | sudo tee -a /etc/rc.conf >/dev/null || warn "No pude escribir KEYMAP en /etc/rc.conf."
        fi
        command -v loadkeys >/dev/null 2>&1 && sudo loadkeys "$KB_CONSOLA" 2>/dev/null || true
    fi

    # --------------------------------------------------------
    # 6. Clonar y compilar dwl (sin parches)
    # --------------------------------------------------------
    cd "$HOME"
    if [ ! -d dwl ]; then
        info "Clonando dwl..."
        git clone "$DWL_REPO"
    fi
    cd dwl
    fix_owner

    if [ -f config.h ]; then
        warn "config.h ya existe: se conserva tu version (no se sobreescribe)."
        warn "Si quieres regenerarlo, borra ~/dwl/config.h y vuelve a ejecutar."
    else
        info "Escribiendo config.h personalizado (atajos, volumen, brillo, screenshot)..."

        cat > config.h <<EOF
/* Configuracion de dwl generada por install-dwl-v0.8.0.sh
 * Personaliza este archivo y aplica cambios con: dwl-rebuild
 */
#include <xkbcommon/xkbcommon-keysyms.h>

/* appearance */
static const int sloppyfocus        = 1;
static const int bypass_surface_visibility = 0;
static const unsigned int borderpx  = 2;
static const float rootcolor[]      = {0.11f, 0.11f, 0.18f, 1.0f};
static const float bordercolor[]    = {0.19f, 0.19f, 0.26f, 1.0f};
static const float focuscolor[]     = {0.53f, 0.70f, 0.98f, 1.0f};
static const float urgentcolor[]    = {0.93f, 0.31f, 0.31f, 1.0f};

/* tagging */
static const char *tags[] = { "1", "2", "3", "4", "5", "6", "7", "8", "9" };

static const Rule rules[] = {
    /* app_id     title       tags mask     isfloating   monitor */
    { "Gimp",     NULL,       0,            1,           -1 },
    { "firefox",  NULL,       1 << 0,       0,           -1 },
};

/* layout(s) */
static const Layout layouts[] = {
    { "[]=",      tile },
    { "><>",      NULL },
    { "[M]",      monocle },
};

/* monitor(s) */
static const MonitorRule monrules[] = {
    /* name       mfact nmaster scale layout       rotate/reflect */
    { NULL,       0.50f, 1,      1,    &layouts[0], WL_OUTPUT_TRANSFORM_NORMAL },
};

/* keyboard */
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

/* Modificador (tecla Windows/Super) */
#define MODKEY WLR_MODIFIER_LOGO

/* Configuracion de TAGKEYS */
#define TAGKEYS(KEY,SKEY,TAG) \\
    { MODKEY,                    KEY,            view,            {.ui = 1 << TAG} }, \\
    { MODKEY|WLR_MODIFIER_CTRL,  KEY,            toggleview,      {.ui = 1 << TAG} }, \\
    { MODKEY|WLR_MODIFIER_SHIFT, SKEY,           tag,             {.ui = 1 << TAG} }, \\
    { MODKEY|WLR_MODIFIER_CTRL|WLR_MODIFIER_SHIFT,SKEY,toggletag, {.ui = 1 << TAG} }

/* commands */
static const char *termcmd[]    = { "foot", NULL };
static const char *browsercmd[] = { "firefox", NULL };
static const char *dmenucmd[]   = { "wmenu-run", "-f", "monospace:size=11", "-nb", "#1e1e2e", "-nf", "#cdd6f4", "-sb", "#89b4fa", "-sf", "#ffffff", NULL };
/* Volumen via PipeWire (el wrapper dwl-session ya levanta wireplumber) */
static const char *upvol[]      = { "wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "5%+", NULL };
static const char *downvol[]    = { "wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "5%-", NULL };
static const char *mutevol[]    = { "wpctl", "set-mute",   "@DEFAULT_AUDIO_SINK@", "toggle", NULL };
static const char *brup[]       = { "brightnessctl", "set", "+5%", NULL };
static const char *brdown[]     = { "brightnessctl", "set", "5%-", NULL };
static const char *screenshot[] = { "sh", "-c", "grim ~/Pictures/\$(date +'%Y-%m-%d_%H-%M-%S').png", NULL };
static const char *lfcmd[]      = { "foot", "-e", "lf", NULL };

static const Key keys[] = {
    /* modifier                  key                            function        argument */
    { MODKEY,                    XKB_KEY_d,                     spawn,          {.v = dmenucmd } },
    { MODKEY,                    XKB_KEY_Return,                spawn,          {.v = termcmd } },
    { MODKEY,                    XKB_KEY_t,                     spawn,          {.v = termcmd } },
    { MODKEY,                    XKB_KEY_b,                     spawn,          {.v = browsercmd } },
    { MODKEY,                    XKB_KEY_e,                     spawn,          {.v = lfcmd } },
    { MODKEY,                    XKB_KEY_q,                     killclient,     {0} },
    { MODKEY,                    XKB_KEY_f,                     setlayout,      {.v = &layouts[2]} },
    { MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_T,                     togglefloating, {0} },
    { MODKEY,                    XKB_KEY_r,                     setlayout,      {0} },
    { MODKEY,                    XKB_KEY_j,                     focusstack,     {.i = +1 } },
    { MODKEY,                    XKB_KEY_k,                     focusstack,     {.i = -1 } },
    { MODKEY,                    XKB_KEY_h,                     setmfact,       {.f = -0.05} },
    { MODKEY,                    XKB_KEY_l,                     setmfact,       {.f = +0.05} },
    { MODKEY,                    XKB_KEY_i,                     incnmaster,     {.i = +1 } },
    { MODKEY,                    XKB_KEY_space,                 setlayout,      {0} },
    { MODKEY,                    XKB_KEY_Tab,                   view,           {0} },

    { 0,                         XKB_KEY_XF86AudioRaiseVolume,  spawn,          {.v = upvol } },
    { 0,                         XKB_KEY_XF86AudioLowerVolume,  spawn,          {.v = downvol } },
    { 0,                         XKB_KEY_XF86AudioMute,         spawn,          {.v = mutevol } },
    { 0,                         XKB_KEY_XF86MonBrightnessUp,   spawn,          {.v = brup } },
    { 0,                         XKB_KEY_XF86MonBrightnessDown, spawn,          {.v = brdown } },
    { 0,                         XKB_KEY_Print,                 spawn,          {.v = screenshot } },
    { MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_E,                     quit,           {0} },

    TAGKEYS(          XKB_KEY_1, XKB_KEY_exclam,                     0),
    TAGKEYS(          XKB_KEY_2, XKB_KEY_quotedbl,                   1),
    TAGKEYS(          XKB_KEY_3, XKB_KEY_numbersign,                 2),
    TAGKEYS(          XKB_KEY_4, XKB_KEY_dollar,                     3),
    TAGKEYS(          XKB_KEY_5, XKB_KEY_percent,                    4),
    TAGKEYS(          XKB_KEY_6, XKB_KEY_ampersand,                  5),
    TAGKEYS(          XKB_KEY_7, XKB_KEY_slash,                      6),
    TAGKEYS(          XKB_KEY_8, XKB_KEY_parenleft,                  7),
    TAGKEYS(          XKB_KEY_9, XKB_KEY_parenright,                 8),
};

static const Button buttons[] = {
    { MODKEY, Button1, movemouse,      {0} },
    { MODKEY, Button2, togglefloating, {0} },
    { MODKEY, Button3, resizemouse,    {0} },
};
EOF
        info "config.h escrito con layout '$KB_XKB'."
    fi

    info "Compilando dwl..."
    make clean 2>/dev/null || true
    make
    sudo make install

    # --------------------------------------------------------
    # 7. Barra externa (dwl no trae barra propia)
    # --------------------------------------------------------
    BARRA_ELEGIDA=""
    if [ "$BARRA" = "waybar" ]; then
        if instalar_waybar; then BARRA_ELEGIDA="waybar"; fi
    else
        if compilar_dwl_bar; then
            BARRA_ELEGIDA="dwl-bar"
        else
            error "dwl-bar no compilo. Cayo a Waybar (esta en los repos de Void)."
            if instalar_waybar; then BARRA_ELEGIDA="waybar"; fi
        fi
    fi

    case "$BARRA_ELEGIDA" in
        dwl-bar)
            BARRA_CMD="dwl -s /usr/local/bin/dwl-status-runner"
            info "Barra: dwl-bar; el supervisor gestiona el stdin de estado y el wallpaper."
            ;;
        waybar)
            BARRA_CMD="dwl -s /usr/local/bin/dwl-status-runner"
            info "Barra: Waybar."
            warn "Waybar muestra reloj/bateria/CPU, pero NO las etiquetas (tags) de dwl:"
            warn "su modulo dwl/tags exige parchear dwl con el IPC patch."
            ;;
        *)
            BARRA_CMD="dwl -s /usr/local/bin/dwl-status-runner"
            warn "No hay barra instalada; el supervisor consumira el estado de dwl sin dibujar una barra."
            ;;
    esac

    info "Instalando el supervisor de barra y wallpaper..."
    sudo tee /usr/local/bin/dwl-status-runner >/dev/null <<'EOF'
#!/bin/sh
# Arrancado por dwl -s cuando el compositor ya esta listo.
# En dwl-bar pasa stdin a la barra; en Waybar drena el estado para no bloquear dwl.
# dash manda stdin de los procesos en segundo plano a /dev/null salvo que se
# duplique a otro descriptor antes; el descriptor 3 conserva la tuberia de dwl.
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

# El fondo necesita Wayland; por eso se inicia aqui y no antes de dwl.
if [ -n "$DWL_WALLPAPER" ] && [ -f "$DWL_WALLPAPER" ] && command -v swaybg >/dev/null 2>&1; then
    swaybg -i "$DWL_WALLPAPER" -m fill </dev/null >/dev/null 2>&1 &
    HIJOS="$HIJOS $!"
fi

case "$DWL_BAR_KIND" in
    dwl-bar)
        dwl-bar <&3 &
        PID_BARRA=$!
        HIJOS="$HIJOS $PID_BARRA"
        ;;
    waybar)
        cat <&3 >/dev/null &
        HIJOS="$HIJOS $!"
        waybar </dev/null &
        PID_BARRA=$!
        HIJOS="$HIJOS $PID_BARRA"
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
    # 9. lf (navegador de archivos)
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
    # 10. Wallpaper
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
    # 11. Wrapper de sesion (lo ejecuta greetd/tuigreet)
    # --------------------------------------------------------
    info "Creando el wrapper de sesion..."
    sudo tee /usr/local/bin/dwl-session >/dev/null <<EOF
#!/bin/sh
# dwl-session: arranque de la sesion dwl.
# Lo ejecuta greetd/tuigreet DESPUES de autenticar al usuario.
export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=dwl
export XDG_SESSION_DESKTOP=dwl
export MOZ_ENABLE_WAYLAND=1
export QT_QPA_PLATFORM=wayland
export GDK_BACKEND=wayland,x11
export DWL_BAR_KIND="$BARRA_ELEGIDA"
export DWL_WALLPAPER="$WALLPAPER_PATH"

# XDG_RUNTIME_DIR lo crea turnstiled por PAM. Si no existe o no pertenece a
# este usuario, se usa /run/user/UID cuando ya este creado o un dir privado.
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

# seatd: dwl necesita /run/seatd.sock para abrir GPU, teclado y raton.
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

# Audio de usuario. Los procesos iniciados aqui se cierran al salir de dwl.
iniciar_daemon_usuario pipewire pipewire
iniciar_daemon_usuario wireplumber wireplumber
iniciar_daemon_usuario pipewire-pulse pipewire-pulse

# dwl-status-runner inicia swaybg cuando el socket Wayland ya esta disponible.
$BARRA_CMD &
DWL_PID=\$!
wait "\$DWL_PID"
DWL_STATUS=\$?
DWL_PID=""
limpiar_daemons_usuario
trap - EXIT HUP INT TERM
exit "\$DWL_STATUS"
EOF
    sudo chmod +x /usr/local/bin/dwl-session

    # --- Ajustes segun el hardware detectado ----------------------------
    # NVIDIA propietario + wlroots: sin esto el cursor puede no verse.
    if printf '%s' "$GPU_VENDORS" | grep -q nvidia; then
        info "GPU NVIDIA: anadiendo WLR_NO_HARDWARE_CURSORS=1 al wrapper."
        sudo sed -i 's|^dwl |export WLR_NO_HARDWARE_CURSORS=1\ndwl |' /usr/local/bin/dwl-session
    fi

    # Hibridas: WLR_DRM_DEVICES se deja comentado porque el orden correcto de
    # las tarjetas depende de cada equipo y un valor mal puesto deja la
    # pantalla en negro. Se imprime tal cual para que solo haya que descomentar.
    if [ "$GPU_HIBRIDA" -eq 1 ] && [ -n "$GPU_CARDS" ]; then
        sudo sed -i "s|^dwl |# HIBRIDA: si arranca en pantalla negra, descomenta la linea siguiente:\n# export WLR_DRM_DEVICES=$GPU_CARDS\ndwl |" /usr/local/bin/dwl-session
    fi

    info "Instalando el comando 'dwl-rebuild'..."
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

    # --------------------------------------------------------
    # 12. Sesion Wayland (la lee el menu F3 de tuigreet)
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

    info "Instalacion basica de dwl completada."
}

# ==================================================================
# FUNCION: gaming (Steam + drivers)
# ==================================================================
instalar_gaming() {

    GAMING_USER=$(id -un)

    # --------------------------------------------------------
    # 1. Repositorios PRIMERO, en su propia transaccion
    # --------------------------------------------------------
    # steam vive en el repo *nonfree* y sus librerias de 32 bits en *multilib*.
    # Si los repos se instalan en la MISMA orden que los paquetes que dependen
    # de ellos, xbps sincroniza el indice antes de que existan y luego no
    # encuentra steam. Tres pasos, tal cual dice el README.voidlinux de steam:
    #   # xbps-install -S void-repo-multilib{,-nonfree}
    #   # xbps-install -S
    info "Habilitando repositorios nonfree y multilib..."
    sudo xbps-install -Sy void-repo-nonfree void-repo-multilib void-repo-multilib-nonfree

    info "Resincronizando los indices de los repositorios nuevos..."
    sudo xbps-install -Sy || warn "La resincronizacion fallo; puede que steam no aparezca."

    # Los drivers pertenecen al modo completo aunque Steam no figure en el
    # indice (por ejemplo, si el espejo de repositorios aun no esta disponible).
    instalar_drivers_gpu

    STEAM_VER=$(xbps-query -R -p version steam 2>/dev/null || true)
    if [ -z "$STEAM_VER" ]; then
        error "Despues de activar nonfree, 'steam' sigue sin aparecer."
        warn  "Compruebalo a mano con:  xbps-query -Rs steam"
        warn  "Se omite la instalacion gaming; el resto del sistema queda instalado."
        return 0
    fi
    info "Steam localizado en los repositorios: $STEAM_VER"

    # --------------------------------------------------------
    # 2. Librerias de 32 bits que pide Steam en x86_64
    # --------------------------------------------------------
    # Steam es un binario de 32 bits: sin estas librerias se instala pero no
    # arranca. Lista oficial de /usr/share/doc/steam/README.voidlinux.
    STEAM_32="libgcc-32bit libstdc++-32bit libdrm-32bit libglvnd-32bit libva-32bit"
    case " $GPU_VENDORS " in
        *" nvidia "*) STEAM_32="$STEAM_32 nvidia-libs-32bit" ;;
    esac
    case " $GPU_VENDORS " in
        *" intel "*|*" amd "*|*" desconocida "*) STEAM_32="$STEAM_32 mesa-dri-32bit" ;;
    esac
    info "Instalando las librerias de 32 bits que necesita Steam en x86_64..."
    sudo xbps-install -Sy $STEAM_32 || \
        warn "Alguna libreria de 32 bits fallo. Repitelo a mano: sudo xbps-install -S $STEAM_32"

    # --------------------------------------------------------
    # 3. Steam (SOLO en su transaccion)
    # --------------------------------------------------------
    # En xbps, si un paquete de la lista falla se cancela TODA la instalacion.
    # Antes steam iba junto a gamemode y gamescope: si uno fallaba, steam no
    # se instalaba. Ahora cada uno va por separado.
    info "Instalando Steam..."
    if ! sudo xbps-install -Sy steam; then
        error "Steam no se pudo instalar. Comprueba:"
        error "  xbps-query -Rs steam     (debe salir la version)"
        error "  df -h                    (steam ocupa ~1GB con su runtime)"
        warn  "Se omite el resto de la instalacion gaming."
        return 0
    fi

    # --------------------------------------------------------
    # 4. Extras, cada uno en su transaccion
    # --------------------------------------------------------
    info "Instalando gamemode, gamescope y mono (opcionales)..."
    sudo xbps-install -Sy gamemode  || warn "gamemode no se instalo (opcional; no afecta a Steam)."
    sudo xbps-install -Sy gamescope || warn "gamescope no se instalo (opcional; no afecta a Steam)."
    sudo xbps-install -Sy mono      || warn "mono no se instalo (opcional; algunos juegos lo piden)."

    # --------------------------------------------------------
    # 5. Ajustes para Proton / SteamPlay
    # --------------------------------------------------------
    # Proton abre muchisimos descriptores de fichero: con el limite por defecto
    # los juegos mueren con "eventfd: Too many open files".
    info "Subiendo el limite de ficheros abiertos (lo pide Proton)..."
    sudo mkdir -p /etc/security/limits.d
    printf '* soft nofile 524288\n* hard nofile 524288\n' | \
        sudo tee /etc/security/limits.d/00-steam-proton.conf >/dev/null

    # Steam y la aceleracion por hardware necesitan el grupo video.
    if sudo usermod -aG video "$GAMING_USER" 2>/dev/null; then
        info "Usuario $GAMING_USER anadido al grupo 'video' (lo pide Steam)."
    else
        warn "No pude anadir a $GAMING_USER al grupo video."
        warn "Hazlo a mano: sudo usermod -aG video $GAMING_USER"
    fi

    # dbus tiene que estar levantado o Steam no arranca.
    enable_svc dbus

    info "Steam corre sobre XWayland automaticamente."
    if [ "$GPU_HIBRIDA_NVIDIA" -eq 1 ]; then
        warn "Equipo HIBRIDO Intel/AMD + NVIDIA: para que un juego use NVIDIA, lanzalo con:"
        warn "  prime-run steam"
        warn "o pon en las opciones de lanzamiento del juego:"
        warn "  prime-run %command%"
    fi
    info "gamescope es un mini-compositor Wayland: lanza juegos con"
    info "'gamescope -- %command%' desde las propiedades de lanzamiento en Steam."

    info "Instalacion gaming completada."
    warn "REINICIA: los grupos nuevos (video) y el driver de GPU solo aplican tras reiniciar."
    warn "Abre Steam por primera vez desde foot ('steam') para que se actualice."
}

# ==================================================================
# EJECUCION
# ==================================================================
instalar_base
configurar_greetd

if [ "$OPCION" = "2" ]; then
    instalar_gaming
fi

# LO ULTIMO: greetd se levanta solo cuando ya no queda nada pendiente.
iniciar_greetd

info "=========================================="
info " ¡Instalación de DWL completada con éxito!"
info "=========================================="
info "En la pantalla de tuigreet escribe tu usuario y contraseña."
info "  F2  = cambiar el comando de la sesion"
info "  F3  = elegir otra sesion (lee /usr/share/wayland-sessions)"
info "  F12 = apagar / reiniciar"
info ""
info "Barra instalada: ${BARRA_ELEGIDA:-ninguna}"
info ""
info "Archivos clave para personalizar tu entorno:"
info "  ~/dwl/config.h                Atajos, colores, reglas, layout de teclado (dwl-rebuild)"
info "  ~/.config/lf/lfrc             Configuración del gestor de archivos"
info "  /usr/local/bin/dwl-session     Variables y programas al iniciar sesión"
info "  /etc/greetd/config.toml       greetd + tuigreet"
info "  /etc/pam.d/greetd             Donde se activo pam_turnstile (XDG_RUNTIME_DIR)"
info ""
info "Para aplicar cambios tras editar config.h ejecuta: dwl-rebuild"
info ""
warn "IMPORTANTE: reinicia antes de usar dwl. Los grupos nuevos"
warn "('${SEAT_GROUP:-_seatd}' y video) solo se aplican al volver a iniciar"
warn "sesion, y sin ellos dwl no puede abrir la GPU ni los dispositivos de"
warn "entrada. Aunque ya veas tuigreet en la tty$GREETD_VT, NO entres todavia."
warn "Comando sugerido: sudo reboot"

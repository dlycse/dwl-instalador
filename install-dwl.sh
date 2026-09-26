#!/bin/sh
# install-dwl-v0.9.0.sh v0.9.0
# Instalador de dwl (dwm para Wayland) para VOID LINUX.
#
# Modos:
#   1) Basico:   dwl + dwlb, foot, wmenu, swaybg, pipewire
#   2) Completo: basico + Steam, drivers de GPU (incluido hibridas/Optimus)
#
# CAMBIO v0.9.0: la barra ya no es dwl-bar (MadcowOG) sino dwlb, de kolunmi:
#   https://github.com/kolunmi/dwlb
# dwlb trae colores configurables, texto de estado con comandos en linea
# (^fg ^bg ^lm ...), regiones clicables, ocultar tags vacios, escalado HiDPI
# y control remoto (dwlb -toggle-visibility all, etc.). Se instala tambien su
# pagina de manual (man 1 dwlb) y un archivo de configuracion propio en
# ~/.config/dwlb/config, mas un generador de estado en dwlb-status.
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
# Barra: dwlb, de kolunmi (repositorio personal de su autor).
DWLB_REPO="https://github.com/kolunmi/dwlb.git"
WALLPAPER_DIR="$HOME/Pictures"
WALLPAPER_PATH="$WALLPAPER_DIR/wallpaper.jpg"
WALLPAPER_URL="https://wallpapercave.com/download/empty-error-wallpapers-wp8330753"

# Apariencia de dwlb (paleta Catppuccin Mocha, igual que config.h de dwl)
DWLB_FONT="${DWLB_FONT:-monospace:size=11}"
DWLB_PAD="${DWLB_PAD:-2}"
DWLB_ACTIVE_FG="#ffffff"
DWLB_ACTIVE_BG="#89b4fa"
DWLB_OCCUPIED_FG="#cdd6f4"
DWLB_OCCUPIED_BG="#313244"
DWLB_INACTIVE_FG="#a6adc8"
DWLB_INACTIVE_BG="#1e1e2e"
DWLB_URGENT_FG="#1e1e2e"
DWLB_URGENT_BG="#f38ba8"
DWLB_MIDDLE_BG="#1e1e2e"

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

# ==================================================================
# MENU DE SELECCION
# ==================================================================
echo "=========================================="
echo "    Instalador dwl (Void Linux) v0.9.0"
echo "=========================================="
echo "Barra: dwlb (https://github.com/kolunmi/dwlb)"
echo "Gestor de inicio: greetd + tuigreet"
echo "(si tenias lightdm, se desactivara y desinstalara)"
echo
echo "1) Instalacion BASICA (dwl + dwlb, foot, wmenu, swaybg)"
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

    if [ "$GPU_HIBRIDA_NVIDIA" -eq 1 ]; then
        info "Configurando arranque en GPU dedicada bajo demanda (PRIME)..."
        info "Creando /usr/local/bin/prime-run (Void no trae nvidia-prime)..."
        sudo tee /usr/local/bin/prime-run >/dev/null <<'EOF'
#!/bin/sh
# prime-run: ejecuta una aplicacion usando la GPU NVIDIA en equipos hibridos.
#   prime-run steam
#   prime-run mpv video.mkv
# Creado por install-dwl-v0.9.0.sh porque Void no empaqueta nvidia-prime.
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
# FUNCION: barra dwlb (repositorio de kolunmi)
# ==================================================================
# dwl -s <cmd> arranca <cmd> cuando el compositor ya esta listo y le envia el
# estado (tags, titulo, layout) por su entrada estandar. dwlb lee ese stdin
# salvo que se compile dwl con el parche IPC y se use -ipc.
#
# Dependencias de dwlb (README del autor):
#   libwayland-client, libwayland-cursor, pixman, fcft
compilar_dwlb() {
    info "Instalando dependencias de dwlb (pixman, fcft, tllist)..."
    if ! sudo xbps-install -Sy pixman pixman-devel fcft fcft-devel tllist \
            freetype-devel fontconfig-devel harfbuzz-devel utf8proc-devel; then
        warn "Alguna dependencia de dwlb fallo; intento compilar de todas formas."
    fi

    cd "$HOME" || return 1
    if [ -d dwlb ]; then
        info "Ya existe ~/dwlb: se reutiliza el clon existente."
    else
        info "Clonando dwlb desde $DWLB_REPO ..."
        git clone "$DWLB_REPO" || return 1
    fi
    cd "$HOME/dwlb" || return 1
    fix_owner || return 1

    # --- config.h propio de dwlb ---------------------------------------
    # dwlb usa el estilo suckless: config.def.h -> config.h. Aqui se dejan
    # los valores por defecto del binario; el ajuste fino se hace luego en
    # ~/.config/dwlb/config, que NO obliga a recompilar.
    if [ -f config.def.h ] && [ ! -f config.h ]; then
        cp config.def.h config.h
        info "Creado ~/dwlb/config.h a partir de config.def.h."
    fi

    # --- Parche de compatibilidad layer-shell (por si acaso) -----------
    # Si una version futura de dwlb exigiera una version de zwlr_layer_shell_v1
    # mayor que la que anuncia el wlroots de Void, el bind fallaria con:
    #   "invalid version for global zwlr_layer_shell_v1: have 3, wanted 4"
    # Se ata la peticion a la version realmente anunciada.
    if grep -qE 'zwlr_layer_shell_v1_interface, [0-9]+\)' dwlb.c 2>/dev/null; then
        DWLB_LS_VER=$(grep -oE 'zwlr_layer_shell_v1_interface, [0-9]+\)' dwlb.c | head -n1 | grep -oE '[0-9]+')
        if [ -n "$DWLB_LS_VER" ] && [ "$DWLB_LS_VER" -gt 1 ]; then
            sed -i "s|&zwlr_layer_shell_v1_interface, $DWLB_LS_VER)|\&zwlr_layer_shell_v1_interface, (version < $DWLB_LS_VER ? version : $DWLB_LS_VER))|" dwlb.c || \
                warn "No pude aplicar el parche layer-shell a dwlb; sigo igualmente."
            info "Parche layer-shell aplicado a dwlb (pide como mucho la version $DWLB_LS_VER)."
        fi
    fi

    make clean 2>/dev/null || true
    if ! make; then
        error "Fallo la compilacion de dwlb. Revisa que pixman-devel y fcft-devel esten instalados."
        return 1
    fi
    sudo make install || return 1

    # Pagina de manual: el Makefile suele instalarla, pero si no, se copia.
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
    info "Escribiendo la configuracion de dwlb..."
    mkdir -p "$HOME/.config/dwlb"

    # dwlb lee $XDG_CONFIG_HOME/dwlb/config: son las MISMAS opciones de la
    # linea de comandos, una por linea, sin el guion inicial obligatorio de
    # agrupar. Cambiar aqui NO requiere recompilar: basta con reiniciar dwl.
    write_config "$HOME/.config/dwlb/config" <<EOF
# Configuracion de dwlb  (https://github.com/kolunmi/dwlb)
# Generada por install-dwl-v0.9.0.sh
# Una opcion por linea, tal cual se pasarian en la linea de comandos.
# Referencia completa: man 1 dwlb

-font $DWLB_FONT
-vertical-padding $DWLB_PAD

# Tags: oculta los vacios e inactivos para que la barra quede limpia.
-hide-vacant-tags

# El titulo de la ventana enfocada va centrado.
-center-title

# Permite ^fg() ^bg() ^lm() en el texto de estado (lo usa dwlb-status).
-status-commands

# Barra arriba y visible al iniciar.
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

# HiDPI: descomenta si tu monitor usa escalado 2x (o 1.25/1.5 -> tambien 2).
# -scale 2
EOF

    # --- Generador de texto de estado -----------------------------------
    # Se alimenta a dwlb con:  dwlb-status | dwlb -status-stdin all
    # Usa los comandos en linea de dwlb: ^fg(), ^bg(), ^lm() para clics.
    info "Instalando 'dwlb-status' (texto de estado de la barra)..."
    sudo tee /usr/local/bin/dwlb-status >/dev/null <<'EOF'
#!/bin/sh
# dwlb-status: imprime el texto de estado para dwlb, una linea por refresco.
# Formato de dwlb: ^fg(RRGGBB) ^bg(RRGGBB) ^lm(comando) ... ^lm()
# Consulta 'man 1 dwlb', seccion Commands.
#
# Se usa asi:   dwlb-status | dwlb -status-stdin all

COLOR_ETIQ="89b4fa"   # azul  (etiquetas)
COLOR_TXT="cdd6f4"    # texto normal
COLOR_ALERTA="f38ba8" # rojo  (bateria baja)

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
    # Clic izquierdo sobre la hora: abre un calendario en foot.
    printf '^lm(foot -e sh -c "cal -3; read x")^fg(%s)%s^fg()^lm()' \
        "$COLOR_TXT" "$(date '+%a %d/%m  %H:%M')"
}

while :; do
    printf '%s%s%s%s%s\n' \
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

    SESSION_CMD="/usr/local/bin/dwl-session"
    info "Comando de la sesion: $SESSION_CMD"

    sudo mkdir -p /etc/greetd
    backup_file /etc/greetd/config.toml

    sudo tee /etc/greetd/config.toml >/dev/null <<EOF
# Generado por install-dwl-v0.9.0.sh (v0.9.0)
# Documentacion: man 1 tuigreet

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
            printf '\n# Anadido por install-dwl-v0.9.0.sh para turnstile (XDG_RUNTIME_DIR)\nsession\toptional\tpam_turnstile.so\n' | \
                sudo tee -a "$PAM_FILE" >/dev/null
            info "Anadido 'session optional pam_turnstile.so' a $PAM_FILE"
            warn "Si algo falla al iniciar sesion, restaura la copia .bak-* de $PAM_FILE."
        fi
    else
        warn "No encontre pam_turnstile.so: se omite la parte de PAM."
        warn "Sin el, XDG_RUNTIME_DIR puede quedar vacio (el wrapper dwl-session tiene un plan B)."
    fi

    if [ -L "/var/service/agetty-tty$GREETD_VT" ]; then
        warn "Habia un agetty en tty$GREETD_VT; lo quito para que greetd pueda usarla."
        disable_svc "agetty-tty$GREETD_VT"
    fi

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
        *)     warn "runit no confirma que greetd este activo: $ESTADO_GREETD" ;;
    esac
}

# ==================================================================
# FUNCION: instalacion basica de dwl
# ==================================================================
instalar_base() {

    # --------------------------------------------------------
    # 0. Kernel 7.x opcional
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
        pixman pixman-devel fcft fcft-devel tllist \
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
    printf "Escribe tu pais (ej: Colombia, Mexico, Argentina, Espana).\nDeja vacio para usar Colombia por defecto: "
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

    # dwlb puede hablar por IPC solo si dwl trae el protocolo dwl-ipc-unstable.
    if [ -f protocols/dwl-ipc-unstable-v2.xml ] || [ -f protocols/dwl-ipc-unstable-v1.xml ]; then
        DWLB_IPC=1
        info "dwl incluye el protocolo IPC: dwlb usara -ipc (clic en los tags funcional)."
    else
        DWLB_IPC=0
        info "dwl sin parche IPC: dwlb leera el estado por stdin (-no-ipc)."
    fi

    if [ -f config.h ]; then
        warn "config.h ya existe: se conserva tu version (no se sobreescribe)."
        warn "Si quieres regenerarlo, borra ~/dwl/config.h y vuelve a ejecutar."
    else
        info "Escribiendo config.h personalizado (atajos, volumen, brillo, screenshot, barra)..."

        cat > config.h <<EOF
/* Configuracion de dwl generada por install-dwl-v0.9.0.sh
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
/* Control remoto de la barra dwlb (man 1 dwlb, seccion Commands) */
static const char *bartoggle[]  = { "dwlb", "-toggle-visibility", "all", NULL };
static const char *barmove[]    = { "dwlb", "-toggle-location", "all", NULL };

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

    /* Barra dwlb: Super+s la oculta/muestra, Super+Shift+S la manda abajo/arriba */
    { MODKEY,                    XKB_KEY_s,                     spawn,          {.v = bartoggle } },
    { MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_S,                     spawn,          {.v = barmove } },

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
    # 7. Barra dwlb (dwl no trae barra propia)
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
# Arrancado por dwl -s cuando el compositor ya esta listo.
# Con dwlb en modo stdin, le pasa la tuberia de estado de dwl.
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
    dwlb)
        # dwlb lee su configuracion de ~/.config/dwlb/config; aqui solo se
        # decide el modo (ipc o stdin), que depende de como se compilo dwl.
        if [ "$DWL_BAR_MODE" = "-ipc" ]; then
            # Con IPC dwlb no usa stdin: hay que consumir la tuberia igual,
            # o dwl se bloquea al escribir el estado.
            cat <&3 >/dev/null &
            HIJOS="$HIJOS $!"
            dwlb -ipc </dev/null &
        else
            dwlb -no-ipc <&3 &
        fi
        PID_BARRA=$!
        HIJOS="$HIJOS $PID_BARRA"

        # Texto de estado (CPU, RAM, volumen, bateria, reloj).
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
    # 8. lf (navegador de archivos)
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
    # 10. Wrapper de sesion (lo ejecuta greetd/tuigreet)
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
export DWL_BAR_MODE="$DWLB_MODO"
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

# dwl-status-runner inicia dwlb y swaybg cuando el socket Wayland ya existe.
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
# Recompila la barra dwlb (solo hace falta si editas ~/dwlb/config.h o
# actualizas el repo). Para cambiar colores/fuente basta editar
# ~/.config/dwlb/config y reiniciar la sesion: no requiere compilar.
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
    # 11. Sesion Wayland (la lee el menu F3 de tuigreet)
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

    info "Habilitando repositorios nonfree y multilib..."
    sudo xbps-install -Sy void-repo-nonfree void-repo-multilib void-repo-multilib-nonfree

    info "Resincronizando los indices de los repositorios nuevos..."
    sudo xbps-install -Sy || warn "La resincronizacion fallo; puede que steam no aparezca."

    instalar_drivers_gpu

    STEAM_VER=$(xbps-query -R -p version steam 2>/dev/null || true)
    if [ -z "$STEAM_VER" ]; then
        error "Despues de activar nonfree, 'steam' sigue sin aparecer."
        warn  "Compruebalo a mano con:  xbps-query -Rs steam"
        warn  "Se omite la instalacion gaming; el resto del sistema queda instalado."
        return 0
    fi
    info "Steam localizado en los repositorios: $STEAM_VER"

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

    info "Instalando Steam..."
    if ! sudo xbps-install -Sy steam; then
        error "Steam no se pudo instalar. Comprueba:"
        error "  xbps-query -Rs steam     (debe salir la version)"
        error "  df -h                    (steam ocupa ~1GB con su runtime)"
        warn  "Se omite el resto de la instalacion gaming."
        return 0
    fi

    info "Instalando gamemode, gamescope y mono (opcionales)..."
    sudo xbps-install -Sy gamemode  || warn "gamemode no se instalo (opcional; no afecta a Steam)."
    sudo xbps-install -Sy gamescope || warn "gamescope no se instalo (opcional; no afecta a Steam)."
    sudo xbps-install -Sy mono      || warn "mono no se instalo (opcional; algunos juegos lo piden)."

    info "Subiendo el limite de ficheros abiertos (lo pide Proton)..."
    sudo mkdir -p /etc/security/limits.d
    printf '* soft nofile 524288\n* hard nofile 524288\n' | \
        sudo tee /etc/security/limits.d/00-steam-proton.conf >/dev/null

    if sudo usermod -aG video "$GAMING_USER" 2>/dev/null; then
        info "Usuario $GAMING_USER anadido al grupo 'video' (lo pide Steam)."
    else
        warn "No pude anadir a $GAMING_USER al grupo video."
        warn "Hazlo a mano: sudo usermod -aG video $GAMING_USER"
    fi

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
info " Instalacion de DWL completada con exito!"
info "=========================================="
info "En la pantalla de tuigreet escribe tu usuario y contrasena."
info "  F2  = cambiar el comando de la sesion"
info "  F3  = elegir otra sesion (lee /usr/share/wayland-sessions)"
info "  F12 = apagar / reiniciar"
info ""
info "Barra instalada: ${BARRA_ELEGIDA:-ninguna}  (modo ${DWLB_MODO:-n/a})"
info "  Repositorio: https://github.com/kolunmi/dwlb  (autor: kolunmi)"
info "  Manual:      man 1 dwlb"
info "  Super+s        oculta/muestra la barra"
info "  Super+Shift+S  la mueve arriba/abajo"
info ""
info "Archivos clave para personalizar tu entorno:"
info "  ~/dwl/config.h                Atajos, colores, reglas, teclado (dwl-rebuild)"
info "  ~/.config/dwlb/config         Fuente y colores de la barra (sin recompilar)"
info "  /usr/local/bin/dwlb-status    Bloques de estado de la barra (CPU, RAM, bateria...)"
info "  ~/dwlb/config.h               Valores compilados de dwlb (dwlb-rebuild)"
info "  ~/.config/lf/lfrc             Configuracion del gestor de archivos"
info "  /usr/local/bin/dwl-session    Variables y programas al iniciar sesion"
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

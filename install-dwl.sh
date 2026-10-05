#!/bin/sh
# ============================================================================
#  install-dwl.sh  -  Instalador de dwl + dwlb para VOID LINUX
#  VERSION: 0.8
#  (La version SOLO se cambia cuando lo diga el usuario: no la subas por tu
#   cuenta al hacer cambios. Ahora mismo es la 0.8.)
# ----------------------------------------------------------------------------
#  Modos:
#    1) Basico:   dwl + dwlb (barra), foot, wmenu, swaybg, pipewire
#    2) Completo: basico + Steam y drivers de GPU (incluidas hibridas/Optimus)
#
#  Gestor de inicio: greetd + tuigreet (unico; lightdm se desinstala)
#
#  Puntos clave de esta version (correcciones respecto a install-dwl-v0.7.sh):
#    - compilar_dwlb() tiene su linea de apertura (antes rompia la sintaxis).
#    - Se llama a detectar_gpus antes de usar GPU_VENDORS/GPU_HIBRIDA_NVIDIA.
#    - dwl se COMPILA CON XWAYLAND (se descomentan XWAYLAND y XLIBS).
#    - Se fija la version de dwl: se elige el tag compatible con la wlroots
#      instalada (comprobado con pkg-config) y se compila hasta que uno vaya.
#    - Los atajos de tags se generan segun la distribucion de teclado y segun
#      la aridad de TAGKEYS de la version de dwl (2 o 3 argumentos).
#    - El supervisor de la barra lee ~/.config/dwlb/config y le pasa a dwlb
#      las opciones por linea de comandos (dwlb NO sabe leer archivos de
#      configuracion), descartando las opciones que ese dwlb no conozca.
#    - Se anade el grupo audio (sin elogind el audio depende de el).
#    - Bus de sesion D-Bus via dbus-run-session.
#    - Steam/multilib protegido: comprueba arquitectura y no aborta el script.
#    - QT_QPA_PLATFORM="wayland;xcb" para que las apps Qt no se rompan.
#
#  Modo no interactivo (para pruebas o instalaciones automaticas):
#     MODO=1|2  PAIS=...  KB_OPCION=1|2|3  KERNEL_OPCION=1|2
#     PARCHES=si|no  POWER_SUDO=si|no  ENTRADA_AUTOMATICA=1
#  Utilidad: regenerar solo config.h de un clon de dwl:
#     DWL_SOLO_CONFIG_H=/ruta/a/dwl sh install-dwl.sh
# ============================================================================

VERSION="0.8"
NOMBRE_SCRIPT="install-dwl.sh"

# ----------------------------------------------------------------------------
# Colores y mensajes
# ----------------------------------------------------------------------------
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
BLUE="\033[1;34m"
RESET="\033[0m"

info()  { printf "%b[+]%b %s\n" "$GREEN" "$RESET" "$1"; }
warn()  { printf "%b[!]%b %s\n" "$YELLOW" "$RESET" "$1"; }
error() { printf "%b[x]%b %s\n" "$RED" "$RESET" "$1"; }
titulo() { printf "\n%b== %s ==%b\n" "$BLUE" "$1" "$RESET"; }

# Valor por defecto de una pregunta.
# Si la variable ya viene definida en el entorno, se respeta (util para
# instalaciones automaticas). Con ENTRADA_AUTOMATICA=1 no pregunta nada.
pedir() {
    # pedir VAR "texto" "valor por defecto"
    VAR_PEDIDA="$1"; TEXTO="$2"; DEFECTO="$3"
    eval "VALOR_PREVIO=\${$VAR_PEDIDA:-}"
    if [ -n "$VALOR_PREVIO" ]; then
        info "$VAR_PEDIDA ya estaba definido: $VALOR_PREVIO"
        return 0
    fi
    if [ "${ENTRADA_AUTOMATICA:-0}" = "1" ]; then
        eval "$VAR_PEDIDA=\$DEFECTO"
        info "(automatico) $TEXTO -> ${DEFECTO}"
        return 0
    fi
    printf "%s" "$TEXTO"
    if [ -n "$DEFECTO" ]; then printf " [%s]" "$DEFECTO"; fi
    printf ": "
    read -r RESPUESTA
    [ -n "$RESPUESTA" ] || RESPUESTA="$DEFECTO"
    eval "$VAR_PEDIDA=\$RESPUESTA"
}

# Pregunta si/no. pedir_si_no VAR "texto" si|no
pedir_si_no() {
    VAR_PEDIDA="$1"; TEXTO="$2"; DEFECTO="$3"
    eval "VALOR_PREVIO=\${$VAR_PEDIDA:-}"
    if [ -n "$VALOR_PREVIO" ]; then
        info "$VAR_PEDIDA ya estaba definido: $VALOR_PREVIO"
        return 0
    fi
    case "$DEFECTO" in si|s|S) PISTA="S/n" ;; *) PISTA="s/N" ;; esac
    if [ "${ENTRADA_AUTOMATICA:-0}" = "1" ]; then
        eval "$VAR_PEDIDA=\$DEFECTO"
        info "(automatico) $TEXTO -> $DEFECTO"
        return 0
    fi
    printf "%s [%s]: " "$TEXTO" "$PISTA"
    read -r RESPUESTA
    [ -n "$RESPUESTA" ] || RESPUESTA="$DEFECTO"
    case "$RESPUESTA" in
        s|S|si|SI|Si|y|Y|yes|YES) eval "$VAR_PEDIDA=si" ;;
        *)                         eval "$VAR_PEDIDA=no" ;;
    esac
}

# ----------------------------------------------------------------------------
# Modo utilidad: regenerar solo config.h (no toca nada del sistema)
# ----------------------------------------------------------------------------
KB_XKB="${KB_XKB:-latam}"
DWL_SOLO_CONFIG_H="${DWL_SOLO_CONFIG_H:-}"

if [ -n "$DWL_SOLO_CONFIG_H" ]; then
    info "$NOMBRE_SCRIPT v$VERSION (utilidad: solo config.h)"
    if [ ! -d "$DWL_SOLO_CONFIG_H" ]; then
        error "No existe el directorio $DWL_SOLO_CONFIG_H"
        exit 1
    fi
else
    : # flujo normal, mas abajo
fi

# ----------------------------------------------------------------------------
# 0. Comprobaciones previas (se saltan en el modo utilidad)
# ----------------------------------------------------------------------------
if [ -z "$DWL_SOLO_CONFIG_H" ]; then

if [ "$(id -u)" -eq 0 ]; then
    error "No ejecutes este script como root: los archivos quedarian en /root."
    exit 1
fi

for CMD in sudo xbps-install xbps-query xbps-uhelper sv; do
    if ! command -v "$CMD" >/dev/null 2>&1; then
        error "Falta '$CMD'. Este instalador requiere XBPS y runit de Void Linux."
        [ "$CMD" = "sudo" ] && error "Instalalo con: xbps-install -S sudo  (y anade tu usuario a sudoers con visudo)"
        exit 1
    fi
done

if [ ! -d /var/service ]; then
    error "No existe /var/service. Comprueba que Void Linux y runit esten bien instalados."
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

if ! command -v git >/dev/null 2>&1; then
    error "Falta 'git'. Instalalo antes de continuar con: sudo xbps-install -S git"
    exit 1
fi

# Espacio libre: los paquetes se instalan en / y la compilacion ocurre en
# $HOME. Se mira la particion que este mas justa de las dos. Se usa df -Pk
# (POSIX) en vez de --output, que no existe en todos los df.
libre_gb() { df -Pk "$1" 2>/dev/null | awk 'NR==2 {printf "%d", ($4/1048576)+0.5}'; }
FREE_HOME=$(libre_gb "$HOME")
FREE_ROOT=$(libre_gb /)
FREE_GB=$FREE_HOME
if [ -n "$FREE_HOME" ] && [ -n "$FREE_ROOT" ] && [ "$FREE_ROOT" -lt "$FREE_HOME" ] 2>/dev/null; then
    FREE_GB=$FREE_ROOT
fi
if [ -n "$FREE_GB" ] && [ "$FREE_GB" -lt 12 ] 2>/dev/null; then
    warn "Solo detecto ${FREE_GB}GB libres (miro $HOME y /)."
    warn "La instalacion BASICA necesita unos 12GB; si luego eliges el modo"
    warn "COMPLETO (Steam + drivers de GPU) conviene tener 25GB o mas."
    pedir_si_no CONTINUAR_DISCO "Continuar de todas formas?" "no"
    if [ "$CONTINUAR_DISCO" != "si" ]; then
        error "Cancelado por el usuario."
        exit 1
    fi
fi

# Arquitectura y libc: condiciona Steam/multilib
ARQ_XBPS=$(xbps-uhelper arch 2>/dev/null || echo "desconocida")
case "$ARQ_XBPS" in
    x86_64)      ARQ_BASE="x86_64";  LIBC="glibc" ;;
    x86_64-musl) ARQ_BASE="x86_64";  LIBC="musl"  ;;
    i686)        ARQ_BASE="i686";    LIBC="glibc" ;;
    *musl)       ARQ_BASE="desconocida"; LIBC="musl" ;;
    *)           ARQ_BASE="desconocida"; LIBC="desconocida" ;;
esac
info "Arquitectura XBPS: $ARQ_XBPS  (base: $ARQ_BASE, libc: $LIBC)"

REAL_USER=$(id -un)
info "Usuario: $REAL_USER"

fi  # fin de las comprobaciones previas

# ----------------------------------------------------------------------------
# 0c. Variables de configuracion
# ----------------------------------------------------------------------------
DWL_REPO="https://codeberg.org/dwl/dwl.git"
DWL_REPO_ESPEJO="https://github.com/djpohly/dwl.git"

# dwl sigue a la ultima wlroots y su API cambia: en vez de clonar HEAD se
# elige un tag compatible con la wlroots instalada. Formato: tag:wlroots.
DWL_TAGS_COMPAT="v0.9:0.20 v0.8:0.19 v0.7:0.18"
DWL_TAG_FORZADO="${DWL_TAG:-}"
DWL_TAG_USADO=""
DWL_PARCHES_USADOS=""
DWL_XWAYLAND="no"

DWLB_REPO="https://github.com/kolunmi/dwlb.git"
# Commit de dwlb probado (rama master). Si no existe, se usa master.
DWLB_COMMIT="${DWLB_COMMIT:-48dbe00bdb98a1ae6a0e60558ce14503616aa759}"

# Parches opcionales (dwl-patches). Se aplican solo si entran limpios.
DWL_PATCHES_BASE="https://codeberg.org/dwl/dwl-patches/raw/branch/main/patches"
PARCHES_IPC_URL="$DWL_PATCHES_BASE/ipc/ipc.patch"
PARCHES_GAPS_URL="$DWL_PATCHES_BASE/vanitygaps/vanitygaps.patch"
PARCHES_GAPS_07="$DWL_PATCHES_BASE/vanitygaps/vanitygaps-0.7.patch"
PARCHES_GAPS_08="$DWL_PATCHES_BASE/vanitygaps/vanitygaps-0.8.patch"

WALLPAPER_DIR="$HOME/Pictures"
WALLPAPER_PATH="$WALLPAPER_DIR/wallpaper.jpg"
WALLPAPER_URL="https://wallpapercave.com/download/empty-error-wallpapers-wp8330753"

# Apariencia de la barra (paleta Catppuccin Mocha)
DWLB_FONT="${DWLB_FONT:-monospace:size=11}"
DWLB_PAD="${DWLB_PAD:-1}"
# Lineas del lanzador wmenu (wmenu-run lista todo el PATH: sin esto seria una
# sola tira horizontal de lado a lado de la pantalla).
MENU_LINEAS="${MENU_LINEAS:-10}"
case "$MENU_LINEAS" in
    ''|*[!0-9]*) MENU_LINEAS=10 ;;
esac
[ "$MENU_LINEAS" -ge 1 ] 2>/dev/null || MENU_LINEAS=10
[ "$MENU_LINEAS" -le 50 ] 2>/dev/null || MENU_LINEAS=50
DWLB_ACTIVE_FG="#ffffff";  DWLB_ACTIVE_BG="#89b4fa"
DWLB_OCCUPIED_FG="#cdd6f4"; DWLB_OCCUPIED_BG="#313244"
DWLB_INACTIVE_FG="#a6adc8"; DWLB_INACTIVE_BG="#1e1e2e"
DWLB_URGENT_FG="#1e1e2e";   DWLB_URGENT_BG="#f38ba8"
DWLB_MIDDLE_BG="#1e1e2e"

# VT de greetd. Void trae agetty en las tty 1-6, asi que la 7 es la correcta.
GREETD_VT="${GREETD_VT:-7}"
GREETER_USER="_greeter"

# Variables que se rellenan mas tarde (inicializadas para que nunca queden
# indefinidas, evitando abortos raros en segun que shell)
GPU_VENDORS=""
GPU_HIBRIDA=0
GPU_HIBRIDA_NVIDIA=0
GPU_CARDS=""
GPU_NUM=0
GPU_LISTA=""
EXTRA_ENV=""
KB_CONSOLA=""
KB_OPCION="${KB_OPCION:-3}"
TZ_INPUT=""
KERNEL_ELEGIDO=""
KERNEL_ELEGIDO_HEADERS=""
BARRA_ELEGIDA=""
DWLB_MODO="-no-ipc"
SEAT_GROUP="_seatd"
PARCHES_USAR=""

# ============================================================================
# MENU DE SELECCION
# ============================================================================
if [ -z "$DWL_SOLO_CONFIG_H" ]; then
echo "=========================================="
echo "    Instalador dwl (Void Linux) v$VERSION"
echo "=========================================="
echo "Compositor: dwl  (https://codeberg.org/dwl/dwl)"
echo "Barra:      dwlb (https://github.com/kolunmi/dwlb)"
echo "Inicio:     greetd + tuigreet (si tenias lightdm, se quita)"
echo
echo "1) Instalacion BASICA   (dwl + dwlb, foot, wmenu, swaybg, pipewire)"
echo "2) Instalacion COMPLETA (basica + Steam y drivers de GPU)"
echo "3) Salir"
pedir OPCION "Opcion [1-3]" "${MODO:-1}"

case "$OPCION" in
    1|2) ;;
    3) info "Saliendo..."; exit 0 ;;
    *) error "Opcion no valida."; exit 1 ;;
esac
fi  # fin del menu

# ============================================================================
# FUNCIONES AUXILIARES DE ARCHIVOS Y SERVICIOS
# ============================================================================

# Escribe un fichero de configuracion sin pisar el del usuario.
# Se usa con heredoc: write_config /ruta/archivo <<'EOF' ... EOF
write_config() {
    if [ -f "$1" ]; then
        warn "$1 ya existe: se conserva tu version. La nueva quedo en $1.nuevo"
        cat > "$1.nuevo" || return 1
    else
        cat > "$1" || return 1
    fi
}

# Escribe SIEMPRE (con copia de seguridad si ya existe).
write_config_forzado() {
    RUTA="$1"
    if [ -f "$RUTA" ]; then
        backup_file "$RUTA"
    fi
    cat > "$RUTA" || return 1
}

backup_file() {
    if [ -f "$1" ]; then
        BACKUP_PATH="$1.bak-$(date +%Y%m%d%H%M%S)"
        if sudo cp -a "$1" "$BACKUP_PATH" 2>/dev/null || cp -a "$1" "$BACKUP_PATH" 2>/dev/null; then
            info "Copia de seguridad: $BACKUP_PATH"
        else
            warn "No pude hacer copia de seguridad de $1"
        fi
    fi
}

fix_owner() {
    if [ "$(stat -c %U .)" != "$(id -un)" ] || [ -n "$(find . ! -user "$(id -un)" -print -quit 2>/dev/null)" ]; then
        info "Devolviendo la propiedad de $(pwd) a $(id -un)..."
        sudo chown -R "$(id -un):$(id -gn)" . || return 1
    fi
}

enable_svc() {
    if [ -L "/var/service/$1" ]; then
        if [ ! -d "/etc/sv/$1" ]; then
            error "Existe el enlace /var/service/$1, pero falta el servicio /etc/sv/$1."
            return 1
        fi
        info "El servicio $1 ya estaba habilitado en runit."
        return 0
    fi
    if [ -d "/etc/sv/$1" ]; then
        sudo ln -s "/etc/sv/$1" /var/service/ || return 1
        info "Servicio $1 habilitado en runit."
        return 0
    fi
    warn "No encontre /etc/sv/$1. Activalo a mano con: sudo ln -s /etc/sv/$1 /var/service/"
    return 1
}

disable_svc() {
    if [ -L "/var/service/$1" ]; then
        sudo sv stop "$1" 2>/dev/null || true
        sudo rm -f "/var/service/$1"
        info "Servicio $1 desactivado."
    fi
}

# Sustituye marcadores @MARCADOR@ en un archivo por un valor literal.
# El valor puede llevar varias lineas: se escapan los saltos de linea para
# que sed los escriba como lineas nuevas (si no, sed se atraganta).
sustituir() {
    F="$1"; M="$2"; V="$3"
    V=$(printf '%s' "$V" | sed -e 's/[&\\|]/\\&/g' -e '$!s/$/\\/')
    # Los archivos de /usr/local/bin los escribe root: si no se puede escribir
    # en ellos, la sustitucion se hace con sudo (si no, sed fallaria en silencio
    # y el wrapper quedaria con los marcadores @...@ sin sustituir).
    if [ -w "$F" ]; then
        sed -i "s|$M|$V|g" "$F" || warn "No pude sustituir $M en $F"
    else
        sudo sed -i "s|$M|$V|g" "$F" || warn "No pude sustituir $M en $F"
    fi
}

paquete_existe() { xbps-query -R "$1" >/dev/null 2>&1; }
paquete_instalado() { xbps-query "$1" >/dev/null 2>&1; }

# Instala paquetes de forma tolerante: primero en bloque (rapido) y, si falla,
# uno a uno para que un paquete inexistente no tumbe toda la instalacion.
#   instalar_paquetes "etiqueta" paquete1 paquete2 ...
instalar_paquetes() {
    ETIQUETA="$1"; shift
    DISPONIBLES=""
    FALTANTES=""
    for P in "$@"; do
        if paquete_existe "$P"; then
            DISPONIBLES="$DISPONIBLES $P"
        else
            FALTANTES="$FALTANTES $P"
        fi
    done
    [ -n "$FALTANTES" ] && warn "No estan en los repositorios de Void (se omiten):$FALTANTES"
    if [ -z "$DISPONIBLES" ]; then
        warn "No hay nada que instalar en el grupo '$ETIQUETA'."
        return 0
    fi

    info "Instalando ($ETIQUETA):$DISPONIBLES"
    if sudo xbps-install -Sy $DISPONIBLES; then
        return 0
    fi

    warn "La instalacion en bloque fallo. Reintento paquete por paquete..."
    FALLOS=""
    for P in $DISPONIBLES; do
        if ! sudo xbps-install -y "$P" >/dev/null 2>&1; then
            FALLOS="$FALLOS $P"
        fi
    done
    if [ -z "$FALLOS" ]; then
        info "Todos los paquetes de '$ETIQUETA' quedaron instalados (uno a uno)."
        return 0
    fi
    error "No se pudieron instalar estos paquetes:$FALLOS"
    return 1
}

# Fuente para wmenu: dwlb usa fcft ("monospace:size=11") y wmenu usa Pango
# ("monospace 11"). Aqui se convierte.
fuente_pango() {
    FUENTE="$1"
    FAMILIA="${FUENTE%%:*}"
    TAM=""
    case "$FUENTE" in
        # OJO: 'pixelsize=' contiene 'size=', por eso va primero.
        *pixelsize=*) TAM="${FUENTE#*pixelsize=}"; TAM="${TAM%%:*}" ;;
        *size=*)      TAM="${FUENTE#*size=}";      TAM="${TAM%%:*}" ;;
    esac
    case "$TAM" in ''|*[!0-9.]*) TAM=11 ;; esac
    [ -n "$FAMILIA" ] || FAMILIA="monospace"
    printf '%s %s' "$FAMILIA" "$TAM"
}

# ============================================================================
# FUNCION: detectar TODAS las GPUs (incluidas hibridas / Optimus)
# ============================================================================
detectar_gpus() {
    if ! command -v lspci >/dev/null 2>&1; then
        info "Instalando pciutils para detectar las GPU..."
        sudo xbps-install -Sy pciutils || return 1
    fi
    if ! command -v lspci >/dev/null 2>&1; then
        error "pciutils se instalo, pero lspci sigue sin estar disponible."
        return 1
    fi

    GPU_LISTA=$(lspci -nn 2>/dev/null | grep -iE 'vga|3d controller|display controller' || true)
    GPU_VENDORS=""

    if printf '%s' "$GPU_LISTA" | grep -qiE '\[10de:[[:xdigit:]]{4}\]|(^|[^[:alnum:]])NVIDIA([^[:alnum:]]|$)'; then
        GPU_VENDORS="$GPU_VENDORS nvidia"
    fi
    if printf '%s' "$GPU_LISTA" | grep -qiE '\[1002:[[:xdigit:]]{4}\]|(^|[^[:alnum:]])Apple([^[:alnum:]]|$)|(^|[^[:alnum:]])(AMD|Radeon|ATI)([^[:alnum:]]|$)'; then
        GPU_VENDORS="$GPU_VENDORS amd"
    fi
    if printf '%s' "$GPU_LISTA" | grep -qiE '\[8086:[[:xdigit:]]{4}\]|(^|[^[:alnum:]])Intel([^[:alnum:]]|$)'; then
        GPU_VENDORS="$GPU_VENDORS intel"
    fi
    GPU_VENDORS=$(printf '%s' "$GPU_VENDORS" | sed 's/^ //')

    GPU_NUM=$(printf '%s\n' "$GPU_LISTA" | grep -c . || true)
    GPU_CARDS=$(ls -1 /dev/dri/card* 2>/dev/null | sort -V | tr '\n' ':' | sed 's/:$//')

    [ -n "$GPU_VENDORS" ] || GPU_VENDORS="desconocida"

    if [ "$GPU_NUM" -ge 2 ] 2>/dev/null; then
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
    [ "$GPU_HIBRIDA" -eq 1 ] && info "Equipo con varias GPU: se instalan los drivers de cada fabricante."
    [ "$GPU_HIBRIDA_NVIDIA" -eq 1 ] && info "Hibrida Intel/AMD + NVIDIA: se habilita PRIME bajo demanda."
    [ -n "$GPU_CARDS" ] && info "Nodos DRM: $GPU_CARDS"
    return 0
}

# ============================================================================
# FUNCION: detectar hardware (VM y variables extra del wrapper)
# ============================================================================
detectar_hardware() {
    ES_VM=0
    if grep -qw hypervisor /proc/cpuinfo 2>/dev/null; then
        ES_VM=1
        VM_NOMBRE=$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo "desconocida")
        warn "Maquina virtual detectada ($VM_NOMBRE)."
        warn "Si dwl no arranca con 'couldn't create renderer', activa la aceleracion 3D"
        warn "en la VM. Aun sin ella, el wrapper reintenta solo con render por software."
    fi

    EXTRA_ENV=""
    if [ "$ES_VM" -eq 1 ]; then
        EXTRA_ENV="export WLR_NO_HARDWARE_CURSORS=1"
    fi
    return 0
}

# ============================================================================
# FUNCION: elegir el tag de dwl compatible con la wlroots instalada
# ============================================================================
wlroots_pc_instalada() {
    # Imprime la version de wlroots que ofrece pkg-config (0.20, 0.19, 0.18...)
    pkg-config --list-all 2>/dev/null | awk '$1 ~ /^wlroots-[0-9]/ { sub(/^wlroots-/,"",$1); print $1 }' | sort -V | tail -n1
}

# Deja el resultado en TAG_ELEGIDO (no usa stdout, para que los avisos no
# se mezclen con el valor devuelto).
elegir_tag_dwl() {
    TAG_ELEGIDO=""
    if [ -n "$DWL_TAG_FORZADO" ]; then
        TAG_ELEGIDO="$DWL_TAG_FORZADO"
        return 0
    fi
    WLR_PC=$(wlroots_pc_instalada)
    if [ -n "$WLR_PC" ]; then
        for PAR in $DWL_TAGS_COMPAT; do
            TAG="${PAR%%:*}"; VER="${PAR##*:}"
            if [ "$VER" = "$WLR_PC" ]; then
                TAG_ELEGIDO="$TAG"
                return 0
            fi
        done
        warn "No hay un tag de dwl probado para la wlroots $WLR_PC; probare el mas nuevo."
    else
        warn "No encontre la wlroots en pkg-config con nombre versionado (wlroots-0.XX)."
    fi
    TAG_ELEGIDO=$(printf '%s' "$DWL_TAGS_COMPAT" | awk '{print $1}' | cut -d: -f1)
    return 0
}

# ============================================================================
# FUNCION: generar config.h a partir del config.def.h DEL TAG QUE SE COMPILA
# ----------------------------------------------------------------------------
# Asi el config.h siempre encaja con la API de esa version (por ejemplo
# TAGKEYS cambio de 3 a 2 argumentos entre v0.8 y v0.9) y no hay que mantener
# a mano un config.h para cada version de dwl.
# ============================================================================
generar_config_h() {
    REPO="${1:-$HOME/dwl}"
    [ -d "$REPO" ] || { error "No existe el directorio de dwl: $REPO"; return 1; }
    cd "$REPO" || return 1
    [ -f config.def.h ] || { error "No encuentro $REPO/config.def.h"; return 1; }

    cp -f config.def.h config.h || return 1

    # --- Aridad de TAGKEYS: v0.7/v0.8 usan (KEY,SKEY,TAG); v0.9 usa (KEY,TAG)
    if grep -q 'define TAGKEYS(KEY,SKEY,TAG)' config.h; then
        TAGKEYS_ARIDAD=3
    else
        TAGKEYS_ARIDAD=2
    fi
    info "config.h: TAGKEYS con $TAGKEYS_ARIDAD argumentos (segun la version de dwl)."

    # --- Parche vanitygaps aplicado? (anade incgaps/decgaps/togglegaps)
    GAPS=0
    if grep -q 'incgaps' dwl.c 2>/dev/null; then
        GAPS=1
        info "config.h: se anaden los atajos de gaps del parche vanitygaps."
    fi

    # --- Ajustes simples (funcionan igual en v0.7, v0.8 y v0.9)
    sed -i 's|^static const int sloppyfocus.*|static const int sloppyfocus               = 1;  /* el foco sigue al raton */|' config.h
    sed -i 's|^static const unsigned int borderpx.*|static const unsigned int borderpx         = 2;  /* grosor del borde */|' config.h
    [ -n "$(sed -n '/^static const unsigned int snap/p' config.h)" ] && \
        sed -i 's|^static const unsigned int snap.*|static const unsigned int snap             = 32; /* iman al mover flotantes */|' config.h
    sed -i 's|^static const float rootcolor\[\].*|static const float rootcolor[]             = COLOR(0x1e1e2eff);|' config.h
    sed -i 's|^static const float bordercolor\[\].*|static const float bordercolor[]           = COLOR(0x313244ff);|' config.h
    sed -i 's|^static const float focuscolor\[\].*|static const float focuscolor[]            = COLOR(0x89b4faff);|' config.h
    sed -i 's|^static const float urgentcolor\[\].*|static const float urgentcolor[]           = COLOR(0xf38ba8ff);|' config.h
    sed -i 's|^static const float fullscreen_bg\[\].*|static const float fullscreen_bg[]         = {0.0f, 0.0f, 0.0f, 1.0f};|' config.h
    sed -i 's|^#define TAGCOUNT.*|#define TAGCOUNT (9)|' config.h
    # Con el parche vanitygaps: los gaps empiezan en 0 (nada de separacion) y
    # se suben con Super+Ctrl+u. Asi la primera impresion es la del dwl normal.
    if [ "$GAPS" = "1" ]; then
        sed -i 's|^static const unsigned int gappih.*|static const unsigned int gappih           = 0;  /* gaps horizontales internos (Super+Ctrl+u) */|' config.h
        sed -i 's|^static const unsigned int gappiv.*|static const unsigned int gappiv           = 0;  /* gaps verticales internos */|' config.h
        sed -i 's|^static const unsigned int gappoh.*|static const unsigned int gappoh           = 0;  /* gaps horizontales exteriores */|' config.h
        sed -i 's|^static const unsigned int gappov.*|static const unsigned int gappov           = 0;  /* gaps verticales exteriores */|' config.h
    fi
    sed -i 's|^static int log_level.*|static int log_level = WLR_ERROR;|' config.h
    # Super (tecla Windows) como modificador
    sed -i 's|^#define MODKEY .*|#define MODKEY WLR_MODIFIER_LOGO|' config.h

    # --- Distribucion de teclado
    if grep -q '^[[:space:]]*\.layout = "' config.h; then
        sed -i "s|^\([[:space:]]*\)\.layout = \".*\"|\1.layout = \"$KB_XKB\"|" config.h
    elif grep -q '^[[:space:]]*\.options = ' config.h; then
        # v0.9: el struct solo trae .options y el resto se deja a NULL
        sed -i "s|^\([[:space:]]*\)\.options = \(.*\)|\1.layout = \"$KB_XKB\", .variant = NULL, .options = \2|" config.h
    else
        warn "No pude fijar la distribucion de teclado en config.h (revisalo a mano)."
    fi

    # --- Reglas de ventanas
    sed -i '/^static const Rule rules\[\] = {/,/^};/c\
static const Rule rules[] = {\
\t/* app_id             title       tags mask     isfloating   monitor */\
\t{ "firefox",          NULL,       0,            0,           -1 },\
\t{ "org.gimp.GIMP",    NULL,       0,            1,           -1 },\
\t{ "mpv",              NULL,       0,            1,           -1 },\
\t{ "imv",              NULL,       0,            1,           -1 },\
};' config.h

    # --- Bloque "comandos + keys[]": se reemplaza entero desde '#define SHCMD'
    #     hasta el cierre del array keys[].
    inicio_bloque=$(grep -n '^#define SHCMD' config.h | head -n1 | cut -d: -f1)
    if [ -z "$inicio_bloque" ]; then
        inicio_bloque=$(grep -n '^static const char \*termcmd' config.h | head -n1 | cut -d: -f1)
    fi
    if [ -z "$inicio_bloque" ]; then
        error "No encuentro donde empiezan los comandos en config.h; no lo toco."
        return 1
    fi
    inicio_keys=$(awk -v s="$inicio_bloque" 'NR>s && /^static const Key keys\[\] = \{/ {print NR; exit}' config.h)
    fin_keys=$(awk -v s="${inicio_keys:-0}" 'NR>s && /^};/ {print NR; exit}' config.h)
    if [ -z "$inicio_keys" ] || [ -z "$fin_keys" ]; then
        error "No encuentro el array keys[] en config.h; no lo toco."
        return 1
    fi

    BLOQUE=$(mktemp) || return 1
    escribir_bloque_keys "$BLOQUE" || { rm -f "$BLOQUE"; return 1; }

    head -n "$((inicio_bloque - 1))" config.h > config.h.tmp || return 1
    cat "$BLOQUE" >> config.h.tmp || return 1
    tail -n "+$((fin_keys + 1))" config.h >> config.h.tmp || return 1
    mv -f config.h.tmp config.h || return 1
    rm -f "$BLOQUE"

    # --- Rueda del raton con Super: sube y baja el volumen -----------------
    inicio_axes=$(grep -n '^static const Axis axes\[\] = {' config.h | head -n1 | cut -d: -f1)
    if [ -n "$inicio_axes" ]; then
        fin_axes=$(awk -v s="$inicio_axes" 'NR>s && /^};/ {print NR; exit}' config.h)
        if [ -n "$fin_axes" ]; then
            head -n "$((inicio_axes - 1))" config.h > config.h.tmp
            cat >> config.h.tmp <<'AXES_EOF'
static const Axis axes[] = {
	/* rueda del raton con Super: volumen (pasos del 3%) */
	{ MODKEY, AxisUp,   spawn, {.v = upvol} },
	{ MODKEY, AxisDown, spawn, {.v = downvol} },
};
AXES_EOF
            tail -n "+$((fin_axes + 1))" config.h >> config.h.tmp
            mv -f config.h.tmp config.h || return 1
        fi
    fi

    # --- Aviso dentro del propio archivo
    printf '\n/* ------------------------------------------------------------------\n * config.h generado por %s v%s para dwl %s\n * Para aplicar cambios: dwl-rebuild\n * ------------------------------------------------------------------ */\n' \
        "$NOMBRE_SCRIPT" "$VERSION" "${DWL_TAG_USADO:-local}" >> config.h

    # --- Comprobacion minima de cordura: llaves equilibradas
    ABRE=$(tr -cd '{' < config.h | wc -c)
    CIERRA=$(tr -cd '}' < config.h | wc -c)
    if [ "$ABRE" != "$CIERRA" ]; then
        error "config.h quedo desequilibrado ($ABRE '{' contra $CIERRA '}'); revisalo."
        return 1
    fi
    info "config.h regenerado a partir de config.def.h de dwl (llaves: $ABRE/$CIERRA)."
    return 0
}

# Escribe en $1 el bloque "comandos + keys[]" ya adaptado a la version de dwl
escribir_bloque_keys() {
    DESTINO="$1"

    # Teclas de los tags: en un teclado latam/es, Shift+1 no da '1' sino '!',
    # por eso, en las versiones con TAGKEYS(KEY,SKEY,TAG), hay que pasar la
    # tecla de nivel 1 correcta para cada distribucion.
    S1=""; S2=""; S3=""; S4=""; S5=""; S6=""; S7=""; S8=""; S9=""
    if [ "$TAGKEYS_ARIDAD" = "3" ]; then
        case "$KB_XKB" in
            us)
                set -- exclam at numbersign dollar percent asciicircum ampersand asterisk parenleft
                ;;
            es)
                # es-ES: 3 -> periodcentered (el "·")
                set -- exclam quotedbl periodcentered dollar percent ampersand slash parenleft parenright
                ;;
            *)
                # latam: 2 -> quotedbl, 3 -> numbersign, 7 -> slash
                set -- exclam quotedbl numbersign dollar percent ampersand slash parenleft parenright
                ;;
        esac
        S1="$1"; S2="$2"; S3="$3"; S4="$4"; S5="$5"; S6="$6"; S7="$7"; S8="$8"; S9="$9"
    fi

    cat > "$DESTINO" <<'CMD_EOF'
/* ======================================================================
 * COMANDOS Y ATAJOS
 * (generado por install-dwl.sh; si lo editas, ejecuta dwl-rebuild)
 * ====================================================================== */
/* Atajo para ordenes de shell al estilo dwm: SHCMD("orden") */
#define SHCMD(cmd) { .v = (const char*[]){ "/bin/sh", "-c", cmd, NULL } }

static const char *termcmd[]    = { "foot", NULL };
static const char *browsercmd[] = { "firefox", NULL };
static const char *lfcmd[]      = { "foot", "-e", "lf", NULL };
/* wmenu se dibuja abajo (-b) y NO toca la barra: antes se ocultaba y se
 * volvia a mostrar con dwlb -toggle-visibility, lo que invertia el estado
 * si tu ya la tenias oculta.
 *
 * -l N: wmenu-run lista TODOS los comandos de tu PATH (unos dos mil), y sin
 * -l el menu se dibuja como una sola tira horizontal de lado a lado de la
 * pantalla. Con -l N se ve una caja de N lineas (N se cambia con la variable
 * MENU_LINEAS al ejecutar el instalador). */
static const char *menucmd[]    = { "wmenu-run", "-b", "-l", "@MENU_LINEAS@",
                                    "-f", "@WMENU_FONT@",
                                    "-N", "1e1e2e", "-n", "cdd6f4",
                                    "-M", "1e1e2e", "-m", "89b4fa",
                                    "-S", "89b4fa", "-s", "1e1e2e", NULL };
static const char *lockcmd[]    = { "swaylock", NULL };
/* Volumen via PipeWire, pasos del 3% */
static const char *upvol[]      = { "wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "3%+", "-l", "1.0", NULL };
static const char *downvol[]    = { "wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "3%-", NULL };
static const char *mutevol[]    = { "wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle", NULL };
/* Brillo, pasos del 5% */
static const char *brup[]       = { "brightnessctl", "set", "+5%", NULL };
static const char *brdown[]     = { "brightnessctl", "set", "5%-", NULL };
static const char *screenshot[] = { "sh", "-c", "grim \"$HOME/Pictures/$(date +%Y-%m-%d_%H-%M-%S).png\"", NULL };
/* Control de la barra dwlb (man 1 dwlb, seccion Commands) */
static const char *bartoggle[]  = { "dwlb", "-toggle-visibility", "all", NULL };
static const char *barmove[]    = { "dwlb", "-toggle-location", "all", NULL };

static const Key keys[] = {
	/* ---------------- PROGRAMAS ---------------- */
	{ MODKEY,                    XKB_KEY_d,      spawn,            {.v = menucmd } },
	{ MODKEY,                    XKB_KEY_Return, spawn,            {.v = termcmd } },
	{ MODKEY,                    XKB_KEY_t,      spawn,            {.v = termcmd } },
	{ MODKEY,                    XKB_KEY_b,      spawn,            {.v = browsercmd } },
	{ MODKEY,                    XKB_KEY_r,      spawn,            {.v = lfcmd } },

	/* ---------------- VENTANAS ---------------- */
	{ MODKEY,                    XKB_KEY_q,      killclient,       {0} },
	{ MODKEY,                    XKB_KEY_j,      focusstack,       {.i = +1 } },
	{ MODKEY,                    XKB_KEY_Down,   focusstack,       {.i = +1 } },
	{ MODKEY,                    XKB_KEY_k,      focusstack,       {.i = -1 } },
	{ MODKEY,                    XKB_KEY_Up,     focusstack,       {.i = -1 } },
	{ MODKEY,                    XKB_KEY_h,      setmfact,         {.f = -0.05f} },
	{ MODKEY,                    XKB_KEY_l,      setmfact,         {.f = +0.05f} },
	{ MODKEY,                    XKB_KEY_i,      incnmaster,       {.i = +1 } },
	{ MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_T,      togglefloating,   {0} },
	{ MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_Return, zoom,             {0} },

	/* ---------------- LAYOUTS ---------------- */
	{ MODKEY,                    XKB_KEY_f,      setlayout,        {.v = &layouts[2]} },  /* monocle */
	{ MODKEY,                    XKB_KEY_space,  setlayout,        {0} },                 /* rotar */
	{ MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_F,      togglefullscreen, {0} },

	/* ---------------- BARRA (dwlb) ---------------- */
	{ MODKEY,                    XKB_KEY_w,      spawn,            {.v = bartoggle } },
	{ MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_W,      spawn,            {.v = barmove } },

	/* ---------------- BLOQUEO Y SESION ---------------- */
	{ MODKEY,                    XKB_KEY_Escape, spawn,            {.v = lockcmd } },
	{ MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_E,      quit,             {0} },
	{ WLR_MODIFIER_CTRL|WLR_MODIFIER_ALT, XKB_KEY_BackSpace, quit, {0} },

	/* ---------------- TAGS ---------------- */
CMD_EOF

    if [ "$TAGKEYS_ARIDAD" = "3" ]; then
        cat >> "$DESTINO" <<TAGKEYS_EOF
	TAGKEYS(          XKB_KEY_1, XKB_KEY_$S1,                        0),
	TAGKEYS(          XKB_KEY_2, XKB_KEY_$S2,                        1),
	TAGKEYS(          XKB_KEY_3, XKB_KEY_$S3,                        2),
	TAGKEYS(          XKB_KEY_4, XKB_KEY_$S4,                        3),
	TAGKEYS(          XKB_KEY_5, XKB_KEY_$S5,                        4),
	TAGKEYS(          XKB_KEY_6, XKB_KEY_$S6,                        5),
	TAGKEYS(          XKB_KEY_7, XKB_KEY_$S7,                        6),
	TAGKEYS(          XKB_KEY_8, XKB_KEY_$S8,                        7),
	TAGKEYS(          XKB_KEY_9, XKB_KEY_$S9,                        8),
TAGKEYS_EOF
    else
        cat >> "$DESTINO" <<'TAGKEYS_EOF'
	/* v0.9+: dwl prueba el nivel 0 y el nivel 1 de la tecla, asi que
	 * Super+Shift+1..9 funciona igual en us, es y latam. */
	TAGKEYS(          XKB_KEY_1,                        0),
	TAGKEYS(          XKB_KEY_2,                        1),
	TAGKEYS(          XKB_KEY_3,                        2),
	TAGKEYS(          XKB_KEY_4,                        3),
	TAGKEYS(          XKB_KEY_5,                        4),
	TAGKEYS(          XKB_KEY_6,                        5),
	TAGKEYS(          XKB_KEY_7,                        6),
	TAGKEYS(          XKB_KEY_8,                        7),
	TAGKEYS(          XKB_KEY_9,                        8),
TAGKEYS_EOF
    fi

    cat >> "$DESTINO" <<'COLA_EOF'
	{ MODKEY,                    XKB_KEY_Tab,    view,             {0} },  /* tag anterior */
	{ MODKEY,                    XKB_KEY_0,      view,             {.ui = ~0} }, /* ver todos */

	/* ---------------- MONITORES ----------------
	 * En teclado latam/es, Shift+coma y Shift+punto NO dan '<' y '>'.
	 * Se registran las dos variantes para que funcione en las tres
	 * distribuciones (y en v0.9 dwl mira los dos niveles de la tecla). */
	{ MODKEY,                    XKB_KEY_comma,  focusmon,         {.i = WLR_DIRECTION_LEFT} },
	{ MODKEY,                    XKB_KEY_period, focusmon,         {.i = WLR_DIRECTION_RIGHT} },
	{ MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_less,       tagmon,       {.i = WLR_DIRECTION_LEFT} },
	{ MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_greater,    tagmon,       {.i = WLR_DIRECTION_RIGHT} },
	{ MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_semicolon,  tagmon,       {.i = WLR_DIRECTION_LEFT} },
	{ MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_colon,      tagmon,       {.i = WLR_DIRECTION_RIGHT} },

	/* ---------------- TECLAS ESPECIALES (sin Super) ---------------- */
	{ 0,                         XKB_KEY_XF86AudioRaiseVolume,  spawn, {.v = upvol } },
	{ 0,                         XKB_KEY_XF86AudioLowerVolume,  spawn, {.v = downvol } },
	{ 0,                         XKB_KEY_XF86AudioMute,         spawn, {.v = mutevol } },
	{ 0,                         XKB_KEY_XF86MonBrightnessUp,   spawn, {.v = brup } },
	{ 0,                         XKB_KEY_XF86MonBrightnessDown, spawn, {.v = brdown } },
	{ 0,                         XKB_KEY_Print,                 spawn, {.v = screenshot } },
COLA_EOF

    if [ "$GAPS" = "1" ]; then
        cat >> "$DESTINO" <<'GAPS_EOF'

	/* ---------------- GAPS (parche vanitygaps) ----------------
	 * Los gaps empiezan en 0 (sin separacion). Super+Ctrl+u anade 5 px por
	 * pulsacion, Super+Shift+u los quita, Super+Ctrl+0 los activa/desactiva
	 * y Super+Ctrl+Shift+0 los devuelve a 0. */
	{ MODKEY|WLR_MODIFIER_CTRL,  XKB_KEY_u,      incgaps,          {.i = +5 } },
	{ MODKEY|WLR_MODIFIER_CTRL|WLR_MODIFIER_SHIFT, XKB_KEY_U,     incgaps, {.i = -5 } },
	{ MODKEY|WLR_MODIFIER_CTRL,  XKB_KEY_0,      togglegaps,       {0} },
	/* Shift+0 no da el mismo simbolo en todas las distribuciones: se
	 * registran las tres variantes. */
	{ MODKEY|WLR_MODIFIER_CTRL|WLR_MODIFIER_SHIFT, XKB_KEY_0,          defaultgaps, {0} },
	{ MODKEY|WLR_MODIFIER_CTRL|WLR_MODIFIER_SHIFT, XKB_KEY_parenright, defaultgaps, {0} },
	{ MODKEY|WLR_MODIFIER_CTRL|WLR_MODIFIER_SHIFT, XKB_KEY_equal,      defaultgaps, {0} },
GAPS_EOF
    fi

    cat >> "$DESTINO" <<'FIN_EOF'

	/* ---------------- CONSOLAS (no borrar) ----------------
	 * Si dwl se congela, Ctrl+Alt+Fx es la unica salida a una tty. */
#define CHVT(n) { WLR_MODIFIER_CTRL|WLR_MODIFIER_ALT,XKB_KEY_F##n, chvt, {.ui = (n)} }
	CHVT(1), CHVT(2), CHVT(3), CHVT(4),  CHVT(5),  CHVT(6),
	CHVT(7), CHVT(8), CHVT(9), CHVT(10), CHVT(11), CHVT(12),
};
FIN_EOF

    sustituir "$DESTINO" "@WMENU_FONT@" "$(fuente_pango "$DWLB_FONT")"
    sustituir "$DESTINO" "@MENU_LINEAS@" "$MENU_LINEAS"
    return 0
}

# ============================================================================
# FUNCION: dwl (clonar/actualizar, parchear, compilar e instalar)
# ============================================================================
# Aplica un parche: primero con git apply y, si el contexto no cuadra, con
# patch(1) y algo de tolerancia. Si queda cualquier duda, se deshace todo.
aplicar_un_parche() {
    ARCH="$1"
    if git apply --check "$ARCH" 2>/dev/null && git apply "$ARCH" 2>/dev/null; then
        return 0
    fi
    if patch -p1 --fuzz=3 --no-backup-if-mismatch -s < "$ARCH" 2>/dev/null; then
        if [ -z "$(find . -name '*.rej' -print -quit 2>/dev/null)" ]; then
            find . -name '*.orig' -delete 2>/dev/null || true
            return 0
        fi
    fi
    # Deshacer lo que haya quedado a medias
    find . -name '*.rej' -delete 2>/dev/null || true
    find . -name '*.orig' -delete 2>/dev/null || true
    git checkout -- . 2>/dev/null || true
    git clean -fd -- protocols >/dev/null 2>&1 || true
    return 1
}

# Ya aplicado, comprobamos que de verdad ha hecho lo que tenia que hacer.
parche_ipc_ok() {
    [ -f protocols/dwl-ipc-unstable-v2.xml ] ||     [ -f protocols/dwl-ipc-unstable-v1.xml ] ||     grep -q 'dwl_ipc_manager_bind' dwl.c 2>/dev/null
}

parche_gaps_ok() {
    grep -q 'incgaps' dwl.c 2>/dev/null
}

aplicar_parches_dwl() {
    # $1 = directorio del repo. Aplica ipc y vanitygaps si entran limpios.
    REPO="$1"
    cd "$REPO" || return 1
    PARCHES_APLICADOS=""

    if ! command -v curl >/dev/null 2>&1; then
        warn "No hay curl: se omiten los parches."
        return 0
    fi

    mkdir -p parches-local || return 1
    for PAR in ipc:ipc.patch vanitygaps:vanitygaps.patch; do
        NOMBRE="${PAR%%:*}"; ARCHIVO="${PAR##*:}"
        case "$NOMBRE" in
            ipc)        URL="$PARCHES_IPC_URL" ;;
            vanitygaps) URL="$PARCHES_GAPS_URL" ;;
        esac
        DESTINO="parches-local/$ARCHIVO"
        if [ ! -s "$DESTINO" ]; then
            curl -fsSL --max-time 30 -o "$DESTINO" "$URL" 2>/dev/null || true
            # Los gaps tienen variantes por version
            if [ ! -s "$DESTINO" ]; then
                case "$DWL_TAG_USADO" in
                    v0.7) curl -fsSL --max-time 30 -o "$DESTINO" "$PARCHES_GAPS_07" 2>/dev/null || true ;;
                    v0.8) curl -fsSL --max-time 30 -o "$DESTINO" "$PARCHES_GAPS_08" 2>/dev/null || true ;;
                esac
            fi
        fi
        if [ ! -s "$DESTINO" ]; then
            warn "No pude descargar el parche '$NOMBRE'; se omite."
            continue
        fi

        if aplicar_un_parche "$DESTINO"; then
            case "$NOMBRE" in
                ipc)  if parche_ipc_ok;  then PARCHES_APLICADOS="$PARCHES_APLICADOS $NOMBRE"; info "Parche 'ipc' aplicado (tags clicables en la barra)."; else
                          warn "El parche 'ipc' no dejo el protocolo esperado; lo deshago."
                          git checkout -- . 2>/dev/null || true
                          git clean -fd -- protocols >/dev/null 2>&1 || true
                      fi ;;
                *)    if parche_gaps_ok; then PARCHES_APLICADOS="$PARCHES_APLICADOS $NOMBRE"; info "Parche 'vanitygaps' aplicado (atajos de gaps)."; else
                          warn "El parche 'vanitygaps' no entro bien; lo deshago."
                          git checkout -- . 2>/dev/null || true
                      fi ;;
            esac
        else
            warn "El parche '$NOMBRE' no entra limpio en dwl $DWL_TAG_USADO; se omite."
        fi
    done
    DWL_PARCHES_USADOS=$(printf '%s' "$PARCHES_APLICADOS" | sed 's/^ //')
    return 0
}

preparar_xwayland() {
    # dwl trae XWAYLAND y XLIBS comentados en config.mk: sin eso Steam y
    # cualquier app X11 no abren. Solo se activa si los headers estan.
    if ! pkg-config --exists xcb xcb-icccm 2>/dev/null; then
        warn "Faltan los headers de xcb-icccm (paquete xcb-util-wm-devel):"
        warn "  sudo xbps-install -S xcb-util-wm-devel libxcb-devel"
        warn "dwl se compilara SIN Xwayland."
        DWL_XWAYLAND="no"
        return 0
    fi
    sed -i 's/^#\(XWAYLAND = .*\)/\1/; s/^#\(XLIBS = .*\)/\1/' config.mk || return 1
    if grep -q '^XWAYLAND = -DXWAYLAND' config.mk; then
        DWL_XWAYLAND="si"
        info "Xwayland activado en config.mk (Steam y apps X11 funcionaran)."
    else
        DWL_XWAYLAND="no"
        warn "No pude activar XWAYLAND en config.mk; dwl se compilara sin Xwayland."
    fi
    return 0
}

compilar_dwl() {
    titulo "dwl: compositor"

    cd "$HOME" || return 1
    if [ -d dwl/.git ]; then
        info "Ya existe ~/dwl: se actualiza el repositorio y sus tags."
        cd "$HOME/dwl" || return 1
        fix_owner || return 1
        git remote set-url origin "$DWL_REPO" 2>/dev/null || true
        git fetch --tags --force 2>/dev/null || warn "No pude actualizar desde git; uso lo que hay."
    else
        info "Clonando dwl desde $DWL_REPO ..."
        if ! git clone "$DWL_REPO" dwl; then
            warn "El clon desde Codeberg fallo; pruebo el espejo de GitHub..."
            git clone "$DWL_REPO_ESPEJO" dwl || { error "No pude clonar dwl."; return 1; }
        fi
        cd "$HOME/dwl" || return 1
    fi
    fix_owner || return 1

    # --- Orden de candidatos: primero el tag elegido, luego el resto ---
    elegir_tag_dwl
    TAG_PREFERIDO="$TAG_ELEGIDO"
    CANDIDATOS="$TAG_PREFERIDO"
    for PAR in $DWL_TAGS_COMPAT; do
        T="${PAR%%:*}"
        [ "$T" = "$TAG_PREFERIDO" ] && continue
        CANDIDATOS="$CANDIDATOS $T"
    done
    info "wlroots instalada: $(wlroots_pc_instalada 2>/dev/null || echo '?'). Candidatos: $CANDIDATOS"

    # --- Parches opcionales (se preguntan una vez) ---
    if [ -z "${PARCHES_PREGUNTADO:-}" ]; then
        PARCHES_PREGUNTADO=1
        pedir_si_no PARCHES_USAR "Aplicar parches opcionales de dwl (IPC = tags clicables, y vanitygaps)?" "${PARCHES:-si}"
        [ "$PARCHES_USAR" = "si" ] || info "Se compila dwl sin parches."
    fi

    for TAG in $CANDIDATOS; do
        info "------ Probando dwl $TAG ------"
        git checkout -f "$TAG" >/dev/null 2>&1 || { warn "$TAG no existe en el clon."; continue; }
        git clean -fdx >/dev/null 2>&1 || true
        DWL_TAG_USADO="$TAG"
        DWL_PARCHES_USADOS=""

        # 1) Parches (opcionales)
        if [ "$PARCHES_USAR" = "si" ]; then
            aplicar_parches_dwl "$HOME/dwl" || true
        fi

        # 2) Xwayland
        DWL_XWAYLAND="no"
        preparar_xwayland || true

        # 3) config.h adaptado a ESTE tag
        if ! generar_config_h "$HOME/dwl"; then
            warn "No pude generar config.h para $TAG; paso al siguiente candidato."
            continue
        fi

        # 4) Compilar
        info "Compilando dwl $TAG (Xwayland: $DWL_XWAYLAND, parches:${DWL_PARCHES_USADOS:- ninguno})..."
        make clean >/dev/null 2>&1 || true
        if make; then
            if sudo make install; then
                info "dwl $TAG instalado en /usr/local/bin/dwl."
                return 0
            fi
            warn "La compilacion fue bien, pero 'make install' fallo."
        else
            warn "dwl $TAG no compilo con estos parches."
        fi

        # 5) Reintento sin parches
        if [ -n "$DWL_PARCHES_USADOS" ]; then
            warn "Reintento dwl $TAG sin parches..."
            git checkout -f "$TAG" >/dev/null 2>&1 || true
            git clean -fdx >/dev/null 2>&1 || true
            DWL_PARCHES_USADOS=""
            DWL_XWAYLAND="no"
            preparar_xwayland || true
            if generar_config_h "$HOME/dwl"; then
                make clean >/dev/null 2>&1 || true
                if make && sudo make install; then
                    info "dwl $TAG instalado sin parches."
                    return 0
                fi
            fi
        fi
        warn "dwl $TAG no sirvio con esta wlroots."
    done

    error "No pude compilar dwl con ningun tag. Revisa la salida de 'make' en ~/dwl."
    error "Sugerencia: comprueba 'pkg-config --modversion wlroots-0.20' y prueba"
    error "  DWL_TAG=v0.9 sh $NOMBRE_SCRIPT"
    return 1
}

# ============================================================================
# FUNCION: dwlb (barra) - compilar e instalar
# ============================================================================
compilar_dwlb() {
    titulo "dwlb: barra de estado"

    cd "$HOME" || return 1
    if [ -d dwlb/.git ]; then
        info "Ya existe ~/dwlb: se reutiliza el clon."
    else
        info "Clonando dwlb desde $DWLB_REPO ..."
        git clone "$DWLB_REPO" || return 1
    fi
    cd "$HOME/dwlb" || return 1
    fix_owner || return 1

    # Commit probado (si no esta en el clon, se sigue con master).
    if [ -n "$DWLB_COMMIT" ]; then
        git fetch --all --tags --force >/dev/null 2>&1 || true
        if git cat-file -e "$DWLB_COMMIT^{commit}" 2>/dev/null; then
            git checkout -f "$DWLB_COMMIT" >/dev/null 2>&1 && info "dwlb fijado al commit ${DWLB_COMMIT%${DWLB_COMMIT#???????}}..."
        else
            warn "El commit probado de dwlb no esta disponible; uso la rama por defecto."
        fi
    fi

    # dwlb usa el estilo suckless: config.def.h -> config.h
    if [ -f config.def.h ] && [ ! -f config.h ]; then
        cp config.def.h config.h
        info "Creado ~/dwlb/config.h a partir de config.def.h."
    fi

    # Parche de compatibilidad layer-shell (por si el wlroots instalado anuncia
    # una version menor que la que pide dwlb.c).
    if grep -qE 'zwlr_layer_shell_v1_interface, [0-9]+\)' dwlb.c 2>/dev/null; then
        # OJO: hay que quedarse con el numero anterior al parentesis; si no, el
        # "1" de "v1_interface" se cuela y el test numerico falla.
        DWLB_LS_VER=$(grep -oE ', [0-9]+\)' dwlb.c | head -n1 | tr -dc '0-9')
        case "$DWLB_LS_VER" in ''|*[!0-9]*) DWLB_LS_VER="" ;; esac
        if [ -n "$DWLB_LS_VER" ] && [ "$DWLB_LS_VER" -gt 1 ]; then
            sed -i "s|&zwlr_layer_shell_v1_interface, $DWLB_LS_VER)|\&zwlr_layer_shell_v1_interface, (version < $DWLB_LS_VER ? version : $DWLB_LS_VER))|" dwlb.c 2>/dev/null || \
                warn "No pude aplicar el parche layer-shell a dwlb; sigo igualmente."
        fi
    fi

    make clean >/dev/null 2>&1 || true
    if ! make; then
        error "Fallo la compilacion de dwlb."
        error "Comprueba que esten: pixman-devel fcft-devel wayland-devel"
        return 1
    fi
    sudo make install || return 1

    if [ -f dwlb.1 ] && ! command -v man >/dev/null 2>&1; then
        :
    elif [ -f dwlb.1 ] && [ ! -f /usr/local/share/man/man1/dwlb.1 ]; then
        sudo mkdir -p /usr/local/share/man/man1
        sudo cp dwlb.1 /usr/local/share/man/man1/dwlb.1
        info "Manual instalado: man 1 dwlb"
    fi

    if ! command -v dwlb >/dev/null 2>&1; then
        error "dwlb no quedo en el PATH tras 'make install'."
        return 1
    fi
    info "dwlb instalado: $(command -v dwlb)"
    return 0
}

# ============================================================================
# FUNCION: configuracion de dwlb (~/.config/dwlb/config) - la lee el supervisor
# ----------------------------------------------------------------------------
# dwlb NO sabe leer archivos de configuracion (no hay getline/fopen en dwlb.c):
# sus opciones solo existen en la linea de comandos. Asi que este archivo lo
# lee /usr/local/bin/dwl-status-runner y le pasa las opciones a dwlb.
# ============================================================================
configurar_dwlb() {
    titulo "Configuracion de la barra"
    mkdir -p "$HOME/.config/dwlb"

    write_config_forzado "$HOME/.config/dwlb/config" <<EOF
# Configuracion de dwlb (https://github.com/kolunmi/dwlb)
# Generada por $NOMBRE_SCRIPT v$VERSION
#
# dwlb NO lee este archivo: lo lee /usr/local/bin/dwl-status-runner y le pasa
# cada linea a dwlb como si fuera un argumento. Por eso:
#   - una opcion por linea, tal cual se escribiria en la terminal;
#   - el valor no puede llevar espacios;
#   - si una opcion no existe en tu version de dwlb, el supervisor la ignora
#     y avisa, en vez de dejar la barra sin arrancar.
# Opciones validas en tu dwlb:  dwlb -h
# Tras editar: cierra sesion y vuelve a entrar (no hace falta recompilar nada).
#
# OJO: aqui van OPCIONES de arranque, nunca ordenes como -status, -title,
# -show, -hide, -toggle-visibility, -set-top, -set-bottom o -toggle-location:
# esas son ordenes para una barra que YA esta corriendo y, al arrancar, harian
# que dwlb enviara la orden y terminara sin dibujar nada (el supervisor las
# descarta si las encuentra).
#
# El supervisor anade por su cuenta, si dwl no lleva el parche IPC:
#   -tags 9 1 2 3 4 5 6 7 8 9   para que se vean los numeros de tag
#   -no-hide-vacant-tags        porque sin ipc todos los tags parecen vacios

-font $DWLB_FONT
-vertical-padding $DWLB_PAD

# Tags: oculta los vacios y los inactivos para que la barra quede limpia.
-hide-vacant-tags

# El titulo de la ventana enfocada, centrado.
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
-middle-bg-color $DWLB_MIDDLE_BG

# HiDPI: descomenta si tu monitor usa escalado 2x (1.25 y 1.5 tambien valen).
# -scale 2
EOF
    info "Escrito ~/.config/dwlb/config"

    # --- Generador del texto de estado (CPU, RAM, volumen, bateria, reloj) ---
    sudo tee /usr/local/bin/dwlb-status >/dev/null <<'STATUS_EOF'
#!/bin/sh
# dwlb-status: imprime el texto de estado para la barra dwlb.
# Se usa asi:   dwlb-status | dwlb -status-stdin all
# Comandos en linea de dwlb: ^fg(RRGGBB) ^bg(RRGGBB) ^lm(cmd) ^mm(cmd) ^rm(cmd)
# Consulta: man 1 dwlb   (y https://github.com/kolunmi/dwlb)

COLOR_ETIQ="89b4fa"    # azul  (etiquetas)
COLOR_TXT="cdd6f4"     # texto normal
COLOR_ALERTA="f38ba8"  # rojo  (bateria baja)

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
        if [ "$CAP" -le 15 ] 2>/dev/null && [ "$EST" != "Charging" ]; then
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
    # Clic izquierdo en la hora: calendario. Clic central: terminal.
    printf '^lm(foot -e sh -c "cal -3; printf \\"Pulsa Enter para cerrar\\"; read x")^mm(foot)^fg(%s)%s^fg()^mm()^lm()' \
        "$COLOR_TXT" "$(date '+%a %d/%m  %H:%M')"
}

while :; do
    printf '^mm(foot)%s%s%s%s%s^mm()\n' \
        "$(bloque_cpu)" "$(bloque_ram)" "$(bloque_volumen)" \
        "$(bloque_bateria)" "$(bloque_fecha)"
    sleep 5
done
STATUS_EOF
    sudo chmod +x /usr/local/bin/dwlb-status
    info "Instalado /usr/local/bin/dwlb-status"
}

# ============================================================================
# FUNCION: supervisor de la barra y el fondo (lo lanza dwl -s)
# ============================================================================
escribir_supervisor() {
    sudo tee /usr/local/bin/dwl-status-runner >/dev/null <<'RUNNER_EOF'

#!/bin/sh
# dwl-status-runner: lo arranca dwl con -s cuando el compositor ya esta listo.
# Se puede lanzar de dos formas:
#   - automaticamente: dwl -s /usr/local/bin/dwl-status-runner   (lo hace dwl-session)
#   - a mano, para probar:   dwl -s /usr/local/bin/dwl-status-runner
#
# Hace tres cosas: prepara el entorno minimo que dwlb necesita, arranca UNA
# barra dwlb con las opciones de ~/.config/dwlb/config y le da el estado
# (CPU, RAM, volumen, reloj). Todo queda en el registro de la sesion (LOG).
#
# Lo que conviene saber de dwlb (leido en su codigo fuente):
#   * necesita XDG_RUNTIME_DIR; si no esta definido, aborta con
#     "Could not retrieve XDG_RUNTIME_DIR" y no dibuja nada.
#   * sin -ipc lee el estado de su ENTRADA ESTANDAR y, si esa entrada se cierra
#     (EOF), la barra termina. Por eso el estado va por tuberia y el generador
#     la mantiene abierta.
#   * con -ipc NO lee stdin: el estado se le manda por su socket con
#     'dwlb -status-stdin all' (eso funciona igual con y sin ipc).
#   * con -ipc y un dwl SIN el parche IPC aborta con
#     "Compositor does not support all needed protocols".
#   * sin ipc no puede saber en que tag estas: los muestra con -tags, fijos.

# --- 0. Entorno minimo garantizado -----------------------------------------
# runit arranca los servicios con PATH=/usr/bin:/usr/sbin (ver /etc/runit/2) y
# greetd/tuigreet no leen /etc/profile, asi que /usr/local/bin (donde viven
# dwlb y dwlb-status) NO esta en el PATH de la sesion. Se anade aqui, y no solo
# en dwl-session, porque este script tambien se puede lanzar a mano.
for DIR_BIN in /usr/local/sbin /usr/local/bin /usr/sbin /usr/bin /sbin /bin; do
    case ":$PATH:" in
        *":$DIR_BIN:"*) ;;
        *) PATH="${PATH:+$PATH:}$DIR_BIN" ;;
    esac
done
export PATH

# dwlb necesita XDG_RUNTIME_DIR para crear su socket.
if [ -z "$XDG_RUNTIME_DIR" ] || [ ! -d "$XDG_RUNTIME_DIR" ] || [ ! -w "$XDG_RUNTIME_DIR" ]; then
    UID_RUN=$(id -u)
    for CAND in "/run/user/$UID_RUN" "$HOME/.xdg-runtime"; do
        if [ -d "$CAND" ] && [ -w "$CAND" ]; then
            XDG_RUNTIME_DIR="$CAND"
            break
        fi
        if mkdir -p "$CAND" 2>/dev/null && chmod 0700 "$CAND" 2>/dev/null && [ -w "$CAND" ]; then
            XDG_RUNTIME_DIR="$CAND"
            break
        fi
    done
    if [ -n "$XDG_RUNTIME_DIR" ]; then
        export XDG_RUNTIME_DIR
    fi
fi

LOG="${XDG_RUNTIME_DIR:-/tmp}/dwl-session-$(id -u).log"
log() { printf '%s dwl-status-runner: %s\n' "$(date '+%H:%M:%S')" "$1" >> "$LOG" 2>/dev/null || true; }

# Binarios resueltos una sola vez (por si el PATH no los trae).
DWLB_BIN=$(command -v dwlb 2>/dev/null || true)
if [ -z "$DWLB_BIN" ] || [ ! -x "$DWLB_BIN" ]; then DWLB_BIN=/usr/local/bin/dwlb; fi
DWLB_STATUS_BIN=$(command -v dwlb-status 2>/dev/null || true)
if [ -z "$DWLB_STATUS_BIN" ] || [ ! -x "$DWLB_STATUS_BIN" ]; then DWLB_STATUS_BIN=/usr/local/bin/dwlb-status; fi

CONF="${XDG_CONFIG_HOME:-$HOME/.config}/dwlb/config"
HIJOS=""
PID_BARRA=""
PID_ESTADO=""
OPCIONES_DWLB=""
TAGS_DEF='@TAGS_DEF@'

limpiar_hijos() {
    for PID_HIJO in $HIJOS; do
        kill "$PID_HIJO" 2>/dev/null || true
    done
    HIJOS=""
    PID_BARRA=""
    PID_ESTADO=""
}

# OJO: aqui no se usa 'wait': en dash, 'wait PID' de un proceso que forma parte
# de una tuberia espera a TODA la tuberia, y el generador de estado (que sigue
# vivo a proposito) bloquearia la limpieza. Los generadores que se queden sin
# lector mueren solos al recibir SIGPIPE cuando escriben.
trap limpiar_hijos EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

esta_vivo() { [ -n "$1" ] && kill -0 "$1" 2>/dev/null; }

log "inicio: pid=$$ PATH=$PATH"
log "XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-(SIN DEFINIR)}"
log "dwlb=$DWLB_BIN  dwlb-status=$DWLB_STATUS_BIN"
[ -x "$DWLB_BIN" ] || log "ERROR: no encuentro el ejecutable dwlb. Reinstalalo con install-dwl.sh"

# dwl le da a la orden de -s un tubo por su salida estandar (ver run() en dwl.c):
# si nadie lo lee y dwl escribiera algo, dwl se quedaria bloqueado. Se vacia.
exec 3<&0
cat <&3 >/dev/null 2>&1 &
HIJOS="$HIJOS $!"

# --- Opciones de la barra desde el archivo de configuracion ----------------
# Solo se aceptan opciones que aparezcan en 'dwlb -h': una opcion desconocida
# hace que dwlb no arranque, y eso dejaria la sesion sin barra.
leer_opciones_dwlb() {
    [ -f "$CONF" ] || return 0
    AYUDA=$("$DWLB_BIN" -h 2>&1 || true)
    LISTA=$(printf '%s\n' "$AYUDA" | tr ' \t' '\n\n' | grep '^-' || true)
    N=0
    while IFS= read -r LINEA || [ -n "$LINEA" ]; do
        case "$LINEA" in ''|'#'*) continue ;; esac
        CLAVE="${LINEA%% *}"
        case "$CLAVE" in
            # Estas NO son opciones de arranque: son ORDENES que dwlb manda a
            # una barra que ya esta corriendo. Al arrancar, dwlb enviaria la
            # orden y terminaria sin dibujar nada.
            -status|-status-stdin|-title|-show|-hide|-toggle-visibility|\
            -set-top|-set-bottom|-toggle-location|-target-socket)
                log "opcion ignorada (es una orden, no una opcion de arranque): $LINEA"
                continue ;;
        esac
        if printf '%s\n' "$LISTA" | grep -qx -- "$CLAVE"; then
            OPCIONES_DWLB="$OPCIONES_DWLB $LINEA"
            N=$((N + 1))
        else
            printf 'dwl-status-runner: opcion ignorada (%s no existe en este dwlb): %s\n' \
                "$CLAVE" "$LINEA" >&2
            log "opcion ignorada (no existe en este dwlb): $LINEA"
        fi
    done < "$CONF"
    log "$N opciones tomadas de $CONF:$OPCIONES_DWLB"
}

# --- Estado: quien se lo da a la barra ------------------------------------
# Con ipc la barra NO lee stdin: el texto se le manda por su socket con
# 'dwlb -status-stdin all'. Cada vuelta abre un dwlb nuevo en modo orden, asi
# que si el socket aun no existia, el intento siguiente (5 s) ya lo encuentra.
generador_estado_ipc() {
    while :; do
        "$DWLB_STATUS_BIN" 2>/dev/null | "$DWLB_BIN" -status-stdin all >/dev/null 2>&1
        sleep 5
    done &
}

# --- Arranque de la barra --------------------------------------------------
# $1 = -ipc | -no-ipc    $2 = opciones extra para este intento
# Deja la barra en PID_BARRA y devuelve 0 si sigue viva un segundo despues.
arrancar_barra() {
    MODO_BARRA="$1"
    EXTRA="$2"
    case "$MODO_BARRA" in
        -ipc)
            # La barra no lee stdin; el estado va por el socket.
            # shellcheck disable=SC2086
            "$DWLB_BIN" $OPCIONES_DWLB $EXTRA -ipc </dev/null >>"$LOG" 2>&1 &
            PID_BARRA=$!
            generador_estado_ipc
            PID_ESTADO=$!
            ;;
        *)
            # La barra LEE su stdin: hay que darle la tuberia del estado. Con
            # esto, ademas, nunca ve un EOF (la tuberia la mantiene abierta el
            # bucle del generador) y no hereda un stdin que pueda cerrarse.
            # OJO: con 'A | B &' el $! es el pid de B (dwlb), que es justo el
            # que hay que vigilar.
            # shellcheck disable=SC2086
            { while :; do "$DWLB_STATUS_BIN" 2>/dev/null; sleep 5; done; } | \
                "$DWLB_BIN" $OPCIONES_DWLB $EXTRA -no-ipc >>"$LOG" 2>&1 &
            PID_BARRA=$!
            PID_ESTADO=""
            ;;
    esac
    HIJOS="$HIJOS $PID_BARRA $PID_ESTADO"
    log "lanzado: dwlb $OPCIONES_DWLB $EXTRA $MODO_BARRA   (pid $PID_BARRA)"
    sleep 1
    if esta_vivo "$PID_BARRA"; then
        log "la barra esta viva ($MODO_BARRA)"
        return 0
    fi
    log "la barra murio al arrancar (el motivo esta en las lineas de dwlb de arriba)"
    return 1
}

# --- Modo de la barra: lo dice dwl-session; si no, se deduce ----------------
if [ -z "$DWL_BAR_MODE" ]; then
    DWL_BAR_MODE="-no-ipc"
    for DWL_CAND in "$HOME/dwl/dwl" /usr/local/bin/dwl; do
        [ -f "$DWL_CAND" ] || continue
        # El protocolo IPC deja su nombre en el binario: 'grep -a' busca dentro
        # de un archivo binario.
        if grep -aq "dwl_ipc_manager" "$DWL_CAND" 2>/dev/null; then
            DWL_BAR_MODE="-ipc"
        fi
        break
    done
    log "modo de barra deducido del binario de dwl: $DWL_BAR_MODE"
fi

# --- Fondo de pantalla (necesita Wayland, por eso se lanza aqui) -----------
if [ -n "$DWL_WALLPAPER" ] && [ -f "$DWL_WALLPAPER" ] && command -v swaybg >/dev/null 2>&1; then
    swaybg -i "$DWL_WALLPAPER" -m fill </dev/null >/dev/null 2>&1 &
    HIJOS="$HIJOS $!"
fi

# --- Barra -----------------------------------------------------------------
# Si DWL_BAR_KIND no viene definido (lanzado a mano), se supone dwlb.
case "${DWL_BAR_KIND:-dwlb}" in
    dwlb)
        leer_opciones_dwlb
        if [ ! -x "$DWLB_BIN" ]; then
            log "no se intenta nada: falta el ejecutable dwlb"
        else
            case "$DWL_BAR_MODE" in
                -ipc)
                    if arrancar_barra -ipc ""; then
                        :
                    else
                        log "reintento sin ipc (dwl podria no llevar el parche IPC)"
                        limpiar_hijos
                        arrancar_barra -no-ipc "$TAGS_DEF -no-hide-vacant-tags" || \
                            log "dwlb NO arranca en ningun modo: la sesion se queda sin barra"
                    fi
                    ;;
                *)
                    if arrancar_barra -no-ipc "$TAGS_DEF -no-hide-vacant-tags"; then
                        :
                    else
                        log "reintento con ipc"
                        limpiar_hijos
                        arrancar_barra -ipc "" || \
                            log "dwlb NO arranca en ningun modo: la sesion se queda sin barra"
                    fi
                    ;;
            esac
        fi
        ;;
    *)
        log "sin barra (DWL_BAR_KIND='$DWL_BAR_KIND')"
        ;;
esac

if esta_vivo "$PID_BARRA"; then
    # Se pregunta por la vida de la barra en vez de usar 'wait' (ver arriba).
    while esta_vivo "$PID_BARRA"; do
        sleep 2
    done
    log "la barra dejo de funcionar (dwlb ya no esta en pie)"
fi
ESTADO_BARRA=0
limpiar_hijos
trap - EXIT HUP INT TERM
exit "$ESTADO_BARRA"
RUNNER_EOF
    sudo chmod +x /usr/local/bin/dwl-status-runner
    info "Instalado /usr/local/bin/dwl-status-runner"
}

# ============================================================================
# FUNCION: diagnostico de la barra (dwl-bar-diag)
# ----------------------------------------------------------------------------
# Se ejecuta DENTRO de dwl (Super+Enter abre foot) y dice, una por una, todas
# las cosas que pueden impedir que aparezca dwlb, incluida una prueba en vivo
# de los dos modos con el error exacto que da dwlb.
# ============================================================================
escribir_diagnostico() {
    sudo tee /usr/local/bin/dwl-bar-diag >/dev/null <<'DIAG_EOF'

#!/bin/sh
# dwl-bar-diag: averigua por que no aparece la barra dwlb.
# Ejecutalo DENTRO de la sesion dwl (Super+Enter abre una terminal foot):
#     dwl-bar-diag
# Desde una consola de texto tambien sirve, pero sin WAYLAND_DISPLAY no puede
# hacer la prueba en vivo de dwlb.

sep() { printf '\n== %s ==\n' "$1"; }

echo "dwl-bar-diag: revision de la barra dwlb  ($(date '+%Y-%m-%d %H:%M'))"

sep "entorno"
echo "usuario.............. $(id -un) (uid $(id -u))"
echo "XDG_RUNTIME_DIR...... ${XDG_RUNTIME_DIR:-(SIN DEFINIR -> dwlb NO puede arrancar)}"
echo "WAYLAND_DISPLAY...... ${WAYLAND_DISPLAY:-(SIN DEFINIR)}"
echo "PATH................. $PATH"

# El PATH es la causa mas comun: runit arranca greetd con PATH=/usr/bin:/usr/sbin
# y /usr/local/bin (donde vive dwlb) no esta. dwl-session y dwl-status-runner ya
# lo corrigen solos, pero conviene saber si el entorno que llega aqui lo trae.
case ":$PATH:" in
    *:/usr/local/bin:*) echo "  /usr/local/bin ....... en el PATH (correcto)" ;;
    *) echo "  /usr/local/bin ....... FALTA en el PATH (es el fallo tipico:" \
            "/usr/local/bin no esta en el PATH de las sesiones de greetd; el" \
            "instalador nuevo lo corrige en dwl-session y en el supervisor)" ;;
esac
# Para que el resto de la revision sea fiable, se anaden las rutas de siempre.
for DIR_BIN in /usr/local/sbin /usr/local/bin /usr/sbin /usr/bin /sbin /bin; do
    case ":$PATH:" in
        *":$DIR_BIN:"*) ;;
        *) PATH="${PATH:+$PATH:}$DIR_BIN" ;;
    esac
done
export PATH

sep "binarios (¿estan y son ejecutables?)"
for B in dwl dwlb dwlb-status dwl-status-runner dwl-session swaybg foot wmenu-run; do
    R=$(command -v "$B" 2>/dev/null || true)
    if [ -n "$R" ] && [ -x "$R" ]; then
        printf '  %-20s %s\n' "$B" "$R"
    else
        printf '  %-20s NO ENCONTRADO (deberia estar en /usr/local/bin)\n' "$B"
    fi
done

sep "ficheros instalados"
ls -l /usr/local/bin/dwl /usr/local/bin/dwlb /usr/local/bin/dwlb-status \
      /usr/local/bin/dwl-status-runner /usr/local/bin/dwl-session 2>&1 | sed 's/^/  /'

sep "¿le falta alguna libreria a dwlb?"
if command -v ldd >/dev/null 2>&1; then
    FALTAN=$(ldd /usr/local/bin/dwlb 2>/dev/null | grep 'not found' || true)
    if [ -n "$FALTAN" ]; then
        echo "  SI, FALTAN:"; printf '%s\n' "$FALTAN" | sed 's/^/    /'
    else
        echo "  no: todas las librerias estan"
    fi
else
    echo "  (ldd no esta instalado; se omite)"
fi

sep "procesos"
procesos() {
    # $1 = nombre exacto (dwl, dwlb, dwlb-status, dwl-status-runner).
    # Se mira el primer y el segundo campo de la orden (con los scripts, el
    # segundo es la ruta del script) para no confundir unos con otros.
    LISTA=$(ps -eo pid=,args= 2>/dev/null | awk -v p="$1" '
        { args = $0; sub(/^[ \t]*[0-9]+[ \t]+/, "", args); split(args, a, " ")
          if (a[1] == p || a[1] ~ ("/" p "$") || a[2] == p || a[2] ~ ("/" p "$")) print $0 }')
    if [ -n "$LISTA" ]; then
        printf '%s\n' "$LISTA" | sed 's/^/  /'
    else
        printf '  %s: no esta corriendo\n' "$1"
    fi
}
procesos dwl
procesos dwlb
procesos dwlb-status
procesos dwl-status-runner

sep "¿el dwl instalado lleva el parche IPC?"
if grep -aq "dwl_ipc_manager" /usr/local/bin/dwl 2>/dev/null; then
    echo "  SI: la barra puede ir con -ipc (tags clicables)"
else
    echo "  NO: la barra tiene que ir con -no-ipc (usa Super+1..9 para los tags)"
fi

sep "configuracion de la barra (~/.config/dwlb/config)"
CONF_DWLB="${XDG_CONFIG_HOME:-$HOME/.config}/dwlb/config"
if [ -f "$CONF_DWLB" ]; then
    sed 's/^/  /' "$CONF_DWLB"
else
    echo "  (no existe; el supervisor usara los valores por defecto de dwlb)"
fi

sep "sockets de la barra (XDG_RUNTIME_DIR/dwlb/)"
if [ -n "$XDG_RUNTIME_DIR" ] && [ -d "$XDG_RUNTIME_DIR/dwlb" ]; then
    ls -l "$XDG_RUNTIME_DIR/dwlb" 2>&1 | sed 's/^/  /'
else
    echo "  no existe el directorio ${XDG_RUNTIME_DIR:-?}/dwlb (dwlb no ha llegado a arrancar)"
fi

sep "PRUEBA EN VIVO (3 segundos por modo, dwlb tal cual y sin mas opciones)"
if [ -z "$WAYLAND_DISPLAY" ]; then
    echo "  No hay WAYLAND_DISPLAY: esto hay que ejecutarlo DENTRO de dwl"
    echo "  (Super+Enter abre foot, y ahi: dwl-bar-diag)."
else
    for M in -no-ipc -ipc; do
        ERR=/tmp/dwlb-diag.err
        # -no-ipc lee el estado de su entrada estandar: se le da una tuberia
        # viva (con </dev/null moriria por EOF, y eso es normal, no un fallo).
        sleep 8 | /usr/local/bin/dwlb "$M" >/dev/null 2>"$ERR" &
        P=$!
        sleep 3
        if kill -0 "$P" 2>/dev/null; then
            echo "  OK ..... dwlb $M aguanta: la barra deberia haber aparecido 3 segundos"
            kill "$P" 2>/dev/null
        else
            echo "  FALLO .. dwlb $M murio al arrancar y dijo:"
            sed 's/^/           /' "$ERR"
        fi
        rm -f "$ERR"
        sleep 1
    done
fi

sep "registro de la sesion (ultimas 40 lineas)"
LOG="${XDG_RUNTIME_DIR:-/tmp}/dwl-session-$(id -u).log"
if [ -f "$LOG" ]; then
    tail -n 40 "$LOG" | sed 's/^/  /'
else
    echo "  no existe $LOG"
fi

sep "fin"
echo "Copia esta salida entera si tienes que pedir ayuda con la barra."
DIAG_EOF
    sudo chmod +x /usr/local/bin/dwl-bar-diag
    info "Instalado /usr/local/bin/dwl-bar-diag (diagnostico de la barra)"
}

# ============================================================================
# FUNCION: wrapper de sesion (lo ejecuta greetd/tuigreet)
# ============================================================================
escribir_sesion() {
    sudo tee /usr/local/bin/dwl-session >/dev/null <<'SESION_EOF'
#!/bin/sh
# dwl-session: arranca la sesion de dwl. Lo ejecuta greetd (via dwl-greeter).
# Archivo generado por install-dwl.sh; puedes editarlo a mano.

# --- 0. PATH de la sesion --------------------------------------------------
# runit arranca los servicios con PATH=/usr/bin:/usr/sbin (ver /etc/runit/2) y
# greetd/tuigreet no leen /etc/profile: sin esto, /usr/local/bin (dwlb,
# dwlb-status, dwl-status-runner, dwl-greeter...) NO esta en el PATH y la barra
# no arranca, aunque todo este bien instalado.
for DIR_BIN in /usr/local/sbin /usr/local/bin /usr/sbin /usr/bin /sbin /bin; do
    case ":$PATH:" in
        *":$DIR_BIN:"*) ;;
        *) PATH="${PATH:+$PATH:}$DIR_BIN" ;;
    esac
done
export PATH

# --- 1. Bus de sesion D-Bus ------------------------------------------------
# Firefox, los portales y muchas apps lo necesitan. greetd no lo crea.
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ] && [ -z "$DWL_SESSION_DBUS" ] \
   && command -v dbus-run-session >/dev/null 2>&1; then
    DWL_SESSION_DBUS=1
    export DWL_SESSION_DBUS
    exec dbus-run-session -- "$0" "$@"
fi

export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=dwl
export XDG_SESSION_DESKTOP=dwl
export MOZ_ENABLE_WAYLAND=1
# Qt: primero Wayland y, si la app no lo soporta, cae a Xwayland.
export QT_QPA_PLATFORM="wayland;xcb"
export GDK_BACKEND="wayland,x11"
export _JAVA_AWT_WM_NONREPARENTING=1
export DWL_BAR_KIND="@BARRA@"
export DWL_BAR_MODE="@MODO@"
export DWL_WALLPAPER="@WALLPAPER@"
@EXTRA_ENV@

SESSION_UID=$(id -u)

# --- 2. Log de la sesion (util para depurar) -------------------------------
LOGFILE="${XDG_RUNTIME_DIR:-/tmp}/dwl-session-$SESSION_UID.log"
log() { printf '%s %s\n' "$(date '+%H:%M:%S')" "$1" >> "$LOGFILE" 2>/dev/null || true; }
log "dwl-session: inicio (usuario $SESSION_UID)"

# --- 3. XDG_RUNTIME_DIR (lo prepara turnstiled via PAM) --------------------
RUNDIR_OWNER=""
if [ -n "$XDG_RUNTIME_DIR" ] && [ -d "$XDG_RUNTIME_DIR" ]; then
    RUNDIR_OWNER=$(stat -c %u "$XDG_RUNTIME_DIR" 2>/dev/null || true)
fi
if [ "$RUNDIR_OWNER" != "$SESSION_UID" ]; then
    RUNDIR="/run/user/$SESSION_UID"
    RUNDIR_OWNER=$(stat -c %u "$RUNDIR" 2>/dev/null || true)
    if [ ! -d "$RUNDIR" ] || [ "$RUNDIR_OWNER" != "$SESSION_UID" ]; then
        RUNDIR="$HOME/.xdg-runtime"
        mkdir -p "$RUNDIR" 2>/dev/null || { echo "dwl-session: no pude crear XDG_RUNTIME_DIR" >&2; exit 1; }
        chmod 0700 "$RUNDIR" 2>/dev/null || { echo "dwl-session: no pude proteger XDG_RUNTIME_DIR" >&2; exit 1; }
        log "dwl-session: uso el directorio de respaldo $RUNDIR"
    fi
    export XDG_RUNTIME_DIR="$RUNDIR"
else
    chmod 0700 "$XDG_RUNTIME_DIR" 2>/dev/null || true
fi
LOGFILE="$XDG_RUNTIME_DIR/dwl-session-$SESSION_UID.log"

# --- 4. seatd: dwl necesita /run/seatd.sock (GPU, teclado, raton) ----------
if [ ! -S /run/seatd.sock ]; then
    i=0
    while [ "$i" -lt 10 ] && [ ! -S /run/seatd.sock ]; do
        i=$((i + 1))
        sleep 1
    done
    if [ ! -S /run/seatd.sock ]; then
        log "AVISO: /run/seatd.sock no aparece. Revisa: sudo sv status seatd"
    fi
fi

# --- 5. Demonios de usuario (audio) ---------------------------------------
SESSION_DAEMON_PIDS=""
DWL_PID=""

iniciar_daemon_usuario() {
    DAEMON_NAME=$1
    shift
    if pgrep -u "$SESSION_UID" -x "$DAEMON_NAME" >/dev/null 2>&1; then
        return 0
    fi
    if ! command -v "$DAEMON_NAME" >/dev/null 2>&1; then
        log "dwl-session: no se encontro $DAEMON_NAME; se omite."
        return 0
    fi
    "$@" >/dev/null 2>&1 &
    SESSION_DAEMON_PIDS="$SESSION_DAEMON_PIDS $!"
}

limpiar_daemons_usuario() {
    for PID_DAEMON in $SESSION_DAEMON_PIDS; do
        kill "$PID_DAEMON" 2>/dev/null || true
    done
    for PID_DAEMON in $SESSION_DAEMON_PIDS; do
        wait "$PID_DAEMON" 2>/dev/null || true
    done
    SESSION_DAEMON_PIDS=""
}

terminar_sesion() {
    if [ -n "$DWL_PID" ]; then
        kill "$DWL_PID" 2>/dev/null || true
    fi
    exit "$1"
}
trap limpiar_daemons_usuario EXIT
trap 'terminar_sesion 129' HUP
trap 'terminar_sesion 130' INT
trap 'terminar_sesion 143' TERM

iniciar_daemon_usuario pipewire pipewire
iniciar_daemon_usuario wireplumber wireplumber
iniciar_daemon_usuario pipewire-pulse pipewire-pulse

# --- 6. dwl (el supervisor -s arranca la barra y el fondo) ----------------
# Todo lo que impriman dwl y su supervisor (dwlb, fallos de la barra...) va al
# registro de la sesion: es lo primero que hay que mirar si algo no sale.
: >> "$LOGFILE" 2>/dev/null || LOGFILE=/dev/null
log "dwl-session: arrancando: @BARRA_CMD@"
INICIO=$(date +%s)
@BARRA_CMD@ >>"$LOGFILE" 2>&1 &
DWL_PID=$!
wait "$DWL_PID"
DWL_STATUS=$?
DWL_PID=""
log "dwl-session: dwl termino con estado $DWL_STATUS"

# Si dwl muere en los primeros segundos (por ejemplo "couldn't create
# renderer" en una VM sin aceleracion 3D), se reintenta con render por software.
if [ "$DWL_STATUS" -ne 0 ] && [ -z "$WLR_RENDERER" ] && [ $(( $(date +%s) - INICIO )) -lt 5 ]; then
    log "dwl-session: dwl fallo al arrancar; reintento con WLR_RENDERER=pixman"
    export WLR_RENDERER=pixman
    export WLR_NO_HARDWARE_CURSORS=1
    export LIBGL_ALWAYS_SOFTWARE=1
    @BARRA_CMD@ >>"$LOGFILE" 2>&1 &
    DWL_PID=$!
    wait "$DWL_PID"
    DWL_STATUS=$?
    DWL_PID=""
    log "dwl-session: dwl termino con estado $DWL_STATUS (render por software)"
fi

limpiar_daemons_usuario
trap - EXIT HUP INT TERM
log "dwl-session: fin"
exit "$DWL_STATUS"
SESION_EOF
    sudo chmod +x /usr/local/bin/dwl-session
    info "Instalado /usr/local/bin/dwl-session"
}

# ============================================================================
# FUNCION: wallpaper
# ============================================================================
descargar_wallpaper() {
    mkdir -p "$WALLPAPER_DIR"
    if [ -f "$WALLPAPER_PATH" ]; then
        return 0
    fi
    info "Descargando wallpaper..."
    WALLPAPER_TMP="$WALLPAPER_PATH.tmp"
    if curl -fsSL --max-time 30 -A "Mozilla/5.0" \
        -e "https://wallpapercave.com/" -o "$WALLPAPER_TMP" "$WALLPAPER_URL" 2>/dev/null \
        && [ -s "$WALLPAPER_TMP" ] \
        && file "$WALLPAPER_TMP" | grep -qi image; then
        mv "$WALLPAPER_TMP" "$WALLPAPER_PATH"
        info "Wallpaper en $WALLPAPER_PATH"
    else
        warn "No se pudo descargar un wallpaper valido; se omite (swaybg no arrancara)."
        rm -f "$WALLPAPER_TMP"
        WALLPAPER_PATH=""
    fi
}

# ============================================================================
# FUNCION: lf (navegador de archivos)
# ============================================================================
configurar_lf() {
    info "Configurando lf..."
    mkdir -p "$HOME/.config/lf"
    write_config "$HOME/.config/lf/lfrc" <<'LF_EOF'
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
LF_EOF
}

# ============================================================================
# FUNCION: chuleta de atajos (~/Atajos.txt)
# ============================================================================
escribir_atajos() {
    info "Creando la chuleta de atajos ~/Atajos.txt (leela con: nano ~/Atajos.txt)"
    write_config "$HOME/Atajos.txt" <<'ATAJOS_EOF'

==============================================================================
 ATAJOS DE TECLADO - dwl + dwlb
==============================================================================
  "Super" es la tecla del logo de Windows (en teclados Mac, Command).

------------------------------------------------------------------------------
 SI ACABAS DE INSTALAR, CON ESTO YA ALCANZA
------------------------------------------------------------------------------

  Super+Enter.................. abrir una terminal (foot)
  Super+d...................... lanzador de programas (wmenu)
  Super+q...................... cerrar la ventana actual
  Super+r...................... gestor de archivos (lf)
  Super+b...................... navegador (Firefox)
  Super+Shift+e................ cerrar sesion (volver al login)
  Ctrl+Alt+F1.................. consola de emergencia si algo se congela

  Con esos siete ya puedes manejarte. El resto se aprende sobre la marcha.

------------------------------------------------------------------------------
 GLOSARIO RAPIDO
------------------------------------------------------------------------------

  tag.......................... "escritorio virtual": hay 9 y cada uno guarda
                                sus propias ventanas
  area maestra................. la ventana grande y principal del mosaico
  layout....................... como se reparten las ventanas en pantalla
  monocle...................... una sola ventana ocupando toda la pantalla
  flotante..................... ventana fuera del mosaico; la mueves a mano
  barra........................ la linea de arriba (dwlb): tags, titulo,
                                CPU, RAM, volumen, bateria y hora
  gaps......................... separacion entre ventanas (vienen
                                DESACTIVADOS, y solo si aplicaste el parche)

  dwl es un gestor de ventanas en mosaico: no apila ventanas como Windows,
  las reparte automaticamente por la pantalla.

------------------------------------------------------------------------------
 PROGRAMAS
------------------------------------------------------------------------------

  Super+d...................... lanzador de comandos (wmenu-run)
                                lista TODOS los comandos instalados: escribe
                                las primeras letras para filtrar y pulsa Enter.
                                Se dibuja como una caja pegada abajo; el numero
                                de lineas se cambia con MENU_LINEAS al ejecutar
                                el instalador (por defecto 10).
  Super+Enter.................. terminal (foot)
  Super+t...................... terminal (foot), atajo alternativo
  Super+b...................... navegador (Firefox)
  Super+r...................... gestor de archivos (lf), dentro de foot
  Super+Escape................. bloquear la pantalla (swaylock)

------------------------------------------------------------------------------
 VENTANAS
------------------------------------------------------------------------------

  Super+q...................... cerrar la ventana enfocada
  Super+j...................... enfocar la siguiente ventana
  Super+Abajo.................. enfocar la siguiente (igual que Super+j)
  Super+k...................... enfocar la ventana anterior
  Super+Arriba................. enfocar la anterior (igual que Super+k)
  Super+h...................... achicar el area maestra
  Super+l...................... agrandar el area maestra
  Super+i...................... una ventana mas en el area maestra
  Super+Shift+t................ alternar flotante / volver al mosaico
  Super+Shift+Enter............ traer la ventana al area maestra (zoom)

------------------------------------------------------------------------------
 BARRA (dwlb)
------------------------------------------------------------------------------

  Super+w...................... ocultar o mostrar la barra
  Super+Shift+w................ mover la barra arriba o abajo

  La barra es dwlb (https://github.com/kolunmi/dwlb). Muestra los tags, el
  layout, el titulo, CPU, RAM, volumen, bateria y la hora.

  Su aspecto (fuente y colores) vive en ~/.config/dwlb/config. Ese archivo lo
  lee /usr/local/bin/dwl-status-runner: dwlb NO lee archivos de configuracion,
  asi que el supervisor le pasa las opciones como argumentos. Para aplicar
  cambios basta cerrar sesion y volver a entrar.

------------------------------------------------------------------------------
 LAYOUTS
------------------------------------------------------------------------------

  []=.......................... mosaico: area maestra + columna de ventanas
                                (el inicial)
  "><>"........................ flotante: cada ventana se mueve y se
                                redimensiona a mano
  [M].......................... monocle: una sola ventana a pantalla completa

  Super+Space.................. rotar de layout
  Super+f...................... ir directo a monocle
  Super+Shift+f................ pantalla completa real, sin barra (video,
                                juegos)

    Nota: el layout flotante no tiene tecla propia; se llega rotando con
    Super+Space.

------------------------------------------------------------------------------
 TAGS (los 9 escritorios)
------------------------------------------------------------------------------

  Super+1 ... 9................ ir a ese tag
  Super+Shift+1 ... 9.......... mover la ventana actual a ese tag
  Super+Ctrl+1 ... 9........... ver ese tag junto con el actual
  Super+Ctrl+Shift+1..9........ que la ventana aparezca en ambos tags
  Super+Tab.................... volver al tag anterior
  Super+0...................... ver los 9 tags a la vez

    Nota: en teclado latam/es, Shift+numero no produce el mismo numero. El
    instalador genera las teclas correctas segun tu distribucion (latam, es o
    us) y segun tu version de dwl, asi que Super+Shift+1..9 funciona en las
    tres.

  Idea de uso: terminal en el tag 1, navegador en el 2, musica en el 3,
  chat en el 4.

------------------------------------------------------------------------------
 MONITORES
------------------------------------------------------------------------------

  Super+punto.................. enfocar el monitor de la derecha
  Super+coma................... enfocar el monitor de la izquierda
  Super+Shift+>................ enviar la ventana al monitor de la derecha
  Super+Shift+<................ enviar la ventana al monitor de la izquierda

    Nota: tambien valen Super+Shift+punto y Super+Shift+coma, y
    Super+Shift+: / Super+Shift+;, porque en teclado latam/es Shift+coma y
    Shift+punto no producen < y >.

------------------------------------------------------------------------------
 GAPS - SOLO SI APLICASTE EL PARCHE
------------------------------------------------------------------------------

  dwl NO trae gaps: son del parche vanitygaps. Si el instalador pudo
  aplicarlo (te lo dice al terminar), los atajos son:

  Super+Ctrl+u................. aumentar 5 px la separacion entre ventanas
  Super+Ctrl+Shift+u........... quitar 5 px de separacion
  Super+Ctrl+0................. activar o desactivar los gaps
  Super+Ctrl+Shift+0........... devolver los gaps a 0 (sin separacion)

  Los gaps empiezan en 0: al instalar, las ventanas se ven pegadas como en el
  dwl de serie. Pulsa Super+Ctrl+u un par de veces y aparece la separacion.

  Si dwl se compilo sin parches, estos atajos no existen (y no pasa nada).

------------------------------------------------------------------------------
 TECLAS ESPECIALES (sin Super)
------------------------------------------------------------------------------

  Subir volumen................ sube 3 %
  Bajar volumen................ baja 3 %
  Mute......................... silenciar o restaurar
  Brillo arriba................ sube 5 %
  Brillo abajo................. baja 5 %
  Print / Impr Pant............ captura de pantalla (grim) en ~/Pictures

------------------------------------------------------------------------------
 SALIR Y CONSOLAS
------------------------------------------------------------------------------

  Super+Shift+e................ cerrar la sesion de dwl (vuelves al login)
  Ctrl+Alt+Backspace........... cerrar la sesion (atajo alternativo)
  Ctrl+Alt+F1 ... F12.......... cambiar de consola (tty)

  AVISO: no borres los Ctrl+Alt+Fx del config.h. Si dwl se congela son la
  unica manera de salir a una consola para hacer 'sudo reboot'.

------------------------------------------------------------------------------
 RATON SOBRE LAS VENTANAS
------------------------------------------------------------------------------

  Super+clic izquierdo......... mover la ventana (arrastrando)
  Super+clic central........... alternar ventana flotante
  Super+clic derecho........... redimensionar la ventana (arrastrando)
  Super+rueda.................. subir o bajar el volumen

------------------------------------------------------------------------------
 RATON SOBRE LA BARRA
------------------------------------------------------------------------------

  clic izquierdo en la hora... abre un calendario (cal -3) en foot
  clic central en el estado.... abre una terminal (foot)
  clic en los numeros de tag... solo funciona si dwlb corre en modo -ipc
                                (es decir, si dwl lleva el parche IPC)

  Para saber en que modo esta tu barra:

        pgrep -a dwlb

  dwlb -ipc.................... los clics en los tags funcionan
  dwlb -no-ipc................. no funcionan: usa Super+1 ... 9

  La barra la arranca dwl-session (la sesion que lanza greetd). Si arrancas dwl
  a mano desde una consola de texto, hazlo asi:

        dwl -s /usr/local/bin/dwl-status-runner

  (dwl a secas NO lleva barra: nadie la arrancaria.)

  Si la barra NO aparece al entrar en dwl, ejecuta DENTRO de dwl:

        dwl-bar-diag

  Es un diagnostico que revisa el PATH, XDG_RUNTIME_DIR, los binarios, las
  librerias, los procesos y ademas prueba dwlb en vivo 3 segundos en cada modo
  diciendo el error exacto que da. El motivo tambien queda en el registro de la
  sesion (el supervisor prueba solo, primero en un modo y luego en el otro):

        pgrep -a dwl; pgrep -a dwlb; pgrep -a dwlb-status
        tail -n 40 $XDG_RUNTIME_DIR/dwl-session-$(id -u).log

  Las lineas que empiezan por "dwl-status-runner:" son suyas; las de dwlb
  (por ejemplo "Compositor does not support all needed protocols") explican
  por que no arranco.

    Los clics del estado (calendario y terminal) funcionan en los dos modos,
    porque van incrustados en el texto que genera /usr/local/bin/dwlb-status.

------------------------------------------------------------------------------
 CAMBIAR ESTOS ATAJOS
------------------------------------------------------------------------------

  Paso 1....................... editar ~/dwl/config.h
  Paso 2....................... ejecutar dwl-rebuild (recompila e instala)
  Paso 3....................... Super+Shift+e para salir y volver a entrar

  OJO: si vuelves a ejecutar el instalador, el config.h se regenera a partir
  del config.def.h de dwl y se guarda una copia de tu version anterior
  (config.h.bak-<fecha>).

------------------------------------------------------------------------------
 ARCHIVOS PARA PERSONALIZAR
------------------------------------------------------------------------------

  ~/dwl/config.h................ atajos, colores, reglas y teclado de dwl
                                (aplicar con: dwl-rebuild)
  ~/.config/dwlb/config......... fuente y colores de la barra (sin recompilar)
  /usr/local/bin/dwlb-status.... que muestra la barra y sus clics
  /usr/local/bin/dwl-session.... variables y programas al iniciar la sesion
  /usr/local/bin/dwl-status-runner.. arranca la barra y el fondo
  /usr/local/bin/dwl-greeter.... opciones de la pantalla de login
  ~/.config/lf/lfrc............. navegador de archivos lf
  ~/.config/dwl/dwl-session.log. registro de la ultima sesion (dentro de
                                /run/user/<tu uid>/)

------------------------------------------------------------------------------
 REFERENCIAS
------------------------------------------------------------------------------

  dwl (compositor)............. https://codeberg.org/dwl/dwl
  dwlb (barra)................. https://github.com/kolunmi/dwlb
  lf (archivos)................ https://github.com/gokcehan/lf

  Manuales en tu terminal: man 1 dwlb | man 1 foot | man 1 lf

==============================================================================
ATAJOS_EOF
}

# ============================================================================
# FUNCION: herramientas dwl-rebuild / dwlb-rebuild
# ============================================================================
escribir_rebuilds() {
    sudo tee /usr/local/bin/dwl-rebuild >/dev/null <<'REBUILD_EOF'
#!/bin/sh
# Recompila e instala dwl con el config.h que tengas en ~/dwl.
set -e
cd "$HOME/dwl"
make clean
make
sudo make install
echo "Listo. Cierra sesion y vuelve a entrar para aplicar los cambios."
REBUILD_EOF
    sudo chmod +x /usr/local/bin/dwl-rebuild

    sudo tee /usr/local/bin/dwlb-rebuild >/dev/null <<'REBUILD2_EOF'
#!/bin/sh
# Recompila la barra dwlb (solo hace falta si editas ~/dwlb/config.h o
# actualizas el repositorio). Para cambiar fuente o colores basta con editar
# ~/.config/dwlb/config y reiniciar la sesion: no hay que compilar nada.
set -e
cd "$HOME/dwlb"
git pull --ff-only 2>/dev/null || echo "Aviso: no pude actualizar desde git; compilo lo que hay."
make clean
make
sudo make install
echo "Listo. Reinicia la sesion de dwl para ver la barra nueva."
REBUILD2_EOF
    sudo chmod +x /usr/local/bin/dwlb-rebuild
}

# ============================================================================
# FUNCION: greetd + tuigreet
# ============================================================================
configurar_greetd() {
    titulo "greetd + tuigreet (pantalla de inicio)"

    if [ -d /etc/sv/lightdm ] || command -v lightdm >/dev/null 2>&1; then
        info "Encontre lightdm instalado: lo quito (no se usa con greetd)."
        disable_svc lightdm
        PAQUETES_LIGHTDM=""
        for PKG in lightdm lightdm-gtk3-greeter; do
            if paquete_instalado "$PKG"; then
                PAQUETES_LIGHTDM="$PAQUETES_LIGHTDM $PKG"
            fi
        done
        if [ -n "$PAQUETES_LIGHTDM" ]; then
            sudo xbps-remove -R $PAQUETES_LIGHTDM || \
                warn "No se pudo desinstalar lightdm. Hazlo a mano: sudo xbps-remove -R$PAQUETES_LIGHTDM"
        fi
    fi

    instalar_paquetes "greetd" greetd tuigreet turnstile acpid || \
        warn "Algun paquete de greetd no se instalo; revisa la salida de arriba."

    info "Configurando turnstile (prepara XDG_RUNTIME_DIR mediante PAM)..."
    enable_svc turnstiled || warn "turnstiled no esta disponible; dwl-session usara su directorio de respaldo."

    PAM_FILE="/etc/pam.d/greetd"
    PAM_MODULO=""
    for M in /usr/lib/security/pam_turnstile.so /usr/lib64/security/pam_turnstile.so; do
        [ -f "$M" ] && PAM_MODULO="$M"
    done
    if [ -n "$PAM_MODULO" ]; then
        if [ ! -f "$PAM_FILE" ]; then
            warn "No existe $PAM_FILE (el paquete greetd deberia haberlo creado)."
        elif grep -q 'pam_turnstile.so' "$PAM_FILE"; then
            info "pam_turnstile ya estaba en $PAM_FILE."
        else
            backup_file "$PAM_FILE"
            printf '\n# Anadido por %s para turnstile (XDG_RUNTIME_DIR)\nsession\toptional\tpam_turnstile.so\n' "$NOMBRE_SCRIPT" | \
                sudo tee -a "$PAM_FILE" >/dev/null
            info "Anadido 'session optional pam_turnstile.so' a $PAM_FILE"
            warn "Si algo falla al iniciar sesion, restaura la copia .bak-* de $PAM_FILE."
        fi
    else
        warn "No encontre pam_turnstile.so: se omite la parte de PAM."
        warn "Sin el, XDG_RUNTIME_DIR puede quedar vacio (dwl-session tiene un plan B)."
    fi

    # --- Permisos para apagar/reiniciar desde la pantalla de login ----------
    POWER_SUDO="${POWER_SUDO_DEF:-}"
    buscar_bin() {
        # Busca un binario en el PATH y tambien en las rutas de root, que no
        # siempre estan en el PATH del usuario.
        K=""
        for POSIBLE in "$@"; do
            if command -v "$POSIBLE" >/dev/null 2>&1; then K=$(command -v "$POSIBLE"); break; fi
            for D in /usr/sbin /usr/bin /sbin /bin; do
                if [ -x "$D/$POSIBLE" ]; then K="$D/$POSIBLE"; break 2; fi
            done
        done
        printf '%s' "$K"
    }
    SHUTDOWN_BIN=$(buscar_bin shutdown poweroff)
    REBOOT_BIN=$(buscar_bin reboot)
    if [ -n "$SHUTDOWN_BIN" ] && [ -n "$REBOOT_BIN" ] && [ "$GREETER_USER" != "$(id -un)" ]; then
        pedir_si_no POWER_SUDO "Permitir que la pantalla de login apague/reinicie el equipo (regla en /etc/sudoers.d)?" "${POWER_SUDO_DEF:-si}"
        if [ "$POWER_SUDO" = "si" ]; then
            SUDOERS_FILE="/etc/sudoers.d/10-dwl-greeter-power"
            sudo mkdir -p /etc/sudoers.d
            printf '# Permite al greeter (usuario %s) apagar y reiniciar sin contrasena.\n# Creado por %s v%s\n%s ALL=(root) NOPASSWD: %s, %s\n' \
                "$GREETER_USER" "$NOMBRE_SCRIPT" "$VERSION" "$GREETER_USER" "$SHUTDOWN_BIN" "$REBOOT_BIN" | \
                sudo tee "$SUDOERS_FILE" >/dev/null
            sudo chmod 0440 "$SUDOERS_FILE"
            if command -v visudo >/dev/null 2>&1 && ! sudo visudo -cf "$SUDOERS_FILE" >/dev/null 2>&1; then
                error "La regla de sudoers no es valida: la borro para no romper sudo."
                sudo rm -f "$SUDOERS_FILE"
                POWER_SUDO="no"
            else
                info "Creado $SUDOERS_FILE (apagar/reiniciar desde tuigreet)."
            fi
        fi
    fi

    # --- Lanzador del greeter (evita comillas raras dentro del TOML) --------
    if [ "$POWER_SUDO" = "si" ]; then
        POWER_SHUTDOWN_CMD="sudo $SHUTDOWN_BIN"
        POWER_REBOOT_CMD="sudo $REBOOT_BIN"
    else
        POWER_SHUTDOWN_CMD="$SHUTDOWN_BIN"
        POWER_REBOOT_CMD="$REBOOT_BIN"
    fi
    OPCIONES_POWER=""
    [ -n "$POWER_SHUTDOWN_CMD" ] && OPCIONES_POWER="$OPCIONES_POWER --power-shutdown '$POWER_SHUTDOWN_CMD'"
    [ -n "$POWER_REBOOT_CMD" ]   && OPCIONES_POWER="$OPCIONES_POWER --power-reboot '$POWER_REBOOT_CMD'"

    sudo tee /usr/local/bin/dwl-greeter >/dev/null <<GREETER_EOF
#!/bin/sh
# Pantalla de inicio: greetd ejecuta este script, que lanza tuigreet.
# Editarlo no requiere nada mas que reiniciar el servicio:
#     sudo sv restart greetd
exec tuigreet \\
    --time --time-format '%H:%M  %d/%m/%Y' \\
    --user-menu --remember \\
    --greeting 'Bienvenido a dwl' \\
    --cmd /usr/local/bin/dwl-session$OPCIONES_POWER "\$@"
GREETER_EOF
    sudo chmod +x /usr/local/bin/dwl-greeter
    info "Instalado /usr/local/bin/dwl-greeter"

    # --- config.toml de greetd ---------------------------------------------
    sudo mkdir -p /etc/greetd
    backup_file /etc/greetd/config.toml
    sudo tee /etc/greetd/config.toml >/dev/null <<EOF
# Generado por $NOMBRE_SCRIPT v$VERSION
# Documentacion: man 1 greetd  |  man 1 tuigreet

[terminal]
# VT de la pantalla de inicio. Void trae agetty en las tty 1-6, por eso la 7.
# Cambialo a 1 si desactivas agetty-tty1.
vt = $GREETD_VT

[default_session]
# Se ejecuta un script en vez de la linea de tuigreet directamente, para que
# las comillas de las opciones no dependan de como las interprete greetd.
command = "/usr/local/bin/dwl-greeter"
user = "$GREETER_USER"
EOF
    info "Escrito /etc/greetd/config.toml (comando: /usr/local/bin/dwl-greeter)"

    if [ -L "/var/service/agetty-tty$GREETD_VT" ]; then
        warn "Habia un agetty en tty$GREETD_VT; lo quito para que greetd pueda usarla."
        disable_svc "agetty-tty$GREETD_VT"
    fi

    if [ ! -d /etc/sv/greetd ]; then
        error "El paquete greetd no creo /etc/sv/greetd; no habilito un servicio incompleto."
        return 1
    fi
    return 0
}

iniciar_greetd() {
    if [ ! -x /usr/local/bin/dwl-session ]; then
        error "No existe /usr/local/bin/dwl-session: no arranco greetd."
        return 1
    fi
    if [ ! -x /usr/local/bin/dwl-greeter ]; then
        error "No existe /usr/local/bin/dwl-greeter: no arranco greetd."
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
    return 0
}

# ============================================================================
# FUNCION: headers del kernel (necesarios para los modulos DKMS de NVIDIA)
# ============================================================================
instalar_headers_kernel() {
    for D in /lib/modules/*; do
        [ -d "$D" ] || continue
        KVER=$(basename "$D")
        SERIE=$(printf '%s' "$KVER" | sed -n 's/^\([0-9][0-9]*\.[0-9][0-9]*\).*/linux\1/p')
        [ -n "$SERIE" ] || continue
        if paquete_existe "$SERIE-headers"; then
            if ! paquete_instalado "$SERIE-headers"; then
                info "Instalando headers del kernel: $SERIE-headers"
                sudo xbps-install -Sy "$SERIE-headers" || warn "No pude instalar $SERIE-headers"
            fi
        else
            warn "No hay paquete $SERIE-headers para el kernel $KVER."
        fi
    done
}

# ============================================================================
# FUNCION: drivers de GPU
# ============================================================================
instalar_drivers_gpu() {
    titulo "Drivers de GPU"
    info "Instalando drivers para: $GPU_VENDORS"

    for VENDOR in $GPU_VENDORS; do
        case "$VENDOR" in
            nvidia)
                warn "GPU NVIDIA: en Wayland el driver propietario funciona mejor"
                warn "que antes, pero puede dar guerra (cursor invisible, apps que no arrancan)."
                instalar_paquetes "nvidia" nvidia nvidia-libs nvidia-dkms
                if paquete_existe "nvidia-libs-32bit"; then
                    instalar_paquetes "nvidia 32 bits" nvidia-libs-32bit
                fi
                sudo mkdir -p /etc/modprobe.d
                printf 'options nvidia-drm modeset=1\n' | sudo tee /etc/modprobe.d/nvidia-drm-modeset.conf >/dev/null
                info "nvidia-drm modeset=1 configurado (imprescindible en Wayland)."
                instalar_headers_kernel
                ;;
            amd)
                instalar_paquetes "amd" mesa-dri mesa mesa-vulkan-radeon linux-firmware-amd vulkan-loader
                ;;
            intel)
                instalar_paquetes "intel" mesa-dri mesa mesa-vulkan-intel intel-video-accel vulkan-loader
                ;;
            desconocida)
                warn "No identifique la GPU. Instalo los drivers libres (mesa) por si acaso."
                instalar_paquetes "mesa" mesa-dri mesa vulkan-loader || true
                ;;
        esac
    done

    if [ "$GPU_HIBRIDA_NVIDIA" -eq 1 ]; then
        info "Configurando uso de la GPU dedicada bajo demanda (PRIME)..."
        info "Creando /usr/local/bin/prime-run (Void no trae nvidia-prime)..."
        sudo tee /usr/local/bin/prime-run >/dev/null <<'PRIME_EOF'
#!/bin/sh
# prime-run: ejecuta una aplicacion con la GPU NVIDIA en equipos hibridos.
#     prime-run steam
#     prime-run mpv video.mkv
# Lo deja install-dwl.sh porque Void no empaqueta nvidia-prime.
export __NV_PRIME_RENDER_OFFLOAD=1
export __NV_PRIME_RENDER_OFFLOAD_PROVIDER=NVIDIA-G0
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export __VK_LAYER_NV_optimus=NVIDIA_only
exec "$@"
PRIME_EOF
        sudo chmod +x /usr/local/bin/prime-run

        if [ -n "$GPU_CARDS" ]; then
            warn "En hibridas, si dwl arranca en pantalla negra es que wlroots eligio"
            warn "la GPU equivocada. Fija las GPUs en /usr/local/bin/dwl-session con:"
            warn "  export WLR_DRM_DEVICES=$GPU_CARDS"
            warn "(los valores detectados quedan como comentario dentro del wrapper)."
        else
            warn "En hibridas, si dwl arranca en pantalla negra es que wlroots eligio"
            warn "la GPU equivocada: descomenta WLR_DRM_DEVICES dentro de"
            warn "/usr/local/bin/dwl-session (mira con: ls /dev/dri)."
        fi
    fi
    return 0
}

# ============================================================================
# FUNCION: gaming (Steam + drivers)
# ============================================================================
instalar_gaming() {
    titulo "Steam y gaming"

    # --- Espacio: Steam + drivers piden bastante mas que el modo basico -----
    FREE_GB_AHORA=$(libre_gb "$HOME")
    FREE_ROOT_AHORA=$(libre_gb /)
    if [ -n "$FREE_ROOT_AHORA" ] && [ -n "$FREE_GB_AHORA" ] && [ "$FREE_ROOT_AHORA" -lt "$FREE_GB_AHORA" ] 2>/dev/null; then
        FREE_GB_AHORA=$FREE_ROOT_AHORA
    fi
    if [ -n "$FREE_GB_AHORA" ] && [ "$FREE_GB_AHORA" -lt 25 ] 2>/dev/null; then
        warn "Modo COMPLETO con ${FREE_GB_AHORA}GB libres: Steam y los drivers"
        warn "suelen necesitar 25GB o mas. Si el disco se llena, la instalacion"
        warn "puede fallar a medias (y Steam sin sitio para los juegos no sirve)."
        pedir_si_no CONTINUAR_STEAM "Continuar con Steam y drivers de todas formas?" "si"
        if [ "$CONTINUAR_STEAM" != "si" ]; then
            warn "Se omiten Steam y los drivers de GPU."
            return 0
        fi
    fi

    # --- Multilib solo en x86_64 con glibc ---------------------------------
    if [ "$ARQ_BASE" != "x86_64" ] || [ "$LIBC" != "glibc" ]; then
        warn "Steam necesita multilib x86_64 con glibc, y tu sistema es:"
        warn "  arquitectura XBPS: $ARQ_XBPS"
        warn "Se omiten Steam y los repositorios multilib; el resto queda instalado."
        instalar_drivers_gpu
        return 0
    fi

    info "Habilitando repositorios nonfree y multilib..."
    if ! sudo xbps-install -Sy void-repo-nonfree void-repo-multilib void-repo-multilib-nonfree; then
        warn "No pude habilitar los repositorios nonfree/multilib."
        warn "Se omiten Steam y los drivers propietarios; el resto queda instalado."
        instalar_drivers_gpu
        return 0
    fi
    info "Resincronizando los indices de los repositorios nuevos..."
    sudo xbps-install -Sy || warn "La resincronizacion fallo; puede que steam no aparezca."

    instalar_headers_kernel
    instalar_drivers_gpu

    STEAM_VER=$(xbps-query -R -p version steam 2>/dev/null || true)
    if [ -z "$STEAM_VER" ]; then
        error "Despues de activar nonfree, 'steam' sigue sin aparecer."
        warn "Compruebalo a mano con: xbps-query -Rs steam"
        warn "Se omite la parte de Steam; el resto queda instalado."
        return 0
    fi
    info "Steam localizado en los repositorios: $STEAM_VER"

    # Librerias de 32 bits que suelen hacer falta (nombres comprobados en Void)
    LIBS32="mesa-dri-32bit libglvnd-32bit libdrm-32bit libva-32bit"
    case " $GPU_VENDORS " in
        *" nvidia "*) LIBS32="$LIBS32 nvidia-libs-32bit" ;;
    esac
    case " $GPU_VENDORS " in
        *" amd "*|*" desconocida "*) LIBS32="$LIBS32 mesa-vulkan-radeon-32bit" ;;
    esac
    case " $GPU_VENDORS " in
        *" intel "*) LIBS32="$LIBS32 mesa-vulkan-intel-32bit" ;;
    esac
    instalar_paquetes "librerias 32 bits" $LIBS32 || \
        warn "Alguna libreria de 32 bits fallo; puedes repetirlo luego."

    if ! instalar_paquetes "steam" steam; then
        error "Steam no se pudo instalar. Comprueba con: xbps-query -Rs steam"
        warn "Se omite el resto de la parte gaming."
        return 0
    fi

    info "Instalando gamemode, gamescope y mono (opcionales)..."
    instalar_paquetes "gaming extra" gamemode gamescope mono || \
        warn "Alguno de los extras no se instalo (no afecta a Steam)."

    info "Subiendo el limite de ficheros abiertos (lo pide Proton)..."
    sudo mkdir -p /etc/security/limits.d
    printf '* soft nofile 524288\n* hard nofile 524288\n' | \
        sudo tee /etc/security/limits.d/00-steam-proton.conf >/dev/null

    if getent group video >/dev/null 2>&1; then
        sudo usermod -aG video "$REAL_USER" 2>/dev/null && \
            info "Usuario $REAL_USER anadido al grupo 'video' (lo pide Steam)."
    fi

    info "Steam corre sobre Xwayland: dwl se compilo con Xwayland ($DWL_XWAYLAND)."
    if [ "$DWL_XWAYLAND" != "si" ]; then
        warn "OJO: dwl se compilo SIN Xwayland, asi que Steam NO abrira."
        warn "Instala los headers y recompila:"
        warn "  sudo xbps-install -S xcb-util-wm-devel libxcb-devel"
        warn "  cd ~/dwl && dwl-rebuild   (tras volver a ejecutar el instalador)"
    fi
    if [ "$GPU_HIBRIDA_NVIDIA" -eq 1 ]; then
        warn "Equipo HIBRIDO Intel/AMD + NVIDIA: para usar la NVIDIA lanza el juego con:"
        warn "  prime-run steam"
        warn "o pon en las opciones de lanzamiento del juego:  prime-run %command%"
    fi
    info "gamescope es un mini-compositor: lanza juegos con 'gamescope -- %command%'"
    info "desde las propiedades de lanzamiento en Steam."

    warn "REINICIA: los grupos nuevos (video) y el driver de GPU solo aplican tras reiniciar."
    warn "Abre Steam por primera vez desde foot ('steam') para que se actualice."
    return 0
}

# ============================================================================
# FUNCION: instalacion base
# ============================================================================
instalar_base() {
    titulo "Instalacion base"

    # ---------------------------------------------------------------- kernel
    info "Kernel en uso: $(uname -r)"
    # OJO: en xbps-query el patron de --regex se compara con "nombre-version"
    # (linux6.18-6.18.54_1), asi que '^linux6\.18$' no encajaria nunca y la
    # busqueda saldria vacia. Se busca por subcadena y se filtra aqui; el
    # prefijo "[*] "/"[-] " (instalado o no) se quita de forma tolerante.
    KERNEL_NUEVO=$(xbps-query -R -s linux 2>/dev/null | \
        sed 's/^\[[^]]*\][[:space:]]*//' | \
        awk '{print $1}' | \
        grep -E '^linux[0-9][0-9]*\.[0-9][0-9]*-[0-9]' | \
        sed 's/-[0-9].*$//' | \
        sed 's/^linux//' | \
        sort -t. -k1,1n -k2,2n -u | tail -n1)
    [ -n "$KERNEL_NUEVO" ] && KERNEL_NUEVO="linux$KERNEL_NUEVO"
    KERNEL_ACTUAL_SERIE="linux$(uname -r | sed -n 's/^\([0-9][0-9]*\.[0-9][0-9]*\).*/\1/p')"

    if [ -z "$KERNEL_NUEVO" ]; then
        warn "No encontre paquetes de kernel linuxX.Y en XBPS; se conserva el actual."
    elif [ "$KERNEL_NUEVO" = "$KERNEL_ACTUAL_SERIE" ]; then
        info "Ya estas usando la serie de kernel mas reciente de los repositorios ($KERNEL_NUEVO)."
    else
        info "Kernel mas reciente disponible: $KERNEL_NUEVO (en uso: $KERNEL_ACTUAL_SERIE)"
        printf "  1) Conservar el kernel actual (%s) [predeterminado]\n" "$KERNEL_ACTUAL_SERIE"
        printf "  2) Instalar %s junto al actual (con sus headers)\n" "$KERNEL_NUEVO"
        pedir OPCION_KERNEL "Opcion [1-2]" "${KERNEL_OPCION:-1}"
        case "$OPCION_KERNEL" in
            1) info "Se conserva el kernel actual." ;;
            2)
                info "Instalando $KERNEL_NUEVO y $KERNEL_NUEVO-headers..."
                if instalar_paquetes "kernel" "$KERNEL_NUEVO" "$KERNEL_NUEVO-headers"; then
                    KERNEL_ELEGIDO="$KERNEL_NUEVO"
                    KERNEL_ELEGIDO_HEADERS="$KERNEL_NUEVO-headers"
                    warn "Despues de reiniciar, elige ese kernel en el gestor de arranque."
                else
                    warn "No se pudo instalar $KERNEL_NUEVO; se conserva el kernel actual."
                fi
                ;;
            *) warn "Opcion no valida: se conserva el kernel actual." ;;
        esac
    fi

    # ----------------------------------------------------------- 1. paquetes
    instalar_paquetes "dependencias de compilacion" \
        base-devel pkg-config file patch \
        libinput libinput-devel \
        wayland wayland-devel wayland-protocols \
        libxkbcommon libxkbcommon-devel \
        wlroots wlroots-devel \
        libseat libseat-devel seatd \
        xorg-server-xwayland \
        libxcb libxcb-devel xcb-util xcb-util-wm xcb-util-wm-devel \
        mesa mesa-dri libdrm libdrm-devel \
        pixman pixman-devel fcft fcft-devel tllist \
        pango-devel cairo-devel fontconfig fontconfig-devel \
        || warn "Alguna dependencia no se instalo; si dwl no compila, revisa la lista de arriba."

    instalar_paquetes "aplicaciones del escritorio" \
        foot wmenu swaybg swaylock swayidle \
        grim slurp wl-clipboard brightnessctl wlr-randr \
        pipewire wireplumber alsa-pipewire \
        dbus fastfetch btop nano lf \
        mpv zathura zathura-pdf-poppler imv \
        xdg-utils xdg-desktop-portal xdg-desktop-portal-wlr xdg-desktop-portal-gtk \
        polkit firefox chrony curl procps-ng pciutils \
        dejavu-fonts-ttf nerd-fonts noto-fonts-emoji \
        || warn "Alguna aplicacion no se instalo; la sesion funcionara igual."

    # Verificacion de lo imprescindible para compilar
    FALTAN=""
    for C in cc make pkg-config git; do
        command -v "$C" >/dev/null 2>&1 || FALTAN="$FALTAN $C"
    done
    if [ -n "$FALTAN" ]; then
        error "Faltan herramientas basicas:$FALTAN"
        error "Instalalas con: sudo xbps-install -S base-devel pkg-config git"
        return 1
    fi
    if ! pkg-config --exists wlroots 2>/dev/null; then
        warn "pkg-config no encuentra wlroots (ni wlroots-0.XX). dwl no compilara."
        warn "Revisa: sudo xbps-install -S wlroots-devel"
    fi

    # ------------------------------------------------------ 2. servicios/grupos
    info "Habilitando servicios (dbus, chronyd, seatd, acpid)..."
    enable_svc dbus || warn "No pude habilitar dbus; dwl-session usa dbus-run-session igualmente."
    enable_svc chronyd || warn "No pude habilitar chronyd; la hora seguira con el reloj configurado."
    enable_svc acpid || warn "acpid no disponible (util para la tapa y los botones del portatil)."

    titulo "Grupos del usuario $REAL_USER"
    if getent group _seatd >/dev/null 2>&1; then
        SEAT_GROUP="_seatd"
    else
        error "No existe el grupo _seatd que crea el paquete seatd de Void."
        warn "Reinstala/verifica seatd con: sudo xbps-install -f seatd"
        SEAT_GROUP=""
    fi

    for GRUPO in "$SEAT_GROUP" video audio; do
        [ -n "$GRUPO" ] || continue
        if ! getent group "$GRUPO" >/dev/null 2>&1; then
            warn "No existe el grupo '$GRUPO'; no lo agrego."
            continue
        fi
        if sudo usermod -aG "$GRUPO" "$REAL_USER"; then
            info "Usuario $REAL_USER agregado al grupo '$GRUPO'."
        else
            warn "No pude anadir a $REAL_USER al grupo '$GRUPO'."
            warn "Hazlo a mano: sudo usermod -aG $GRUPO $REAL_USER"
        fi
    done

    case "$SEAT_GROUP" in
        '') ;;
        *) if groups "$REAL_USER" 2>/dev/null | tr ' ' '\n' | grep -qx "$SEAT_GROUP"; then
               info "Confirmado: $REAL_USER esta en '$SEAT_GROUP'."
           else
               warn "No pude confirmar que $REAL_USER este en '$SEAT_GROUP'."
               warn "Si dwl no arranca: sudo usermod -aG $SEAT_GROUP $REAL_USER"
           fi ;;
    esac
    enable_svc seatd || return 1
    warn "Los grupos nuevos solo se aplican despues de cerrar sesion y volver a entrar (o reiniciar)."

    # ------------------------------------------------------ 3. hardware/gpus
    detectar_gpus || true
    detectar_hardware

    # ------------------------------------------------------ 4. zona horaria
    titulo "Zona horaria"
    printf "Escribe tu pais (ej: Colombia, Mexico, Argentina, Espana).\n"
    pedir PAIS_INPUT "Pais (vacio = Colombia)" "${PAIS:-Colombia}"

    PAIS_NORM=$(printf '%s' "$PAIS_INPUT" | tr '[:upper:]' '[:lower:]' | \
        sed 's/á/a/g; s/é/e/g; s/í/i/g; s/ó/o/g; s/ú/u/g; s/ñ/n/g')

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
            warn "La zona horaria indicada contiene caracteres no permitidos."
            TZ_INPUT=""
            ;;
    esac

    if [ -n "$TZ_INPUT" ] && [ -f "/usr/share/zoneinfo/$TZ_INPUT" ]; then
        info "Pais: $PAIS_INPUT -> zona horaria: $TZ_INPUT"
        sudo ln -sf "/usr/share/zoneinfo/$TZ_INPUT" /etc/localtime || warn "No pude enlazar /etc/localtime."
        sudo hwclock --systohc 2>/dev/null || warn "No pude sincronizar el reloj de hardware (se ignora)."
        if grep -qE '^[#[:space:]]*TIMEZONE=' /etc/rc.conf 2>/dev/null; then
            sudo sed -i "s|^[#[:space:]]*TIMEZONE=.*|TIMEZONE=\"$TZ_INPUT\"|" /etc/rc.conf || warn "No pude actualizar TIMEZONE en /etc/rc.conf."
        else
            printf 'TIMEZONE="%s"\n' "$TZ_INPUT" | sudo tee -a /etc/rc.conf >/dev/null || warn "No pude escribir TIMEZONE en /etc/rc.conf."
        fi
    else
        warn "No reconoci '$PAIS_INPUT' como pais. Se deja la zona horaria sin cambios."
    fi

    # ------------------------------------------------------ 5. teclado
    titulo "Teclado"
    while :; do
        printf "Distribucion de teclado:\n"
        printf "  1) Ingles (us)\n"
        printf "  2) Espanol de Espana (es)\n"
        printf "  3) Latinoamericano (latam)\n"
        pedir OPCION_TECLADO "Opcion [1-3]" "$KB_OPCION"
        case "$OPCION_TECLADO" in
            1) KB_XKB="us";    KB_CONSOLA="us";        break ;;
            2) KB_XKB="es";    KB_CONSOLA="es";        break ;;
            3) KB_XKB="latam"; KB_CONSOLA="la-latin1"; break ;;
            *) warn "Opcion no valida, elige 1, 2 o 3." ;;
        esac
    done
    info "Teclado: $KB_XKB (consola: $KB_CONSOLA)"

    if [ -n "$KB_CONSOLA" ]; then
        if grep -qE '^[#[:space:]]*KEYMAP=' /etc/rc.conf 2>/dev/null; then
            sudo sed -i "s|^[#[:space:]]*KEYMAP=.*|KEYMAP=\"$KB_CONSOLA\"|" /etc/rc.conf || warn "No pude actualizar KEYMAP en /etc/rc.conf."
        else
            printf 'KEYMAP="%s"\n' "$KB_CONSOLA" | sudo tee -a /etc/rc.conf >/dev/null || warn "No pude escribir KEYMAP en /etc/rc.conf."
        fi
        command -v loadkeys >/dev/null 2>&1 && sudo loadkeys "$KB_CONSOLA" 2>/dev/null || true
    fi

    # ------------------------------------------------------ 6. dwl
    compilar_dwl || return 1

    # ------------------------------------------------------ 7. dwlb (barra)
    if compilar_dwlb; then
        BARRA_ELEGIDA="dwlb"
        configurar_dwlb
    else
        error "dwlb no compilo: la sesion arrancara sin barra."
        warn "Revisalo con: cd ~/dwlb && make    (necesita pixman-devel y fcft-devel)"
        BARRA_ELEGIDA=""
    fi

    if [ "$BARRA_ELEGIDA" = "dwlb" ] &&        { printf '%s' "$DWL_PARCHES_USADOS" | grep -q ipc ||          [ -f "$HOME/dwl/protocols/dwl-ipc-unstable-v2.xml" ] ||          [ -f "$HOME/dwl/protocols/dwl-ipc-unstable-v1.xml" ]; }; then
        DWLB_MODO="-ipc"
        info "dwl lleva el parche IPC: la barra usara -ipc (tags clicables)."
    else
        DWLB_MODO="-no-ipc"
        info "La barra usara -no-ipc (el estado llega por stdin desde dwl)."
    fi

    # Ruta absoluta de dwl: si el PATH de la sesion no lo trae, no arrancaria.
    DWL_RUTA=$(command -v dwl 2>/dev/null || true)
    if [ -z "$DWL_RUTA" ] || [ ! -x "$DWL_RUTA" ]; then
        DWL_RUTA="/usr/local/bin/dwl"
    fi
    BARRA_CMD="$DWL_RUTA -s /usr/local/bin/dwl-status-runner"

    # ------------------------------------------------------ 8. wallpaper y lf
    descargar_wallpaper
    configurar_lf

    # ------------------------------------------------------ 9. supervisor + sesion
    escribir_supervisor
    escribir_diagnostico
    # Tags para la barra cuando dwl NO lleva el parche IPC (sin ipc dwlb no
    # sabe en que tag estas: los muestra como etiquetas fijas, sin estado).
    DWLB_TAGS_DEF="-tags 9"
    i=1
    while [ "$i" -le 9 ]; do
        DWLB_TAGS_DEF="$DWLB_TAGS_DEF $i"
        i=$((i + 1))
    done
    sustituir /usr/local/bin/dwl-status-runner "@TAGS_DEF@" "$DWLB_TAGS_DEF"
    escribir_sesion
    sustituir /usr/local/bin/dwl-session "@BARRA@" "$BARRA_ELEGIDA"
    sustituir /usr/local/bin/dwl-session "@MODO@" "$DWLB_MODO"
    sustituir /usr/local/bin/dwl-session "@WALLPAPER@" "$WALLPAPER_PATH"
    sustituir /usr/local/bin/dwl-session "@BARRA_CMD@" "$BARRA_CMD"

    EXTRA_SESION="$EXTRA_ENV"
    if printf '%s' "$GPU_VENDORS" | grep -q nvidia; then
        case "$EXTRA_SESION" in
            *WLR_NO_HARDWARE_CURSORS*) ;;
            *) EXTRA_SESION="$EXTRA_SESION
export WLR_NO_HARDWARE_CURSORS=1" ;;
        esac
    fi
    if [ "$GPU_HIBRIDA" -eq 1 ] && [ -n "$GPU_CARDS" ]; then
        EXTRA_SESION="$EXTRA_SESION
# HIBRIDA: si dwl arranca en pantalla negra, descomenta la linea siguiente:
# export WLR_DRM_DEVICES=$GPU_CARDS"
    fi
    sustituir /usr/local/bin/dwl-session "@EXTRA_ENV@" "$EXTRA_SESION"

    if command -v sh >/dev/null 2>&1; then
        sh -n /usr/local/bin/dwl-session 2>/dev/null || warn "dwl-session tiene un error de sintaxis."
        sh -n /usr/local/bin/dwl-status-runner 2>/dev/null || warn "dwl-status-runner tiene un error de sintaxis."
    fi

    escribir_rebuilds

    # ------------------------------------------------------ 10. sesion Wayland
    info "Registrando la sesion dwl en /usr/share/wayland-sessions..."
    sudo mkdir -p /usr/share/wayland-sessions
    sudo tee /usr/share/wayland-sessions/dwl.desktop >/dev/null <<'DESKTOP_EOF'
[Desktop Entry]
Name=dwl
Comment=dwm para Wayland (dwl + dwlb)
Exec=/usr/local/bin/dwl-session
Type=Application
DesktopNames=dwl
DESKTOP_EOF

    # ------------------------------------------------------ 11. chuleta
    escribir_atajos

    info "Instalacion base completada."
    return 0
}

# ============================================================================
# MODO UTILIDAD: regenerar solo config.h
# ============================================================================
if [ -n "$DWL_SOLO_CONFIG_H" ]; then
    if [ -n "$DWL_TAG_FORZADO" ] && [ -d "$DWL_SOLO_CONFIG_H/.git" ]; then
        if (cd "$DWL_SOLO_CONFIG_H" && git checkout -f "$DWL_TAG_FORZADO" >/dev/null 2>&1); then
            DWL_TAG_USADO="$DWL_TAG_FORZADO"
        fi
    fi
    if [ -z "$DWL_TAG_USADO" ] && [ -d "$DWL_SOLO_CONFIG_H/.git" ]; then
        DWL_TAG_USADO=$(cd "$DWL_SOLO_CONFIG_H" && git describe --tags 2>/dev/null || echo "local")
    fi
    DWL_TAG_USADO="${DWL_TAG_USADO:-local}"
    if generar_config_h "$DWL_SOLO_CONFIG_H"; then
        info "Listo: $DWL_SOLO_CONFIG_H/config.h"
        exit 0
    fi
    exit 1
fi

# ============================================================================
# EJECUCION
# ============================================================================
instalar_base
ESTADO_BASE=$?

if [ "$ESTADO_BASE" -ne 0 ]; then
    error "La instalacion base fallo. NO se toca greetd (asi puedes seguir usando"
    error "el gestor de inicio que ya tenias). Corrige el error y vuelve a ejecutar."
    exit 1
fi

configurar_greetd || warn "Hubo problemas con greetd: revisalo antes de reiniciar."

if [ "$OPCION" = "2" ]; then
    instalar_gaming
fi

# LO ULTIMO: greetd se levanta solo cuando ya no queda nada pendiente.
iniciar_greetd || warn "greetd no arranco. Arrancalo a mano: sudo sv start greetd"

echo
info "=========================================="
info " Instalacion de dwl completada"
info "=========================================="
info "En la pantalla de tuigreet escribe tu usuario y contrasena."
info "  F2  = cambiar el comando de la sesion"
info "  F3  = elegir otra sesion (lee /usr/share/wayland-sessions)"
info "  F12 = apagar / reiniciar"
info ""
info "Resumen de lo instalado:"
info "  Compositor:  dwl $DWL_TAG_USADO   (Xwayland: $DWL_XWAYLAND)"
info "  Parches:     ${DWL_PARCHES_USADOS:-ninguno}"
info "  Barra:       ${BARRA_ELEGIDA:-ninguna}  (modo ${DWLB_MODO})"
info "  Teclado:     $KB_XKB"
info "  Kernel:      $(uname -r)${KERNEL_ELEGIDO:+ (ademas: $KERNEL_ELEGIDO con $KERNEL_ELEGIDO_HEADERS)}"
info "  GPU(s):      $GPU_VENDORS"
info ""
info "Archivos clave para personalizar tu entorno:"
info "  ~/dwl/config.h                Atajos, colores y reglas (dwl-rebuild)"
info "  ~/Atajos.txt                  Chuleta de atajos: nano ~/Atajos.txt"
info "  ~/.config/dwlb/config         Fuente y colores de la barra (sin recompilar)"
info "  /usr/local/bin/dwlb-status    Bloques de estado (CPU, RAM, bateria...)"
info "  /usr/local/bin/dwl-session    Variables y programas al iniciar sesion"
info "  /usr/local/bin/dwl-greeter    Opciones de la pantalla de login"
info "  /etc/greetd/config.toml       greetd"
info "  /etc/pam.d/greetd             Donde se activo pam_turnstile"
info "  /usr/local/bin/dwl-bar-diag   Si la barra no aparece: ejecutalo dentro"
info "                                de dwl (Super+Enter) y dice por que"
info ""
info "Si al entrar en dwl no ves la barra, el motivo queda en el registro"
info "de la sesion (el supervisor prueba solo -ipc y -no-ipc y lo anota):"
info "  pgrep -a dwl; pgrep -a dwlb; pgrep -a dwlb-status"
info "  tail -n 40 \$XDG_RUNTIME_DIR/dwl-session-\$(id -u).log"
info ""
info "Para aplicar cambios tras editar config.h: dwl-rebuild"
info ""
warn "IMPORTANTE: reinicia antes de usar dwl. Los grupos nuevos"
warn "('${SEAT_GROUP:-_seatd}', video y audio) solo se aplican al volver a"
warn "iniciar sesion, y sin ellos dwl no puede abrir la GPU, los dispositivos"
warn "de entrada ni el sonido. Aunque ya veas tuigreet en la tty$GREETD_VT,"
warn "NO entres todavia: usa 'sudo reboot'."

#!/bin/sh
# install-dwl.sh
# Instalador de dwl (dwm para Wayland) usando dwl-bar como barra externa
# (sin parchear el codigo fuente de dwl), con dos modos:
#   1) Basico: dwl + dwl-bar, foot, wmenu, slstatus, swaybg, pipewire
#   2) Completo: basico + Steam, drivers de GPU y utilidades de gaming
#
# SOLO PARA VOID LINUX.
# Minimo 20GB libres para evitar errores de almacenamiento.
# RECUERDA INSTALAR GIT ANTES DE EJECUTAR ESTE SCRIPT:
#   sudo xbps-install -S git
#
# NOTA: a diferencia de una version anterior de este script, aqui NO se
# aplica ningun parche sobre dwl.c. dwl-bar es un programa aparte que se
# arranca con la opcion -s de dwl ("dwl -s dwl-bar"), igual que somebar
# o dwlb. Esto evita el problema de que un parche quede desactualizado
# contra una version mas nueva de dwl (hunks que fallan al aplicar).
#
# NOTA: este script asume que ya tienes LightDM instalado y habilitado
# (por ejemplo, si ya corriste install-dwm.sh antes). Si no lo tienes,
# el script lo instala y habilita igual.
#
# Uso: sh install-dwl.sh   (como usuario normal, NO como root)
# Revisar sintaxis sin ejecutar: sh -n install-dwl.sh

set -e

# ----------------------------------------------------------------
# Colores para mensajes
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
        cat > "$1.nuevo"
    else
        cat > "$1"
    fi
}

fix_owner() {
    if [ "$(stat -c %U .)" != "$(id -un)" ] || [ -n "$(find . -maxdepth 2 ! -user "$(id -un)" -print -quit)" ]; then
        info "Devolviendo la propiedad de $(pwd) a $(id -un)..."
        sudo chown -R "$(id -un):$(id -gn)" .
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

DISTRO_ID="unknown"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO_ID="${ID:-unknown}"
fi
info "Distro detectada: $DISTRO_ID"

if [ "$DISTRO_ID" != "void" ]; then
    warn "Este script fue pensado para Void Linux (xbps)."
    printf "Continuar de todas formas? [y/N] "
    read -r CONTINUAR
    case "$CONTINUAR" in
        y|Y) ;;
        *) error "Cancelado por el usuario."; exit 1 ;;
    esac
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
SLSTATUS_REPO="https://git.suckless.org/slstatus"
WALLPAPER_DIR="$HOME/Pictures"
WALLPAPER_PATH="$WALLPAPER_DIR/wallpaper.jpg"
WALLPAPER_URL="https://wallpapercave.com/download/empty-error-wallpapers-wp8330753"

# ==================================================================
# MENU DE SELECCION
# ==================================================================
echo "=========================================="
echo "    Instalador dwl (Void Linux) v0.3.0"
echo "=========================================="
echo "1) Instalacion BASICA (dwl+dwl-bar, foot, wmenu, slstatus, swaybg)"
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
# FUNCION: instalacion basica de dwl
# ==================================================================
instalar_base() {

    # --------------------------------------------------------
    # 1. Paquetes necesarios y dependencias
    # --------------------------------------------------------
    info "Instalando dependencias de dwl, dwl-bar y del entorno Wayland..."
    sudo xbps-install -Sy \
        base-devel file pkg-config \
        libinput libinput-devel \
        wayland wayland-devel wayland-protocols \
        libxkbcommon libxkbcommon-devel \
        wlroots wlroots-devel \
        libseat libseat-devel seatd \
        xorg-server-xwayland xorg-server \
        mesa-dri libdrm-devel \
        pango-devel cairo-devel \
        foot wmenu void-repo-multilib \
        pipewire wireplumber alsa-pipewire \
        swaybg swaylock grim slurp wl-clipboard \
        brightnessctl curl \
        nerd-fonts lf mpv zathura zathura-pdf-poppler xdg-utils imv \
        lightdm lightdm-gtk3-greeter \
        chrony firefox btop cowsay dbus

    info "Habilitando servicios (dbus, chronyd, seatd)..."
    [ -L /var/service/dbus ]    || sudo ln -s /etc/sv/dbus /var/service/
    [ -L /var/service/chronyd ] || sudo ln -s /etc/sv/chronyd /var/service/

    # --------------------------------------------------------
    # Obtener el usuario real (no root si se ejecutó con sudo)
    # --------------------------------------------------------
    REAL_USER="${SUDO_USER:-$USER}"

    # --------------------------------------------------------
    # Crear e integrar grupo seat de forma automática
    # --------------------------------------------------------
    info "Configurando el grupo 'seat' para el usuario $REAL_USER..."

    sudo groupadd -f seat
    sudo usermod -aG seat "$REAL_USER"

    if groups "$REAL_USER" | grep -q '\bseat\b'; then
        info "Usuario $REAL_USER agregado exitosamente al grupo 'seat'."
    else
        warn "No se pudo agregar a $REAL_USER al grupo 'seat'. Inténtalo manualmente con: sudo usermod -aG seat $REAL_USER"
    fi

    info "Habilitando servicio seatd..."
    [ -L /var/service/seatd ]   || sudo ln -s /etc/sv/seatd /var/service/

    warn "El grupo 'seat' solo se aplica despues de cerrar sesion y volver a entrar (o reiniciar)."

    # --------------------------------------------------------
    # 2. Zona horaria y reloj
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

    if [ -n "$TZ_INPUT" ] && [ -f "/usr/share/zoneinfo/$TZ_INPUT" ]; then
        info "Pais: $PAIS_INPUT -> Zona horaria: $TZ_INPUT"
        sudo ln -sf "/usr/share/zoneinfo/$TZ_INPUT" /etc/localtime
        sudo hwclock --systohc || warn "No se pudo sincronizar el reloj de hardware (se ignora)."
        if grep -qE '^[#[:space:]]*TIMEZONE=' /etc/rc.conf 2>/dev/null; then
            sudo sed -i "s|^[#[:space:]]*TIMEZONE=.*|TIMEZONE=\"$TZ_INPUT\"|" /etc/rc.conf
        else
            printf 'TIMEZONE="%s"\n' "$TZ_INPUT" | sudo tee -a /etc/rc.conf >/dev/null
        fi
    else
        warn "No reconoci '$PAIS_INPUT' como pais. Se deja la zona horaria sin cambios."
    fi

    # --------------------------------------------------------
    # 3. Teclado (layout que usara la consola)
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
            sudo sed -i "s|^[#[:space:]]*KEYMAP=.*|KEYMAP=\"$KB_CONSOLA\"|" /etc/rc.conf
        else
            printf 'KEYMAP="%s"\n' "$KB_CONSOLA" | sudo tee -a /etc/rc.conf >/dev/null
        fi
        command -v loadkeys >/dev/null 2>&1 && sudo loadkeys "$KB_CONSOLA" 2>/dev/null || true
    fi

    # --------------------------------------------------------
    # 4. Clonar y compilar dwl (SIN PARCHES, version vanilla)
    # --------------------------------------------------------
    cd "$HOME"
    if [ ! -d dwl ]; then
        info "Clonando dwl..."
        git clone "$DWL_REPO"
    fi
    cd dwl
    fix_owner

    if [ -f config.h ]; then
        warn "config.h ya existe: se conserva tu version, no se modifica."
    else
        info "Copiando config.def.h -> config.h (configuracion por defecto de dwl, sin parches)..."
        cp config.def.h config.h
        warn "El layout de teclado que elegiste ('$KB_XKB') NO se escribe automaticamente"
        warn "en config.h para evitar romper la compilacion con una edicion a ciegas."
        warn "Para activarlo, edita ~/dwl/config.h, busca 'xkb_rules' y agrega, por ejemplo:"
        warn '  .layout = "'"$KB_XKB"'",'
        warn "y luego ejecuta: dwl-rebuild"
    fi

    info "Compilando dwl (version vanilla, sin parches; como usuario, solo la instalacion usa sudo)..."
    make clean 2>/dev/null || true
    make
    sudo make install

    # --------------------------------------------------------
    # 5. dwl-bar (barra externa, se arranca con 'dwl -s dwl-bar')
    # --------------------------------------------------------
    if command -v dwl-bar >/dev/null 2>&1; then
        info "dwl-bar ya esta instalado; se reutiliza."
    else
        info "Clonando y compilando dwl-bar..."
        cd "$HOME"
        [ -d dwl-bar ] || git clone "$DWLBAR_REPO"
        cd dwl-bar
        fix_owner
        make clean 2>/dev/null || true
        make
        sudo make install
    fi

    # --------------------------------------------------------
    # 6. slstatus (utilidad de estado independiente; opcional)
    # --------------------------------------------------------
    if [ -x "$HOME/slstatus/slstatus" ] || command -v slstatus >/dev/null 2>&1; then
        info "slstatus ya esta compilado (de una instalacion anterior); se reutiliza."
    else
        info "Compilando slstatus (utilidad de estado, uso opcional/independiente)..."
        cd "$HOME"
        [ -d slstatus ] || git clone "$SLSTATUS_REPO"
        cd slstatus
        fix_owner

        WIFI_IFACE=$(ip route | grep default | awk '{print $5}' | head -n1 || true)
        [ -z "$WIFI_IFACE" ] && WIFI_IFACE="eth0"
        BAT_NAME=$(ls /sys/class/power_supply/ 2>/dev/null | grep -E '^BAT' | head -n1 || true)
        [ -z "$BAT_NAME" ] && BAT_NAME="n/a"

        {
            cat <<'SLEOF'
/* See LICENSE file for copyright and license details. */
const unsigned int interval = 1000;
static const char unknown_str[] = "n/a";
#define MAXLEN 2048

static const struct arg args[] = {
SLEOF
            if [ -d "/sys/class/net/$WIFI_IFACE/wireless" ]; then
                printf '        { wifi_essid,   "  %%s  ",      "%s" },\n' "$WIFI_IFACE"
            fi
            if [ "$BAT_NAME" != "n/a" ]; then
                printf '        { battery_perc, "BAT: %%s%%%%  ", "%s" },\n' "$BAT_NAME"
            fi
            cat <<'SLEOF'
        { datetime,     "%s",           "%Y-%m-%d %I:%M %p" },
};
SLEOF
        } | write_config config.h

        make clean
        make
        sudo make install
    fi

    warn "dwl-bar muestra tags/titulo/layout por si solo. Para reloj/bateria/etc dentro"
    warn "de la barra hace falta 'someblocks' (github.com/SlashandDash/someblocks o"
    warn "similar) alimentando a dwl-bar; no se instala en este script. Avisame si lo quieres agregar."

    # --------------------------------------------------------
    # 7. lf (navegador de archivos)
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
    # 8. Wallpaper
    # --------------------------------------------------------
    mkdir -p "$WALLPAPER_DIR"
    if [ ! -f "$WALLPAPER_PATH" ]; then
        info "Descargando wallpaper..."
        wget -q -U "Mozilla/5.0" --referer="https://wallpapercave.com/" \
            -O "$WALLPAPER_PATH" "$WALLPAPER_URL" || true
        if ! file "$WALLPAPER_PATH" | grep -qi image; then
            warn "No se pudo descargar un wallpaper valido; se omite."
            rm -f "$WALLPAPER_PATH"
        fi
    fi

    # --------------------------------------------------------
    # 9. Wrapper de sesion (lo usa lightdm)
    # --------------------------------------------------------
    info "Creando script wrapper para la sesion..."
    sudo tee /usr/local/bin/dwl-session >/dev/null <<EOF
#!/bin/sh
export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=dwl
export MOZ_ENABLE_WAYLAND=1
export QT_QPA_PLATFORM=wayland
export GDK_BACKEND=wayland,x11

# Audio (PipeWire). Void no usa systemd, se arrancan a mano.
pipewire &
wireplumber &
pipewire-pulse &

# Fondo de pantalla
[ -f "$WALLPAPER_PATH" ] && swaybg -i "$WALLPAPER_PATH" -m fill &

# dwl arranca dwl-bar como su proceso de arranque (-s), sin parches.
dwl -s dwl-bar
EOF
    sudo chmod +x /usr/local/bin/dwl-session

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
    # 10. Registrar sesion Wayland en lightdm
    # --------------------------------------------------------
    info "Instalando y habilitando lightdm (si no estaba)..."
    sudo xbps-install -Sy lightdm lightdm-gtk3-greeter

    info "Registrando la sesion dwl (Wayland) en lightdm..."
    sudo mkdir -p /usr/share/wayland-sessions
    sudo tee /usr/share/wayland-sessions/dwl.desktop >/dev/null <<EOF
[Desktop Entry]
Name=dwl
Comment=dwm para Wayland (con dwl-bar)
Exec=/usr/local/bin/dwl-session
Type=Application
EOF

    info "Instalacion basica de dwl completada."
}

# ==================================================================
# FUNCION: instalacion gaming (Steam + drivers de GPU) para dwl
# ==================================================================
instalar_gaming() {

    info "Habilitando repositorios nonfree y multilib..."
    sudo xbps-install -Sy void-repo-nonfree void-repo-multilib void-repo-multilib-nonfree

    command -v lspci >/dev/null 2>&1 || sudo xbps-install -Sy pciutils
    GPU_INFO=$(lspci -k | grep -A2 -iE "vga|3d controller" || true)

    if printf '%s' "$GPU_INFO" | grep -qi nvidia; then
        GPU_VENDOR="nvidia"
    elif printf '%s' "$GPU_INFO" | grep -qiE "amd|radeon|ati"; then
        GPU_VENDOR="amd"
    elif printf '%s' "$GPU_INFO" | grep -qi intel; then
        GPU_VENDOR="intel"
    else
        GPU_VENDOR="desconocida"
    fi
    info "GPU detectada: $GPU_VENDOR"

    info "Instalando drivers de GPU..."
    case "$GPU_VENDOR" in
        nvidia)
            warn "GPU NVIDIA detectada. El soporte de Wayland con el driver propietario"
            warn "mejoro mucho pero puede seguir dando problemas (cursor invisible, apps que no arrancan)."
            sudo xbps-install -Sy nvidia nvidia-libs-32bit
            echo "options nvidia-drm modeset=1" | sudo tee /etc/modprobe.d/nvidia-drm-modeset.conf >/dev/null
            warn "Si dwl no arranca o el cursor no se ve, agrega esta linea a"
            warn "/usr/local/bin/dwl-session, antes de 'dwl -s dwl-bar':"
            warn '  export WLR_NO_HARDWARE_CURSORS=1'
            ;;
        amd)
            sudo xbps-install -Sy mesa-dri mesa-vulkan-radeon mesa-dri-32bit \
                mesa-vulkan-radeon-32bit linux-firmware-amd vulkan-loader
            ;;
        intel)
            sudo xbps-install -Sy mesa-dri mesa-vulkan-intel mesa-dri-32bit \
                mesa-vulkan-intel-32bit intel-video-accel vulkan-loader
            ;;
        *)
            warn "No se pudo identificar la GPU automaticamente."
            warn "Instala el driver correspondiente a mano despues."
            ;;
    esac

    info "Instalando Steam, gamemode y gamescope..."
    sudo xbps-install -Sy steam gamemode gamescope

    info "Steam corre sobre XWayland automaticamente (ya quedo habilitado por dwl/wlroots)."
    info "gamescope es en si mismo un mini-compositor Wayland: puedes lanzar juegos"
    info "pesados con 'gamescope -- %command%' desde las propiedades de lanzamiento en Steam."

    info "Instalacion gaming completada."
    warn "Reinicia el equipo para que el driver de GPU quede activo."
    warn "Abre Steam por primera vez desde foot ('steam') para que complete su actualizacion interna."
}

# ==================================================================
# EJECUCION
# ==================================================================
instalar_base
if [ "$OPCION" = "2" ]; then
    instalar_gaming
fi



info "=========================================="
info " ¡Instalación de DWL completada con éxito!"
info "=========================================="
info "En la pantalla de inicio de LightDM elige la sesión 'dwl'."
info ""
info "Archivos clave para personalizar tu entorno:"
info "  ~/dwl/config.h                Atajos, colores, reglas, layout de teclado (requiere dwl-rebuild)"
info "  ~/dwl-bar/src/config.h        Apariencia de la barra externa dwl-bar"
info "  ~/slstatus/config.h           Utilidad de estado independiente (opcional)"
info "  ~/.config/lf/lfrc             Configuración del gestor de archivos"
info "  /usr/local/bin/dwl-session     Variables y programas al iniciar sesión"
info ""
info "Para aplicar cambios tras editar config.h ejecuta: dwl-rebuild"
info ""
warn "IMPORTANTE: Para que los permisos del grupo 'seat' surtan efecto,"
warn "ES NECESARIO REINICIAR el equipo antes de iniciar sesión en DWL."
warn "Comando sugerido: sudo reboot"

# ------------------------------------------------------------------
# Habilitar Display Manager (LightDM)
# ------------------------------------------------------------------
info "Habilitando el servicio LightDM..."
[ -L /var/service/lightdm ] || sudo ln -s /etc/sv/lightdm /var/service/

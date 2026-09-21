#!/bin/sh
# install-dwm.sh
# Instalador rapido de dwm + rice personalizado (Void Linux)
# Uso: sh install-dwm.sh   (como usuario normal, NO como root)
# Revisar sintaxis sin ejecutar: sh -n install-dwm.sh

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

# ----------------------------------------------------------------
# Comprobaciones previas
# ----------------------------------------------------------------
if [ "$(id -u)" -eq 0 ]; then
    error "No ejecutes este script como root: los archivos quedarian en /root."
    error "Usa tu usuario normal (el script usa sudo cuando lo necesita)."
    exit 1
fi

if ! command -v sudo >/dev/null 2>&1; then
    error "Falta 'sudo'. Instalalo y agrega tu usuario a sudoers (visudo) antes de continuar."
    exit 1
fi

# ----------------------------------------------------------------
# 0. Detectar distro (para avisar si no es Void)
# ----------------------------------------------------------------
DISTRO_ID="unknown"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO_ID="${ID:-unknown}"
fi

info "Distro detectada: $DISTRO_ID"

if [ "$DISTRO_ID" != "void" ]; then
    warn "Este script fue pensado para Void Linux (xbps)."
    warn "Detecte '$DISTRO_ID'. Los pasos de instalacion de paquetes probablemente fallen."
    printf "Continuar de todas formas? [y/N] "
    read -r CONTINUAR
    case "$CONTINUAR" in
        y|Y) ;;
        *) error "Cancelado por el usuario."; exit 1 ;;
    esac
fi

# ----------------------------------------------------------------
# Auto-deteccion de hardware
# ----------------------------------------------------------------
info "Detectando hardware..."

# Interfaz de red por defecto
WIFI_IFACE=$(ip route | grep default | awk '{print $5}' | head -n1 || true)
if [ -z "$WIFI_IFACE" ]; then
    warn "No se pudo detectar interfaz de red activa, usando 'eth0' por defecto."
    WIFI_IFACE="eth0"
fi

# Nombre de la bateria
BAT_NAME=$(ls /sys/class/power_supply/ 2>/dev/null | grep -E '^BAT' | head -n1 || true)
if [ -z "$BAT_NAME" ]; then
    warn "No se detecto bateria; no se mostrara en la barra."
    BAT_NAME="n/a"
fi

info "Interfaz de red: $WIFI_IFACE"
info "Bateria: $BAT_NAME"

# ----------------------------------------------------------------
# 1. Variables de configuracion (edita a tu gusto)
# ----------------------------------------------------------------
DWM_REPO="https://git.suckless.org/dwm"
SLSTATUS_REPO="https://git.suckless.org/slstatus"
VANITYGAPS_URL="https://dwm.suckless.org/patches/vanitygaps/dwm-vanitygaps-6.2.diff"

WALLPAPER_DIR="$HOME/Pictures"
WALLPAPER_PATH="$WALLPAPER_DIR/wallpaper.jpg"

# Wallpaper fijo (Empty Error - wallpapercave).
# Si esta URL no devuelve una imagen, se omite; lo ideal es una URL directa a un .jpg
WALLPAPER_URL="https://wallpapercave.com/download/empty-error-wallpapers-wp8330753"

# ----------------------------------------------------------------
# 2. Paquetes necesarios
# ----------------------------------------------------------------
# Nota: 'xorg' y 'nerd-fonts' son metapaquetes muy pesados. Si quieres algo mas
# ligero, revisa xorg-minimal y una sola fuente (xbps-query -Rs nerd-fonts).
info "Instalando dependencias base..."
sudo xbps-install -Sy \
    base-devel git file libX11-devel libXft-devel libXinerama-devel \
    freetype-devel fontconfig-devel xorg xinit curl wget \
    dmenu st slock dunst fastfetch picom feh \
    alsa-utils brightnessctl scrot \
    nerd-fonts \
    lightdm lightdm-gtk3-greeter \
    chrony firefox btop \
    dbus

info "Habilitando servicios (dbus, chronyd)..."
[ -L /var/service/dbus ]    || sudo ln -s /etc/sv/dbus /var/service/
[ -L /var/service/chronyd ] || sudo ln -s /etc/sv/chronyd /var/service/

# ----------------------------------------------------------------
# 2b. Zona horaria y reloj
# ----------------------------------------------------------------
info "Configuracion de zona horaria."
printf "Escribe tu pais (ej: Colombia, Mexico, Argentina, España).\nDeja vacio para usar Colombia por defecto: "
read -r PAIS_INPUT
PAIS_INPUT="${PAIS_INPUT:-Colombia}"

# Normalizar: minusculas y sin tildes
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
    */*)
        # El usuario escribio Region/Ciudad directamente (ej. America/Denver)
        TZ_INPUT="$PAIS_INPUT"
        ;;
    *)
        TZ_INPUT=""
        ;;
esac

if [ -n "$TZ_INPUT" ] && [ -f "/usr/share/zoneinfo/$TZ_INPUT" ]; then
    info "Pais: $PAIS_INPUT -> Zona horaria: $TZ_INPUT"
    sudo ln -sf "/usr/share/zoneinfo/$TZ_INPUT" /etc/localtime
    sudo hwclock --systohc || warn "No se pudo sincronizar el reloj de hardware (se ignora)."
    # En Void, TIMEZONE en /etc/rc.conf sobrescribe /etc/localtime en cada arranque
    if grep -qE '^[#[:space:]]*TIMEZONE=' /etc/rc.conf 2>/dev/null; then
        sudo sed -i "s|^[#[:space:]]*TIMEZONE=.*|TIMEZONE=\"$TZ_INPUT\"|" /etc/rc.conf
    else
        printf 'TIMEZONE="%s"\n' "$TZ_INPUT" | sudo tee -a /etc/rc.conf >/dev/null
    fi
else
    warn "No reconoci '$PAIS_INPUT' como pais, y tampoco es una ruta valida de zona horaria."
    warn "Se deja la zona horaria del sistema sin cambios. Puedes revisar opciones con:"
    warn "  find /usr/share/zoneinfo -type f | sed 's#/usr/share/zoneinfo/##' | less"
    warn "y luego corregirla a mano con: sudo ln -sf /usr/share/zoneinfo/Region/Ciudad /etc/localtime"
fi

# ----------------------------------------------------------------
# 3. Clonar y compilar dwm
# ----------------------------------------------------------------
cd "$HOME"
if [ ! -d dwm ]; then
    info "Clonando dwm..."
    git clone "$DWM_REPO"
fi
cd dwm

# El parche vanitygaps es para dwm 6.2, pero HEAD del repo esta en 6.8+.
# Nos fijamos en el tag 6.2 para que el patch aplique limpio.
info "Fijando dwm en el tag 6.2 (version compatible con el parche vanitygaps)..."
git fetch --tags
git checkout tags/6.2 -b v6.2-local 2>/dev/null || git checkout v6.2-local

info "Escribiendo config.h de dwm..."
cat > config.h <<'EOF'
#include <X11/XF86keysym.h>
/* See LICENSE file for copyright and license details. */

/* appearance */
static const unsigned int borderpx  = 2;
static const unsigned int gappih    = 10;
static const unsigned int gappiv    = 10;
static const unsigned int gappoh    = 10;
static const unsigned int gappov    = 10;
static       int smartgaps          = 0;
static const unsigned int snap      = 32;
static const int showbar            = 1;
static const int topbar             = 1;
static const char *fonts[]          = { "JetBrainsMono Nerd Font:size=11" };
static const char dmenufont[]       = "JetBrainsMono Nerd Font:size=11";

static const char col_gray1[]       = "#1e1e2e";
static const char col_gray2[]       = "#313244";
static const char col_gray3[]       = "#cdd6f4";
static const char col_gray4[]       = "#ffffff";
static const char col_cyan[]        = "#89b4fa";
static const char *colors[][3]      = {
        [SchemeNorm] = { col_gray3, col_gray1, col_gray2 },
        [SchemeSel]  = { col_gray4, col_gray1, col_cyan  },
};

static const char *tags[] = { "1", "2", "3", "4", "5", "6", "7", "8", "9" };

static const Rule rules[] = {
        { "Gimp",     NULL,       NULL,       0,            1,           -1 },
        { "firefox",  NULL,       NULL,       1 << 0,       0,           -1 },
};

/* layout(s) */
static const float mfact     = 0.50;
static const int nmaster     = 1;
static const int resizehints = 1;

#define FORCE_VSPLIT 1
#include "vanitygaps.c"

static const Layout layouts[] = {
        { "[]=",      tile },
        { "><>",      NULL },
        { "[M]",      monocle },
};

#define MODKEY Mod4Mask
#define TAGKEYS(KEY,TAG) \
        { MODKEY,                       KEY,      view,           {.ui = 1 << TAG} }, \
        { MODKEY|ControlMask,           KEY,      toggleview,     {.ui = 1 << TAG} }, \
        { MODKEY|ShiftMask,             KEY,      tag,            {.ui = 1 << TAG} }, \
        { MODKEY|ControlMask|ShiftMask, KEY,      toggletag,      {.ui = 1 << TAG} },

#define SHCMD(cmd) { .v = (const char*[]){ "/bin/sh", "-c", cmd, NULL } }

static char dmenumon[2] = "0";
static const char *dmenucmd[]   = { "dmenu_run", "-m", dmenumon, "-fn", dmenufont, "-nb", col_gray1, "-nf", col_gray3, "-sb", col_cyan, "-sf", col_gray4, NULL };
static const char *termcmd[]    = { "st", NULL };
static const char *browsercmd[] = { "firefox", NULL };

static const Key keys[] = {
        { MODKEY,                       XK_d,          spawn,          {.v = dmenucmd } },
        { MODKEY,                       XK_Return,     spawn,          {.v = termcmd } },
        { MODKEY,                       XK_t,          spawn,          {.v = termcmd } },
        { MODKEY,                       XK_b,          spawn,          {.v = browsercmd } },

        { MODKEY,                       XK_q,          killclient,     {0} },
        { MODKEY,                       XK_f,          setlayout,      {.v = &layouts[2]} },
        { MODKEY,                       XK_w,          togglebar,      {0} },
        { MODKEY|ShiftMask,             XK_t,          togglefloating, {0} },
        { MODKEY,                       XK_r,          setlayout,      {0} },

        { MODKEY,                       XK_j,          focusstack,     {.i = +1 } },
        { MODKEY,                       XK_k,          focusstack,     {.i = -1 } },
        { MODKEY,                       XK_h,          setmfact,       {.f = -0.05} },
        { MODKEY,                       XK_l,          setmfact,       {.f = +0.05} },
        { MODKEY,                       XK_Down,       focusstack,     {.i = +1 } },
        { MODKEY,                       XK_Up,         focusstack,     {.i = -1 } },

        { MODKEY,                       XK_i,          incnmaster,     {.i = +1 } },
        { MODKEY,                       XK_comma,      focusmon,       {.i = -1 } },
        { MODKEY,                       XK_period,     focusmon,       {.i = +1 } },
        { MODKEY|ShiftMask,             XK_comma,      tagmon,         {.i = -1 } },
        { MODKEY|ShiftMask,             XK_period,     tagmon,         {.i = +1 } },

        { MODKEY|ControlMask,           XK_u,          incrgaps,       {.i = +1 } },
        { MODKEY|ControlMask|ShiftMask, XK_u,          incrgaps,       {.i = -1 } },
        { MODKEY|ControlMask,           XK_0,          togglegaps,     {0} },
        { MODKEY|ControlMask|ShiftMask, XK_0,          defaultgaps,    {0} },

        { 0, XF86XK_AudioRaiseVolume,   spawn, SHCMD("amixer set Master 3%+") },
        { 0, XF86XK_AudioLowerVolume,   spawn, SHCMD("amixer set Master 3%-") },
        { 0, XF86XK_AudioMute,          spawn, SHCMD("amixer set Master toggle") },
        { 0, XF86XK_MonBrightnessUp,    spawn, SHCMD("brightnessctl set +5%") },
        { 0, XF86XK_MonBrightnessDown,  spawn, SHCMD("brightnessctl set 5%-") },

        { 0,                             XK_Print,      spawn,          SHCMD("scrot ~/Pictures/%Y-%m-%d_%H-%M-%S.png") },

        { MODKEY,                       XK_space,      setlayout,      {0} },
        { MODKEY,                       XK_Tab,        view,           {0} },
        { MODKEY|ShiftMask,             XK_e,          quit,           {0} },

        TAGKEYS(                        XK_1,                      0)
        TAGKEYS(                        XK_2,                      1)
        TAGKEYS(                        XK_3,                      2)
        TAGKEYS(                        XK_4,                      3)
        TAGKEYS(                        XK_5,                      4)
        TAGKEYS(                        XK_6,                      5)
        TAGKEYS(                        XK_7,                      6)
        TAGKEYS(                        XK_8,                      7)
        TAGKEYS(                        XK_9,                      8)
};

static const Button buttons[] = {
        { ClkLtSymbol,          0,              Button1,        setlayout,      {0} },
        { ClkLtSymbol,          0,              Button3,        setlayout,      {.v = &layouts[2]} },
        { ClkWinTitle,          0,              Button2,        zoom,           {0} },
        { ClkStatusText,        0,              Button2,        spawn,          {.v = termcmd } },
        { ClkClientWin,         MODKEY,         Button1,        movemouse,      {0} },
        { ClkClientWin,         MODKEY,         Button2,        togglefloating, {0} },
        { ClkClientWin,         MODKEY,         Button3,        resizemouse,    {0} },
        { ClkTagBar,            0,              Button1,        view,           {0} },
        { ClkTagBar,            0,              Button3,        toggleview,     {0} },
        { ClkTagBar,            MODKEY,         Button1,        tag,            {0} },
        { ClkTagBar,            MODKEY,         Button3,        toggletag,      {0} },
};
EOF

info "Descargando parche vanitygaps..."
[ -f dwm-vanitygaps-6.2.diff ] || curl -fsSO "$VANITYGAPS_URL"

if [ ! -f vanitygaps.c ]; then
    info "Aplicando parche vanitygaps a dwm.c..."
    if ! patch -p1 -N --fuzz=3 < dwm-vanitygaps-6.2.diff; then
        error "El parche no aplico. Revisa dwm.c.rej si existe y depuralo antes de seguir."
        exit 1
    fi
fi

info "Compilando dwm..."
sudo make clean install

# ----------------------------------------------------------------
# 4. Clonar y compilar slstatus
# ----------------------------------------------------------------
cd "$HOME"
if [ ! -d slstatus ]; then
    info "Clonando slstatus..."
    git clone "$SLSTATUS_REPO"
fi
cd slstatus

# Solo se agregan a la barra los modulos que existen en este equipo:
# wifi si la interfaz es inalambrica, bateria si hay BAT*.
info "Escribiendo config.h de slstatus..."
{
    cat <<'EOF'
/* See LICENSE file for copyright and license details. */
const unsigned int interval = 1000;
static const char unknown_str[] = "n/a";
#define MAXLEN 2048

static const struct arg args[] = {
EOF
    if [ -d "/sys/class/net/$WIFI_IFACE/wireless" ]; then
        printf '        { wifi_essid,   "  %%s  ",      "%s" },\n' "$WIFI_IFACE"
    fi
    if [ "$BAT_NAME" != "n/a" ]; then
        printf '        { battery_perc, "BAT: %%s%%%%  ", "%s" },\n' "$BAT_NAME"
    fi
    cat <<'EOF'
        { datetime,     "%s",           "%Y-%m-%d %I:%M %p" },
};
EOF
} > config.h

info "Compilando slstatus..."
sudo make clean install

# ----------------------------------------------------------------
# 5. picom
# ----------------------------------------------------------------
info "Configurando picom..."
mkdir -p "$HOME/.config/picom"
cat > "$HOME/.config/picom/picom.conf" <<'EOF'
backend = "xrender";
vsync = false;

opacity-rule = [
  "90:class_g = 'st-256color'"
];

shadow = false;
fading = false;
EOF

# ----------------------------------------------------------------
# 6. Wallpaper
# ----------------------------------------------------------------
mkdir -p "$WALLPAPER_DIR"
if [ ! -f "$WALLPAPER_PATH" ]; then
    info "Descargando wallpaper..."
    wget -q -U "Mozilla/5.0" --referer="https://wallpapercave.com/" \
        -O "$WALLPAPER_PATH" "$WALLPAPER_URL" || true
    if ! file "$WALLPAPER_PATH" | grep -qi image; then
        warn "No se pudo descargar un wallpaper valido; se omite."
        warn "Puedes copiar tu propia imagen a $WALLPAPER_PATH y se usara al iniciar sesion."
        rm -f "$WALLPAPER_PATH"
    fi
fi

# Aplicarlo ya mismo si hay una sesion X corriendo
if [ -f "$WALLPAPER_PATH" ] && [ -n "$DISPLAY" ] && command -v feh >/dev/null 2>&1; then
    feh --bg-fill "$WALLPAPER_PATH" || true
fi

# ----------------------------------------------------------------
# 7. Script wrapper (para que LightDM inicie todo)
# ----------------------------------------------------------------
info "Creando script wrapper para la sesion..."
sudo tee /usr/local/bin/dwm-session >/dev/null <<EOF
#!/bin/sh
# Comandos de inicio
[ -f "$WALLPAPER_PATH" ] && feh --bg-fill "$WALLPAPER_PATH" &
picom --config "$HOME/.config/picom/picom.conf" &
dunst &
slstatus &

# Ejecutar dwm (siempre al final con exec)
exec dwm
EOF

sudo chmod +x /usr/local/bin/dwm-session

# ----------------------------------------------------------------
# 7b. ~/.xinitrc (para poder usar "startx" ademas de lightdm)
# ----------------------------------------------------------------
if [ -f "$HOME/.xinitrc" ]; then
    info "Respaldando ~/.xinitrc existente en ~/.xinitrc.bak"
    cp "$HOME/.xinitrc" "$HOME/.xinitrc.bak"
fi
info "Creando ~/.xinitrc para que 'startx' use dwm..."
echo "exec /usr/local/bin/dwm-session" > "$HOME/.xinitrc"

# ----------------------------------------------------------------
# 8. Registrar sesion dwm en lightdm
# ----------------------------------------------------------------
info "Registrando sesion dwm en lightdm..."
sudo mkdir -p /usr/share/xsessions
sudo tee /usr/share/xsessions/dwm.desktop >/dev/null <<EOF
[Desktop Entry]
Name=dwm
Comment=Dynamic window manager
Exec=/usr/local/bin/dwm-session
Type=Application
EOF

# ----------------------------------------------------------------
# 9. Teclado (el usuario elige)
# ----------------------------------------------------------------
info "Configuracion de teclado."
KB_LAYOUT=""
KB_CONSOLA=""
while true; do
    printf "Selecciona la distribucion de teclado:\n"
    printf "  1) Ingles (us)\n"
    printf "  2) Español de España (es)\n"
    printf "  3) Latinoamericano (latam)\n"
    printf "  4) No cambiar\n"
    printf "Opcion [3]: "
    read -r OPCION_TECLADO
    OPCION_TECLADO="${OPCION_TECLADO:-3}"

    case "$OPCION_TECLADO" in
        1) KB_LAYOUT="us";    KB_CONSOLA="us";         break ;;
        2) KB_LAYOUT="es";    KB_CONSOLA="es";         break ;;
        3) KB_LAYOUT="latam"; KB_CONSOLA="la-latin1";  break ;;
        4) KB_LAYOUT="";      KB_CONSOLA="";           break ;;
        *) warn "Opcion no valida, elige 1, 2, 3 o 4." ;;
    esac
done

if [ -n "$KB_LAYOUT" ]; then
    info "Configurando teclado en '$KB_LAYOUT'..."

    # Aplicar de inmediato a la sesion X actual (si hay una corriendo)
    command -v setxkbmap >/dev/null 2>&1 && setxkbmap "$KB_LAYOUT" 2>/dev/null || true

    # Dejarlo fijo para Xorg (aplica tambien en la pantalla de login de lightdm)
    sudo mkdir -p /etc/X11/xorg.conf.d
    sudo tee /etc/X11/xorg.conf.d/00-keyboard.conf >/dev/null <<EOF
Section "InputClass"
        Identifier "system-keyboard"
        MatchIsKeyboard "on"
        Option "XkbLayout" "$KB_LAYOUT"
EndSection
EOF

    # Consola (TTY) en Void: /etc/rc.conf (KEYMAP) + aplicar ahora con loadkeys
    if [ -n "$KB_CONSOLA" ]; then
        if grep -qE '^[#[:space:]]*KEYMAP=' /etc/rc.conf 2>/dev/null; then
            sudo sed -i "s|^[#[:space:]]*KEYMAP=.*|KEYMAP=\"$KB_CONSOLA\"|" /etc/rc.conf
        else
            printf 'KEYMAP="%s"\n' "$KB_CONSOLA" | sudo tee -a /etc/rc.conf >/dev/null
        fi
        # Solo funciona en una TTY; si falla, se ignora
        command -v loadkeys >/dev/null 2>&1 && sudo loadkeys "$KB_CONSOLA" 2>/dev/null || true
    fi
else
    info "Se deja el layout de teclado actual sin cambios."
fi

# ----------------------------------------------------------------
# 10. Kernel (opcional): instalar la serie de kernel mas nueva
# ----------------------------------------------------------------
# En Void cada serie es un paquete: linux6.18, linux6.19, ...
# El paquete 'linux' apunta a la serie por defecto (estable con DKMS);
# las mas nuevas se instalan aparte y el kernel actual se conserva.
KERNEL_NUEVO=""
CUR_KERNEL="$(uname -r)"
CUR_SERIES="$(printf '%s' "$CUR_KERNEL" | cut -d. -f1,2)"
info "Kernel en uso: $CUR_KERNEL"

printf "Quieres instalar la serie de kernel mas nueva de los repos de Void? [s/N]: "
read -r ACT_KERNEL
case "$ACT_KERNEL" in
    s|S|si|Si|SI|y|Y)
        # Busca las series disponibles y se queda con la de version mas alta
        NEWEST_KERNEL=$(xbps-query --regex -Rs '^linux[0-9]+\.[0-9]+-[0-9._]+' \
            | awk '{print $2}' | sed 's/-[0-9][0-9._]*$//' | sort -uV | tail -n1)

        if [ -z "$NEWEST_KERNEL" ]; then
            warn "No pude consultar las series de kernel disponibles (revisa conexion y repos)."
        elif [ "$NEWEST_KERNEL" = "linux$CUR_SERIES" ]; then
            info "Ya usas la serie mas nueva ($NEWEST_KERNEL)."
        else
            info "Serie mas nueva disponible: $NEWEST_KERNEL"
            BOOT_FREE_MB=$(df -Pm /boot | awk 'NR==2 {print $4}')
            if [ "${BOOT_FREE_MB:-0}" -lt 300 ]; then
                warn "Poco espacio libre en /boot (${BOOT_FREE_MB} MB); se omite la instalacion del kernel."
                warn "Libera kernels viejos: 'sudo vkpurge list' y luego 'sudo vkpurge rm <version>'."
            else
                warn "Es una serie mas nueva que la predeterminada de Void y puede estar menos probada."
                warn "Tu kernel actual se conserva en el menu de arranque por si necesitas volver a el."
                if sudo xbps-install -y "$NEWEST_KERNEL" "$NEWEST_KERNEL-headers"; then
                    # Recompilar modulos DKMS (nvidia, virtualbox, etc.) para el kernel nuevo
                    if command -v dkms >/dev/null 2>&1; then
                        sudo xbps-reconfigure -f "$NEWEST_KERNEL" \
                            || warn "Fallo la reconfiguracion DKMS de $NEWEST_KERNEL."
                    fi
                    KERNEL_NUEVO="$NEWEST_KERNEL"
                    info "Kernel $NEWEST_KERNEL instalado; se usara despues de reiniciar."
                else
                    warn "No se pudo instalar $NEWEST_KERNEL; se deja el kernel actual."
                fi
            fi
        fi
        ;;
    *)
        info "Se deja el kernel actual sin cambios."
        ;;
esac

# ----------------------------------------------------------------
# 11. Habilitar lightdm y terminar
# ----------------------------------------------------------------
[ -L /var/service/lightdm ] || sudo ln -s /etc/sv/lightdm /var/service/

info "¡Instalación lista!"
if [ -n "$KERNEL_NUEVO" ]; then
    warn "Reinicia para usar $KERNEL_NUEVO y verifica con 'uname -r'."
    warn "Si el kernel nuevo da problemas, elige el anterior en el menu de arranque."
fi
warn "Reinicia el equipo (o cierra sesion) para aplicar teclado, zona horaria y lightdm."
warn "Si no ves la sesión de DWM en el login, asegúrate de que /usr/local/bin/ esté en tu PATH"

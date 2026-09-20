#!/bin/sh
# install-dwm.sh
# Instalador rápido de dwm + rice personalizado (Void Linux)
# Uso: sh install-dwm.sh

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
# 0. Detectar distro (para elegir wallpaper / avisar si no es Void)
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
# Auto-detección de hardware
# ----------------------------------------------------------------
info "Detectando hardware..."

# Detectar interfaz de red por defecto
WIFI_IFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
if [ -z "$WIFI_IFACE" ]; then
    warn "No se pudo detectar interfaz de red activa, usando 'eth0' por defecto."
    WIFI_IFACE="eth0"
fi

# Detectar nombre de la batería
BAT_NAME=$(ls /sys/class/power_supply/ | grep -E '^BAT' | head -n1)
if [ -z "$BAT_NAME" ]; then
    warn "No se detectó batería, configurando en n/a."
    BAT_NAME="n/a"
fi

info "Interfaz de red: $WIFI_IFACE"
info "Batería: $BAT_NAME"

# ----------------------------------------------------------------
# 1. Variables de configuracion (edita a tu gusto)
# ----------------------------------------------------------------
DWM_REPO="https://git.suckless.org/dwm"
SLSTATUS_REPO="https://git.suckless.org/slstatus"
VANITYGAPS_URL="https://dwm.suckless.org/patches/vanitygaps/dwm-vanitygaps-6.2.diff"

# (FIX: ya NO se sobreescriben WIFI_IFACE / BAT_NAME aqui;
#  se respeta lo detectado automaticamente arriba)

WALLPAPER_DIR="$HOME/Pictures"
WALLPAPER_PATH="$WALLPAPER_DIR/wallpaper.jpg"

# Wallpaper fijo (Empty Error - wallpapercave)
WALLPAPER_URL="https://wallpapercave.com/download/empty-error-wallpapers-wp8330753"

# ----------------------------------------------------------------
# 2. Paquetes necesarios
# ----------------------------------------------------------------
info "Instalando dependencias base..."
sudo xbps-install -Sy \
    base-devel libX11-devel libXft-devel libXinerama-devel \
    freetype-devel fontconfig-devel xorg xinit git curl wget \
    dmenu st slock dunst picom feh \
    alsa-utils brightnessctl scrot \
    nerd-fonts \
    lightdm lightdm-gtk3-greeter \
    dbus

info "Habilitando servicios (dbus, lightdm)..."
[ -L /var/service/dbus ]    || sudo ln -s /etc/sv/dbus /var/service/
[ -L /var/service/lightdm ] || sudo ln -s /etc/sv/lightdm /var/service/

# ----------------------------------------------------------------
# 3. Clonar y compilar dwm
# ----------------------------------------------------------------
cd "$HOME"
if [ ! -d dwm ]; then
    info "Clonando dwm..."
    git clone "$DWM_REPO"
fi
cd dwm

# FIX: el parche vanitygaps es para dwm 6.2, pero HEAD del repo esta
# en 6.8+. Nos fijamos en el tag 6.2 para que el patch aplique limpio.
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
static const int lockfullscreen = 1;
static const int refreshrate = 120;

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
[ -f dwm-vanitygaps-6.2.diff ] || curl -sO "$VANITYGAPS_URL"

if [ ! -f vanitygaps.c ]; then
    info "Aplicando parche vanitygaps a dwm.c..."
    if ! patch -p1 -N --fuzz=3 < dwm-vanitygaps-6.2.diff; then
        error "El parche no aplicó. Aunque ahora estamos en el tag 6.2 (la version"
        error "para la que se hizo el parche), algo mas fallo. Revisa dwm.c.rej si existe"
        error "y avisame para depurarlo antes de seguir."
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

info "Escribiendo config.h de slstatus..."
cat > config.h <<EOF
/* See LICENSE file for copyright and license details. */
const unsigned int interval = 1000;
static const char unknown_str[] = "n/a";
#define MAXLEN 2048

static const struct arg args[] = {
        { wifi_essid,     "  %s  ",          "$WIFI_IFACE" },
        { battery_perc,   "BAT: %s%%  ",     "$BAT_NAME" },
        { datetime,       "%s",              "%Y-%m-%d %I:%M %p" },
};
EOF

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
    wget -q -O "$WALLPAPER_PATH" "$WALLPAPER_URL" || warn "No se pudo descargar el wallpaper."
fi
# ----------------------------------------------------------------
# 7. Crear script Wrapper (Para que LightDM inicie todo)
# ----------------------------------------------------------------
info "Creando script wrapper para la sesion..."
sudo tee /usr/local/bin/dwm-session >/dev/null <<EOF
#!/bin/sh
# Comandos de inicio
feh --bg-fill "$WALLPAPER_PATH" &
picom --config "$HOME/.config/picom/picom.conf" &
slstatus &

# Ejecutar dwm (siempre al final con exec)
exec dwm
EOF

sudo chmod +x /usr/local/bin/dwm-session

# ----------------------------------------------------------------
# 7b. Crear ~/.xinitrc (para poder usar "startx" ademas de lightdm)
# ----------------------------------------------------------------
info "Creando ~/.xinitrc para que 'startx' use dwm en vez del xinitrc generico..."
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

# terminando la configuracion

info "¡Instalación lista!"
warn "Si no ves la sesión de DWM en el login, asegúrate de que /usr/local/bin/ esté en tu PATH"

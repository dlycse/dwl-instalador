#!/bin/sh
# install-dwl v0.9.8 - SIN HABILITACION AUTOMATICA DE SERVICIOS = SIN CUELGUES
# NO toca NINGUN enlace de /var/service durante la instalacion para evitar que runit/systemd
# arranque servicios a mitad del script y lo cuelguen.
# Al final te muestra 2 comandos que tu ejecutas manualmente si quieres habilitar greetd.
set -e

G="\033[1;32m"; Y="\033[1;33m"; R="\033[1;31m"; C="\033[1;36m"; N="\033[0m"
info() { printf "%b[+]%b %s\n" "$G" "$N" "$1"; }
warn() { printf "%b[!]%b %s\n" "$Y" "$N" "$1"; }
err() { printf "%b[x]%b %s\n" "$R" "$N" "$1"; exit 1; }
hdr() { printf "%b%s%b\n" "$C" "$1" "$N"; }

VERSION="v0.9.8"
[ "$(id -u)" -eq 0 ] && err "No ejecutes como root."
for c in sudo git; do command -v $c >/dev/null || { error "Falta $c."; exit 1; }; done

# Detectar distro
DISTRO_FAMILIA="unknown"; [ -f /etc/os-release ] && . /etc/os-release
case "${ID:-unknown}" in
 void) DISTRO_FAMILIA="void" ;;
 arch|manjaro|endeavouros|garuda|artix|archcraft|arcolinux|parabola|cachyos) DISTRO_FAMILIA="arch" ;;
 *) case "${ID_LIKE:-}" in *arch*)DISTRO_FAMILIA="arch";;*void*)DISTRO_FAMILIA="void";;esac ;;
esac
info "install-dwl $VERSION - Distro: ${ID:-unknown}"
[ "$DISTRO_FAMILIA" = "unknown" ] && err "Solo compatible con Void y Arch."

: "${WMENU_FONT_SIZE:=11}"; : "${DWLB_FONT_SIZE:=10}"
WALLPAPER_PATH="${WALLPAPER_PATH:-$HOME/Pictures/wallpaper.jpg}"
GREETD_VT=1 # Siempre tty1 en ambas distros, se ve directamente al arrancar

# ----------------------------------------------------------------
# FUNCIONES POR DISTRO - NINGUNA MODIFICA /var/service NI ARRANCA SERVICIOS
# ----------------------------------------------------------------
if [ "$DISTRO_FAMILIA" = "void" ]; then
 PKGMAN(){ sudo xbps-install -Sy "$@"; }
 PKGHAS(){ xbps-query "$1" >/dev/null 2>&1; }
 PKGREM(){ sudo xbps-remove -R "$@"; }
 SEAT_GRP="_seatd"; GREETER_USER="_greeter"; NEED_TURNSTILE=1
 PKGS="base-devel file pkg-config libinput libinput-devel void-repo-nonfree void-repo-multilib void-repo-multilib-nonfree wayland wayland-devel wayland-protocols libxkbcommon libxkbcommon-devel wlroots wlroots-devel libseat libseat-devel seatd xorg-server-xwayland mesa-dri libdrm-devel pango-devel cairo-devel pixman pixman-devel fcft fcft-devel tllist foot wmenu fastfetch pipewire wireplumber alsa-pipewire swaybg swaylock grim slurp wl-clipboard brightnessctl curl procps-ng nano nerd-fonts lf mpv zathura zathura-pdf-poppler xdg-utils imv chrony firefox btop cowsay dbus pciutils greetd tuigreet turnstile"
 # NO HABILITAR NINGUN SERVICIO AUTOMATICAMENTE
 habilitar_servicios_base(){
 # Solo crear los enlaces si no existen, pero APAGARLOS INMEDIATAMENTE
 for svc in dbus chronyd seatd; do
 if [ ! -L "/var/service/$svc" ] && [ -d "/etc/sv/$svc" ]; then
 sudo ln -sf "/etc/sv/$svc" /var/service/
 sudo sv stop "$svc" 2>/dev/null 
 fi
 done
 }
else
 # ARCH
 PKGMAN(){ sudo pacman -Sy --needed --noconfirm "$@"; }
 PKGHAS(){ pacman -Q "$1" >/dev/null 2>&1; }
 PKGREM(){ sudo pacman -Rns --noconfirm "$@"; }
 SEAT_GRP="seat"; GREETER_USER="greeter"; NEED_TURNSTILE=0
 WLR_PKG=$(pacman -Ssq '^wlroots[0-9]*\.[0-9]+$' 2>/dev/null |sort -V|tail -n1);[ -z "$WLR_PKG" ] && WLR_PKG="wlroots0.19"
 info "wlroots detectado: $WLR_PKG"
 PKGS="base-devel libinput wayland wayland-protocols libxkbcommon $WLR_PKG seatd xorg-xwayland mesa libdrm pango cairo pixman fcft tllist foot wmenu fastfetch pipewire wireplumber pipewire-alsa pipewire-pulse swaybg swaylock grim slurp wl-clipboard brightnessctl curl procps-ng nano ttf-nerd-fonts-symbols ttf-nerd-fonts-symbols-mono lf mpv zathura zathura-pdf-poppler xdg-utils imv chrony firefox btop cowsay dbus pciutils greetd greetd-tuigreet"
 habilitar_servicios_base(){
 for svc in dbus chronyd seatd; do
 if ! systemctl is-enabled --quiet "$svc" 2>/dev/null ; then
 sudo systemctl enable "$svc" 2>/dev/null 
 fi
 sudo systemctl stop "$svc" 2>/dev/null 
 done
 }
 command -v pacman >/dev/null || err "Falta pacman."
fi

# Menu
echo;hdr "==========================================";printf" install-dwl %s\n""$VERSION";hdr "=========================================="
echo"1) Instalar"
echo"2) Salir"
printf"Opcion [1]: ";read -r O;O="${O:-1}";[ "$O" = "2" ] && exit0

info "Instalando paquetes..."
if [ "$DISTRO_FAMILIA"="arch" ]; then
 sudo pacman -Sy --noconfirm archlinux-keyring 2>/dev/null ||true
 if ! PKGMAN $PKGS; then
 warn "Fallo descarga 404, regenerando mirrors..."
 PKGHAS reflector||PKGMAN reflector
 sudo reflector --latest 20 --sort rate --save /etc/pacman.d/mirrorlist||true
 PKGMAN $PKGS||err "Fallo instalando paquetes."
 fi
else
 PKGMAN $PKGS||err "Fallo instalando paquetes."
fi

info "Preparando servicios base (no se arrancan ahora)..."
habilitar_servicios_base

# Agregar usuario a grupos
RU=$(id -un)
getent group "$SEAT_GRP">/dev/null||err "No existe grupo $SEAT_GRP."
sudo usermod -aG "$SEAT_GRP" "$RU"
getent group video>/dev/null&&sudo usermod -aG video "$RU"
warn "Grupos ($SEAT_GRP, video) se aplican al reiniciar."

# Opcion kernel en Void
if [ "$DISTRO_FAMILIA"="void" ]; then
 info "Kernel actual: $(uname -r)"
 KVER=$(xbps-query --regex -Rs '^linux[0-9]+\.[0-9]+' 2>/dev/null |awk '{print $2}'|grep -E '^linux[0-9]+\.[0-9]+-[0-9]+\.[0-9]+'|sort -V|tail -n1)
 KPKG=$(printf'%s'"$KVER"|sed 's/-[0-9]\..*$//')
 if [ -n "$KPKG" ]; then
 printf"Kernel mas nuevo disponible: %s\n 1) Conservar actual 2) Instalar (recomendado)\nOpcion [2]: ";read -r OK;OK="${OK:-2}"
 [ "$OK" = "2" ] && sudo xbps-install -Sy "$KPKG"||info "Se conserva kernel actual."
 fi
fi

# Zona horaria
printf "Pais (vacio Colombia): "; read -r PAIS; PAIS="${PAIS:-Colombia}"
PN=$(echo "$PAIS" | tr '[:upper:]' '[:lower:]' | sed 's/á/a/g;s/é/e/g;s/í/i/g;s/ó/o/g;s/ú/u/g;s/ñ/n/g')
case "$PN" in colombia) TZ=America/Bogota;; mexico) TZ=America/Mexico_City;; argentina) TZ=America/Buenos_Aires;; chile) TZ=America/Santiago;; peru) TZ=America/Lima;; espana) TZ=Europe/Madrid;; usa) TZ=America/New_York;; */*) TZ="$PAIS";; *) TZ="" ;; esac
if [ -n "$TZ" ] && [ -f "/usr/share/zoneinfo/$TZ" ]; then sudo ln -sf "/usr/share/zoneinfo/$TZ" /etc/localtime; info "Zona horaria: $TZ"; fi

# Teclado
printf "Teclado 1=us 2=es 3=latam [3]: "; read -r KB; KB="${KB:-3}"
case "$KB" in 1) KBL=us; KBC=us;; 2) KBL=es; KBC=es;; *) KBL=latam; KBC=la-latin1;; esac
if [ "$DISTRO_FAMILIA" = "void" ]; then
 if grep -q KEYMAP /etc/rc.conf 2>/dev/null ; then
 sudo sed -i "s|^.*KEYMAP=.*|KEYMAP=\"$KBC\"|" /etc/rc.conf
 else
 echo "KEYMAP=\"$KBC\"" | sudo tee -a /etc/rc.conf >/dev/null
 fi
else
 if grep -q ^KEYMAP= /etc/vconsole.conf 2>/dev/null ; then
 sudo sed -i "s|^KEYMAP=.*|KEYMAP=$KBC|" /etc/vconsole.conf
 else
 echo "KEYMAP=$KBC" | sudo tee -a /etc/vconsole.conf >/dev/null
 fi
fi
command -v loadkeys >/dev/null && sudo loadkeys "$KBC" 2>/dev/null || true
if [ "$DISTRO_FAMILIA"="arch" ]; then grep -q ^KEYMAP= /etc/vconsole.conf 2>/dev/null &&sudo sed -i "s|^KEYMAP=.*|KEYMAP=$KBC|" /etc/vconsole.conf||echo"KEYMAP=$KBC"|sudo tee -a /etc/vconsole.conf>/dev/null;fi
command -v loadkeys>/dev/null&&sudo loadkeys "$KBC" 2>/dev/null ||true

# Compilar dwl
cd "$HOME"; [ -d dwl ] || git clone https://codeberg.org/dwl/dwl.git; cd dwl
[ "$(stat -c %U .)" != "$(id -un)" ] && sudo chown -R "$(id -un):$(id -gn)" .
if [ -f protocols/dwl-ipc-unstable-v2.xml ] || [ -f protocols/dwl-ipc-unstable-v1.xml ]; then DWLB_IPC=1; else DWLB_IPC=0; fi
[ "$DWLB_IPC" -eq 1 ] && info "IPC disponible para dwlb."
if [ -f config.h ] && { grep -q 'static const char \*tags\[\]' config.h || ! grep -q TAGCOUNT config.h; }; then mv config.h config.h.old-$(date +%Y%m%d%H%M%S); fi
if [ ! -f config.h ]; then
cat > config.h <<CFG
#define COLOR(hex){((hex>>24)&0xFF)/255.0f,((hex>>16)&0xFF)/255.0f,((hex>>8)&0xFF)/255.0f,(hex&0xFF)/255.0f}
static const int sloppyfocus=1,bypass_surface_visibility=0;
static const unsigned int borderpx=2,snap=32;
static const float rootcolor[]=COLOR(0x1e1e2eff),bordercolor[]=COLOR(0x313244ff),focuscolor[]=COLOR(0x89b4faff),urgentcolor[]=COLOR(0xf38ba8ff),fullscreen_bg[]={0,0,0,1};
#define TAGCOUNT (9);static int log_level=WLR_ERROR;
static const Rule rules[]={{"firefox",NULL,1<<0,0,-1}};
static const Layout layouts[]={{"[]=",tile},{" >< ",NULL},{"[M]",monocle}};
static const MonitorRule monrules[]={{NULL,0.55f,1,1,&layouts[0],WL_OUTPUT_TRANSFORM_NORMAL,-1,-1}};
static const struct xkb_rule_names xkb_rules={.layout="$KBL"};
static const int repeat_rate=25,repeat_delay=600,tap_to_click=1,tap_and_drag=1,drag_lock=1,natural_scrolling=0,disable_while_typing=1;
static const enum libinput_config_scroll_method scroll_method=LIBINPUT_CONFIG_SCROLL_2FG;
static const enum libinput_config_accel_profile accel_profile=LIBINPUT_CONFIG_ACCEL_PROFILE_ADAPTIVE;static const double accel_speed=0.0;
#define MODKEY WLR_MODIFIER_LOGO
#define TAGKEYS(K,S,T){MODKEY,K,view,{.ui=1<<T}},{MODKEY|WLR_MODIFIER_SHIFT,S,tag,{.ui=1<<T}}
static const char *term[]={"foot",NULL},*br[]={"firefox",NULL},*dm[]={"sh","-c","dwlb -toggle-visibility all; wmenu-run -f 'monospace $WMENU_FONT_SIZE' -N 1e1e2e -n cdd6f4 -S 89b4fa -s ffffff; dwlb -toggle-visibility all",NULL},*uv[]={"wpctl","set-volume","@DEFAULT_AUDIO_SINK@","3%+","-l","1.0",NULL},*dv[]={"wpctl","set-volume","@DEFAULT_AUDIO_SINK@","3%-",NULL},*mv[]={"wpctl","set-mute","@DEFAULT_AUDIO_SINK@","toggle",NULL},*bu[]={"brightnessctl","set","+5%",NULL},*bd[]={"brightnessctl","set","5%-",NULL},*ss[]={"sh","-c","grim ~/Pictures/\$(date +%Y%m%d_%H%M%S).png",NULL},*bt[]={"dwlb","-toggle-visibility","all",NULL};
static const Key keys[]={
{MODKEY,XKB_KEY_Return,spawn,{.v=term}},{MODKEY,XKB_KEY_d,spawn,{.v=dm}},{MODKEY,XKB_KEY_b,spawn,{.v=br}},{MODKEY,XKB_KEY_q,killclient,{0}},{MODKEY,XKB_KEY_j,focusstack,{.i=+1}},{MODKEY,XKB_KEY_k,focusstack,{.i=-1}},{MODKEY,XKB_KEY_h,setmfact,{.f=-0.05f}},{MODKEY,XKB_KEY_l,setmfact,{.f=+0.05f}},{MODKEY,XKB_KEY_w,spawn,{.v=bt}},{MODKEY,XKB_KEY_f,setlayout,{.v=&layouts[2]}},{MODKEY,XKB_KEY_space,setlayout,{0}},
TAGKEYS(XKB_KEY_1,XKB_KEY_exclam,0),TAGKEYS(XKB_KEY_2,XKB_KEY_quotedbl,1),TAGKEYS(XKB_KEY_3,XKB_KEY_numbersign,2),TAGKEYS(XKB_KEY_4,XKB_KEY_dollar,3),TAGKEYS(XKB_KEY_5,XKB_KEY_percent,4),TAGKEYS(XKB_KEY_6,XKB_KEY_ampersand,5),TAGKEYS(XKB_KEY_7,XKB_KEY_slash,6),TAGKEYS(XKB_KEY_8,XKB_KEY_parenleft,7),TAGKEYS(XKB_KEY_9,XKB_KEY_parenright,8),{MODKEY,XKB_KEY_Tab,view,{0}},{MODKEY,XKB_KEY_0,view,{.ui=~0}},
{0,XKB_KEY_XF86AudioRaiseVolume,spawn,{.v=uv}},{0,XKB_KEY_XF86AudioLowerVolume,spawn,{.v=dv}},{0,XKB_KEY_XF86AudioMute,spawn,{.v=mv}},{0,XKB_KEY_XF86MonBrightnessUp,spawn,{.v=bu}},{0,XKB_KEY_XF86MonBrightnessDown,spawn,{.v=bd}},{0,XKB_KEY_Print,spawn,{.v=ss}},{MODKEY|WLR_MODIFIER_SHIFT,XKB_KEY_E,quit,{0}}};
static const Button buttons[]={{MODKEY,BTN_LEFT,moveresize,{.ui=CurMove}},{MODKEY,BTN_MIDDLE,togglefloating,{0}},{MODKEY,BTN_RIGHT,moveresize,{.ui=CurResize}}};
static const Axis axes[]={{MODKEY,AxisUp,spawn,{.v=uv}},{MODKEY,AxisDown,spawn,{.v=dv}}};
CFG
fi
info "Compilando dwl...";make clean 2>/dev/null ;make||err "Error compilando dwl.";sudo make install

# Compilar dwlb
cd "$HOME";[ -d dwlb ] || git clone https://github.com/kolunmi/dwlb.git;cd dwlb
[ -f config.def.h ] && [ ! -f config.h ] && cp config.def.h config.h
if grep -qE 'zwlr_layer_shell_v1_interface, [0-9]+\)' dwlb.c 2>/dev/null ; then V=$(grep -oE 'zwlr_layer_shell_v1_interface, [0-9]+\)' dwlb.c|head -n1|sed -n 's/.*,[[:space:]]*\([0-9][0-9]*\))$/\1/p');[ -n "$V" ] && [ "$V" -gt 1 ] && sed -i "s|&zwlr_layer_shell_v1_interface, $V)|\&zwlr_layer_shell_v1_interface, (version < $V ? version : $V))|" dwlb.c;fi
make clean 2>/dev/null ;make||err "Error compilando dwlb.";sudo make install
mkdir -p "$HOME/.config/dwlb"
cat > "$HOME/.config/dwlb/config" <<EOF
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
E="89b4fa";T="cdd6f4";A="f38ba8"
while :; do
 V=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null ||echo"");VS="^fg($E)VOL^fg($T) --"
 [ -n "$V" ] && {N=$(echo"$V"|awk '{printf "%d",$2*100}');case "$V" in *MUTED*)VS="^fg($E)VOL^fg($A) mudo";;*)VS="^fg($E)VOL^fg($T) ${N}%";;esac;}
 CPU=$(cut -d' ' -f1 /proc/loadavg);RAM=$(awk '/^MemTotal:/{t=$2}/^MemAvailable:/{a=$2}END{printf "%.1fG",(t-a)/1048576}' /proc/meminfo);D=$(date '+%a %d/%m %H:%M')
 printf'^mm(foot)^fg(%s)CPU^fg(%s) %s ^fg(%s)RAM^fg(%s) %s %s ^lm(foot -e sh -c "cal -3; read x")^fg(%s)%s^fg()^lm()^mm()\n'"$E""$T""$CPU""$E""$T""$RAM""$VS""$T""$D"
 sleep 5
done
STAT
sudo chmod +x /usr/local/bin/dwlb-status
[ "$DWLB_IPC" -eq 1 ] && BM="-ipc"||BM="-no-ipc"

# Runner barra
sudo tee /usr/local/bin/dwl-status-runner >/dev/null <<'RUN'
#!/bin/sh
exec 3<&0;H="";PB=""
clean(){for p in $H;do kill "$p" 2>/dev/null ;done;wait 2>/dev/null ;}
trap clean EXIT
[ -n "$DWL_WALLPAPER" ] && [ -f "$DWL_WALLPAPER" ] && command -v swaybg>/dev/null&&{swaybg -i "$DWL_WALLPAPER" -m fill < /dev/null >/dev/null 2>&1&H="$H $!";}
if [ "$DWL_BAR_MODE"="-ipc" ]; then cat <&3>/dev/null&H="$H $!";dwlb -ipc < /dev/null&else dwlb -no-ipc <&3&fi
PB=$!;H="$H $PB";sleep1;(dwlb-status|dwlb -status-stdin all)< /dev/null >/dev/null 2>&1&H="$H $!";wait"$PB";clean
RUN
sudo chmod +x /usr/local/bin/dwl-status-runner

# Wallpaper
mkdir -p "$(dirname "$WALLPAPER_PATH")"
if [ ! -f "$WALLPAPER_PATH" ]; then T="${WALLPAPER_PATH}.tmp";curl -fsSL --max-time25 -A Mozilla/5.0 -o "$T" https://wallpapercave.com/download/empty-error-wallpapers-wp8330753&&file "$T"|grep -qi image&&mv "$T" "$WALLPAPER_PATH"||rm -f "$T";fi

# Sesion dwl
grep -qw hypervisor /proc/cpuinfo&&VM_FLAGS="export WLR_NO_HARDWARE_CURSORS=1"||VM_FLAGS=""
sudo tee /usr/local/bin/dwl-session >/dev/null <<EOF
#!/bin/sh
export XDG_SESSION_TYPE=wayland XDG_CURRENT_DESKTOP=dwl MOZ_ENABLE_WAYLAND=1 QT_QPA_PLATFORM=wayland GDK_BACKEND=wayland,x11
export DWL_BAR_KIND="dwlb" DWL_BAR_MODE="$BM" DWL_WALLPAPER="$WALLPAPER_PATH"
$VM_FLAGS
SU=\$(id -u)
if [ ! -d "\$XDG_RUNTIME_DIR" ] || [ "\$(stat -c %u "\$XDG_RUNTIME_DIR" 2>/dev/null )"!="\$SU" ]; then R="/run/user/\$SU";if[ ! -d "\$R" ] || [ "\$(stat -c %u "\$R" 2>/dev/null )"!="\$SU" ]; then R="\$HOME/.xdg-runtime";mkdir -p "\$R";chmod700"\$R";fi;export XDG_RUNTIME_DIR="\$R";fi
P="";ud(){n="\$1";shift;pgrep -u "\$SU" -x "\$n">/dev/null&&return0;command -v "\$n">/dev/null&&{"\$@">/dev/null2>&1&P="\$P \$!";};}
clean(){for p in \$P;do kill "$p" 2>/dev/null ;done;wait 2>/dev/null ;}
trap clean EXIT
ud pipewire pipewire;ud wireplumber wireplumber;command -v pipewire-pulse>/dev/null&&ud pipewire-pulse pipewire-pulse
IN=\$(date +%s)
dwl -s /usr/local/bin/dwl-status-runner&DP=\$!;wait"\$DP";ST=\$?
if[ "\$ST" -ne0 ] && [ -z "\$WLR_RENDERER" ] && [ \$((\$(date +%s)-IN)) -lt 5 ]; then echo"Reintento pixman...">&2;export WLR_RENDERER=pixman LIBGL_ALWAYS_SOFTWARE=1;dwl -s /usr/local/bin/dwl-status-runner&DP=\$!;wait"\$DP";fi
clean;exit"\$ST"
EOF
sudo chmod +x /usr/local/bin/dwl-session

# Scripts utilidad
sudo tee /usr/local/bin/dwl-rebuild >/dev/null <<'RB';sudo chmod +x /usr/local/bin/dwl-rebuild
#!/bin/sh;set -e;cd "$HOME/dwl";make clean;make;sudo make install;echo"✅ dwl recompilado."
RB
sudo tee /usr/local/bin/dwlb-rebuild >/dev/null <<'RB';sudo chmod +x /usr/local/bin/dwlb-rebuild
#!/bin/sh;set -e;cd "$HOME/dwlb";make clean;make;sudo make install;echo"✅ dwlb recompilado."
RB
sudo mkdir -p /usr/share/wayland-sessions
sudo tee /usr/share/wayland-sessions/dwl.desktop >/dev/null <<DSK
[Desktop Entry]
Name=dwl
Exec=/usr/local/bin/dwl-session
Type=Application
DesktopNames=dwl
DSK
mkdir -p "$HOME/.config/lf"
cat > "$HOME/.config/lf/lfrc" <<'LFRC'
set ifs "\n"
cmd open ${{ case $(file --mime-type -Lb "$f") in text/*|inode/x-empty)nano $fx;;image/*)setsid -f imv $fx>/dev/null 2>&1;;video/*|audio/*)setsid -f mpv $fx>/dev/null 2>&1;;application/pdf)setsid -f zathura $fx>/dev/null 2>&1;;*)for f in $fx;do setsid -f xdg-open "$f">/dev/null 2>&1;done;;esac }}
LFRC

# ----------------------------------------------------------------
# ESCRIBIR ARCHIVOS DE GREETD - NO TOCAR NINGUN ENLACE DE /var/service AUN
# ----------------------------------------------------------------
info "Escribiendo configuracion de greetd (no se habilita aun para no interrumpir)..."
id -u "$GREETER_USER">/dev/null 2>&1||sudo useradd -r -s /sbin/nologin -d /var/lib/greetd "$GREETER_USER"
sudo usermod -aG tty,video,input "$GREETER_USER"
sudo mkdir -p /var/lib/greetd;sudo chown "$GREETER_USER:$GREETER_USER" /var/lib/greetd 2>/dev/null ;sudo chmod700 /var/lib/greetd
sudo mkdir -p /etc/greetd
sudo tee /etc/greetd/config.toml >/dev/null <<TOML
[terminal]
vt = $GREETD_VT
[default_session]
command = "tuigreet --cmd /usr/local/bin/dwl-session"
user = "$GREETER_USER"
TOML
if [ "$DISTRO_FAMILIA"="void" ]; then
 # Escribir run script SIN crear el enlace aun
 sudo tee /etc/sv/greetd/run >/dev/null <<'RUN'
#!/bin/sh
sleep 3
exec greetd -c /etc/greetd/config.toml
RUN
 sudo chmod +x /etc/sv/greetd/run
 if [ "$NEED_TURNSTILE" -eq 1 ] && [ -f /etc/pam.d/greetd ] && ! grep -q pam_turnstile.so /etc/pam.d/greetd; then echo -e "\nsession optional pam_turnstile.so"|sudo tee -a /etc/pam.d/greetd>/dev/null;fi
else
 # Arch: escribir drop-in systemd sin habilitar aun
 sudo mkdir -p /etc/systemd/system/greetd.service.d
 sudo tee /etc/systemd/system/greetd.service.d/10-wait-ready.conf >/dev/null <<INI
[Unit]
After=systemd-logind.service systemd-user-sessions.service systemd-udev-settle.service plymouth-quit-wait.service
Wants=systemd-logind.service
ExecStartPre=/bin/sleep 2
Conflicts=getty@tty1.service
INI
 sudo ln -sf /usr/lib/systemd/system/greetd.service /etc/systemd/system/autovt@tty1.service 2>/dev/null 
fi

# ----------------------------------------------------------------
# FINAL - NO SE HABILITO NINGUN GREETD AUTOMATICAMENTE, 0 CUELGUES
# ----------------------------------------------------------------
echo;hdr "==========================================";hdr " ✅ install-dwl $VERSION INSTALADO!";hdr "=========================================="
echo
echo " 📦 Distro: ${ID:-unknown}"
echo " 🖋️ Fuentes: wmenu=$WMENU_FONT_SIZE / dwlb=$DWLB_FONT_SIZE"
echo
if [ "$DISTRO_FAMILIA"="void" ]; then
warn "----------------------------------------"
warn " PASO FINAL (hazlo ANTES de reiniciar):"
warn "----------------------------------------"
echo" Ejecuta ESTOS DOS COMANDOS para habilitar greetd:"
echo
echo" sudo rm -f /var/service/agetty-tty1"
echo" sudo ln -sf /etc/sv/greetd /var/service/"
echo
else
warn "----------------------------------------"
warn " PASO FINAL (hazlo ANTES de reiniciar):"
warn "----------------------------------------"
echo" Ejecuta ESTOS DOS COMANDOS para habilitar greetd:"
echo
echo" sudo systemctl mask getty@tty1"
echo" sudo systemctl enable greetd"
fi
echo
warn " Despues escribe: sudo reboot"
warn " Tras reiniciar veras tuigreet directamente en tty1."
echo
info "Atajos: Super+Enter=foot | Super+d=wmenu | Super+q=cerrar | Super+Shift+e=salir"

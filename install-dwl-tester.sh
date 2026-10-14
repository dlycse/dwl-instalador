#!/bin/sh
# ============================================================
# install-dwl v1.0.22 — Wayland con dwl + dwlb (Void + Arch + Fedora + Debian/Ubuntu)
# REGLA DE VERSIONES: cada funcion nueva o problema resuelto sube 0.01
# (1.0.5 -> 1.0.6 -> 1.0.7 ...). Al subir, cambia VERSION abajo y este encabezado.
# VERSION 1.0.22: arreglo: el dwl actual pone el segundo layout en FLOTANTE; ahora se fija en monocle
#   (parche que cubre el codigo nuevo y el antiguo de dwl.c). Super+Space pasa a mosaico <-> monocle.
# VERSION 1.0.21: layouts solo con Super+Space (mosaico <-> monocle). Se quitan Super+M y Super+Shift+T;
#   el segundo layout de dwl arranca en monocle (parche de dwl.c). Super+F sigue maximizando.
# VERSION 1.0.20: foot: la seccion de colores se elige probando foot instalado ([colors-dark] o [colors]).
#   Arch (foot nuevo) daba "[colors]: invalid section name". Afecta a todas las distros por igual.
# VERSION 1.0.19: Super+F alterna maximizar (togglefullscreen) y mosaico, en vez de monocle.
# VERSION 1.0.18: mosaico siempre: se quitan los atajos de ventana flotante (Super+Shift+Espacio y
#   Super+clic central) para que las ventanas no se superpongan. Solo cambia la compilacion de dwl.
# VERSION 1.0.17: fix — Fedora/Nobara: foot 1.25+ avisa "[colors]: use [colors-dark]" en cada arranque;
#   en Fedora el foot.ini usa [colors-dark]. Void/Arch/Debian siguen con [colors] (foot 1.21 no lo conoce).
# VERSION 1.0.16: Fedora/Nobara: SDDM lanza 'dwl' por nombre; el binario real pasa a dwl-bin
#   y 'dwl' es un envoltorio que ejecuta dwl-session. El runner escribe log en ~/.cache/dwl-runner.log.
#   Solo afecta a Fedora/Nobara: Void, Arch y Debian siguen igual.
# VERSION 1.0.15: fix — Nobara (ID=nobara, ID_LIKE=fedora) no era reconocido; ahora es familia fedora.
# VERSION 1.0.14: fix — wallpaperaccess.com da 403 en algunas redes (VirtualBox). Respaldo en
#   Wikimedia Commons (CC BY-SA 4.0), valida JPEG/PNG y anota el origen en .wallpaper-instalador.
# VERSION 1.0.13: fix — wlroots 0.20 compilaba SIN backend DRM (dwl: "disabled at compile-time")
#   porque Ubuntu 24.04 / Mint 22 trae libdisplay-info 0.1.1 (wlroots pide >= 0.2.0). Ahora se
#   compila libdisplay-info 0.2.0 desde fuente si el sistema no lo cumple.
# VERSION 1.0.12: sin tuigreet en la distro (Ubuntu 24.04 / Mint) no se configura greetd;
#   se conserva el gestor de sesion que ya hay.
# VERSION 1.0.11: fixes para Mint/Ubuntu: meson >= 1.4 (ensure_meson), espera al candado de apt
#   (APT_LOCK) y solo se piden paquetes con candidato instalable (apt_disponible).
# VERSION 1.0.8: fix — foot 1.21 (Debian 13) no conoce [colors-dark] ni alpha-mode:
#   se usa [colors] y solo alpha. Validado con foot --check-config.
# VERSION 1.0.7: fix — wayland necesita libxml2 (dtd_validation, por defecto activo):
#   se anade libxml2-dev/-devel/libxml2 y libudev-dev en Debian (lo pide libdrm).
# VERSION 1.0.6: si ya hay un gestor de sesion (lightdm, gdm, sddm...), pregunta
#   si se cambia a greetd + tuigreet o se conserva (por defecto se conserva).
# VERSION 1.0.5: barra con el tag activo marcado (parche IPC de dwl, corregido:
#   focusclient() con 3 argumentos, global IPC sin duplicar y sin el evento
#   focused_geometry que dwlb no conoce). Ver el bloque "Parche IPC" mas abajo.
# ------------------------------------------------------------
# CAMBIO PRINCIPAL RESPECTO A LAS REVISIONES ANTERIORES:
#   TODO lo relacionado con el INICIO DE SESION (usuario greeter,
#   /etc/greetd/config.toml, servicio runit/systemd de greetd,
#   tuigreet, PAM y el arranque del servicio) se ha movido AL
#   FINAL DEL SCRIPT, como ultimo bloque de codigo.
#
#   Motivo: en v1.x greetd se configuraba y se habilitaba en
#   medio del script, antes de que existieran
#   /usr/local/bin/dwl-session y
#   /usr/share/wayland-sessions/dwl.desktop. runit/systemd
#   arrancaba greetd, tuigreet lanzaba una sesion incompleta o
#   moria, y el servicio quedaba "down" / crashlooping.
#
#   Ahora el orden es:
#     1) paquetes  2) kernel  3) servicios base  4) dwl
#     5) dwlb      6) tema + barra  7) wallpaper
#     8) dwl-session  9) rebuilders  10) wayland-sessions
#    11) >>> INICIO DE SESION (greetd/tuigreet) <<<  <- FINAL
#
# CORRECCIONES ACUMULADAS:
#  FIX 1  greetd corre como ROOT (nunca con chpst -u greetd).
#  FIX 2  SIN archivo 'down' y SIN 'sv stop' (v1.0 dejaba el
#         servicio instalado pero jamas arrancado -> tty1 muerto).
#  FIX 3  Kernel dinamico leido con xbps-query.
#  FIX 4  seatd, dbus y turnstiled habilitados en /var/service.
#  FIX 5  Botones de power de tuigreet solo si existe loginctl.
#  FIX 6  (0.9.7) Ruta ABSOLUTA al binario greetd en el 'run' de
#         runit: runit no hereda el PATH del usuario y 'exec
#         greetd' fallaba en silencio -> servicio down permanente.
#  FIX 7  (0.9.7) Servicio de LOG (svlogd) para greetd, para que
#         se pueda ver por que no arranca (/var/log/greetd/current).
#  FIX 8  (0.9.7) Espera activa a que runsvdir cree
#         /var/service/greetd/supervise antes de 'sv start', y
#         verificacion final de que el proceso esta vivo.
#  FIX 9  (0.9.7) Se usa SUDO_USER/HOME real: si ejecutabas el
#         script con sudo, $USER era root y dwl se clonaba en
#         /root y los grupos se daban a root.
#  FIX 10 (0.9.7) pam_turnstile solo se anade si el modulo existe
#         y turnstiled esta habilitado (si no, rompia el login).
#  FIX 11 (0.9.7 rev.2) ¡EL BUG QUE CONGELABA LA PANTALLA!
#         Si ejecutas el script desde tty1, tu shell ES el proceso
#         supervisado agetty-tty1 (agetty -> login -> tu shell, mismo
#         PID). 'sv force-stop agetty-tty1' = SIGKILL a tu propia
#         sesion: el script moria y tty1 quedaba muerto (sin agetty
#         y sin greetd). Ahora se detecta el tty/sesion y, si es
#         peligroso, NO se toca /var/service: el cambio se programa
#         en /etc/rc.shutdown y se aplica al reiniciar.
#  FIX 12 (0.9.7 rev.2) sudo -v al inicio + keep-alive en segundo
#         plano (la credencial caduca durante el 'make' de dwl/dwlb)
#         y 'timeout' en las llamadas a sv/systemctl para que nunca
#         se quede colgado esperando una password invisible.
#  FIX 13 (0.9.7 rev.3) Arch: wlroots se DETECTA en los repos
#         (wlroots0.20 / 0.19 / 0.18...). El nombre fijo
#         'wlroots0.19' desaparecio y pacman abortaba TODA la
#         instalacion por ese unico paquete.
#  FIX 14 (0.9.7 rev.3) Arch: la lista se filtra con 'pacman -Si',
#         se instala en lote y, si falla, uno a uno (+ AUR con
#         yay/paru). Ningun paquete perdido tumba la instalacion.
#  FIX 15 (0.9.7 rev.3) dwl trae "wlroots-0.20" escrito a fuego en
#         config.mk: se detecta el pkg-config real del sistema y se
#         parchea, asi compila igual con 0.19, 0.20 o la que venga.
# ============================================================
set +e

VERSION="1.0.22"
BUILD="estable (tags en la barra + anti wlroots-fantasma + anti tty1-kill)"

TIMEOUT_BIN="$(command -v timeout 2>/dev/null || true)"
# sudo con red de seguridad: si algo se cuelga (p.ej. pidiendo password),
# se mata a los 25 s en vez de esperar para siempre.
srun(){ if [ -n "$TIMEOUT_BIN" ]; then "$TIMEOUT_BIN" 25 sudo "$@"; else sudo "$@"; fi; }

# ---------- Estetica: solo visual, no cambia la logica ----------
# Colores 24-bit solo si la salida es una terminal (en logs/tuberias, texto plano).
if [ -t 1 ]; then
  ESC="$(printf '\033')"
  R="${ESC}[0m"; B="${ESC}[1m"; DIM="${ESC}[2m"
  RED="${ESC}[38;2;255;45;61m"; CYAN="${ESC}[38;2;119;226;242m"
  YEL="${ESC}[38;2;255;214;31m"; GRN="${ESC}[38;2;90;230;130m"; GREY="${ESC}[38;2;120;120;130m"
else
  R=""; B=""; DIM=""; RED=""; CYAN=""; YEL=""; GRN=""; GREY=""
fi
line(){ printf "%s%s%s\n" "$RED" "────────────────────────────────────────────────────────────" "$R"; }
# hdr TITULO: caja cyan de ancho fijo. El titulo va en ASCII (sin tildes)
# porque en sh ${#var} cuenta bytes y el ancho de la caja depende de eso.
hdr(){
  _pad=$((59 - 13 - ${#1})); [ "$_pad" -lt 1 ] && _pad=1
  printf "\n%s%s  ╔═══════════════════════════════════════════════════════════╗\n" "$CYAN" "$B"
  printf "  ║   ▓▒░  %s  ░▒▓%*s║\n" "$1" "$_pad" ""
  printf "  ╚═══════════════════════════════════════════════════════════╝%s\n" "$R"
}
banner(){
  printf "%s%s" "$RED" "$B"
  cat <<'BANNER'
  █▀▄ █░█░█ █░░
  █▄▀ ▀▄▀▄▀ █▄▄
BANNER
  printf "%s░▒▓ INSTALADOR DE DWL · WAYLAND ▓▒░%s\n" "$CYAN" "$R"
  printf "%s  v%s · %s%s\n" "$GREY" "$VERSION" "$BUILD" "$R"
  printf "%s  by %s%s%s\n" "$GREY" "$CYAN" "dlycse" "$R"
  line
}
info(){ printf "%s▸%s %s\n" "$CYAN" "$R" "$1"; }
warn(){ printf "  %s⚠%s %s\n" "$YEL" "$R" "$1"; }
ok(){   printf "  %s✓%s %s\n" "$GRN" "$R" "$1"; }
err(){  printf "  %s✗%s %s\n" "$RED" "$R" "$1"; exit 1; }
confirm(){
  printf "  %s[?]%s %s [s/N]: " "$CYAN" "$R" "$1"
  read -r ANS
  case "$ANS" in s|S|y|Y|si|SI|yes|YES) return 0;; *) return 1;; esac
}

DWLB_FONT_SIZE=10
KB_LAYOUT="latam"
KB_CONSOLE="la-latin1"

[ -t 1 ] && clear 2>/dev/null
banner
printf "  %sInicio de sesion (greetd/tuigreet) al FINAL%s\n" "$DIM" "$R"

# ---------- FIX 9: usuario y HOME reales (sudo seguro) ----------
REAL_USER="${SUDO_USER:-${USER:-$(id -un)}}"
[ -z "$REAL_USER" ] || [ "$REAL_USER" = "root" ] && REAL_USER="$(id -un 2>/dev/null)"
REAL_HOME="$(getent passwd "$REAL_USER" 2>/dev/null | cut -d: -f6)"
[ -z "$REAL_HOME" ] && REAL_HOME="/home/$REAL_USER"
info "Usuario destino: $REAL_USER   HOME: $REAL_HOME"

# ---------- FIX 12: credencial sudo viva todo el rato ----------
sudo -v || err "Necesitas privilegios de sudo para continuar."
( while :; do sudo -v; sleep 60; done ) >/dev/null 2>&1 &
SUDO_KEEPALIVE=$!
trap 'kill "$SUDO_KEEPALIVE" 2>/dev/null' EXIT INT TERM
ok "Credencial sudo cacheada (se renueva sola durante la compilacion)"

hdr "DETECCION DEL SISTEMA"
# ---------- Deteccion de distro ----------
FAMILIA="unknown"
[ -f /etc/os-release ] && . /etc/os-release
case "${ID:-unknown}" in
  void) FAMILIA="void" ;;
  arch|manjaro|endeavouros|garuda|artix|archcraft|cachyos|arcolinux|parabola) FAMILIA="arch" ;;
  fedora|nobara) FAMILIA="fedora" ;;
  devuan) err "Devuan usa sysvinit, no systemd: este instalador no es compatible." ;;
  debian|ubuntu|linuxmint|pop|zorin|elementary|kali|raspbian|neon|mx) FAMILIA="debian" ;;
  *) case "${ID_LIKE:-}" in *arch*) FAMILIA="arch" ;; *void*) FAMILIA="void" ;; *debian*|*ubuntu*) FAMILIA="debian" ;; *fedora*) FAMILIA="fedora" ;; esac ;;
esac
[ "$FAMILIA" = "unknown" ] && err "Solo compatible con Void Linux, Arch Linux, Fedora y Debian/Ubuntu (y derivadas)."
info "Distro detectada: ${ID:-unknown} (familia: $FAMILIA)"
# ---------- wlroots: se busca en los repos de CADA distro ----------
# dwl necesita la serie wlroots 0.20 (wlroots-0.20). En cada distro se busca
# primero la 0.20.x mas reciente de sus repos (wlr_repo_check). Si no existe,
# se compila la 0.20.x mas reciente desde fuente (build_wlroots_fuente).
# Nunca se fija una version para una distro concreta.
WLR_SERIE="0.20"
WLR_MODO=""          # repo = viene de los repos de la distro; fuente = se compila
WLR_REPO_VER=""
wlr_repo_check(){
  WLR_REPO_VER=""
  case "$FAMILIA" in
    debian) WLR_REPO_VER="$(apt-cache policy "libwlroots-$WLR_SERIE-dev" 2>/dev/null | awk '/Candidat/{print $2; exit}')" ;;
    fedora) WLR_REPO_VER="$(dnf list --available wlroots-devel 2>/dev/null | awk '/^wlroots-devel\./{print $2; exit}')" ;;
    arch)   WLR_REPO_VER="$(pacman -Si "wlroots$WLR_SERIE" 2>/dev/null | awk -F': ' '/^Versi/{print $2; exit}')" ;;
    void)   WLR_REPO_VER="$(xbps-query -R "wlroots$WLR_SERIE-devel" -p pkgver 2>/dev/null | sed "s/^wlroots$WLR_SERIE-devel-//")" ;;
  esac
  case "$WLR_REPO_VER" in
    "$WLR_SERIE".*) return 0 ;;
  esac
  WLR_REPO_VER=""
  return 1
}
# Ultima 0.20.x publicada en el repositorio upstream (tags de wlroots).
# Si no hay red, se usa 0.20.2 (la ultima comprobada).
wlr_ultima_tag(){
  _t="$(git ls-remote --tags --refs https://gitlab.freedesktop.org/wlroots/wlroots.git 2>/dev/null \
        | sed -n "s|.*refs/tags/\(${WLR_SERIE}\.[0-9][0-9]*\)\$|\1|p" | sort -V | tail -n1)"
  printf '%s' "${_t:-0.20.2}"
}
if [ "$FAMILIA" = "debian" ]; then
  [ -d /run/systemd/system ] || err "Este instalador necesita systemd (tu sistema no lo usa)."
  info "Actualizando indice de APT..."
  sudo apt-get $APT_LOCK update -qq >/dev/null 2>&1 || warn "apt-get update reporto errores (revisa la red)"
fi

# ---------- Espacio libre ----------
FREE_GB="$(df -BG --output=avail / 2>/dev/null | tail -n1 | tr -dc '0-9')"
if [ -n "$FREE_GB" ] && [ "$FREE_GB" -lt 20 ]; then
  warn "Solo quedan ${FREE_GB} GB libres en / (se recomiendan 20 GB)."
  confirm "Continuar igualmente?" || err "Cancelado. Libera espacio y vuelve a intentarlo."
else
  ok "Espacio libre: ${FREE_GB:-desconocido} GB"
fi

hdr "CONFIGURACION"
# ---------- Teclado ----------
echo
printf "  %sSelecciona distribucion de teclado:%s\n" "$B" "$R"
printf "    %s1%s) us    %s2%s) es    %s3%s) latam\n" "$CYAN" "$R" "$CYAN" "$R" "$CYAN" "$R"
printf "  %sOpcion [3]:%s " "$CYAN" "$R"; read -r KB; KB="${KB:-3}"
case "$KB" in
  1) KB_LAYOUT="us"; KB_CONSOLE="us" ;;
  2) KB_LAYOUT="es"; KB_CONSOLE="es" ;;
  *) KB_LAYOUT="latam"; KB_CONSOLE="la-latin1" ;;
esac
ok "Teclado seleccionado: $KB_LAYOUT"

# ---------- Zona horaria ----------
echo
printf "  %s[?]%s Pais (ejemplo: Mexico, Paraguay, Bolivia, etc.) %s[vacio = America/Bogota]%s: " "$CYAN" "$R" "$GREY" "$R"; read -r TZIN
TZIN="${TZIN:-America/Bogota}"
resolv_tz(){
  case "$1" in
    [Cc]olombia)                              echo "America/Bogota" ;;
    [Mm]exico|[Mm]éxico)                      echo "America/Mexico_City" ;;
    [Aa]rgentina)                             echo "America/Buenos_Aires" ;;
    [Ee]spana|[Ee]spaña|[Ss]pain)             echo "Europe/Madrid" ;;
    [Cc]hile)                                 echo "America/Santiago" ;;
    [Pp]eru|[Pp]erú)                          echo "America/Lima" ;;
    [Ee]cuador)                               echo "America/Guayaquil" ;;
    [Vv]enezuela)                             echo "America/Caracas" ;;
    [Uu]ruguay)                               echo "America/Montevideo" ;;
    [Bb]olivia)                               echo "America/La_Paz" ;;
    [Pp]araguay)                              echo "America/Asuncion" ;;
    [Gg]uatemala)                             echo "America/Guatemala" ;;
    [Cc]uba)                                  echo "America/Havana" ;;
    [Cc]osta[Rr]ica)                          echo "America/Costa_Rica" ;;
    [Pp]anama|[Pp]anamá)                      echo "America/Panama" ;;
    [Rr]epublica[Dd]ominicana)                echo "America/Santo_Domingo" ;;
    [Ee]stados[Uu]nidos|[Uu][Ss][Aa])         echo "America/New_York" ;;
    *)  # o lo busca tal cual en el arbol zoneinfo
        if [ -f "/usr/share/zoneinfo/$1" ]; then echo "$1"
        else find /usr/share/zoneinfo -type f 2>/dev/null | grep -i "/$1\$" | head -n1 | sed 's|.*/zoneinfo/||'; fi ;;
  esac
}
TZONE="$(resolv_tz "$TZIN")"
if [ -n "$TZONE" ] && [ -f "/usr/share/zoneinfo/$TZONE" ]; then
  sudo ln -sf "/usr/share/zoneinfo/$TZONE" /etc/localtime
  if [ "$FAMILIA" = "void" ]; then
    if grep -q '^TIMEZONE=' /etc/rc.conf 2>/dev/null; then
      sudo sed -i "s|^TIMEZONE=.*|TIMEZONE=\"$TZONE\"|" /etc/rc.conf
    else
      echo "TIMEZONE=\"$TZONE\"" | sudo tee -a /etc/rc.conf >/dev/null
    fi
    [ -d /etc/sv/chronyd ] && { sudo ln -sfn /etc/sv/chronyd /var/service/; sudo sv start chronyd >/dev/null 2>&1; }
  else
    sudo timedatectl set-timezone "$TZONE" 2>/dev/null || true
    sudo systemctl enable --now chronyd.service >/dev/null 2>&1 || sudo systemctl enable --now chrony.service >/dev/null 2>&1 || true
  fi
  ok "Zona horaria: $TZONE"
else
  warn "No encontre la zona '$TZIN'; se deja la que ya tenias"
fi

# Un paquete es "disponible" si tiene candidato instalable. Ojo: apt-cache show puede
# mostrar un paquete sin candidato (firefox-esr en Mint); eso no es disponible.
apt_disponible(){
  _c="$(apt-cache policy "$1" 2>/dev/null | awk '/Candidat|Candidate/{print $2; exit}')"
  [ -n "$_c" ] && [ "$_c" != "(ninguno)" ] && [ "$_c" != "(none)" ]
}

# ---------- Gestor de sesion ya instalado (lightdm, gdm, sddm...) ----------
# Si ya hay uno, se pregunta: cambiarlo a greetd + tuigreet, o dejar el que hay
# (dwl aparece en su menu de sesion). Por defecto (Enter) se deja el que hay.
DM_FOUND=""
for DM in lightdm gdm gdm3 sddm xdm lxdm; do
  if [ -L "/var/service/$DM" ] || [ -f "/usr/lib/systemd/system/$DM.service" ] || command -v "$DM" >/dev/null 2>&1; then
    DM_FOUND="$DM_FOUND $DM"
  fi
done
DM_FOUND="${DM_FOUND# }"
USE_GREETD=1
GREETER_OK=1
if [ "$FAMILIA" = "debian" ] && ! apt_disponible tuigreet; then GREETER_OK=0; fi
if [ "$GREETER_OK" = 0 ]; then
  USE_GREETD=0
  warn "tuigreet no esta en los repos de tu distro (Ubuntu 24.04 y Mint lo no traen): no se configura greetd."
  if [ -n "$DM_FOUND" ]; then
    ok "Se conserva tu gestor de sesion: $DM_FOUND. Elige dwl en su menu."
  else
    warn "No tienes gestor de sesion: instala lightdm o gdm para entrar a dwl."
  fi
elif [ -n "$DM_FOUND" ]; then
  echo
  warn "Ya tienes un gestor de sesion instalado: $DM_FOUND"
  if confirm "Cambiarlo a greetd + tuigreet? (N = dejar $DM_FOUND y elegir dwl en su menu)"; then
    USE_GREETD=1
    info "Se cambiara a greetd + tuigreet (el otro gestor se desactiva, no se desinstala)."
  else
    USE_GREETD=0
    ok "Se mantiene $DM_FOUND. greetd no se configura."
  fi
fi

# ---------- wlroots desde fuente (solo si la distro no trae 0.20.x en sus repos) ----------
# wlroots 0.20.x pide wayland >=1.24, libdrm >=2.4.129, pixman >=0.46, xkbcommon >=1.8
# y wayland-protocols >=1.47. Las distros mas viejas traen versiones mas bajas, asi que
# cada una se comprueba con pkg-config y solo se compila la que no cumple. Las
# dependencias van fijadas por tag; wlroots toma la 0.20.x mas reciente (wlr_ultima_tag).
# Todo va a /usr/local, y PKG_CONFIG_PATH + ld.so.conf lo hacen visible en cualquier distro.
WLR_SRC_DIR=/tmp/dwl-wlroots-src
# apt espera hasta 15 min si otro proceso (gestor de actualizaciones) tiene el candado de dpkg
APT_LOCK="-o DPkg::Lock::Timeout=900"
WLR_LOG=/tmp/dwl-wlroots-build.log
build_meson(){
  _n="$1"; _u="$2"; _t="$3"; shift 3
  info "Compilando $_n $_t..."
  rm -rf "${WLR_SRC_DIR:?}/$_n"
  git clone -q --depth 1 --branch "$_t" "$_u" "$WLR_SRC_DIR/$_n" >>"$WLR_LOG" 2>&1 || return 1
  meson setup "$WLR_SRC_DIR/$_n/build" "$WLR_SRC_DIR/$_n" --prefix=/usr/local --buildtype=release "$@" >>"$WLR_LOG" 2>&1 || return 1
  ninja -C "$WLR_SRC_DIR/$_n/build" >>"$WLR_LOG" 2>&1 || return 1
  # El registro lo escribe el usuario; sudo solo ejecuta la instalacion
  # shellcheck disable=SC2024
  sudo ninja -C "$WLR_SRC_DIR/$_n/build" install >>"$WLR_LOG" 2>&1 || return 1
  ok "$_n $_t instalado en /usr/local"
}
meson_ok(){
  case "$(meson --version 2>/dev/null)" in
    1.[4-9].*|1.[1-9][0-9]*|[2-9].*) return 0 ;;
  esac
  return 1
}
# meson >= 1.4 (libxkbcommon 1.13 lo pide). Si el sistema trae uno viejo (Ubuntu 24.04 / Mint 22: 1.3.2),
# se instala uno nuevo aislado en /opt/dwl-meson y se enlaza en /usr/local/bin. El de apt no se toca.
ensure_meson(){
  if meson_ok; then ok "meson $(meson --version) cumple (>= 1.4)"; return 0; fi
  _mv="$(meson --version 2>/dev/null)"; [ -n "$_mv" ] || _mv="no instalado"
  warn "meson $_mv no sirve: libxkbcommon necesita >= 1.4. Instalo uno nuevo aislado en /opt/dwl-meson..."
  if [ "$FAMILIA" = "debian" ]; then
    sudo DEBIAN_FRONTEND=noninteractive apt-get $APT_LOCK -y install python3-venv >/dev/null 2>&1 || return 1
  fi
  # El registro lo escribe el usuario; sudo solo ejecuta (como en build_meson)
  # shellcheck disable=SC2024
  sudo python3 -m venv /opt/dwl-meson >>"$WLR_LOG" 2>&1 || return 1
  # shellcheck disable=SC2024
  sudo /opt/dwl-meson/bin/pip install -q 'meson>=1.4' >>"$WLR_LOG" 2>&1 || return 1
  sudo ln -sf /opt/dwl-meson/bin/meson /usr/local/bin/meson
  meson_ok || return 1
  ok "meson $(meson --version) instalado en /opt/dwl-meson"
}
build_wlroots_fuente(){
  _wt="$1"
  mkdir -p "$WLR_SRC_DIR"; : > "$WLR_LOG"
  ensure_meson || { warn "No se pudo conseguir meson >= 1.4 (mira $WLR_LOG)"; return 1; }
  # Los .pc de /usr/local no estan en el camino de pkg-config de todas las distros
  PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig:/usr/local/lib/x86_64-linux-gnu/pkgconfig:/usr/local/share/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
  export PKG_CONFIG_PATH
  if ! pkg-config --atleast-version=1.24.0 wayland-server 2>/dev/null; then
    build_meson wayland https://gitlab.freedesktop.org/wayland/wayland.git 1.26.0 \
      -Ddocumentation=false -Dtests=false || return 1
  else ok "wayland $(pkg-config --modversion wayland-server) ya cumple"; fi
  if ! pkg-config --atleast-version=1.47 wayland-protocols 2>/dev/null; then
    build_meson wayland-protocols https://gitlab.freedesktop.org/wayland/wayland-protocols.git 1.49 \
      -Dtests=false || return 1
  else ok "wayland-protocols $(pkg-config --modversion wayland-protocols) ya cumple"; fi
  if ! pkg-config --atleast-version=2.4.129 libdrm 2>/dev/null; then
    build_meson libdrm https://gitlab.freedesktop.org/mesa/drm.git libdrm-2.4.134 \
      -Dtests=false -Dman-pages=disabled -Dvalgrind=disabled -Dinstall-test-programs=false \
      -Dintel=disabled -Dradeon=disabled -Damdgpu=disabled -Dnouveau=disabled -Dvmwgfx=disabled \
      -Dfreedreno=disabled -Dvc4=disabled -Detnaviv=disabled -Dtegra=disabled -Domap=disabled -Dexynos=disabled || return 1
  else ok "libdrm $(pkg-config --modversion libdrm) ya cumple"; fi
  if ! pkg-config --atleast-version=0.46.0 pixman-1 2>/dev/null; then
    build_meson pixman https://gitlab.freedesktop.org/pixman/pixman.git pixman-0.46.4 \
      -Dtests=disabled -Ddemos=disabled || return 1
  else ok "pixman $(pkg-config --modversion pixman-1) ya cumple"; fi
  if ! pkg-config --atleast-version=1.8.0 xkbcommon 2>/dev/null; then
    build_meson libxkbcommon https://github.com/xkbcommon/libxkbcommon.git xkbcommon-1.13.2 \
      -Denable-tools=false -Denable-x11=false -Denable-docs=false -Denable-xkbregistry=false -Denable-wayland=false || return 1
  else ok "xkbcommon $(pkg-config --modversion xkbcommon) ya cumple"; fi
  # wlroots 0.20 solo compila el backend DRM si libdisplay-info >= 0.2.0. Ubuntu 24.04 / Mint 22
  # trae 0.1.1: sin esto wlroots se compila SIN DRM y dwl no abre ("disabled at compile-time").
  if ! pkg-config --atleast-version=0.2.0 libdisplay-info 2>/dev/null; then
    build_meson libdisplay-info https://gitlab.freedesktop.org/emersion/libdisplay-info.git 0.2.0 || return 1
  else ok "libdisplay-info $(pkg-config --modversion libdisplay-info) ya cumple"; fi
  build_meson wlroots https://gitlab.freedesktop.org/wlroots/wlroots.git "$_wt" -Dexamples=false || return 1
  # El enlazador dinamico debe ver /usr/local (las distros no lo incluyen todas)
  printf '/usr/local/lib\n/usr/local/lib64\n' | sudo tee /etc/ld.so.conf.d/dwl-wlroots.conf >/dev/null
  sudo ldconfig
  rm -rf "$WLR_SRC_DIR"
  return 0
}

# Nerd Font para Fedora y Debian: ninguna la empaqueta; se baja la release
# oficial de Nerd Fonts a ~/.local/share/fonts (sin tocarla si ya existe).
nerd_font_github(){
  NF_DIR="$REAL_HOME/.local/share/fonts/JetBrainsMonoNerd"
  if fc-list 2>/dev/null | grep -qi "JetBrainsMono Nerd"; then
    ok "JetBrainsMono Nerd Font ya instalada"
    return 0
  fi
  info "Descargando JetBrainsMono Nerd Font..."
  if curl -fsSL --max-time 180 -o /tmp/JetBrainsMono-nf.zip \
       "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip" \
     && sudo -u "$REAL_USER" mkdir -p "$NF_DIR" \
     && sudo -u "$REAL_USER" unzip -oq /tmp/JetBrainsMono-nf.zip -d "$NF_DIR"; then
    sudo -u "$REAL_USER" fc-cache -f "$NF_DIR" >/dev/null 2>&1
    ok "JetBrainsMono Nerd Font instalada en $NF_DIR"
  else
    warn "No pude instalar la Nerd Font: la barra usara una fuente de respaldo"
  fi
  rm -f /tmp/JetBrainsMono-nf.zip
}

if [ "$FAMILIA" = "void" ]; then
  hdr "PAQUETES - VOID LINUX"
  # ==================== VOID LINUX ====================
  # --- Repositorios extra: nonfree (NVIDIA/Steam) y multilib (32 bits) ---
  # OJO: multilib solo existe en x86_64 con glibc. En musl/aarch64/i686
  # esos paquetes no existen y XBPS fallaria, asi que se comprueba antes.
  if [ "$(uname -m)" = "x86_64" ] && ldd --version 2>/dev/null | grep -qi glibc; then
    info "Activando repositorios nonfree y multilib..."
    sudo xbps-install -Sy void-repo-nonfree void-repo-multilib void-repo-multilib-nonfree \
      || warn "No se pudieron activar los repos extra (continuo sin ellos)"
  else
    info "Sistema sin multilib (musl/aarch64/i686): se instala sin repos extra"
  fi

  # --- wlroots 0.20.x: la de los repos si existe, si no se compila desde fuente ---
  sudo xbps-install -S >/dev/null 2>&1 || warn "No se pudo sincronizar el indice de xbps"
  if wlr_repo_check; then
    WLR_MODO=repo
    ok "wlroots $WLR_REPO_VER en los repos (dwl lo usara)"
    VOID_WLR="wlroots-devel"
    VOID_BUILD=""
  else
    WLR_MODO=fuente
    warn "Tus repositorios no traen wlroots $WLR_SERIE.x: se compilara la $WLR_SERIE.x mas reciente desde fuente. Tarda varios minutos."
    VOID_WLR=""
    # Dependencias de compilacion: las de la plantilla oficial de wlroots0.20 en void-packages
    VOID_BUILD="meson ninja pkg-config libxml2-devel wayland-devel glslang hwids lcms2-devel libgbm-devel libglvnd-devel libseat-devel eudev-libudev-devel libdrm-devel libinput-devel libxkbcommon-devel pixman-devel wayland-protocols vulkan-loader-devel xcb-util-errors-devel xcb-util-wm-devel xcb-util-renderutil-devel libdisplay-info-devel libliftoff-devel libxcb-devel xcb-util-cursor-devel xcb-util-devel xcb-util-image-devel xcb-util-keysyms-devel xcb-util-xrm-devel xorg-server-xwayland"
  fi
  info "Instalando paquetes base para Void Linux..."
  # shellcheck disable=SC2086
  sudo xbps-install -Sy base-devel git libinput-devel wayland-devel wayland-protocols libxkbcommon-devel $VOID_WLR $VOID_BUILD libseat-devel seatd xorg-server-xwayland mesa-dri libdrm-devel pango-devel cairo-devel pixman-devel libgudev-devel fcft-devel tllist foot wmenu fastfetch pipewire wireplumber alsa-pipewire swaybg swaylock grim slurp wl-clipboard brightnessctl curl procps-ng nano nerd-fonts lf mpv zathura zathura-pdf-poppler xdg-utils imv chrony firefox btop cowsay dbus pciutils greetd tuigreet turnstile || err "Fallo instalando paquetes."
  GREETER_USER="greetd"
  SEAT_GROUP="_seatd"

  # ---------- FIX 3: kernel DINAMICO ----------
  echo
  info "--- Actualizacion de kernel ---"
  info "Kernel actual: $(uname -r)"
  if confirm "Buscar e instalar el kernel mas reciente de los repos?"; then
    info "Sincronizando indice de paquetes..."
    sudo xbps-install -S >/dev/null 2>&1
    LATEST_KERN="$(xbps-query -Rs linux 2>/dev/null | grep -oE 'linux[0-9]+\.[0-9]+-' | tr -d '-' | sort -Vu | tail -n1)"
    CURRENT_SERIES="linux$(uname -r | cut -d. -f1,2)"
    if [ -n "$LATEST_KERN" ] && [ "$LATEST_KERN" != "$CURRENT_SERIES" ]; then
      info "Disponible: $LATEST_KERN (tienes: $CURRENT_SERIES)"
      if sudo xbps-install -y "$LATEST_KERN" "${LATEST_KERN}-headers"; then
        ok "Kernel $LATEST_KERN instalado, se activa al reiniciar"
      else
        warn "No se pudo instalar $LATEST_KERN; se mantiene $(uname -r)"
      fi
    elif [ -n "$LATEST_KERN" ]; then
      ok "Ya tienes la serie mas reciente ($CURRENT_SERIES)"
    else
      warn "xbps-query no devolvio kernels; se mantiene $(uname -r)"
    fi
  fi

  # ---------- FIX 4: servicios base de runit ----------
  echo
  info "Habilitando servicios base (dbus, seatd, turnstiled)..."
  for SVC in dbus seatd turnstiled; do
    if [ -d "/etc/sv/$SVC" ]; then
      sudo rm -f "/etc/sv/$SVC/down" "/var/service/$SVC/down"
      sudo ln -sfn "/etc/sv/$SVC" /var/service/
      sudo sv start "$SVC" >/dev/null 2>&1
      ok "Servicio habilitado: $SVC"
    else
      warn "No existe /etc/sv/$SVC (revisa que el paquete este instalado)"
    fi
  done

  # Keymap de consola
  if grep -q '^KEYMAP=' /etc/rc.conf 2>/dev/null; then
    sudo sed -i "s|^.*KEYMAP=.*|KEYMAP=\"$KB_CONSOLE\"|" /etc/rc.conf
  else
    echo "KEYMAP=\"$KB_CONSOLE\"" | sudo tee -a /etc/rc.conf >/dev/null
  fi
  sudo loadkeys "$KB_CONSOLE" 2>/dev/null || true

elif [ "$FAMILIA" = "fedora" ]; then
  hdr "PAQUETES - FEDORA"
  # ==================== FEDORA (dnf + systemd) ====================
  # Nombres comprobados en los indices de Fedora 43 y 44 (base y updates):
  # fcft-devel y tllist-devel son los que pide dwlb; greetd y tuigreet estan
  # en los repos oficiales. wlroots-devel 0.20 solo viene en Fedora 44 (updates,
  # 0.20.2); en Fedora 43 solo hay 0.19, asi que se compila (WLR_MODO=fuente).
  # 'lf' no se encontro en la web de Fedora: si no esta, se avisa abajo.
  info "Instalando paquetes para Fedora..."
  FEDORA_PKGS="gcc make pkgconf-pkg-config git curl unzip fontconfig procps-ng nano pciutils patch perl-interpreter
    wayland-devel wayland-protocols-devel libxkbcommon-devel libinput-devel libseat-devel seatd
    xorg-x11-server-Xwayland mesa-dri-drivers libdrm-devel pango-devel cairo-devel pixman-devel
    libgudev-devel fcft-devel tllist-devel
    foot wmenu fastfetch pipewire wireplumber pipewire-alsa pipewire-pulseaudio
    swaybg swaylock grim slurp wl-clipboard brightnessctl lf mpv zathura zathura-pdf-poppler
    xdg-utils imv chrony firefox btop cowsay dbus-daemon
    greetd greetd-selinux tuigreet jetbrains-mono-fonts"
  # Sin esto, dnf puede leer una cache vieja y no ver la 0.20.2 de updates
  sudo dnf -q makecache >/dev/null 2>&1 || warn "dnf makecache reporto errores (revisa la red)"
  if wlr_repo_check; then
    WLR_MODO=repo
    ok "wlroots $WLR_REPO_VER en tus repositorios (dwl lo usara)"
    FEDORA_PKGS="$FEDORA_PKGS wlroots-devel"
  else
    WLR_MODO=fuente
    warn "Tus repositorios no traen wlroots $WLR_SERIE.x (Fedora 43 trae 0.19): se compilara la $WLR_SERIE.x mas reciente desde fuente. Tarda varios minutos."
    # Dependencias de compilacion (nombres comprobados en el indice de Fedora 43/44)
    FEDORA_PKGS="$FEDORA_PKGS meson ninja-build libffi-devel expat-devel libxml2-devel systemd-devel libglvnd-devel mesa-libEGL-devel mesa-libgbm-devel vulkan-loader-devel vulkan-headers libxcb-devel xcb-util-wm-devel xcb-util-renderutil-devel xcb-util-image-devel xcb-util-errors-devel xcb-util-cursor-devel xcb-util-keysyms-devel xcb-util-devel xcb-util-xrm-devel libdisplay-info-devel libliftoff-devel hwdata libinput-devel libseat-devel libpciaccess-devel bison flex wayland-devel wayland-protocols-devel libxkbcommon-devel libdrm-devel pixman-devel glslang lcms2-devel"
  fi
  # --skip-unavailable: un paquete que no existe en tu version no tumba la instalacion
  # shellcheck disable=SC2086
  sudo dnf install -y --skip-unavailable $FEDORA_PKGS || warn "dnf reporto errores (revisa la salida de arriba)"
  if [ "$WLR_MODO" = repo ]; then
    rpm -q wlroots-devel >/dev/null 2>&1 || err "wlroots-devel no se instalo: dwl no puede compilarse sin el."
  fi
  for p in greetd tuigreet fcft-devel tllist-devel lf; do
    rpm -q "$p" >/dev/null 2>&1 || warn "No se instalo: $p (instalalo a mano o desde un COPR)"
  done

  nerd_font_github

  sudo systemctl enable --now seatd.service 2>/dev/null || true
  sudo systemctl enable --now dbus.service 2>/dev/null || true
  GREETER_USER="greeter"
  SEAT_GROUP="seat"

  # Keymap de consola
  if grep -q '^KEYMAP=' /etc/vconsole.conf 2>/dev/null; then
    sudo sed -i "s|^KEYMAP=.*|KEYMAP=$KB_CONSOLE|" /etc/vconsole.conf
  else
    echo "KEYMAP=$KB_CONSOLE" | sudo tee -a /etc/vconsole.conf >/dev/null
  fi
  sudo loadkeys "$KB_CONSOLE" 2>/dev/null || true

elif [ "$FAMILIA" = "debian" ]; then
  hdr "PAQUETES - DEBIAN / UBUNTU"
  # ==================== DEBIAN Y DERIVADAS (apt + systemd) ====================
  # Nombres comprobados en los indices de Debian forky/sid y Ubuntu 26.10 (stonking).
  # libwlroots-0.20-dev lo trae el repo solo en algunas versiones: se decide abajo
  # (wlr_repo_check). Si no esta, las dependencias de compilacion salen del
  # Build-Depends oficial del paquete wlroots de Debian sid.
  # Firefox: Debian lo da como firefox-esr; Ubuntu solo como snap.
  # seatd de Debian arranca con 'seatd -g video': el grupo de acceso es 'video'.
  # greetd corre como usuario _greetd (lo crea el propio paquete).
  info "Instalando paquetes para Debian/Ubuntu..."
  DEB_PKGS="build-essential git pkgconf patch perl curl unzip fontconfig procps nano pciutils
    libwayland-dev wayland-protocols libxkbcommon-dev libinput-dev libseat-dev seatd
    xwayland libgl1-mesa-dri libdrm-dev libpango1.0-dev libcairo2-dev libpixman-1-dev
    libgudev-1.0-dev libfcft-dev libtllist-dev
    foot wmenu fastfetch pipewire wireplumber pipewire-alsa pipewire-pulse
    swaybg swaylock grim slurp wl-clipboard brightnessctl lf mpv zathura zathura-pdf-poppler
    xdg-utils imv chrony firefox-esr btop cowsay dbus-daemon
    greetd tuigreet fonts-jetbrains-mono"
  if wlr_repo_check; then
    WLR_MODO=repo
    ok "wlroots $WLR_REPO_VER en tus repositorios (dwl lo usara)"
    DEB_PKGS="$DEB_PKGS libwlroots-$WLR_SERIE-dev"
  else
    WLR_MODO=fuente
    warn "Tus repositorios no traen wlroots $WLR_SERIE.x: se compilara la $WLR_SERIE.x mas reciente desde fuente. Tarda varios minutos."
    # Build-Depends de wlroots (Debian sid) + lo que piden wayland, libdrm, pixman y xkbcommon
    DEB_PKGS="$DEB_PKGS meson ninja-build pkgconf libffi-dev libexpat1-dev libxml2-dev libudev-dev libsystemd-dev libcap-dev libegl-dev libegl1-mesa-dev libgbm-dev libgles2-mesa-dev libvulkan-dev libcairo2-dev libpng-dev liblcms2-dev glslang-tools hwdata libdisplay-info-dev libliftoff-dev libinput-dev libseat-dev libpciaccess-dev bison flex libx11-xcb-dev libxcb1-dev libxcb-composite0-dev libxcb-dri3-dev libxcb-errors-dev libxcb-ewmh-dev libxcb-icccm4-dev libxcb-image0-dev libxcb-present-dev libxcb-render-util0-dev libxcb-render0-dev libxcb-res0-dev libxcb-shm0-dev libxcb-xfixes0-dev libxcb-xinput-dev libxkbcommon-dev libwayland-dev xwayland"
  fi
  # Solo se piden los paquetes con candidato instalable en tu version (apt_disponible)
  DEB_OK=""; DEB_NO=""
  for p in $DEB_PKGS; do
    if apt_disponible "$p"; then DEB_OK="$DEB_OK $p"; else DEB_NO="$DEB_NO $p"; fi
  done
  [ -n "$DEB_NO" ] && warn "No estan en los repos de tu version, se omiten:$DEB_NO"
  # 1º intento: todo junto (rapido). Si falla: uno a uno (robusto), como en Arch.
  # shellcheck disable=SC2086
  if ! sudo DEBIAN_FRONTEND=noninteractive apt-get $APT_LOCK install -y $DEB_OK; then
    warn "apt no pudo instalar todo junto: reintento uno a uno"
    for p in $DEB_OK; do
      sudo DEBIAN_FRONTEND=noninteractive apt-get $APT_LOCK install -y "$p" >/dev/null 2>&1 || warn "No se pudo instalar: $p"
    done
  fi
  if [ "$WLR_MODO" = repo ]; then
    dpkg -s "libwlroots-$WLR_SERIE-dev" >/dev/null 2>&1 || err "libwlroots-$WLR_SERIE-dev no se instalo: dwl no puede compilarse sin el."
  fi
  for p in greetd tuigreet libfcft-dev libtllist-dev; do
    dpkg -s "$p" >/dev/null 2>&1 || warn "No se instalo: $p"
  done

  # Firefox: si apt no lo trae (Ubuntu), se instala como snap
  case " $DEB_OK " in
    *" firefox-esr "*) ;;
    *) if command -v snap >/dev/null 2>&1; then
         if snap list firefox >/dev/null 2>&1; then ok "Firefox (snap) ya instalado"
         else info "Instalando Firefox como snap..."
              sudo snap install firefox >/dev/null 2>&1 || warn "No se pudo instalar Firefox (snap): Super+B no abrira nada"
         fi
       else
         warn "Sin Firefox en apt ni snap: instalalo a mano (Super+B lo abre)"
       fi ;;
  esac

  nerd_font_github

  sudo systemctl enable --now seatd.service 2>/dev/null || true
  sudo systemctl enable --now dbus.service 2>/dev/null || true
  GREETER_USER="_greetd"
  SEAT_GROUP="video"

  # Keymap de consola (systemd lee /etc/vconsole.conf)
  if grep -q '^KEYMAP=' /etc/vconsole.conf 2>/dev/null; then
    sudo sed -i "s|^KEYMAP=.*|KEYMAP=$KB_CONSOLE|" /etc/vconsole.conf
  else
    echo "KEYMAP=$KB_CONSOLE" | sudo tee -a /etc/vconsole.conf >/dev/null
  fi
  sudo loadkeys "$KB_CONSOLE" 2>/dev/null || true

else
  hdr "PAQUETES - ARCH LINUX"
  # ==================== ARCH LINUX ====================
  info "Instalando paquetes para Arch Linux..."
  sudo pacman -Sy --noconfirm archlinux-keyring 2>/dev/null || true

  # Lista SIN wlroots: el nombre cambia cada serie (0.18 -> 0.19 -> 0.20...)
  ARCH_PKGS="base-devel git libinput wayland wayland-protocols libxkbcommon seatd xorg-xwayland mesa libdrm pango cairo pixman fcft tllist foot wmenu fastfetch pipewire wireplumber pipewire-alsa pipewire-pulse swaybg swaylock grim slurp wl-clipboard brightnessctl curl procps-ng nano ttf-jetbrains-mono-nerd ttf-nerd-fonts-symbols ttf-nerd-fonts-symbols-mono lf mpv zathura zathura-pdf-poppler xdg-utils imv chrony firefox btop cowsay dbus pciutils greetd greetd-tuigreet"

  # --- wlroots 0.20.x: la de los repos si existe, si no se compila desde fuente ---
  # (wlroots0.20 es el nombre del paquete de Arch en la serie 0.20; 0.19 y 0.18 no sirven a dwl)
  if wlr_repo_check; then
    WLR_MODO=repo
    ok "wlroots $WLR_REPO_VER en los repos (dwl lo usara)"
    ARCH_PKGS="$ARCH_PKGS wlroots$WLR_SERIE"
  else
    WLR_MODO=fuente
    warn "Tus repositorios no traen wlroots $WLR_SERIE.x: se compilara la $WLR_SERIE.x mas reciente desde fuente. Tarda varios minutos."
    # Dependencias de compilacion (nombres comprobados en el indice de Arch core/extra)
    ARCH_PKGS="$ARCH_PKGS meson ninja gcc make pkgconf git libffi expat libxml2 systemd-libs libglvnd mesa vulkan-headers vulkan-icd-loader libxcb xcb-util-wm xcb-util-renderutil xcb-util-image xcb-util-errors xcb-util-cursor xcb-util-keysyms xcb-util-xrm libdisplay-info libliftoff hwdata libinput seatd libpciaccess bison flex wayland wayland-protocols libxkbcommon libdrm pixman xorg-xwayland glslang lcms2"
  fi

  # --- FIX 14: un paquete que ya no existe NO tumba la instalacion ---
  PKG_OK=""; PKG_NO=""
  for p in $ARCH_PKGS; do
    if pacman -Si "$p" >/dev/null 2>&1 || pacman -Q "$p" >/dev/null 2>&1; then
      PKG_OK="$PKG_OK $p"
    else
      PKG_NO="$PKG_NO $p"
    fi
  done
  [ -n "$PKG_NO" ] && warn "No estan en los repos, se omiten:$PKG_NO"

  arch_install(){
    # 1º intento: todo junto (rapido). Si falla: uno a uno (robusto).
    # shellcheck disable=SC2086
    sudo pacman -Sy --needed --noconfirm $PKG_OK ||
    for p in $PKG_OK; do
      sudo pacman -S --needed --noconfirm "$p" >/dev/null 2>&1 || warn "No se pudo instalar: $p"
    done
  }
  if ! arch_install; then
    warn "Reintentando con mirrorlist regenerada..."
    sudo pacman -Sy --noconfirm reflector 2>/dev/null || true
    sudo reflector --latest 20 --sort rate --save /etc/pacman.d/mirrorlist 2>/dev/null || true
    arch_install || true
  fi

  # --- Los que falten se intentan por AUR si hay helper ---
  if [ -n "$PKG_NO" ]; then
    for h in yay paru pikaur aura; do
      if command -v "$h" >/dev/null 2>&1; then
        info "Intentando por AUR con $h:$PKG_NO"
        # shellcheck disable=SC2086
        sudo -u "$REAL_USER" "$h" -S --needed --noconfirm $PKG_NO >/dev/null 2>&1 \
          || warn "El AUR fallo para:$PKG_NO"
        break
      fi
    done
  fi
  sudo systemctl enable --now seatd.service 2>/dev/null || true
  sudo systemctl enable --now dbus.service 2>/dev/null || true
  GREETER_USER="greeter"
  SEAT_GROUP="seat"

  # Keymap de consola
  if grep -q '^KEYMAP=' /etc/vconsole.conf 2>/dev/null; then
    sudo sed -i "s|^KEYMAP=.*|KEYMAP=$KB_CONSOLE|" /etc/vconsole.conf
  else
    echo "KEYMAP=$KB_CONSOLE" | sudo tee -a /etc/vconsole.conf >/dev/null
  fi
  sudo loadkeys "$KB_CONSOLE" 2>/dev/null || true
fi

# ---------- wlroots desde fuente (si los repos de la distro no traian 0.20.x) ----------
if [ "$WLR_MODO" = fuente ]; then
  echo
  WLR_TAG="$(wlr_ultima_tag)"
  info "Ultima wlroots $WLR_SERIE.x upstream: $WLR_TAG. Compilando (varios minutos; registro en $WLR_LOG)..."
  if build_wlroots_fuente "$WLR_TAG"; then
    ok "wlroots $WLR_TAG instalado en /usr/local (es el que usa dwl)"
  else
    tail -n 25 "$WLR_LOG" 2>/dev/null
    err "No se pudo compilar wlroots $WLR_TAG. Mira el registro completo en $WLR_LOG"
  fi
  pkg-config --atleast-version="$WLR_SERIE.0" "wlroots-$WLR_SERIE" 2>/dev/null || err "pkg-config no encuentra wlroots-$WLR_SERIE tras compilarlo."
fi

# ---------- Permisos de usuario ----------
echo
info "Grupos de hardware para $REAL_USER: $SEAT_GROUP, video, input"
sudo usermod -aG "$SEAT_GROUP",video,input "$REAL_USER"
warn "Los grupos se aplican al reiniciar."

hdr "COMPILAR DWL"
# ---------- Compilar dwl ----------
echo
info "Compilando dwl..."
cd "$REAL_HOME" || err "No existe $REAL_HOME"
[ ! -d dwl ] && sudo -u "$REAL_USER" git clone https://codeberg.org/dwl/dwl.git
cd dwl || err "No se pudo entrar en $REAL_HOME/dwl"
[ "$(stat -c %U . 2>/dev/null)" != "$REAL_USER" ] && sudo chown -R "$REAL_USER:$REAL_USER" .
rm -f config.h
cp config.def.h config.h

# ---------- Parcheo de config.h (FIX 16 + atajos del README) ----------
# Se parte SIEMPRE del config.def.h de la version clonada, y cada parche
# se verifica: si el ancla cambia en una version futura de dwl, avisa en
# vez de quedarse mudo (que es lo que pasaba con el layout, FIX 16).
apply_patch(){
  _d="$1"; _e="$2"
  _b="$(cksum < config.h)"
  sed -i "$_e" config.h 2>/dev/null
  _a="$(cksum < config.h)"
  if [ "$_b" != "$_a" ]; then ok "  config.h: $_d"; else warn "  config.h: NO aplicado -> $_d"; fi
}

info "Ajustando config.h de dwl..."
# 1) MODKEY: dwl trae Alt por defecto; aqui pasa a Super (la tecla Windows)
apply_patch "MODKEY Alt -> Super (LOGO)" \
  's/#define MODKEY WLR_MODIFIER_ALT/#define MODKEY WLR_MODIFIER_LOGO/'
# 2) Layout de teclado (FIX 16: dwl actual no trae '.layout = NULL,')
if grep -q '\.layout = NULL,' config.h; then
  apply_patch "layout $KB_LAYOUT" "s/\.layout = NULL,/.layout = \"$KB_LAYOUT\",/"
elif grep -q '\.options = NULL,' config.h; then
  apply_patch "layout $KB_LAYOUT" "s/\.options = NULL,/.options = NULL, .layout = \"$KB_LAYOUT\",/"
else
  warn "  config.h: no encontre donde poner el layout (se usa XKB_DEFAULT_LAYOUT)"
fi
# 3) Lanzador en Super+D (dwl trae Super+P)
apply_patch "lanzador Super+D" 's/XKB_KEY_p,\(.*\)menucmd/XKB_KEY_d,\1menucmd/'
# 3b) Lanzador mas legible: wmenu a 14 pt (por defecto 10)
apply_patch "lanzador wmenu 14 pt" \
  's/static const char \*menucmd\[\] = { "wmenu-run", NULL };/static const char *menucmd[] = { "wmenu-run", "-f", "monospace 14", NULL };/'
# 4) Terminal en Super+Enter (dwl trae Super+Shift+Enter)
apply_patch "terminal Super+Enter" \
  's/MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_Return,\(.*\)/MODKEY,                    XKB_KEY_Return,\1/'
# 5) Cerrar ventana con Super+Q (dwl trae Super+Shift+C)
apply_patch "cerrar Super+Q" \
  's/MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_c,\(.*\)killclient/MODKEY,                    XKB_KEY_q,\1killclient/'
# 6) Super+F = maximizar / restaurar (togglefullscreen, ver keys[] abajo).
#    Ya no se cambia el layout monocle: el atajo alterna con el mosaico.

# 6b) Solo mosaico: se quitan los atajos que alternan ventanas flotantes
#     (teclado Super+Shift+Espacio y raton Super+clic central). Asi las ventanas
#     nunca se superponen. Super+F maximiza y restaura (togglefullscreen).
apply_patch "sin flotantes (quita togglefloating de teclado y raton)" '/togglefloating/d'

# 7) Atajos extra: se insertan AL PRINCIPIO de keys[] (dwl usa la primera
#    coincidencia, asi que ganan a los de por defecto).
KEYS_FILE="$(mktemp 2>/dev/null || echo /tmp/dwl-keys.$$)"
cat > "$KEYS_FILE" <<KEYS
	{ MODKEY,                    XKB_KEY_f,           togglefullscreen, {0} },
	{ MODKEY,                    XKB_KEY_b,           spawn,            SHCMD("firefox &") },
	{ MODKEY,                    XKB_KEY_r,           spawn,            SHCMD("foot -e lf &") },
	{ MODKEY,                    XKB_KEY_t,           spawn,            {.v = termcmd} },
	{ MODKEY,                    XKB_KEY_w,           spawn,            SHCMD("/usr/local/bin/dwlb-toggle") },
	{ MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_w,           spawn,            SHCMD("/usr/local/bin/dwlb-flip") },
	{ MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_f,           togglefullscreen, {0} },
	{ MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_e,           quit,             {0} },
	{ MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_t,           setlayout,        {.v = &layouts[0]} },
KEYS
if grep -q '^static const Key keys\[\] = {' config.h; then
  sed -i "/^static const Key keys\[\] = {/r $KEYS_FILE" config.h
  ok "  config.h: atajos extra (Firefox, lf, barra, salir, tiling)"
else
  warn "  config.h: no encontre el array keys[] (atajos extra omitidos)"
fi
rm -f "$KEYS_FILE"

# 8) Layouts: solo Super+Space. Se quitan Super+M (monocle) y Super+Shift+T (mosaico),
#    y el segundo layout de dwl arranca en monocle, asi Super+Space alterna mosaico <-> monocle.
apply_patch "quita Super+M y Super+Shift+T (solo Super+Space)" '/XKB_KEY_m,.*setlayout/d;/XKB_KEY_t,.*setlayout/d'

# 8) Rueda del raton + Super = volumen (los ejes vienen vacios en dwl)
apply_patch "volumen con Super+rueda" \
  's|^\([[:space:]]*\){ 0, 0, NULL, {0} },|\1{ MODKEY, AxisUp,   spawn, SHCMD("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+") },\n\1{ MODKEY, AxisDown, spawn, SHCMD("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-") },\n\1{ 0, 0, NULL, {0} },|'

# --- FIX 15: casar dwl con el wlroots REAL del sistema ---
# dwl trae 'wlroots-0.20' (o 0.19...) escrito a fuego en config.mk.
# Si tu distro trae otra serie, aqui se ajusta al que este instalado.
WLR_PC=""
for c in wlroots-0.20 wlroots-0.19 wlroots-0.18 wlroots-0.17 wlroots; do
  if pkg-config --exists "$c" 2>/dev/null; then WLR_PC="$c"; break; fi
done
if [ -n "$WLR_PC" ]; then
  ok "pkg-config de wlroots detectado: $WLR_PC"
  sed -i -e "s/wlroots-0\.[0-9]*/$WLR_PC/g" \
         -e "s/--cflags wlroots\([\`)]\| \)/--cflags $WLR_PC\1/g" \
         -e "s/--libs wlroots\([\`)]\| \)/--libs $WLR_PC\1/g" config.mk
else
  warn "pkg-config no encuentra wlroots: dwl casi seguro fallara al compilar"
fi

# --- Parche IPC de dwl (pastilla del tag activo y [] = en la barra) ---
# dwl upstream no tiene IPC: sin el parche dwlb no sabe que tags estan
# activos. Si el parche no aplica o no compila, se sigue sin el (la barra
# arranca con -no-ipc y no marca el tag activo). No detiene la instalacion.
IPC_OK=0
# Herramientas que el parche necesita: si falta una, el parche NO se aplica
# y dwl se compila sin IPC en silencio (pasaba en Fedora sin 'patch').
for c in patch perl awk sed curl; do
  command -v "$c" >/dev/null 2>&1 || warn "Falta '$c': el parche IPC no se podra aplicar (instalalo y vuelve a correr el instalador)"
done
git checkout -q -- Makefile dwl.c config.def.h 2>/dev/null
rm -f protocols/dwl-ipc-unstable-v2.xml dwl.c.rej dwl.c.orig
if curl -fsSL https://codeberg.org/dwl/dwl-patches/raw/branch/main/patches/ipc/ipc.patch -o /tmp/dwl-ipc.patch 2>/dev/null; then
  patch -p1 -N --no-backup-if-mismatch < /tmp/dwl-ipc.patch >/tmp/dwl-ipc.log 2>&1
  # Un bloque (prototipos dwl_ipc_*) no encaja en dwl main: se inserta a mano
  if [ -f dwl.c.rej ]; then
    awk '/^\+static .*dwl_ipc/ { sub(/^\+/, ""); print }' dwl.c.rej > /tmp/dwl-ipc-protos.txt
    if [ -s /tmp/dwl-ipc-protos.txt ] && grep -q '^static Monitor \*dirtomon(enum wlr_direction dir);$' dwl.c; then
      sed -i '/^static Monitor \*dirtomon(enum wlr_direction dir);$/r /tmp/dwl-ipc-protos.txt' dwl.c
      rm -f dwl.c.rej
    fi
  fi
  if [ -f dwl.c ] && grep -q 'dwl_ipc_manager_bind' dwl.c; then
    # El parche original llama a focusclient() con 2 argumentos; dwl main usa 3 (c, layersurface, lift)
    sed -i 's/focusclient(focustop(monitor), 1);/focusclient(focustop(monitor), NULL, 1);/' dwl.c
    # El parche original crea el global IPC dos veces: se deja solo la primera
    awk '/wl_global_create\(dpy, &zdwl_ipc_manager_v2_interface/ { if (seen++) next } { print }' dwl.c > /tmp/dwl-ipc-dwl.c && mv /tmp/dwl-ipc-dwl.c dwl.c
    # El XML del parche trae un evento focused_geometry (indice 10) que dwlb (main) no conoce:
    # dwlb falla con "has no event 10". Se quita del XML y del envio en dwl.c
    sed -i '/<event name="focused_geometry"/,/<\/event>/d' protocols/dwl-ipc-unstable-v2.xml
    perl -0pi -e 's/\tif \(wl_resource_get_version\(ipc_output->resource\) >= ZDWL_IPC_OUTPUT_V2_FULLSCREEN_SINCE_VERSION\) \{\n\t\tzdwl_ipc_output_v2_send_focused_geometry\(.*?\);\n\t\}\n//s' dwl.c
  fi
  if [ ! -f dwl.c.rej ] && grep -q 'dwl_ipc_manager_bind' dwl.c && [ -f protocols/dwl-ipc-unstable-v2.xml ]; then
    IPC_OK=1
  else
    git checkout -q -- Makefile dwl.c config.def.h 2>/dev/null
    rm -f protocols/dwl-ipc-unstable-v2.xml dwl.c.rej dwl.c.orig
    warn "Parche IPC de dwl no aplicado: la barra no marcara el tag activo"
  fi
else
  warn "No pude bajar el parche IPC (sin red?): la barra no marcara el tag activo"
fi

# 9) Super+Space: dwl crea el segundo layout de cada monitor. Upstream actual lo pone en
#    FLOTANTE (layouts[1]); aqui se fija en monocle (layouts[2]). Se cubren las dos formas
#    del codigo (dwl nuevo y antiguo). Si ninguna coincide, el aviso lo dice.
perl -0pi -e 's/m->lt\[1\] = &layouts\[LENGTH\(layouts\) > 1 && r->lt != &layouts\[1\]\];/m->lt[1] = &layouts[2];/; s/m->lt\[0\] = m->lt\[1\] = r->layout;/m->lt[0] = r->layout;\n\tm->lt[1] = \&layouts[2];/' dwl.c
if grep -q 'm->lt\[1\] = &layouts\[2\];' dwl.c; then
  ok "  dwl.c: Super+Space alterna mosaico <-> monocle"
else
  warn "  dwl.c: no encontre donde fijar monocle como segundo layout (Super+Space no alternara)"
fi

make clean 2>/dev/null
if ! make; then
  if [ "$IPC_OK" = 1 ]; then
    warn "dwl con parche IPC no compilo: reintento sin el parche"
    IPC_OK=0
    git checkout -q -- Makefile dwl.c config.def.h 2>/dev/null
    rm -f protocols/dwl-ipc-unstable-v2.xml
    make clean 2>/dev/null
  fi
  make || err "Error compilando dwl. Mira el error de arriba (suele ser wlroots)."
fi
sudo make install
if [ "$FAMILIA" = "fedora" ]; then
  # SDDM lanza 'dwl' por nombre: el binario real pasa a dwl-bin y 'dwl' es un envoltorio
  sudo mv -f /usr/local/bin/dwl /usr/local/bin/dwl-bin
  printf '#!/bin/sh\nexec /usr/local/bin/dwl-session "$@"\n' | sudo tee /usr/local/bin/dwl >/dev/null
  sudo chmod +x /usr/local/bin/dwl
  ok "Fedora: dwl-bin (binario) + dwl (envoltorio para SDDM)"
fi
if [ "$IPC_OK" = 1 ]; then
  sudo mkdir -p /usr/local/share/dwl && sudo touch /usr/local/share/dwl/ipc
  ok "dwl compilado e instalado (con parche IPC: pastilla del tag activo)"
else
  sudo rm -f /usr/local/share/dwl/ipc
  ok "dwl compilado e instalado (sin parche IPC)"
fi

hdr "COMPILAR DWLB"
# ---------- Compilar dwlb ----------
echo
info "Compilando dwlb (barra de estado)..."
cd "$REAL_HOME" || exit 1
[ ! -d dwlb ] && sudo -u "$REAL_USER" git clone https://github.com/kolunmi/dwlb.git
cd dwlb || err "No se pudo entrar en $REAL_HOME/dwlb"
[ "$(stat -c %U . 2>/dev/null)" != "$REAL_USER" ] && sudo chown -R "$REAL_USER:$REAL_USER" .
[ -f config.def.h ] && [ ! -f config.h ] && cp config.def.h config.h
# Parche compatibilidad versiones nuevas de wayland
if grep -qE 'zwlr_layer_shell_v1_interface, [0-9]+\)' dwlb.c 2>/dev/null; then
  V=$(grep -oE 'zwlr_layer_shell_v1_interface, [0-9]+\)' dwlb.c | head -n1 | sed -n 's/.*, *\([0-9]*\))/\1/p')
  [ -n "$V" ] && [ "$V" -gt 1 ] && sed -i "s|&zwlr_layer_shell_v1_interface, $V)|\&zwlr_layer_shell_v1_interface, (version < $V ? version : $V))|" dwlb.c
fi
make clean 2>/dev/null
make
sudo make install
ok "dwlb instalado (el aviso fcft_set_scaling_filter es normal)"

hdr "TEMA DE LA BARRA Y TERMINAL"
# ---------- Tema dwlb ----------
# dwlb NO lee un archivo de config por si mismo: sus opciones van por linea
# de comandos. /usr/local/bin/dwl-status-runner lee este archivo (una opcion
# por linea, '#' = comentario) y se las pasa a dwlb al arrancar.
sudo -u "$REAL_USER" mkdir -p "$REAL_HOME/.config/dwlb"
cat > "$REAL_HOME/.config/dwlb/config" <<EOF
# Tema de la barra (dwlb). Colores RRGGBB o RRGGBBAA (AA = opacidad, bf = 75%).
-font "JetBrainsMono Nerd Font:size=$DWLB_FONT_SIZE"
-vertical-padding 6
-no-bottom
-tags 9 1 2 3 4 5 6 7 8 9
-active-fg-color 1a1b26
-active-bg-color 7dcfff
-occupied-fg-color c0caf5
-occupied-bg-color 3b4261bf
-inactive-fg-color 7f849c
-inactive-bg-color 1a1b26bf
-urgent-fg-color 1a1b26
-urgent-bg-color f7768e
-middle-bg-color 1a1b26bf
-middle-bg-color-selected 1a1b26bf
-status-commands
EOF
sudo chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.config" 2>/dev/null
ok "Tema dwlb escrito en $REAL_HOME/.config/dwlb/config"

# ---------- Terminal foot transparente (como el st de la captura) ----------
sudo -u "$REAL_USER" mkdir -p "$REAL_HOME/.config/foot"
FOOT_INI="$REAL_HOME/.config/foot/foot.ini"
# foot cambio el nombre de la seccion de colores: [colors] (foot antiguo, p. ej. 1.21 de Debian 13)
# -> [colors-dark] (foot nuevo: Fedora 44 avisa, Arch la rechaza como error). En vez de adivinar
# por distro, se pregunta a foot instalado cual acepta. Asi cada distro usa la que entiende.
foot_colors_sec(){
  _t="$(mktemp 2>/dev/null || echo /tmp/foot-probe.$$)"
  printf '[colors-dark]\nbackground=000000\n' > "$_t"
  _out="$(foot --check-config -c "$_t" 2>&1)"; _rc=$?
  rm -f "$_t"
  if [ "$_rc" -eq 0 ] && ! printf '%s' "$_out" | grep -qi 'invalid'; then
    echo "[colors-dark]"
  else
    echo "[colors]"
  fi
}
FOOT_COLORS_SEC="$(foot_colors_sec)"
[ -f "$FOOT_INI" ] && [ ! -f "$FOOT_INI.bak" ] && cp "$FOOT_INI" "$FOOT_INI.bak"
cat > "$FOOT_INI" <<EOF
[main]
font=JetBrainsMono Nerd Font:size=$DWLB_FONT_SIZE

$FOOT_COLORS_SEC
background=1a1b26
foreground=c0caf5
regular0=15161e
regular1=f7768e
regular2=9ece6a
regular3=e0af68
regular4=7aa2f7
regular5=bb9af7
regular6=7dcfff
regular7=a9b1d6
bright0=414868
bright1=f7768e
bright2=9ece6a
bright3=e0af68
bright4=7aa2f7
bright5=bb9af7
bright6=7dcfff
bright7=c0caf5
# Transparencia del fondo: 0 = invisible, 1 = opaco
alpha=0.75
EOF
sudo chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.config" 2>/dev/null
ok "Terminal foot con fondo transparente (alpha 0.75): $FOOT_INI"

# ---------- Estado de la barra ----------
# Bloques entre corchetes, como en la barra de dwm. ^fg(HEX) = color (sintaxis dwlb).
sudo tee /usr/local/bin/dwlb-status >/dev/null <<'STAT'
#!/bin/sh
# Imprime UNA linea de estado y termina. La llama cada 5 s el runner.
C=7dcfff   # cian: corchetes
G=9ece6a   # verde: etiquetas
W=c0caf5   # blanco: valores
blk(){ printf '^fg(%s)[^fg(%s)%s ^fg(%s)%s^fg(%s)] ' "$C" "$G" "$1" "$W" "$2" "$C"; }
V=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | awk '{printf "%d", $2*100}')
BAT=""
for B in /sys/class/power_supply/BAT*; do
  [ -r "$B/capacity" ] || continue
  CAP=$(cat "$B/capacity" 2>/dev/null)
  ST=$(cat "$B/status" 2>/dev/null | cut -c1)
  [ -n "$CAP" ] && BAT="$CAP%$ST" && break
done
CPU=$(cut -d' ' -f1 /proc/loadavg)
RAM=$(awk '/^MemTotal:/{t=$2} /^MemAvailable:/{a=$2} END{printf "%.1fG",(t-a)/1048576}' /proc/meminfo)
D=$(date '+%H:%M %d/%m')
blk CPU "$CPU"
blk RAM "$RAM"
[ -n "$BAT" ] && blk BAT "$BAT"
blk VOL "${V:-0}%"
printf '^fg(%s)%s\n' "$W" "$D"
STAT
sudo chmod +x /usr/local/bin/dwlb-status

hdr "BARRA Y FONDO"
# ---------- Runner barra + wallpaper ----------
sudo tee /usr/local/bin/dwl-status-runner >/dev/null <<'RUN'
#!/bin/sh
# Fondo (swaybg) + barra (dwlb) + estado.
# La barra lee ~/.config/dwlb/config (una opcion por linea; '#' = comentario).
# Con el parche IPC de dwl (/usr/local/share/dwl/ipc) usa -ipc, que marca el
# tag activo; si no, -no-ipc.
# Vigilante: si la barra se cierra (Super+W la oculta) la sesion NO se
# cae: el bucle la relanza en cuanto toque. dwl mata este grupo al salir.
SB=""; PB=""
HIDDEN="$HOME/.cache/dwlb-hidden"
CONF="$HOME/.config/dwlb/config"
clean(){ [ -n "$PB" ] && kill "$PB" 2>/dev/null; [ -n "$SB" ] && kill "$SB" 2>/dev/null; wait 2>/dev/null; }
trap clean EXIT
mkdir -p "$HOME/Pictures" "$HOME/.cache"
if [ -f "$HOME/Pictures/wallpaper.jpg" ] && command -v swaybg >/dev/null; then
  swaybg -i "$HOME/Pictures/wallpaper.jpg" -m fill < /dev/null >/dev/null 2>&1 & SB=$!
fi
# Opciones de dwlb: cada linea del archivo son argumentos
set --
if [ -f "$CONF" ]; then
  while IFS= read -r L || [ -n "$L" ]; do
    case $L in ''|\#*) continue ;; esac
    eval "set -- \"\$@\" $L"
  done < "$CONF"
fi
if [ -f /usr/local/share/dwl/ipc ]; then set -- -ipc "$@"; else set -- -no-ipc "$@"; fi
# Sin -ipc, dwlb lee stdin y SALE si llega a EOF: se mantiene abierto un FIFO
FIFO="$HOME/.cache/dwlb-stdin.$$"
mkfifo "$FIFO" && exec 3<>"$FIFO" && rm -f "$FIFO"
while :; do
  # 1) barra: arriba salvo que este oculta con Super+W
  if [ -f "$HIDDEN" ]; then
    if [ -n "$PB" ]; then kill "$PB" 2>/dev/null; PB=""; fi
  elif [ -z "$PB" ] || ! kill -0 "$PB" 2>/dev/null; then
    dwlb "$@" <&3 & PB=$!
    sleep 1
  fi
  # 2) una linea de estado cada 5 s (dwlb -status la envia a la barra en marcha)
  if [ -n "$PB" ]; then
    dwlb -status all "$(dwlb-status)" 2>/dev/null
  fi
  sleep 5
done
RUN
sudo chmod +x /usr/local/bin/dwl-status-runner

# ---------- Super+W: ocultar/mostrar barra · Super+Shift+W: arriba/abajo ----------
sudo tee /usr/local/bin/dwlb-toggle >/dev/null <<'TOG'; sudo chmod +x /usr/local/bin/dwlb-toggle
#!/bin/sh
# Oculta o muestra la barra. El runner la relanza en ~1 s.
F="$HOME/.cache/dwlb-hidden"
mkdir -p "$HOME/.cache"
if [ -f "$F" ]; then rm -f "$F"; else : > "$F"; pkill -x dwlb 2>/dev/null; fi
exit 0
TOG
sudo tee /usr/local/bin/dwlb-flip >/dev/null <<'FLIP'; sudo chmod +x /usr/local/bin/dwlb-flip
#!/bin/sh
# Mueve la barra arriba/abajo comentando '-no-bottom' en la config.
C="$HOME/.config/dwlb/config"
mkdir -p "$HOME/.config/dwlb"; [ -f "$C" ] || : > "$C"
if grep -q '^[[:space:]]*-no-bottom' "$C"; then
  sed -i 's|^[[:space:]]*-no-bottom|#-no-bottom|' "$C"
elif grep -q '^#-no-bottom' "$C"; then
  sed -i 's|^#-no-bottom|-no-bottom|' "$C"
else
  echo '-no-bottom' >> "$C"
fi
pkill -x dwlb 2>/dev/null
exit 0
FLIP
ok "Scripts de barra: dwlb-toggle (Super+W) y dwlb-flip (Super+Shift+W)"

# ---------- Wallpaper por defecto ----------
sudo -u "$REAL_USER" mkdir -p "$REAL_HOME/Pictures"
# Se descarga si no hay fondo, o si el que hay lo puso este instalador antes
# (marca .wallpaper-instalador). Un fondo que tu copiaste a mano no se toca.
# Fuentes en orden: wallpaperaccess.com da 403 a algunas redes (p. ej. VirtualBox);
# si falla, se usa Wikimedia Commons (CC BY-SA 4.0). Se valida que sea JPEG o PNG.
WALL="$REAL_HOME/Pictures/wallpaper.jpg"
WALL_MARK="$REAL_HOME/Pictures/.wallpaper-instalador"
wallpaper_bajar(){
  rm -f "$WALL.tmp"
  curl -fsSL --max-time 60 -A "$2" -e "$3" -o "$WALL.tmp" "$1" 2>/dev/null || return 1
  [ -s "$WALL.tmp" ] || return 1
  case "$(head -c 4 "$WALL.tmp" | od -An -tx1 | tr -d ' \n')" in
    ffd8ff*|89504e47) return 0 ;;
  esac
  return 1
}
if [ ! -f "$WALL" ] || [ -f "$WALL_MARK" ]; then
  info "Descargando wallpaper por defecto..."
  _origen=""
  if wallpaper_bajar "https://wallpaperaccess.com/download/anime-4k-laptop-8523463" \
      "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36" \
      "https://wallpaperaccess.com/"; then
    _origen="wallpaperaccess.com/download/anime-4k-laptop-8523463"
  elif wallpaper_bajar "https://upload.wikimedia.org/wikipedia/commons/thumb/2/2b/120408_Pheriche_Pano_4k.jpg/1920px-120408_Pheriche_Pano_4k.jpg" \
      "install-dwl/1.0 (wallpaper por defecto)" "https://commons.wikimedia.org/"; then
    _origen="Wikimedia Commons: 120408 Pheriche Pano 4k.jpg, CC BY-SA 4.0 (https://commons.wikimedia.org/wiki/File:120408_Pheriche_Pano_4k.jpg)"
  fi
  if [ -n "$_origen" ]; then
    mv -f "$WALL.tmp" "$WALL"
    printf '%s\n' "$_origen" | sudo -u "$REAL_USER" tee "$WALL_MARK" >/dev/null
    ok "Wallpaper descargado de: $_origen"
  else
    rm -f "$WALL.tmp"
    warn "No se pudo bajar el wallpaper (sin red o bloqueado). Copia una imagen a ~/Pictures/wallpaper.jpg"
  fi
  sudo chown "$REAL_USER:$REAL_USER" "$WALL" "$WALL_MARK" 2>/dev/null
fi

hdr "CHULETA DE ATAJOS"
# ---------- Chuleta de atajos ----------
cat > "$REAL_HOME/Atajos.txt" <<'ATAJ'
================================================
 ATAJOS DE DWL   (instalado por install-dwl)
================================================
 Super = la tecla Windows (⌘ en teclados Mac)

 VENTANAS
   Super + D                Lanzador de aplicaciones (wmenu)
   Super + Enter            Terminal (foot)
   Super + T                Terminal (foot)
   Super + B                Firefox
   Super + R                Gestor de archivos (lf)
   Super + Q                Cerrar la ventana
   Super + J / Super + K    Siguiente / anterior ventana
   Super + H / Super + L    Achicar / agrandar el area maestra
   Super + Shift + F        Pantalla completa

 TAGS (escritorios)
   Super + 1..9             Ir a ese tag
   Super + Shift + 1..9     Mover la ventana a ese tag
   Super + Ctrl + 1..9      Mostrar / ocultar ese tag
   Super + Tab              Volver al tag anterior
   Super + 0                Ver todos los tags a la vez
   Super + , / Super + .    Monitor anterior / siguiente

 LAYOUTS
   Super + F                Maximizar / restaurar la ventana (alterna con mosaico)
   Super + Espacio          Alterna mosaico <-> monocle (unico atajo de layout)

 BARRA
   Super + W                Ocultar / mostrar la barra
   Super + Shift + W        Mover la barra arriba / abajo
   Super + rueda del raton  Subir / bajar el volumen

 SESION
   Super + Shift + E        Cerrar la sesion
   Super + Shift + Q        Cerrar la sesion
   Ctrl + Alt + Backspace   Cerrar la sesion
   Ctrl + Alt + F1..F12     Cambiar de consola (tu salida de emergencia)

 RATON
   Super + clic izquierdo   Mover la ventana
   Super + clic derecho     Redimensionar

------------------------------------------------
 ARCHIVOS Y COMANDOS
   ~/dwl/config.h                 Atajos y colores -> luego: dwl-rebuild
   ~/.config/dwlb/config          Fuente, colores y tags de la barra
   ~/.config/foot/foot.ini        Terminal con fondo transparente
   /usr/local/bin/dwlb-status     Bloques de estado (CPU, RAM, BAT, VOL)
   /usr/local/bin/dwl-session     Lo que arranca con la sesion
   ~/Pictures/wallpaper.jpg       Tu fondo de pantalla
   nano ~/Atajos.txt              Esta chuleta
------------------------------------------------
ATAJ
sudo chown "$REAL_USER:$REAL_USER" "$REAL_HOME/Atajos.txt" 2>/dev/null
ok "Chuleta de atajos en ~/Atajos.txt"

hdr "SESION DWL"
# ---------- Script de sesion dwl ----------
info "Creando script de sesion..."
grep -qw hypervisor /proc/cpuinfo && VM_FLAGS="export WLR_NO_HARDWARE_CURSORS=1 WLR_RENDERER=pixman" || VM_FLAGS=""
# Fedora: SDDM lanza el binario 'dwl' (envoltorio), y el real es dwl-bin. El runner
# escribe su salida en ~/.cache/dwl-runner.log. Las demas distros no cambian.
if [ "$FAMILIA" = "fedora" ]; then
  DWL_EXEC='dwl-bin -s "/usr/local/bin/dwl-status-runner >$HOME/.cache/dwl-runner.log 2>&1"'
else
  DWL_EXEC="dwl -s /usr/local/bin/dwl-status-runner"
fi
sudo tee /usr/local/bin/dwl-session >/dev/null <<EOF
#!/bin/sh
export XDG_SESSION_TYPE=wayland XDG_CURRENT_DESKTOP=dwl MOZ_ENABLE_WAYLAND=1 QT_QPA_PLATFORM=wayland GDK_BACKEND=wayland,x11 XKB_DEFAULT_LAYOUT=$KB_LAYOUT
$VM_FLAGS
if [ ! -d "\$XDG_RUNTIME_DIR" ] || [ "\$(stat -c %u "\$XDG_RUNTIME_DIR" 2>/dev/null)" != "\$(id -u)" ]; then
  export XDG_RUNTIME_DIR="\$HOME/.xdg-runtime"
  mkdir -p "\$XDG_RUNTIME_DIR"; chmod 700 "\$XDG_RUNTIME_DIR"
fi
P=""
start_daemon(){
  name="\$1"; shift
  pgrep -u "\$(id -u)" -x "\$name" >/dev/null && return 0
  command -v "\$name" >/dev/null && { "\$@" >/dev/null 2>&1 & P="\$P \$!"; }
}
clean(){ for p in \$P; do kill "\$p" 2>/dev/null; done; wait 2>/dev/null; }
trap clean EXIT
start_daemon pipewire pipewire
start_daemon wireplumber wireplumber
command -v pipewire-pulse >/dev/null && start_daemon pipewire-pulse pipewire-pulse
$DWL_EXEC
clean
EOF
sudo chmod +x /usr/local/bin/dwl-session
ok "dwl-session creado en /usr/local/bin/dwl-session"

# ---------- Utilidades de recompilacion ----------
sudo tee /usr/local/bin/dwl-rebuild >/dev/null <<'RB'; sudo chmod +x /usr/local/bin/dwl-rebuild
#!/bin/sh
set -e; cd "$HOME/dwl"; make clean; make; sudo make install; echo "dwl recompilado, reinicia sesion."
RB
sudo tee /usr/local/bin/dwlb-rebuild >/dev/null <<'RB'; sudo chmod +x /usr/local/bin/dwlb-rebuild
#!/bin/sh
set -e; cd "$HOME/dwlb"; git pull --ff-only; make clean; make; sudo make install; echo "dwlb recompilado, reinicia sesion."
RB
# Fedora: dwl-rebuild no debe pisar el envoltorio; instala solo el binario en dwl-bin
if [ "$FAMILIA" = "fedora" ]; then
sudo tee /usr/local/bin/dwl-rebuild >/dev/null <<'RB'; sudo chmod +x /usr/local/bin/dwl-rebuild
#!/bin/sh
set -e; cd "$HOME/dwl"; make clean; make; sudo install -m755 dwl /usr/local/bin/dwl-bin; echo "dwl recompilado, reinicia sesion."
RB
fi

# ---------- Entrada de sesion Wayland ----------
sudo mkdir -p /usr/share/wayland-sessions
sudo tee /usr/share/wayland-sessions/dwl.desktop >/dev/null <<DSK
[Desktop Entry]
Name=dwl
Exec=/usr/local/bin/dwl-session
Type=Application
DesktopNames=dwl
DSK
ok "Sesion Wayland registrada: /usr/share/wayland-sessions/dwl.desktop"


# =========================================================================
# =========================================================================
#   BLOQUE FINAL — INICIO DE SESION (greetd + tuigreet)
#   Debe quedar SIEMPRE al final del script: se ejecuta cuando dwl,
#   dwlb, dwl-session y dwl.desktop ya existen. Si se movia antes,
#   tuigreet arrancaba contra una sesion inexistente y greetd caia.
# =========================================================================
# =========================================================================
hdr "INICIO DE SESION"
printf "  %sgreetd / tuigreet · bloque final v%s%s\n" "$DIM" "$VERSION" "$R"

# --- 0) Comprobaciones previas: la sesion tiene que existir YA ---
for f in /usr/local/bin/dwl-session /usr/local/bin/dwl-status-runner /usr/share/wayland-sessions/dwl.desktop; do
  if [ ! -f "$f" ]; then
    err "Falta $f — el bloque de inicio de sesion no puede continuar."
  fi
done
[ -x /usr/local/bin/dwl-session ] || sudo chmod +x /usr/local/bin/dwl-session
ok "Sesion dwl verificada antes de tocar greetd"

# --- 0b) FIX 11: detectar si tocar tty1 nos mataria la sesion ---
# En tty1 tu shell ES el servicio agetty-tty1; pararlo = suicidio.
ON_TTY1=0
CUR_TTY="$(tty 2>/dev/null || true)"
case "$CUR_TTY" in *tty1*) ON_TTY1=1 ;; esac
IN_SESSION=0
if [ -n "${WAYLAND_DISPLAY:-}" ] || [ -n "${DISPLAY:-}" ] || [ -n "${XDG_SESSION_ID:-}" ]; then
  IN_SESSION=1
fi
[ "$ON_TTY1" -eq 1 ] && IN_SESSION=1
DEFERRED=0
if [ "$IN_SESSION" -eq 1 ]; then
  info "Sesion detectada en ${CUR_TTY:-tty?}: greetd se activara en el REINICIO (modo seguro)."
else
  info "Sin sesion en tty1 (${CUR_TTY:-sin tty}): greetd se puede arrancar ahora mismo."
fi

if [ "$USE_GREETD" = 1 ]; then
# --- 0c) Quitar otros gestores de sesion (lightdm, gdm, sddm...) ---
# Si hay sesion en marcha NO se paran: matarian la sesion. En ese caso
# lo hace el helper dwl-enable-greetd en el apagado/arranque.
for DM in lightdm gdm gdm3 sddm xdm lxdm; do
  if [ -L "/var/service/$DM" ] || [ -f "/usr/lib/systemd/system/$DM.service" ] || command -v "$DM" >/dev/null 2>&1; then
    if [ "${IN_SESSION:-0}" -eq 1 ]; then
      warn "Hay $DM instalado: se desactivara al reiniciar (no ahora, para no cortar tu sesion)"
    else
      info "Desactivando $DM (en su lugar se usa greetd)..."
      if [ "$FAMILIA" = "void" ]; then
        sudo sv down "$DM" >/dev/null 2>&1; sudo rm -f "/var/service/$DM"
      else
        sudo systemctl disable --now "$DM.service" >/dev/null 2>&1
      fi
      ok "$DM desactivado (no desinstalado)"
    fi
  fi
done

# --- 1) Binarios del greeter con ruta absoluta (FIX 6) ---
GREETD_BIN=""
for b in /usr/bin/greetd /usr/local/bin/greetd /usr/sbin/greetd; do
  [ -x "$b" ] && GREETD_BIN="$b" && break
done
[ -z "$GREETD_BIN" ] && GREETD_BIN="$(command -v greetd 2>/dev/null)"
[ -z "$GREETD_BIN" ] && err "No se encuentra el binario greetd. Instala el paquete greetd."
info "Binario greetd: $GREETD_BIN"

TUIGREET_BIN=""
for b in /usr/bin/tuigreet /usr/local/bin/tuigreet /usr/bin/agreety; do
  [ -x "$b" ] && TUIGREET_BIN="$b" && break
done
[ -z "$TUIGREET_BIN" ] && TUIGREET_BIN="$(command -v tuigreet 2>/dev/null)"
if [ -n "$TUIGREET_BIN" ]; then
  ok "Greeter: $TUIGREET_BIN"
else
  warn "No se localiza tuigreet; se usara 'tuigreet' a secas (puede fallar con el PATH de runit)"
  TUIGREET_BIN="tuigreet"
fi

# --- 2) Usuario del greeter ---
info "Configurando usuario greeter '$GREETER_USER'..."
id -u "$GREETER_USER" >/dev/null 2>&1 || sudo useradd -r -s /sbin/nologin -d /var/lib/greetd "$GREETER_USER"
sudo usermod -aG tty,video,input "$GREETER_USER"
sudo mkdir -p /var/lib/greetd /etc/greetd
sudo chown "$GREETER_USER:$GREETER_USER" /var/lib/greetd 2>/dev/null
sudo chmod 700 /var/lib/greetd

# --- 3) FIX 5: botones de power solo si hay loginctl ---
if command -v loginctl >/dev/null 2>&1; then
  POWER_FLAGS="--power-shutdown 'loginctl poweroff' --power-reboot 'loginctl reboot'"
  ok "loginctl presente: tuigreet con botones de apagar/reiniciar"
else
  POWER_FLAGS=""
  warn "Sin loginctl (Void sin elogind): tuigreet va sin botones de power"
fi

# --- 4) /etc/greetd/config.toml ---
sudo tee /etc/greetd/config.toml >/dev/null <<TOML
[terminal]
vt = 1

[default_session]
command = "$TUIGREET_BIN --cmd /usr/local/bin/dwl-session --time --remember --asterisks $POWER_FLAGS"
user = "$GREETER_USER"
TOML
sudo chmod 644 /etc/greetd/config.toml
ok "/etc/greetd/config.toml escrito"
printf "%s-------------------------------------------%s\n" "$GREY" "$R"
sudo cat /etc/greetd/config.toml
printf "%s-------------------------------------------%s\n" "$GREY" "$R"

if [ "$FAMILIA" = "void" ]; then

  # --- 5a) FIX 10: pam_turnstile solo si el modulo existe ---
  if [ -f /etc/pam.d/greetd ] && ! grep -q pam_turnstile.so /etc/pam.d/greetd; then
    if ls /usr/lib/security/pam_turnstile.so /usr/lib64/security/pam_turnstile.so >/dev/null 2>&1 \
       && [ -L /var/service/turnstiled ]; then
      printf '\nsession optional pam_turnstile.so\n' | sudo tee -a /etc/pam.d/greetd >/dev/null
      ok "pam_turnstile anadido a /etc/pam.d/greetd"
    else
      warn "pam_turnstile omitido (modulo o turnstiled ausente) para no romper el login"
    fi
  fi

  # --- 6a) FIX 6: servicio runit con ruta ABSOLUTA y sin 'down' ---
  sudo mkdir -p /etc/sv/greetd
  sudo rm -f /etc/sv/greetd/down /var/service/greetd/down
  sudo tee /etc/sv/greetd/run >/dev/null <<RUN
#!/bin/sh
# greetd DEBE correr como ROOT: gestiona VTs, PAM y abre las sesiones.
# v1.0 lo lanzaba con 'chpst -u greetd:greetd' -> moria al instante.
# Se usa ruta ABSOLUTA porque runit NO hereda el PATH de tu usuario:
# con 'exec greetd' a secas el servicio se quedaba down para siempre.
sleep 2
# Autocuracion de tty1: si aun queda un agetty viejo viviendo en tty1,
# se retira su enlace y su proceso (idempotente; no toca tty2..tty6).
rm -f /var/service/agetty-tty1
pkill -f '/usr/bin/agetty.*tty1' 2>/dev/null
sleep 1
exec $GREETD_BIN -c /etc/greetd/config.toml 2>&1
RUN
  sudo chmod 755 /etc/sv/greetd/run

  # --- 7a) FIX 7: servicio de log para poder diagnosticar ---
  if command -v svlogd >/dev/null 2>&1; then
    sudo mkdir -p /etc/sv/greetd/log /var/log/greetd
    sudo tee /etc/sv/greetd/log/run >/dev/null <<'LOG'
#!/bin/sh
mkdir -p /var/log/greetd
exec svlogd -tt /var/log/greetd
LOG
    sudo chmod 755 /etc/sv/greetd/log/run
    ok "Log de greetd en /var/log/greetd/current"
  else
    warn "svlogd no disponible: sin log de greetd (instala 'runit'/'socklog' para tenerlo)"
  fi

  # --- 8a0) Helper idempotente: activar greetd en tty1 ---
  sudo tee /usr/local/sbin/dwl-enable-greetd >/dev/null <<'EN'
#!/bin/sh
# Activa greetd en tty1 y retira agetty-tty1 y otros gestores de sesion.
# Idempotente y silencioso: se ejecuta en el apagado (rc.shutdown),
# en el arranque (rc.local) o a mano.
rm -f /var/service/agetty-tty1
pkill -f '/usr/bin/agetty.*tty1' 2>/dev/null
for dm in lightdm gdm sddm xdm lxdm; do
  rm -f "/var/service/$dm"
  command -v systemctl >/dev/null 2>&1 && systemctl disable "$dm.service" 2>/dev/null
done
sleep 0.5
ln -sfn /etc/sv/greetd /var/service/
exit 0
EN
  sudo chmod 755 /usr/local/sbin/dwl-enable-greetd

  # --- 8a) FIX 11: si hay sesion en marcha, NO se toca /var/service ---
  if [ "$IN_SESSION" -eq 1 ]; then
    # ===== MODO DIFERIDO: no se toca NADA de /var/service =====
    warn "Estas dentro de una sesion (${CUR_TTY:-tty?}): no se toca agetty ni /var/service"
    info "   Motivo: parar agetty-tty1 mataria tu propia sesion y dejaria tty1 muerto."
    info "   Se programa el cambio para que se aplique solo, sin riesgo."
    # Dos ganchos, ambos idempotentes:
    #   /etc/rc.shutdown -> se aplica al apagar/reiniciar
    #   /etc/rc.local    -> red de seguridad si apagas con el boton
    for RC in /etc/rc.shutdown /etc/rc.local; do
      [ -f "$RC" ] || printf '#!/bin/sh\n# Creado por install-dwl\n' | sudo tee "$RC" >/dev/null
      if ! sudo grep -q 'dwl-enable-greetd' "$RC" 2>/dev/null; then
        printf '\n# install-dwl: greetd en tty1 a partir del proximo arranque\n[ -x /usr/local/sbin/dwl-enable-greetd ] && /usr/local/sbin/dwl-enable-greetd\n' | sudo tee -a "$RC" >/dev/null
      fi
      sudo chmod +x "$RC"
    done
    ok "Activacion programada en /etc/rc.shutdown y /etc/rc.local"
    ok "Servicio greetd creado en /etc/sv/greetd y config en /etc/greetd/config.toml"
    DEFERRED=1
  fi

  if [ "$DEFERRED" -eq 0 ]; then
  # ===== MODO ACTIVO (tty2+, ssh, ...): se puede tocar tty1 sin riesgo =====
  info "Paso 1/4: retirando agetty de tty1..."
  srun sv force-stop agetty-tty1 || true
  srun rm -f /var/service/agetty-tty1 || true
  info "Paso 2/4: habilitando greetd en /var/service..."
  srun ln -sfn /etc/sv/greetd /var/service/ || true

  if [ ! -L /var/service/greetd ]; then
    err "No se pudo crear /var/service/greetd"
  fi
  ok "greetd enlazado en /var/service"

  # runsvdir tarda hasta 5 s en crear supervise/
  i=0
  while [ "$i" -lt 40 ]; do
    [ -d /var/service/greetd/supervise ] && break
    i=$((i+1)); sleep 0.5
  done
  if [ -d /var/service/greetd/supervise ]; then
    info "Paso 3/4: arrancando greetd..."
    if pgrep -x greetd >/dev/null 2>&1; then
      # Ya habia un greetd vivo (instalacion anterior): se reinicia para
      # que relea /etc/greetd/config.toml y no queden dos peleando por tty1.
      info "greetd ya estaba en marcha: reiniciando para releer la config..."
      srun sv restart greetd || srun sv start greetd || true
    else
      srun sv start greetd || true
    fi
  else
    warn "runsvdir no ha recogido el servicio todavia (puede que no estes bajo runit)"
  fi

  # verificacion: el proceso tiene que estar vivo
  info "Paso 4/4: verificando que greetd sigue vivo..."
  i=0; GREETD_UP=0
  while [ "$i" -lt 40 ]; do
    if pgrep -x greetd >/dev/null 2>&1; then GREETD_UP=1; break; fi
    i=$((i+1)); sleep 0.5
  done

  echo
  info "Estado del servicio:"
  sudo sv status greetd 2>/dev/null || warn "sv no pudo consultar el estado"

  if [ "$GREETD_UP" -eq 1 ]; then
    ok "greetd esta CORRIENDO (PID: $(pgrep -x greetd | tr '\n' ' '))"
    info "Si estas en tty1 puede aparecer tuigreet ahora mismo. Es normal."
  else
    FINAL_ERROR=1
    warn "greetd NO arranco. Diagnostico:"
    [ -f /var/log/greetd/current ] && { echo "  --- /var/log/greetd/current ---"; sudo tail -n 20 /var/log/greetd/current; echo "  --------------------------------"; }
    echo "  Prueba manual:  sudo sv down greetd; sudo $GREETD_BIN -c /etc/greetd/config.toml"
    echo "  Revisa tambien: dbus/seatd arriba, tty1 libre (sudo /usr/local/sbin/dwl-enable-greetd)"
  fi
  fi   # <- fin del MODO ACTIVO (DEFERRED=0)

else

  # --- 6b) systemd (Arch, Fedora y Debian) ---
  sudo mkdir -p /etc/systemd/system/greetd.service.d
  sudo tee /etc/systemd/system/greetd.service.d/10-wait-ready.conf >/dev/null <<INI
[Unit]
After=systemd-logind.service systemd-user-sessions.service systemd-udev-settle.service plymouth-quit-wait.service
Wants=systemd-logind.service
Conflicts=getty@tty1.service
INI
  sudo systemctl mask getty@tty1 2>/dev/null
  sudo systemctl enable greetd.service 2>/dev/null
  sudo systemctl set-default graphical.target 2>/dev/null
  if [ "${IN_SESSION:-0}" -eq 1 ]; then
    # Mismo criterio que en runit: no reiniciar el gestor de sesion
    # desde dentro de una sesion (mataria la sesion actual).
    warn "Sesion activa: greetd solo se HABILITA (sin restart). Arranca tras el reboot."
    DEFERRED=1
  else
    sudo systemctl enable --now greetd.service 2>/dev/null
    sudo systemctl restart greetd.service 2>/dev/null
    sleep 2
    echo
    info "Estado del servicio:"
    sudo systemctl status greetd.service --no-pager -l 2>/dev/null | head -n 12
    if systemctl is-active --quiet greetd.service; then
      ok "greetd esta activo (systemd)"
    else
      FINAL_ERROR=1
      warn "greetd no esta activo. Mira: journalctl -u greetd -b"
    fi
  fi
fi
else
  # El usuario eligio mantener su gestor: no se toca greetd ni los gestores actuales
  info "Login: greetd no se configura aqui (ver arriba)."
fi

# --- 9) Resumen final ---
hdr "INSTALACION COMPLETA"
printf "\n  %sUNICO PASO RESTANTE:%s\n\n" "$YEL$B" "$R"
printf "      %s%ssudo reboot%s\n\n" "$B" "$YEL" "$R"
if [ "$USE_GREETD" = 0 ]; then
  if [ -n "$DM_FOUND" ]; then
    echo " Mantienes tu gestor de sesion ($DM_FOUND): greetd no se ha tocado."
    echo " Al reiniciar entra con ese gestor y elige 'dwl' en el menu de sesion."
  else
    echo " greetd no se configuro (tuigreet no esta en tu distro) y no hay gestor de sesion."
    echo " Instala lightdm o gdm (sudo apt install lightdm) para entrar a dwl."
  fi
  echo
elif [ "${DEFERRED:-0}" -eq 1 ]; then
  echo " Modo seguro (estabas dentro de una sesion):"
  echo "   * NO se ha tocado agetty ni /var/service para no matar tu sesion."
  echo "   * El cambio se aplica SOLO: al apagar (/etc/rc.shutdown) y,"
  echo "     por si acaso, al arrancar (/etc/rc.local), ambos llamando a"
  echo "     /usr/local/sbin/dwl-enable-greetd"
  echo "   * Al arrancar: agetty-tty1 fuera, greetd en tty1 -> tuigreet."
  echo
  echo " Si queres activarlo YA sin reiniciar, desde tty2+:"
  echo "     sudo /usr/local/sbin/dwl-enable-greetd"
  echo
else
  echo " greetd ya esta habilitado y verificado."
  echo " Tras reiniciar veras tuigreet directamente en tty1."
fi
if [ "$USE_GREETD" = 1 ]; then
echo " Inicia sesion con tu usuario y entras a dwl."
echo
echo " Si NO aparece tuigreet tras el reboot:"
echo "   Void:  sudo sv status greetd"
echo "          sudo tail -n 30 /var/log/greetd/current"
echo "          sudo /usr/local/sbin/dwl-enable-greetd"
echo "   Arch, Fedora y Debian:  systemctl status greetd"
echo "          journalctl -u greetd -b"
echo "   (recuerda: tty2..tty6 siguen con agetty, entra por ahi)"
echo
fi
echo " Atajos:  Super+Enter terminal    Super+d menu"
echo "          Super+q cerrar          Super+w barra on/off"
echo "          Super+Shift+e salir de sesion"
line
[ "${FINAL_ERROR:-0}" -eq 1 ] && err "Revisa los errores de arriba antes de reiniciar."
ok "Instalacion v$VERSION completada. Realiza ${B}sudo reboot${R} para cargar todo sin problema."
rm -rf ~/dwl-instalador
exit 0

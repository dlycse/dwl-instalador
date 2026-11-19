#!/bin/sh
# ============================================================
# dwl-postsetup.sh — se ejecuta DENTRO del rootfs de la ISO (void-mklive, opcion -x).
# Uso (lo llama mklive.sh, no a mano):  dwl-postsetup.sh <ROOTFS>
#
# Hace lo mismo que install-dwl.sh en Void, pero dentro del rootfs:
#   1) compila e instala dwl + dwlb y aplica la configuracion (con install-dwl.sh, en chroot)
#   2) deja greetd + tuigreet en tty1 y quita agetty-tty1
#   3) verifica que estan los binarios
# Como void-installer copia el rootfs entero al disco, lo que quede aqui llega instalado.
# ============================================================
set -eu

ROOT="${1:?falta la ruta del rootfs}"
HERE="${DWL_MKLIVE_DIR:-$(cd "$(dirname "$0")" && pwd)}"
INSTALLER="${DWL_INSTALLER:-$HERE/install-dwl.sh}"

info(){ printf '==> %s\n' "$*"; }
die(){  printf 'ERROR (dwl-postsetup): %s\n' "$*" >&2; exit 1; }

[ -f "$ROOT/etc/os-release" ] || die "no es un rootfs valido: $ROOT"
[ -f "$INSTALLER" ]           || die "no encuentro install-dwl.sh en $INSTALLER"

# ---------- 1) red y pseudo-sistemas dentro del chroot ----------
cp /etc/resolv.conf "$ROOT/etc/resolv.conf" 2>/dev/null || true
for f in dev proc sys; do
  mkdir -p "$ROOT/$f"
  mountpoint -q "$ROOT/$f" || mount --rbind "/$f" "$ROOT/$f" --make-rslave
done

# ---------- 2) shims: en el chroot no hay systemd ni runit en marcha ----------
# install-dwl.sh llama a systemctl/sv/loadkeys para cosas que solo tienen
# sentido en un sistema arrancado. Aqui devuelven 0 y no hacen nada.
SHIMS="$ROOT/usr/local/sbin"
mkdir -p "$SHIMS"
for c in systemctl sv loadkeys; do
  printf '#!/bin/sh\nexit 0\n' > "$SHIMS/$c"
  chmod 755 "$SHIMS/$c"
done

# ---------- 3) instalar dwl + dwlb con install-dwl.sh dentro del chroot ----------
cp "$INSTALLER" "$ROOT/root/install-dwl.sh"
info "Compilando dwl y dwlb dentro de la ISO (tarda varios minutos)..."
# yes '' responde con Enter a todas las preguntas: distribucion latam, zona America/Bogota,
# sin kernel nuevo y sin cambiar de gestor de sesion (no hay otro en la ISO).
yes '' | chroot "$ROOT" /bin/sh -c 'export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; cd /root && sh ./install-dwl.sh' \
  || die "install-dwl.sh fallo dentro del rootfs (mira el log de arriba)"
rm -f "$ROOT/root/install-dwl.sh"

# ---------- 4) servicios: greetd en tty1, sin agetty en tty1 ----------
RUNSV="$ROOT/etc/runit/runsvdir/default"
mkdir -p "$RUNSV"
rm -f "$RUNSV/agetty-tty1"
for s in dbus seatd turnstiled greetd; do
  if [ -d "$ROOT/etc/sv/$s" ]; then
    ln -sfn "/etc/sv/$s" "$RUNSV/$s"
  else
    info "aviso: no existe /etc/sv/$s en la ISO"
  fi
done

# Grupos que el instalador va a asignar al usuario (ver build-iso.sh: _seatd,input)
chroot "$ROOT" /bin/sh -c 'getent group input >/dev/null || groupadd input; getent group _seatd >/dev/null || groupadd -r _seatd' \
  || info "aviso: no pude crear los grupos input/_seatd"

# ---------- 5) verificacion ----------
for f in usr/local/bin/dwl usr/local/bin/dwl-session usr/local/bin/dwlb etc/greetd/config.toml etc/sv/greetd/run; do
  [ -e "$ROOT/$f" ] || die "falta /$f: la instalacion no quedo completa"
done
info "dwl, dwlb, dwl-session y greetd configurados."

# ---------- 6) limpieza de lo temporal ----------
rm -f "$SHIMS/systemctl" "$SHIMS/sv" "$SHIMS/loadkeys"
rmdir "$SHIMS" 2>/dev/null || true
rm -f "$ROOT/etc/resolv.conf"
info "dwl-postsetup terminado."

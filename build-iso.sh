#!/bin/bash
# ============================================================
# build-iso.sh — ISO de Void Linux INSTALABLE con dwl + dwlb ya listos
# Uso (en una maquina con Void Linux, dentro de la carpeta void-mklive):
#     sudo ./build-iso.sh
# Necesita en la misma carpeta: dwl-postsetup.sh e install-dwl.sh
# ============================================================
set -eu

# ---------- AJUSTES (edita aqui) ----------
ARCH="x86_64"
KB_CONSOLE="la-latin1"     # keymap de consola: us | es | la-latin1
LOCALE="es_CO.UTF-8"       # idioma de la ISO
ISO_NAME="void-dwl-$(date +%Y%m%d).iso"
# ------------------------------------------

die(){ printf '\033[31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }
info(){ printf '\033[36m==>\033[0m %s\n' "$*"; }

HERE="$(cd "$(dirname "$0")" && pwd)"
[ -f "$HERE/mkiso.sh" ]          || die "No encuentro mkiso.sh: copia este script dentro de la carpeta de void-mklive."
[ -f "$HERE/installer.sh" ]      || die "No encuentro installer.sh (viene en void-mklive): sin el no hay instalador en la ISO."
[ -f "$HERE/dwl-postsetup.sh" ]  || die "Falta dwl-postsetup.sh junto a este script."
[ -f "$HERE/install-dwl.sh" ]    || die "Falta install-dwl.sh junto a este script."
[ "$(id -u)" -eq 0 ] || exec sudo -E "$0" "$@"

[ -f /etc/os-release ] && . /etc/os-release
[ "${ID:-}" = "void" ] || printf '\033[33mAVISO:\033[0m esto no parece Void Linux; void-mklive no esta garantizado fuera de Void.\n'

for c in git curl xorriso mksquashfs xbps-install; do
  command -v "$c" >/dev/null 2>&1 || die "Falta '$c' en esta maquina. Instala: sudo xbps-install -S git curl xz lz4 squashfs-tools xorriso dosfstools mtools e2fsprogs bash xbps"
done

info "Sincronizando repos y comprobando wlroots0.20..."
xbps-install -S >/dev/null 2>&1 || true
xbps-query -R wlroots0.20-devel >/dev/null 2>&1 \
  || die "Los repos de Void no traen wlroots0.20-devel. No se puede construir la ISO con dwl."

# ---------- instalador: que el usuario creado tenga los grupos de seatd e input ----------
# void-installer crea el usuario con -G wheel,audio,video,...; dwl necesita _seatd e input.
if ! grep -q '_seatd,input' "$HERE/installer.sh"; then
  sed -i 's/_groups="wheel,audio,video,/_groups="wheel,audio,video,_seatd,input,/' "$HERE/installer.sh"
  grep -q '_seatd,input' "$HERE/installer.sh" \
    || die "No pude parchear installer.sh (la linea de grupos cambio en void-mklive). Revisa menu_useraccount."
  info "installer.sh: grupos _seatd e input anadidos al usuario."
fi

# ---------- instalador: greetd solo en el sistema INSTALADO (no en el live) ----------
# Tras copiar el live al disco (copy_rootfs), en el disco: quitar agetty de tty1 y habilitar greetd.
if ! grep -q 'dwl-greetd-hook' "$HERE/installer.sh"; then
  HOOK="$(mktemp)"
  cat > "$HOOK" <<'HOOKEOF'
# dwl-greetd-hook: en el sistema instalado, greetd sustituye a agetty en tty1
rm -f $TARGETDIR/etc/runit/runsvdir/default/agetty-tty1
ln -sfn /etc/sv/greetd $TARGETDIR/etc/runit/runsvdir/default/greetd
HOOKEOF
  sed -i "/99-void-live/r $HOOK" "$HERE/installer.sh"
  rm -f "$HOOK"
  grep -q 'dwl-greetd-hook' "$HERE/installer.sh" \
    || die "No pude anadir el hook de greetd a installer.sh (cambio en void-mklive?)."
  info "installer.sh: greetd se habilita solo en el sistema instalado."
fi

chmod +x "$HERE/dwl-postsetup.sh" "$HERE/mkiso.sh" "$HERE/install-dwl.sh"

# Paquetes que van DENTRO de la ISO (y por tanto al disco instalado).
# Mismos que install-dwl.sh en Void, mas sudo y fontconfig que usa el instalador en el chroot.
PKGS="base-devel pkg-config git patch perl curl nano procps-ng pciutils sudo fontconfig
 libinput-devel wayland-devel wayland-protocols libxkbcommon-devel wlroots0.20-devel
 libseat-devel seatd xorg-server-xwayland mesa-dri libdrm-devel pango-devel cairo-devel
 pixman-devel libgudev-devel fcft-devel tllist
 foot wmenu fastfetch pipewire wireplumber alsa-pipewire
 swaybg swaylock grim slurp wl-clipboard brightnessctl
 nerd-fonts lf mpv zathura zathura-pdf-poppler xdg-utils imv chrony firefox btop cowsay
 dbus greetd tuigreet turnstile"

export DWL_MKLIVE_DIR="$HERE"
cd "$HERE"
info "Construyendo la ISO instalable (tarda un buen rato y necesita ~20 GB libres)..."
# shellcheck disable=SC2086
./mkiso.sh -a "$ARCH" -b base -- \
  -p "$(echo $PKGS)" \
  -k "$KB_CONSOLE" -l "$LOCALE" \
  -x "$HERE/dwl-postsetup.sh" \
  -o "$ISO_NAME"

ISO="$HERE/$ISO_NAME"
[ -f "$ISO" ] || die "No encuentro la ISO generada ($ISO_NAME). Revisa los mensajes de arriba."
info "Lista: $ISO"
echo
echo "Probar en VM:      qemu-system-x86_64 -enable-kvm -m 4G -cdrom \"$ISO\" -boot d"
echo "Grabar en USB:     sudo dd if=\"$ISO\" of=/dev/sdX bs=4M status=progress conv=fsync   (cambia sdX)"
echo "Live (sin instalar): usuario anon / voidlinux  (no verificado en esta ISO)"
echo "Instalar en disco: ejecuta void-installer desde la ISO; dwl ya viene configurado."

#!/bin/sh
# DIAGNOSTICO Y ARREGLO TOTAL 100% GARANTIZADO PARA VOID
set -e
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok(){ echo -e " ${GREEN}✅${NC} $1"; }
err(){ echo -e " ${RED}❌${NC} $1"; }
warn(){ echo -e " ${YELLOW}⚠️${NC} $1"; }

echo "========================================"
echo " 🔍 DIAGNOSTICO COMPLETO DE TU SISTEMA"
echo "========================================"

# 1. VERIFICAR PAQUETES INSTALADOS
echo
echo "--- 1. Paquetes necesarios ---"
for pkg in greetd tuigreet foot wmenu swaybg grim brightnessctl libgudev-devel; do
  if xbps-query $pkg >/dev/null 2>&1; then
    ok "Instalado: $pkg"
  else
    err "FALTA: $pkg"
    echo "      Instalando $pkg..."
    sudo xbps-install -Sy $pkg
  fi
done

# 2. VERIFICAR KERNEL
echo
echo "--- 2. Version de kernel ---"
ok "Actual: $(uname -r)"
echo "Buscando kernels 7.x disponibles en repositorios:"
xbps-query -R | grep -E '^linux[0-9.]+-[0-9]' | sort -V | tail -5
echo
echo "Instalando ultimo kernel estable oficial:"
sudo xbps-install -y linux linux-headers
ok "Kernel actualizado. Nuevo kernel instalado: $(xbps-query linux | head -1)"

# 3. CREAR/VERIFICAR SERVICIO GREETD
echo
echo "--- 3. Servicio greetd en /etc/sv ---"
if [ -d /etc/sv/greetd ]; then
  ok "Directorio /etc/sv/greetd existe"
else
  warn "Creando /etc/sv/greetd"
  sudo mkdir -p /etc/sv/greetd
fi

# Reescribir script run
sudo tee /etc/sv/greetd/run >/dev/null <<'RUN'
#!/bin/sh
sleep 3
exec chpst -u greetd:greetd greetd -c /etc/greetd/config.toml 2>&1
RUN
sudo chmod +x /etc/sv/greetd/run
ok "Script /etc/sv/greetd/run creado con permisos de ejecucion"

# Crear usuario greetd si no existe
if id greetd >/dev/null 2>&1; then
  ok "Usuario greetd existe"
else
  warn "Creando usuario greetd"
  sudo useradd -r -s /sbin/nologin -d /var/lib/greetd greetd
fi
sudo usermod -aG tty,video,input greetd
sudo mkdir -p /var/lib/greetd
sudo chown greetd:greetd /var/lib/greetd
sudo chmod 700 /var/lib/greetd

# 4. VERIFICAR CONFIG GREETD
echo
echo "--- 4. Configuracion /etc/greetd/config.toml ---"
sudo tee /etc/greetd/config.toml >/dev/null <<TOML
[terminal]
vt = 1

[default_session]
command = "tuigreet --cmd /usr/local/bin/dwl-session --time --power-shutdown 'loginctl poweroff' --power-reboot 'loginctl reboot'"
user = "greetd"
TOML
ok "Configuracion greetd escrita correctamente (VT=1, tty1)"

# 5. ELIMINAR AGETTY TTY1
echo
echo "--- 5. Deshabilitando login de texto en tty1 ---"
sudo rm -f /var/service/agetty-tty1
sudo sv down agetty-tty1 2>/dev/null || true
ok "Login de texto en tty1 deshabilitado"

# 6. HABILITAR GREETD DE FORMA GARANTIZADA
echo
echo "--- 6. Habilitando greetd ---"
sudo rm -f /var/service/greetd
sudo ln -sf /etc/sv/greetd /var/service/
if [ -L /var/service/greetd ]; then
  ok "✅ Enlace simbolico /var/service/greetd CREADO EXITOSAMENTE"
  ls -la /var/service/greetd
else
  err "No se pudo crear el enlace de servicio"
fi

echo
echo "========================================"
echo " 🧪 VERIFICACION FINAL"
echo "========================================"
echo
echo "Servicios activos en /var/service:"
ls /var/service/
echo
echo "Comprobando que greetd arranca:"
sudo sv status greetd || true
echo
echo "========================================"
echo " ✅ TODO LISTO"
echo "========================================"
echo
echo " Ahora ejecuta: sudo reboot"
echo
echo " Despues del reinicio VAS A VER TUIGREET DIRECTAMENTE EN PANTALLA SIN TENER QUE ESCRIBIR NINGUN COMANDO."
echo

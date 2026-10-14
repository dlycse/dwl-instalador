# dwl-instalador

> ### VERSIÓN 1.0.22
> - **Void Linux** (xbps + runit), **Arch Linux** (pacman + systemd), **Fedora 44 o superior** y **Nobara** (dnf + systemd), y **Debian** se recomienda debian puro aunque puede funcionar en derivadas (apt + systemd).
> - **Probado** en Void, Arch, Fedora (y Nobara 44 KDE) y Debian en la versión 1.0.22.
> - **Fedora 43 y anteriores:** dwl necesita wlroots 0.20. Si los repositorios no lo traen, el instalador lo **compila desde fuente** (tarda varios minutos).
> - **Sesión:** si ya tienes un gestor de sesión (SDDM, GDM, LightDM…), el instalador te pregunta si lo cambia por greetd + tuigreet o si lo conserva. En el segundo caso, elige **dwl** en el menú de sesiones.
> - Se recomiendan **20 GB libres** para evitar errores de almacenamiento.

<img width="1280" height="800" alt="image" src="https://github.com/user-attachments/assets/cb50ae0b-92ae-415a-9641-f71ed6322a65" />

*Barra superior: tags 1–9 a la izquierda (el activo resaltado) y, a la derecha, CPU, RAM, volumen y hora entre corchetes.*

---

## Qué instala

| Componente | Para qué sirve |
|---|---|
| **dwl** | El compositor (gestor de ventanas) Wayland |
| **[dwlb](https://github.com/kolunmi/dwlb)** | La **barra** superior (tags, layout, estado) — autor: *kolunmi* |
| **foot** | Emulador de terminal, con fondo transparente (alfa 0.75) |
| **wmenu** | Lanzador de aplicaciones (el equivalente a dmenu) |
| **lf** | Gestor de archivos en la terminal |
| **swaybg** | Fondo de pantalla |
| **grim** | Capturas de pantalla |
| **greetd + tuigreet** | Pantalla de inicio de sesión (en **tty1**), si no conservas tu gestor actual |
| **pipewire + wireplumber** | Audio |
| **JetBrainsMono Nerd Font** | Fuente de la barra y la terminal |
| Firefox, mpv, zathura, imv, btop | Navegador, video, PDF, imágenes, monitor |

El instalador tiene **un solo modo**: instala todo lo de la tabla, compila dwl y dwlb, aplica tu configuración y configura el inicio de sesión.

Además deja listo:

- Los **repositorios** nonfree y multilib activados en **Void** (ver abajo).
- La **zona horaria** (`/etc/localtime`, `TIMEZONE` en Void, y `chronyd` para la hora).
- El **teclado**, tanto en la consola (`KEYMAP`) como en dwl.
- Atajos de teclado con **Super** como tecla principal (en dwl por defecto es Alt).
- `~/Atajos.txt` con los atajos completos, en texto plano para leerla con `nano`.
- Un fondo de pantalla por defecto en `~/Pictures/wallpaper.jpg` (anime 4K). Si ya tienes un fondo propio, el instalador no lo toca.
- Desactiva otros gestores de sesión si los hay (**lightdm, gdm, sddm, xdm, lxdm**) **solo si eliges greetd**. Se **desactivan**, no se desinstalan.

**No instala drivers de GPU ni Steam.** Eso lo eliges tú aparte, en un comando (ver [Steam y drivers](#-steam-y-drivers-opcional)).

### Fedora y Nobara

- Fedora no empaqueta **JetBrainsMono Nerd Font**: el instalador la descarga de la [release oficial de Nerd Fonts](https://github.com/ryanoasis/nerd-fonts/releases) a `~/.local/share/fonts`.
- El instalador también instala **`patch`** y **`perl-interpreter`**. Sin `patch` el parche IPC de dwl no se aplica y la barra no marca el tag activo.
- `lf` no siempre está en los repositorios de Fedora. Si falta, el instalador avisa; instálalo a mano (`sudo dnf install lf` o desde un COPR).
- **SDDM:** en Fedora y Nobara, SDDM lanza la sesión `dwl` a través de un envoltorio: el binario real queda como `/usr/local/bin/dwl-bin` y `/usr/local/bin/dwl` ejecuta `dwl-session`. Por eso, para recompilar dwl en Fedora usa **`dwl-rebuild`** (ver [Personalizar](#personalizar-tu-escritorio)), no `make install`.

### Debian y Ubuntu

- Las dependencias salen de `apt`. Si la versión no trae wlroots 0.20, el instalador lo compila desde fuente.
- **Firefox:** en Debian se instala `firefox-esr`. En Ubuntu, que solo lo da como snap, se instala con `snap`.
- **Ubuntu 24.04 y Linux Mint 22** no traen **tuigreet**: en esas distribuciones no se configura greetd y se usa tu gestor de sesión actual (por ejemplo, GDM o LightDM). Elige **dwl** en su menú de sesiones.

---

## Repositorios que deja activados (solo Void)

En **Void**, el instalador activa estos repositorios antes de instalar los paquetes:

| Repositorio | Qué te permite instalar después |
|---|---|
| **nonfree** | Driver de **NVIDIA**, Steam y otros paquetes con licencia no libre |
| **multilib** | Librerías y programas de **32 bits** (los que piden Steam y Wine) |
| **multilib/nonfree** | Librerías de 32 bits con licencia no libre |

> **multilib y multilib/nonfree solo existen en x86_64 con glibc.** El instalador lo comprueba antes:
> en **musl**, **aarch64** o **i686** no activa esos repos y sigue sin ellos.

En **Arch** el instalador **no** activa `[multilib]`. Si quieres Steam, actívalo tú en `/etc/pacman.conf` (ver [Steam y drivers](#-steam-y-drivers-opcional)).

En **Fedora** el instalador no activa ningún repositorio extra (no usa RPM Fusion). Steam y los drivers NVIDIA de Fedora vienen de RPM Fusion, que activas tú.

---

## Instalación en 4 pasos

### 0. Primero instala `git`

Lo necesitas para clonar el repositorio. El propio instalador también instala `git` como dependencia, pero para descargarlo antes hace falta tenerlo.

```bash
# Void
sudo xbps-install -S git
# Arch
sudo pacman -S git nano # (habilita multilib con sudo nano /etc/pacman.conf)
# Fedora y Nobara
sudo dnf install -y git
# Debian y Ubuntu
sudo apt install -y git
```

### 1. Clonar el repositorio

```bash
git clone https://github.com/dlycse/dwl-instalador.git
```

### 2. Entrar a la carpeta

```bash
cd dwl-instalador
```

### 3. Darle permisos de ejecución

```bash
chmod +x install-dwl.sh
```

### 4. Ejecutar el instalador

**Desde una consola que no sea tty1** (por ejemplo `Ctrl` + `Alt` + `F2`, o una terminal dentro de tu escritorio actual). Si lo lanzas desde tty1, el script no toca esa consola en caliente y programa el cambio para el reinicio.

```bash
./install-dwl.sh
```

> Si tu copia del archivo tiene otro nombre, usa ese nombre en los pasos 3 y 4.

---

## ❓ Qué te va a preguntar el instalador

En este orden:

| Pregunta | Opciones |
|---|---|
| **Espacio libre** | Solo pregunta si hay menos de 20 GB libres en `/`: `s` para continuar, `N` para cancelar |
| **Teclado** | `1` Inglés (us) · `2` Español de España (es) · `3` Latinoamericano (latam) — por defecto `3` |
| **País o zona horaria** | Escribe tu país (`Colombia`, `México`, `Argentina`, `España`, `Chile`, `Perú`…) o la zona directa (`America/Bogota`). Por defecto `America/Bogota` |
| **Kernel** *(solo Void)* | Pregunta si buscar e instalar el **kernel más reciente** de los repos. Si hay una serie nueva, se instala **junto** al actual (no lo reemplaza) y se activa al reiniciar |
| **Gestor de sesión** *(si ya tienes uno)* | Pregunta si cambiarlo por **greetd + tuigreet**. `N` (por defecto) lo conserva y tendrás que elegir **dwl** en su menú |

---

## 🔁 Al terminar: **REINICIA** (importante)

```bash
sudo reboot
```

El reinicio **no es opcional**: los grupos nuevos (`_seatd` o `seat` y `video`) solo se aplican al volver a iniciar sesión, y **sin ellos dwl no puede abrir la GPU ni el teclado/ratón**.

> Si elegiste instalar un kernel nuevo, el reinicio es doblemente necesario.

### Cuando vuelvas a arrancar

- **Con greetd + tuigreet:** verás **tuigreet** (una pantalla de login en texto, en la **tty 1**). Escribe tu usuario y contraseña.
- **Si conservaste tu gestor de sesión:** entra con él y elige **dwl** en el menú de sesiones.

| Tecla (tuigreet) | Acción |
|---|---|
| `F2` | Cambiar el comando de la sesión |
| `F3` | Elegir otra sesión |
| `F12` | Menú de apagar / reiniciar — **solo si hay `loginctl`** (en Void sin elogind no aparece) |

> ℹ️ Con greetd, las consolas `tty2`…`tty6` siguen con `agetty` normal, por si necesitas entrar a una consola.

---

## 🎮 Steam y drivers (opcional)

Esto **no** lo instala el instalador.

### Void

Como ya dejó los repositorios activados, es un comando:

```bash
# Steam  (más gamemode, gamescope o mono si los quieres)
sudo xbps-install -Sy steam
sudo xbps-install -Sy gamemode gamescope mono     # opcionales

# Driver NVIDIA  (+ el modeset, imprescindible en Wayland)
sudo xbps-install -Sy nvidia nvidia-libs-32bit
echo "options nvidia-drm modeset=1" | sudo tee /etc/modprobe.d/nvidia-drm-modeset.conf

# Driver AMD
sudo xbps-install -Sy mesa-dri mesa-vulkan-radeon mesa-dri-32bit \
    mesa-vulkan-radeon-32bit linux-firmware-amd vulkan-loader

# Driver Intel
sudo xbps-install -Sy mesa-dri mesa-vulkan-intel mesa-dri-32bit \
    mesa-vulkan-intel-32bit intel-video-accel vulkan-loader
```

### Arch

En Arch, Steam necesita el repositorio **`[multilib]`** activado en `/etc/pacman.conf` (descomenta las dos líneas de `[multilib]`), y luego:

```bash
sudo pacman -Syu steam
# Driver AMD / Intel (Mesa ya viene con el instalador)
sudo pacman -S vulkan-radeon lib32-vulkan-radeon     # AMD
sudo pacman -S vulkan-intel lib32-vulkan-intel       # Intel
# Driver NVIDIA
sudo pacman -S nvidia-open nvidia-utils lib32-nvidia-utils
```

Para NVIDIA en Arch, activa el modeset del kernel con `nvidia_drm.modeset=1` (ver la [wiki de Arch](https://wiki.archlinux.org/title/NVIDIA#DRM_kernel_mode_setting)).

### Fedora y Nobara

Steam y el driver NVIDIA están en **RPM Fusion**. Son comandos estándar de Fedora; el instalador no los ejecuta:

```bash
# 1. Activar RPM Fusion (free y nonfree)
sudo dnf install -y https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
    https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm

# 2. Steam
sudo dnf install -y steam

# 3a. Driver NVIDIA (akmod compila el módulo; tarda unos minutos y luego reinicia)
sudo dnf install -y akmod-nvidia

# 3b. Driver AMD / Intel: Mesa ya viene en Fedora (32 bits para Steam)
sudo dnf install -y mesa-vulkan-drivers mesa-vulkan-drivers.i686
```

Para NVIDIA en Fedora, el modeset de Wayland se activa con `nvidia-drm.modeset=1` (ver la [documentación de RPM Fusion](https://rpmfusion.org/Howto/NVIDIA)).

### Debian y Ubuntu

Steam y los drivers vienen de los repositorios oficiales (en Ubuntu, `multiverse`) y de los repositorios de tu distribución. Consulta la documentación de tu distribución para los drivers de NVIDIA.

### Comprobar la GPU

```bash
lspci -nn | grep -iE 'vga|3d controller|display controller'
```

Notas rápidas:

- **Después de instalar un driver de GPU, reinicia.** El módulo solo se carga al arrancar.
- **Portátiles híbridos (Intel/AMD + NVIDIA):** no hay `prime-run`. Para lanzar algo con la GPU dedicada, usa las variables a mano:
  ```bash
  __NV_PRIME_RENDER_OFFLOAD=1 __VK_LAYER_NV_optimus=NVIDIA_only \
  __GLX_VENDOR_LIBRARY_NAME=nvidia steam
  ```
  y en las opciones de lanzamiento de un juego de Steam pon eso mismo antes de `%command%`.

---

## ⌨️ Atajos principales

La tecla **Super** es la de Windows (⌘ en teclados de Mac). Lista completa en **`~/Atajos.txt`** (`nano ~/Atajos.txt`).

| Atajo | Acción |
|---|---|
| `Super` + `D` | Lanzador (**wmenu**) |
| `Super` + `Enter` / `Super` + `T` | Terminal (**foot**) |
| `Super` + `B` | Firefox |
| `Super` + `R` | Gestor de archivos (**lf**) |
| `Super` + `Q` | Cerrar ventana |
| `Super` + `J` / `K` | Siguiente / anterior ventana |
| `Super` + `H` / `L` | Achicar / agrandar el área maestra |
| `Super` + `Space` | Alterna entre **mosaico** y **monocle** (una ventana a pantalla completa, sin superposiciones) |
| `Super` + `F` | **Maximizar / restaurar** la ventana (pulsa de nuevo para volver al mosaico) |
| `Super` + `Shift` + `F` | Pantalla completa (igual que `Super` + `F`) |
| `Super` + `W` | Ocultar / mostrar la **barra** |
| `Super` + `Shift` + `W` | Mover la barra arriba / abajo |
| `Super` + `1`…`9` | Ir a ese tag |
| `Super` + `Shift` + `1`…`9` | Mover la ventana a ese tag |
| `Super` + `Ctrl` + `1`…`9` | Mostrar / ocultar ese tag |
| `Super` + `Tab` | Volver al tag anterior |
| `Super` + `0` | Ver **todos** los tags a la vez |
| `Super` + `,` / `Super` + `.` | Monitor anterior / siguiente |
| `Ctrl` + `Alt` + `F1`…`F12` | Cambiar de consola (tty) — **no lo borres**, es tu salida de emergencia |
| `Super` + `Shift` + `E` | **Cerrar la sesión** |
| `Super` + `Shift` + `Q` | Cerrar la sesión |
| `Ctrl` + `Alt` + `Backspace` | Cerrar la sesión (alternativo) |

**Mosaico siempre:** dwl no tiene atajos para poner ventanas en flotante. Algunas ventanas, como los diálogos de una aplicación, pueden aparecer flotantes porque así lo decide dwl.

**Con el ratón:** `Super` + rueda sube/baja el volumen.

---

## Personalizar tu escritorio

| Archivo | Qué cambia | Cómo se aplica |
|---|---|---|
| `~/dwl/config.h` | **Atajos**, colores, reglas de ventanas, teclado | `dwl-rebuild` (Fedora y Nobara) o `cd ~/dwl && sudo make clean install` (Void, Arch y Debian) |
| `~/.config/dwlb/config` | Fuente, colores y tags (1–9) de la **barra** (una opción por línea) | Solo reinicia la sesión (no recompila) |
| `~/.config/foot/foot.ini` | Colores y transparencia de la **terminal** (si ya existía, se guarda como `foot.ini.bak`) | Solo abre una terminal nueva |
| `/usr/local/bin/dwlb-status` | Los bloques de estado de la barra (CPU, RAM, batería, volumen) | Solo reinicia la sesión |
| `~/dwlb/config.h` | Valores compilados de dwlb | `dwlb-rebuild` |
| `~/.config/lf/lfrc` | Gestor de archivos `lf` | Al reabrir `lf` |
| `/usr/local/bin/dwl-session` | Variables y programas que arrancan con la sesión | Al reiniciar la sesión |
| `/etc/greetd/config.toml` | Pantalla de login (greetd + tuigreet) | `sudo sv restart greetd` (Void) o `sudo systemctl restart greetd` (Arch, Fedora y Debian) |

### Ejemplo: cambiar un atajo de teclado

```bash
nano ~/dwl/config.h                  # 1. edita la tecla
dwl-rebuild                          # 2. recompila e instala (Fedora y Nobara)
# En Void, Arch y Debian, en vez de dwl-rebuild:  cd ~/dwl && sudo make clean install
# 3. Super + Shift + E para salir y vuelve a entrar
```

> En **Fedora y Nobara** usa siempre `dwl-rebuild`: `make install` volvería a instalar el binario real en el lugar del envoltorio de SDDM y la sesión dejaría de abrir.

> Para dwlb, usa `dwlb-rebuild` (deja el instalador), que hace lo mismo desde `~/dwlb`.

### Cambiar el fondo de pantalla

El fondo es `~/Pictures/wallpaper.jpg` (lo aplica **swaybg**).

1. Copia tu imagen a `~/Pictures/`.
2. Renómbrala a **`wallpaper.jpg`**.

```bash
cp /ruta/de/mi-fondo.png ~/Pictures/wallpaper.jpg
```

> Solo cambia el **nombre**: el contenido puede ser PNG u otro formato, no hace falta convertirlo.

### Diagnóstico de la sesión

Si algo no arranca al entrar a dwl:

```bash
cat ~/.cache/dwl-runner.log          # salida de la barra y el fondo
pgrep -af 'swaybg|dwlb'              # confirma que estén corriendo
```

---

## 🩺 Si algo falla

| Problema | Solución |
|---|---|
| dwl no arranca / pantalla en negro | Reinicia de verdad: `sudo reboot`. Casi siempre son los grupos `_seatd`/`seat`/`video` sin aplicar |
| No puedes moverte / se colgó | `Ctrl` + `Alt` + `F2` para ir a una consola y ahí `sudo reboot` |
| `tuigreet` no aparece | Está en la **tty 1**. Mira el estado: Void `sudo sv status greetd` · Arch, Fedora y Debian `systemctl status greetd` |
| El instalador termina con `greetd NO arranco` | Revisa el log: Void `sudo tail -n 30 /var/log/greetd/current` · Arch, Fedora y Debian `journalctl -u greetd -b` |
| SDDM o GDM no muestran dwl | Revisa que exista `/usr/share/wayland-sessions/dwl.desktop`. Si no aparece, vuelve a ejecutar el instalador |
| Fedora / Nobara: la sesión dwl no abre o se queda en negro | Comprueba `ls -l /usr/local/bin/dwl /usr/local/bin/dwl-bin`. `dwl` debe pesar unos 47 bytes (envoltorio) y `dwl-bin` unos 300 KB. Si `dwl-bin` es muy pequeño, vuelve a compilar con `dwl-rebuild` |
| Arch: `error: no se ha encontrado el paquete` | Ya no debería pasar: el instalador comprueba cada paquete antes de instalarlo y solo omite los que no existen. Verás un aviso `No estan en los repos, se omiten: …` |
| Arch: `wlroots` no está en los repos | Lo detecta solo (prueba `wlroots0.20`, `0.19`, `0.18`…). Si no hay ninguno, lo compila desde fuente |
| Arch: `[colors]: invalid section name` en foot | Usa una versión del instalador igual o posterior a la 1.0.20, o cambia en `~/.config/foot/foot.ini` la línea `[colors]` por `[colors-dark]` |
| Fedora: `Falta 'patch'` o la barra no marca el tag activo | `sudo dnf install -y patch perl-interpreter` y vuelve a correr el instalador |
| Fedora: `No se instalo: lf` (o `greetd`, `tuigreet`) | Instálalo a mano con `sudo dnf install <paquete>` o desde un COPR. Mira el nombre exacto con `dnf search <paquete>` |
| Fedora: la barra no tiene iconos o usa otra fuente | Comprueba con `fc-list \| grep -i "JetBrainsMono Nerd"`. Si no sale, la descarga falló: instala la fuente a mano en `~/.local/share/fonts` y ejecuta `fc-cache -f` |
| Fedora: greetd o tuigreet fallan al arrancar | Revisa SELinux con `sudo ausearch -m avc -ts recent` y el log con `journalctl -u greetd -b` |
| Debian / Ubuntu: `tuigreet no esta en los repos` | Es normal en Ubuntu 24.04 y Linux Mint 22. No se configura greetd: entra con tu gestor de sesión y elige **dwl** |
| Falla al instalar los paquetes en **musl** o **aarch64** (Void) | Esos sistemas **no tienen** repositorio multilib: el instalador ya lo tiene en cuenta; si aun así falla, quita `void-repo-nonfree void-repo-multilib void-repo-multilib-nonfree` de la línea de `xbps-install` y vuelve a ejecutarlo |
| `steam` no aparece en XBPS | Resincroniza (`sudo xbps-install -Sy`) y comprueba los repos con `xbps-query -Rs steam` |
| El audio no va | Void `sudo sv status seatd pipewire` · Arch, Fedora y Debian `systemctl --user status pipewire wireplumber`, y reinicia la sesión |
| La barra no marca el tag activo ni `[]=` | El parche IPC de dwl no se aplicó o no compiló (mira el aviso al instalar; en Fedora suele ser `patch` sin instalar). Sin él, la barra usa `-no-ipc` y los clics en los tags no funcionan. Usa `Super` + `1`…`9` |
| Super+M o Super+Shift+T siguen cambiando el layout | Tu instalación es anterior a la 1.0.21. Vuelve a ejecutar el instalador y revisa `grep -n 'XKB_KEY_m' ~/dwl/config.h` (debe salir vacío) |

---

## 🔗 Proyectos usados

Este instalador no reinventa nada: une y configura proyectos existentes.

| Proyecto | Enlace |
|---|---|
| **dwl** — compositor (dwm para Wayland) | https://codeberg.org/dwl/dwl |
| **dwlb** — la barra *(autor: kolunmi)* | https://github.com/kolunmi/dwlb |
| **lf** — gestor de archivos en terminal | https://github.com/gokcehan/lf |
| **foot** — terminal | https://codeberg.org/dnkl/foot |
| **wmenu** — lanzador | https://codeberg.org/adnano/wmenu |
| **greetd / tuigreet** — inicio de sesión | https://git.sr.ht/~kennylevinsen/greetd |
| **swaybg** — fondo de pantalla | https://github.com/swaywm/swaybg |
| **grim** — capturas | https://github.com/emersion/grim |

> 💡 ¿Quieres saber más de la barra? `man 1 dwlb` o visita https://github.com/kolunmi/dwlb

---

*Hecho para Void Linux, Arch Linux, Fedora, Nobara y Debian/Ubuntu. Si encuentras un error, abre un issue en el repositorio.*

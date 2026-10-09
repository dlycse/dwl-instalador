# dwl-instalador

> ### ⚠️ VERSIÓN 0.9.7 (rev.3) — beta
> - **Void Linux** (xbps + runit) y **Arch Linux** (pacman + systemd).
> - Probado en simulación (repositorios y gestor de paquetes simulados) y en **Void x86_64 (glibc)**, que es la edición recomendada.
> - La rama de **Arch** todavía no tiene una prueba completa en una máquina real: si algo falla, mira [🩺 Si algo falla](#-si-algo-falla).
> - Se recomiendan **20 GB libres** para evitar errores de almacenamiento.


<img width="1280" height="800" alt="image" src="https://github.com/user-attachments/assets/e84b9413-7f1a-4b3d-bfcd-f187fa14df44" />


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
| **greetd + tuigreet** | Pantalla de inicio de sesión (en **tty1**) |
| **pipewire + wireplumber** | Audio |
| Firefox, mpv, zathura, imv, btop | Navegador, video, PDF, imágenes, monitor |

El instalador tiene **un solo modo**: instala todo lo de la tabla, compila dwl y dwlb, aplica tu configuración y arranca con **greetd + tuigreet**.

Además deja listo:

- Los **repositorios** nonfree y multilib activados en **Void** (ver abajo).
- La **zona horaria** (`/etc/localtime`, `TIMEZONE` en Void, y `chronyd` para la hora).
- El **teclado**, tanto en la consola (`KEYMAP`) como en dwl.
- Atajos de teclado con **Super** como tecla principal (en dwl por defecto es Alt).
- Los comandos `dwl-rebuild` y `dwlb-rebuild`, para recompilar sin entrar a las carpetas.
- `~/Atajos.txt` con la chuleta completa, en texto plano para leerla con `nano`.
- Un fondo de pantalla por defecto en `~/Pictures/wallpaper.jpg` (anime 4K). Si ya tienes un fondo propio, el instalador no lo toca; el que puso una instalación anterior sí se reemplaza.
- Desactiva otros gestores de sesión si los hay (**lightdm, gdm, sddm, xdm, lxdm**). Se **desactivan**, no se desinstalan.

**No instala drivers de GPU ni Steam.** Eso lo eliges tú aparte, en un comando (ver [Steam y drivers](#-steam-y-drivers-opcional)).

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

---

## Instalación en 4 pasos

### 0. Primero instala `git`

Lo necesitas para clonar el repositorio. El propio instalador también instala `git` como dependencia, pero para descargarlo antes hace falta tenerlo.

```bash
# Void
sudo xbps-install -S git
# Arch
sudo pacman -S git
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
chmod +x install-dwl-0.9.7.sh
```

### 4. Ejecutar el instalador

**Desde una consola que no sea tty1** (por ejemplo `Ctrl` + `Alt` + `F2`, o una terminal dentro de tu escritorio actual). Si lo lanzas desde tty1, el script no toca esa consola en caliente y programa el cambio para el reinicio.

```bash
./install-dwl-0.9.7.sh
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
| **Kernel** | Pregunta si buscar e instalar el **kernel más reciente** de los repos. Si hay una serie nueva, se instala **junto** al actual (no lo reemplaza) y se activa al reiniciar |

---

## 🔁 Al terminar: **REINICIA** (importante)

```bash
sudo reboot
```

El reinicio **no es opcional**: los grupos nuevos (`_seatd` o `seat` y `video`) solo se aplican al volver a iniciar sesión, y **sin ellos dwl no puede abrir la GPU ni el teclado/ratón**.

> Aunque ya veas la pantalla de `tuigreet`, **no entres todavía**. Reinicia primero.
> Si elegiste instalar un kernel nuevo, el reinicio es doblemente necesario.

### Cuando vuelvas a arrancar

Verás **tuigreet** (una pantalla de login en texto, en la **tty 1**). Escribe tu usuario y contraseña:

| Tecla | Acción |
|---|---|
| `F2` | Cambiar el comando de la sesión |
| `F3` | Elegir otra sesión |
| `F12` | Menú de apagar / reiniciar — **solo si hay `loginctl`** (en Void sin elogind no aparece) |

> ℹ️ Este instalador usa **greetd + tuigreet** en **tty1**. Las consolas `tty2`…`tty6` siguen con `agetty` normal, por si necesitas entrar a una consola.

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
| `Super` + `W` | Ocultar / mostrar la **barra** |
| `Super` + `Shift` + `W` | Mover la barra arriba / abajo |
| `Super` + `F` | Layout *monocle* (una ventana a pantalla completa) |
| `Super` + `Shift` + `T` | Volver al layout de mosaico (tiling) |
| `Super` + `Shift` + `F` | Ventana a pantalla completa |
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

**Con el ratón:** `Super` + clic izquierdo *mueve* la ventana · `Super` + clic central la vuelve *flotante* · `Super` + clic derecho la *redimensiona* · `Super` + rueda sube/baja el volumen.

---

## Personalizar tu escritorio

| Archivo | Qué cambia | Cómo se aplica |
|---|---|---|
| `~/dwl/config.h` | **Atajos**, colores, reglas de ventanas, teclado | `cd ~/dwl && sudo make clean install` |
| `~/.config/dwlb/config` | Fuente, colores y tags (1–9) de la **barra** (una opción por línea) | Solo reinicia la sesión (no recompila) |
| `~/.config/foot/foot.ini` | Colores y transparencia de la **terminal** (si ya existía, se guarda como `foot.ini.bak`) | Solo abre una terminal nueva |
| `/usr/local/bin/dwlb-status` | Los bloques de estado de la barra (CPU, RAM, batería, volumen) | Solo reinicia la sesión |
| `~/dwlb/config.h` | Valores compilados de dwlb | `dwlb-rebuild` |
| `~/.config/lf/lfrc` | Gestor de archivos `lf` | Al reabrir `lf` |
| `/usr/local/bin/dwl-session` | Variables y programas que arrancan con la sesión | Al reiniciar la sesión |
| `/etc/greetd/config.toml` | Pantalla de login (greetd + tuigreet) | `sudo sv restart greetd` (Void) o `sudo systemctl restart greetd` (Arch) |

### Ejemplo: cambiar un atajo de teclado

```bash
nano ~/dwl/config.h           # 1. edita la tecla
cd ~/dwl && sudo make clean install   # 2. recompila e instala
# 3. Super + Shift + E para salir y vuelve a entrar
```

> Para dwl, el comando es `cd ~/dwl && sudo make clean install`. Para dwlb, usa `dwlb-rebuild`
> (deja el instalador), que hace lo mismo desde `~/dwlb`.

### Cambiar el fondo de pantalla

El fondo es `~/Pictures/wallpaper.jpg` (lo aplica **swaybg**).

1. Copia tu imagen a `~/Pictures/`.
2. Renómbrala a **`wallpaper.jpg`**.

```bash
cp /ruta/de/mi-fondo.png ~/Pictures/wallpaper.jpg
```

> Solo cambia el **nombre**: el contenido puede ser PNG u otro formato, no hace falta convertirlo.

---

## 🩺 Si algo falla

| Problema | Solución |
|---|---|
| dwl no arranca / pantalla en negro | Reinicia de verdad: `sudo reboot`. Casi siempre son los grupos `_seatd`/`seat`/`video` sin aplicar |
| No puedes moverte / se colgó | `Ctrl` + `Alt` + `F2` para ir a una consola y ahí `sudo reboot` |
| `tuigreet` no aparece | Está en la **tty 1**. Mira el estado: Void `sudo sv status greetd` · Arch `systemctl status greetd` |
| El instalador termina con `greetd NO arranco` | Revisa el log: Void `sudo tail -n 30 /var/log/greetd/current` · Arch `journalctl -u greetd -b` |
| Arch: `error: no se ha encontrado el paquete` | Ya no debería pasar: el instalador comprueba cada paquete antes de instalarlo y solo omite los que no existen. Verás un aviso `No estan en los repos, se omiten: …` |
| Arch: `wlroots` no está en los repos | Lo detecta solo (prueba `wlroots0.20`, `0.19`, `0.18`…). Si no hay ninguno, avisa y dwl no compilará |
| Falla al instalar los paquetes en **musl** o **aarch64** (Void) | Esos sistemas **no tienen** repositorio multilib: el instalador ya lo tiene en cuenta; si aun así falla, quita `void-repo-nonfree void-repo-multilib void-repo-multilib-nonfree` de la línea de `xbps-install` y vuelve a ejecutarlo |
| `steam` no aparece en XBPS | Resincroniza (`sudo xbps-install -Sy`) y comprueba los repos con `xbps-query -Rs steam` |
| El audio no va | Void `sudo sv status seatd pipewire` · Arch `systemctl --user status pipewire wireplumber`, y reinicia la sesión |
| La barra no marca el tag activo ni `[]=` | El parche IPC de dwl no se aplicó o no compiló (mira el aviso al instalar). Sin él, la barra usa `-no-ipc` y los clics en los tags no funcionan. Usa `Super` + `1`…`9` |

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

*Hecho para Void Linux y Arch Linux. Si encuentras un error, abre un issue en el repositorio.*

# dwl-instalador

Instalador de **dwl** (el equivalente a *dwm*, pero para **Wayland**) ya preconfigurado para **Void Linux**.

> ### ⚠️ VERSIÓN 0.8 (BETA) — puede contener errores
> **SOLO PARA VOID LINUX.** **se recomienda 20 GB libres + 1 GB efi** para evitar errores de almacenamiento.
>
> Probado en **Void x86_64 (glibc)**, que es la edición recomendada. En **musl** y **aarch64** no existen
> los repositorios *multilib*: mira [🩺 Si algo falla](#-si-algo-falla).

<img width="1600" height="900" alt="Captura del escritorio dwl con la barra dwlb" src="https://github.com/user-attachments/assets/64108d84-8e2a-4731-8a71-3136811234e4" />

---

## 📦 Qué instala

| Componente | Para qué sirve |
|---|---|
| **dwl** | El compositor (gestor de ventanas) Wayland |
| **[dwlb](https://github.com/kolunmi/dwlb)** | La **barra** superior (tags, layout, estado) — autor: *kolunmi* |
| **foot** | Emulador de terminal |
| **wmenu** | Lanzador de aplicaciones (el equivalente a dmenu) |
| **lf** | Gestor de archivos en la terminal |
| **swaybg** | Fondo de pantalla |
| **grim** | Capturas de pantalla |
| **greetd + tuigreet** | Pantalla de inicio de sesión |
| **pipewire** | Audio |
| Firefox, mpv, zathura, imv, btop | Navegador, video, PDF, imágenes, monitor |

El instalador tiene **un solo modo**: instala todo lo de la tabla y arranca con **greetd + tuigreet**.

Además deja listo:

- Los **repositorios** nonfree y multilib activados (ver abajo), para que después instales Steam o los drivers con un comando.
- La **zona horaria** (`/etc/localtime` y `TIMEZONE` en `/etc/rc.conf`).
- El **teclado**, tanto en la consola (`KEYMAP`) como en dwl.
- Los comandos `dwl-rebuild` y `dwlb-rebuild`, para recompilar sin entrar a las carpetas.
- `~/Atajos.txt` con la chuleta completa, en texto plano para leerla con `nano`.

**No instala drivers de GPU ni Steam.** Eso lo eliges tú aparte, en un comando (ver [Steam y drivers](#-steam-y-drivers-opcional)).

---

## 🧩 Repositorios que deja activados

Al instalar los paquetes, el instalador activa también estos repositorios:

| Repositorio | Qué te permite instalar después |
|---|---|
| **nonfree** | Driver de **NVIDIA**, Steam y otros paquetes con licencia no libre |
| **multilib** | Librerías y programas de **32 bits** (los que piden Steam y Wine) |
| **multilib/nonfree** | Librerías de 32 bits con licencia no libre |

Así no tienes que tocar repositorios a mano: cuando quieras Steam o el driver de tu GPU, es un solo comando.

> ⚠️ **multilib y multilib/nonfree solo existen en x86_64 con glibc.** En **musl**, **aarch64** o **i686** no están,
> y XBPS no los encuentra. Ahí sí que hay que quitarlos de la lista (ver [🩺 Si algo falla](#-si-algo-falla)).

---

## 🚀 Instalación en 4 pasos

### 0. Primero instala `git` (es obligatorio)

```bash
sudo xbps-install -S git
```

> Si no lo haces, el instalador se detendrá y te lo recordará.

### 1. Clonar el repositorio

Copia y pega esto en tu terminal para descargar todo el código:

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

```bash
./install-dwl.sh
```

> 📝 Si en tu copia el archivo se llama `install-dwl-v0.8.sh`, usa ese nombre en los pasos 3 y 4.

---

## ❓ Qué te va a preguntar el instalador

| Pregunta | Opciones |
|---|---|
| **Tipo de instalación** | `1` Instalar · `2` Salir |
| **Kernel** | Si hay un kernel `7.x` en los repos, te ofrece instalarlo **junto** al actual (no lo reemplaza) |
| **País / zona horaria** | Escribe tu país (ej. `Colombia`, `México`, `Argentina`) o la zona directa (`America/Bogota`) |
| **Teclado** | `1` Inglés (us) · `2` Español de España (es) · `3` Latinoamericano (latam) — por defecto `3` |

Si tienes menos de 20 GB libres te avisará y podrás decidir si continuar igual.

Los **repositorios** (nonfree y multilib) no se preguntan: se activan solos al instalar los paquetes.

> 💡 Si tu copia del instalador incluye una cuarta opción (`4` No cambiar), no toca ni el `KEYMAP` de la
> consola ni el layout de dwl: deja el teclado tal como lo tenías.

---

## 🔁 Al terminar: **REINICIA** (importante)

```bash
sudo reboot
```

El reinicio **no es opcional**: los grupos nuevos (`_seatd` y `video`) solo se aplican al volver a iniciar sesión, y **sin ellos dwl no puede abrir la GPU ni el teclado/ratón**.

> Aunque ya veas la pantalla de `tuigreet`, **no entres todavía**. Reinicia primero.
> Si elegiste instalar un kernel nuevo, el reinicio es doblemente necesario.

### Cuando vuelvas a arrancar

Verás **tuigreet** (una pantalla de login en texto, en la **tty 7**). Escribe tu usuario y contraseña:

| Tecla | Acción |
|---|---|
| `F2` | Cambiar el comando de la sesión |
| `F3` | Elegir otra sesión |
| `F12` | Apagar / reiniciar |

> ℹ️ Este instalador usa **greetd + tuigreet**. Si tenías `lightdm`, se **desactiva y desinstala** automáticamente.

---

## 🎮 Steam y drivers (opcional)

Esto **no** lo instala el instalador, pero como ya te dejó los repositorios activados es un comando:

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

Para comprobar qué GPU tienes:

```bash
lspci -nn | grep -iE 'vga|3d controller|display controller'
```

Notas rápidas:

- **Después de instalar un driver de GPU, reinicia.** El módulo solo se carga al arrancar.
- **Portátiles híbridos (Intel/AMD + NVIDIA):** Void **no** trae `prime-run`. Para lanzar algo con la GPU
  dedicada, usa las variables a mano:
  ```bash
  __NV_PRIME_RENDER_OFFLOAD=1 __VK_LAYER_NV_optimus=NVIDIA_only \
  __GLX_VENDOR_LIBRARY_NAME=nvidia steam
  ```
  y en las opciones de lanzamiento de un juego de Steam pon eso mismo antes de `%command%`.
- **Si dwl arrancara en negro** en un equipo híbrido, el wrapper `/usr/local/bin/dwl-session`
  ya trae anotada (comentada) la línea `WLR_DRM_DEVICES=...` con **tus** tarjetas: descoméntala.

---

## ⌨️ Atajos principales

La tecla **Super** es la de Windows (⌘ en teclados de Mac). Lista completa en **[Atajos.md](Atajos.md)**.

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
| `Super` + `F` | Layout *monocle* (pantalla completa) |
| `Super` + `Shift` + `F` | Ventana a pantalla completa |
| `Super` + `1`…`9` | Ir a ese tag |
| `Super` + `Shift` + `1`…`9` | Mover la ventana a ese tag |
| `Super` + `Tab` | Volver al tag anterior |
| `Super` + `0` | Ver **todos** los tags a la vez |
| `Ctrl` + `Alt` + `F1`…`F12` | Cambiar de consola (tty) — **no lo borres**, es tu salida de emergencia |
| `Super` + `Shift` + `E` | **Cerrar la sesión** |
| `Ctrl` + `Alt` + `Backspace` | Cerrar la sesión (alternativo) |

**Con el ratón:** `Super` + clic izquierdo *mueve* la ventana · `Super` + clic central la vuelve *flotante* · `Super` + clic derecho la *redimensiona* · `Super` + rueda sube/baja el volumen.

Para ver los atajos desde la terminal (el instalador crea `~/Atajos.txt` en texto plano,
alineado para leerse en `nano`):

```bash
nano ~/Atajos.txt
```

---

## 🎨 Personalizar tu escritorio

| Archivo | Qué cambia | Cómo se aplica |
|---|---|---|
| `~/dwl/config.h` | **Atajos**, colores, reglas de ventanas, teclado | `dwl-rebuild` (= `cd ~/dwl && sudo make clean install`) |
| `~/.config/dwlb/config` | Fuente y colores de la **barra** | Solo reinicia la sesión (no recompila) |
| `/usr/local/bin/dwlb-status` | Los bloques de estado de la barra (CPU, RAM, batería…) | Solo reinicia la sesión |
| `~/dwlb/config.h` | Valores compilados de dwlb | `dwlb-rebuild` |
| `~/.config/lf/lfrc` | Gestor de archivos `lf` | Al reabrir `lf` |
| `/usr/local/bin/dwl-session` | Variables y programas que arrancan con la sesión | Al reiniciar la sesión |
| `/etc/greetd/config.toml` | Pantalla de login (greetd + tuigreet) | `sudo sv restart greetd` |

### Ejemplo: cambiar un atajo de teclado

```bash
nano ~/dwl/config.h           # 1. edita la tecla
dwl-rebuild                   # 2. recompila e instala (está en /usr/local/bin)
# 3. Super+Shift+E para salir y vuelve a entrar
```

> `dwl-rebuild` y `dwlb-rebuild` son los dos comandos que deja el instalador, para no tener que
> entrar a `~/dwl` o `~/dwlb` cada vez.

### Cambiar el fondo de pantalla

El fondo es `~/Pictures/wallpaper.jpg` (lo aplica **swaybg**).

1. Copia tu imagen a `~/Pictures/`.
2. Renómbrala a **`wallpaper.jpg`**.
3. La que venía por defecto puedes borrarla o renombrarla para conservarla.

```bash
cp /ruta/de/mi-fondo.png ~/Pictures/wallpaper.jpg
```

> Solo cambia el **nombre**: el contenido puede ser PNG u otro formato, no hace falta convertirlo.

---

## 🩺 Si algo falla

| Problema | Solución |
|---|---|
| dwl no arranca / pantalla en negro | Reinicia de verdad: `sudo reboot`. Casi siempre son los grupos `_seatd`/`video` sin aplicar |
| No puedes moverte / se colgó | `Ctrl` + `Alt` + `F1` para ir a una consola y ahí `sudo reboot` |
| `tuigreet` no aparece | Está en la **tty 7**: prueba `Ctrl` + `Alt` + `F7` |
| Falla al instalar los paquetes en **musl** o **aarch64** | Esos sistemas **no tienen** repositorio multilib: quita `void-repo-nonfree void-repo-multilib void-repo-multilib-nonfree` de la línea de `xbps-install` y vuelve a ejecutar el instalador |
| `steam` no aparece en XBPS | Resincroniza (`sudo xbps-install -Sy`) y comprueba los repos con `xbps-query -L` y `xbps-query -Rs steam` |
| El instalador dice que falta `git` | `sudo xbps-install -S git` y vuelve a ejecutarlo |
| El audio no va | `sudo sv status seatd pipewire` y reinicia la sesión |
| Quiero ver qué barra estoy usando | `pgrep -a dwlb` → si sale `-no-ipc`, los clics en los tags no funcionan (usa `Super`+`1`…`9`) |

---

## 🔗 Proyectos usados

Este instalador no reinventa nada: une y configura proyectos existentes.

| Proyecto | Enlace |
|---|---|
| **dwl** — compositor (dwm para Wayland) | https://codeberg.org/dwl/dwl |
| **dwlb** — la barra *(autor: kolunmi)* | **[github.com/kolunmi/dwlb](https://github.com/kolunmi/dwlb)** |
| **lf** — gestor de archivos en terminal | https://github.com/gokcehan/lf |
| **foot** — terminal | https://codeberg.org/dnkl/foot |
| **wmenu** — lanzador | https://codeberg.org/adnano/wmenu |
| **greetd / tuigreet** — inicio de sesión | https://git.sr.ht/~kennylevinsen/greetd |
| **swaybg** — fondo de pantalla | https://github.com/swaywm/swaybg |
| **grim** — capturas | https://github.com/emersion/grim |

> 💡 ¿Quieres saber más de la barra? `man 1 dwlb` o visita https://github.com/kolunmi/dwlb

> 💡 ¿Quieres saber más del navegador de archivos? visita https://github.com/gokcehan/lf
---

*Hecho para Void Linux. Si encuentras un error, abre un issue en el repositorio.*

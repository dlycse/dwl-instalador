# dwm-instalador

Instalador de **dwm** (el gestor de ventanas en mosaico de suckless.org) ya preconfigurado para **Void Linux**.

> ### ⚠️ VERSIÓN 0.7 (BETA) — puede contener errores
> **SOLO PARA VOID LINUX.** Necesitas **mínimo 20 GB libres** para evitar errores de almacenamiento.

<img width="2880" height="2160" alt="Captura del escritorio dwm con la barra slstatus" src="https://github.com/user-attachments/assets/daacd093-3cd8-4330-ad5d-e77d1c1ad982" />

---

## 📦 Qué instala

| Componente | Para qué sirve |
|---|---|
| **dwm 6.2** | El gestor de ventanas, con el parche **vanitygaps** (separación entre ventanas) |
| **slstatus** | El contenido de la barra: CPU, RAM, wifi, batería y fecha |
| **st** | Emulador de terminal |
| **dmenu** | Lanzador de aplicaciones |
| **lf** | Gestor de archivos en la terminal — **el único**, no se instala ninguno gráfico |
| **picom** | Compositor (transparencias) |
| **feh** | Fondo de pantalla |
| **dunst** | Notificaciones |
| **scrot** | Capturas de pantalla |
| **lightdm** | Pantalla de inicio de sesión (también funciona con `startx`) |
| **udisks2 + polkit + elogind** | Montar pendrives y discos **sin contraseña** |
| Firefox, mpv, zathura, btop | Navegador, video, PDF, monitor del sistema |

> 📁 **Solo `lf` como gestor de archivos.** Este instalador **no** instala ninguno gráfico
> (ni pcmanfm ni Thunar): si quieres uno, lo instalas tú y le pones el atajo que prefieras.
> ```bash
> sudo xbps-install -S pcmanfm      # o Thunar, o el que quieras
> ```
> La pila de montaje (`udisks2` + `polkit` + `elogind`) **sí** queda configurada, así que
> montar discos sin contraseña funciona igual con cualquier gestor que añadas después.

Apariencia: paleta **Catppuccin Mocha** y fuente **JetBrainsMono Nerd Font**.

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
git clone https://github.com/dlycse/dwm-instalador.git
```

### 2. Entrar a la carpeta

```bash
cd dwm-instalador
```

### 3. Darle permisos de ejecución

```bash
chmod +x install-dwm.sh
```

### 4. Ejecutar el instalador

```bash
./install-dwm.sh
```

> Ejecútalo como **tu usuario normal**, no como root (usa `sudo` internamente cuando lo necesita).

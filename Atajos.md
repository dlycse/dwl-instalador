# ⌨️ Atajos de teclado — dwl + dwlb

Lista de los atajos que **realmente configura** el instalador (**v1.0.41**). Si algo de aquí no coincide con tu equipo, tu copia del instalador es anterior: vuelve a ejecutarlo.

> **¿Qué es "Super"?** Es la tecla con el logo de **Windows** ⊞ (en teclados de Mac es **⌘ Command**).

> 📄 Para leerlo en la terminal, el instalador genera `~/Atajos.txt` (texto plano para `nano`):
>
> ```bash
> nano ~/Atajos.txt
> ```

> ⚠️ **Estado de prueba:** los cambios de 1.0.23 a 1.0.41 están pendientes de prueba en cada distro. Los atajos marcados con *(pendiente de prueba)* no están confirmados en ningún equipo.

---

## 🆘 Lo esencial para empezar

| Quieres… | Presiona |
|---|---|
| Abrir una **terminal** | `Super` + `Enter` |
| Abrir un **programa** (lanzador) | `Super` + `D` |
| **Cerrar** la ventana enfocada | `Super` + `Q` |
| Ver tus **archivos** | `Super` + `R` |
| Abrir el **navegador** | `Super` + `B` |
| **Cerrar la sesión** (volver al login) | `Super` + `Shift` + `E` |
| Ir a una **consola de emergencia** si algo se congela | `Ctrl` + `Alt` + `F1` |

---

## 📖 Mini glosario

| Palabra | Qué significa |
|---|---|
| **Tag** | Un "escritorio virtual". Hay 9 y cada uno guarda sus propias ventanas. |
| **Mosaico** | Layout normal: las ventanas se reparten automáticamente por la pantalla. |
| **Monocle** | Layout donde **una sola ventana** ocupa el área de trabajo. Las demás quedan detrás. |
| **Maximizar** | Ocupar toda la pantalla con la ventana enfocada. Al volver a pulsar, regresa al mosaico. |
| **Barra** | La línea de arriba (**dwlb**): tags, CPU, RAM, volumen y hora. |

---

## 🚀 Programas

| Atajo | Qué abre |
|---|---|
| `Super` + `D` | **Lanzador de aplicaciones** (wmenu) |
| `Super` + `Enter` | **Terminal** (foot) |
| `Super` + `T` | **Terminal** (foot), atajo alternativo |
| `Super` + `B` | **Firefox** |
| `Super` + `R` | **lf**, gestor de archivos (dentro de foot) |

---

## 🪟 Ventanas

| Atajo | Qué hace |
|---|---|
| `Super` + `Q` | **Cerrar** la ventana enfocada |
| `Super` + `J` | Enfocar la **siguiente** ventana |
| `Super` + `K` | Enfocar la **anterior** ventana |
| `Super` + `H` | Hacer el área maestra **más angosta** |
| `Super` + `L` | Hacer el área maestra **más ancha** |
| `Super` + `I` | Meter **una ventana más** en el área maestra |
| `Super` + `F` | **Maximizar / restaurar** la ventana (pulsa de nuevo para volver al mosaico) |
| `Super` + `E` | **Pantalla completa** (mismo efecto que `Super` + `F`, atajo de dwl) |

> ℹ️ **Sin ventanas flotantes:** no hay atajo de teclado ni de ratón para ponerlas en flotante (se quitaron en 1.0.18). Algunas ventanas, como ciertos diálogos, pueden aparecer flotantes porque así lo decide la aplicación o dwl.

---

## 📐 Layouts

| Atajo | Qué hace |
|---|---|
| `Super` + `Space` | **Alterna** entre **mosaico** y **monocle** |

> ℹ️ Es el único atajo de layout. `Super` + `M` (monocle) y el `setlayout` de `Super` + `T` de dwl se quitaron en la v1.0.21 y 1.0.34. `Super` + `Shift` + `T` no está en el instalador.

---

## 🔢 Tags (los 9 escritorios)

| Atajo | Qué hace |
|---|---|
| `Super` + `1` … `9` | **Ir** a ese tag |
| `Super` + `Shift` + `1` … `9` | **Mover** la ventana enfocada a ese tag |
| `Super` + `Ctrl` + `1` … `9` | **Mostrar / ocultar** ese tag (se suma o se quita de la vista) |
| `Super` + `Ctrl` + `Shift` + `1` … `9` | **Mostrar / ocultar** ese tag en la ventana enfocada |
| `Super` + `Tab` | Volver al **tag anterior** |
| `Super` + `0` | Ver **los 9 tags a la vez** |
| `Super` + `Shift` + `0` | Enviar la ventana enfocada a **todos los tags** |

---

## 🖥️ Varios monitores

| Atajo | Qué hace |
|---|---|
| `Super` + `,` | Mover el foco al monitor **anterior** |
| `Super` + `.` | Mover el foco al monitor **siguiente** |
| `Super` + `Shift` + `,` | **Enviar** la ventana al monitor anterior |
| `Super` + `Shift` + `.` | **Enviar** la ventana al monitor siguiente |

---

## 🔊 Volumen

| Acción | Efecto |
|---|---|
| `Super` + **rueda del ratón** hacia arriba | Subir el volumen (+5 %) *(pendiente de prueba)* |
| `Super` + **rueda del ratón** hacia abajo | Bajar el volumen (−5 %) *(pendiente de prueba)* |

> ℹ️ El instalador **no** configura teclas multimedia (volumen, brillo, captura de pantalla). `grim` viene instalado para hacer capturas desde la terminal.

---

## 🚪 Salir, barra y consolas

| Atajo | Qué hace |
|---|---|
| `Super` + `Shift` + `E` | **Cerrar la sesión de dwl** (vuelves al login) |
| `Super` + `Shift` + `Q` | Cerrar la sesión de dwl (atajo de dwl por defecto) |
| `Ctrl` + `Alt` + `Backspace` | Cerrar la sesión (alternativo) |
| `Ctrl` + `Alt` + `F1` … `F12` | Cambiar de **consola (tty)** |
| `Super` + `W` | **Ocultar / mostrar** la barra |
| `Super` + `Shift` + `W` | **Mover la barra** arriba / abajo |

> ⚠️ **No borres los `Ctrl` + `Alt` + `Fx`.** Si dwl se congela, son la única forma de salir a una consola para hacer `sudo reboot`.

---

## 🖱️ Ratón

| Acción | Efecto |
|---|---|
| `Super` + **clic izquierdo** (arrastrar) | Mover la ventana *(pendiente de prueba en mosaico)* |
| `Super` + **clic derecho** (arrastrar) | Redimensionar la ventana *(pendiente de prueba en mosaico)* |
| `Super` + **rueda** | Subir / bajar el volumen *(pendiente de prueba)* |

> ℹ️ Ya no hay atajo de ratón para flotante: el de `Super` + clic central se quitó junto con el de teclado.

---

## 🎨 Cambiar estos atajos

```bash
nano ~/dwl/config.h               # 1. busca la tecla y cámbiala
dwl-rebuild                       # 2. recompila e instala (Fedora y Nobara)
# En Void, Arch y Debian, en vez de dwl-rebuild:  cd ~/dwl && sudo make clean install
# 3. Super + Shift + E para salir, y vuelve a entrar
```

> En **Fedora y Nobara** usa `dwl-rebuild`. `make install` volvería a instalar el binario real en el lugar del envoltorio `dwl`.

| Archivo | Qué se cambia ahí |
|---|---|
| `~/dwl/config.h` | **Atajos**, colores, reglas de ventanas, teclado |
| `~/.config/dwlb/config` | Fuente y colores de la **barra** (no hace falta recompilar) |
| `/usr/local/bin/dwlb-status` | Qué muestra la barra (CPU, RAM, volumen, batería, reloj) |
| `~/.config/lf/lfrc` | Comportamiento del gestor de archivos `lf` |
| `/usr/local/bin/dwl-session` | Programas y variables al iniciar sesión |

---

## 🔗 Referencias

| Proyecto | Enlace |
|---|---|
| **dwlb** (la barra) | [https://github.com/kolunmi/dwlb](https://github.com/kolunmi/dwlb) |
| **dwl** (el compositor) | [https://codeberg.org/dwl/dwl](https://codeberg.org/dwl/dwl) |
| **lf** (gestor de archivos) | [https://github.com/gokcehan/lf](https://github.com/gokcehan/lf) |

Manuales en tu terminal: `man 1 dwlb` · `man 1 foot` · `man 1 lf`

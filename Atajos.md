# ⌨️ Atajos de teclado — dwl + dwlb

Lista **completa y real** de los atajos que deja configurados el instalador.

> **¿Qué es "Super"?** Es la tecla con el logo de **Windows** ⊞ (en teclados de Mac es **⌘ Command**).

> 📄 **¿Estás leyendo esto desde la terminal?** El instalador genera una versión en
> **texto plano** pensada para `nano`, alineada y sin markdown:
>
> ```bash
> nano ~/Atajos.txt
> ```
>
> Este archivo (`Atajos.md`) es el mismo contenido, pero con formato para leerlo en GitHub.

---

## 🆘 Si acabas de instalar, con esto ya puedes usar el sistema

| Quieres… | Presiona |
|---|---|
| Abrir una **terminal** | `Super` + `Enter` |
| Abrir un **programa** (lanzador) | `Super` + `D` |
| **Cerrar** la ventana que estás usando | `Super` + `Q` |
| Ver tus **archivos** | `Super` + `R` |
| Abrir el **navegador** | `Super` + `B` |
| **Cerrar la sesión** (volver al login) | `Super` + `Shift` + `E` |
| Ir a una **consola de emergencia** si algo se congela | `Ctrl` + `Alt` + `F1` |

Con esos siete ya puedes manejarte. El resto lo vas aprendiendo sobre la marcha.

---

## 📖 Mini glosario

Un gestor de ventanas **mosaico** (*tiling*) no apila ventanas como Windows: las **reparte** automáticamente por la pantalla.

| Palabra | Qué significa |
|---|---|
| **Tag** | Un "escritorio virtual". Hay 9 y cada uno guarda sus propias ventanas. |
| **Área maestra** | La ventana grande y principal, normalmente a la izquierda. |
| **Layout** | La forma de repartir las ventanas. |
| **Monocle** | Layout donde **una sola ventana** ocupa toda la pantalla. |
| **Flotante** | Ventana fuera del mosaico: la mueves y redimensionas a mano. |
| **Barra** | La línea de arriba ([**dwlb**](https://github.com/kolunmi/dwlb)): tags, layout, CPU, RAM, volumen, batería y hora. |
| **Gaps** | Separación entre ventanas. **Vienen desactivados** — ver más abajo. |

---

## 🚀 Programas

| Atajo | Qué abre |
|---|---|
| `Super` + `D` | **Lanzador de aplicaciones** (wmenu) |
| `Super` + `Enter` | **Terminal** (foot) |
| `Super` + `T` | **Terminal** (foot) — atajo alternativo |
| `Super` + `B` | **Firefox** |
| `Super` + `R` | **lf**, gestor de archivos (se abre dentro de foot) |

---

## 🪟 Ventanas

| Atajo | Qué hace |
|---|---|
| `Super` + `Q` | **Cerrar** la ventana enfocada |
| `Super` + `J` &nbsp;o&nbsp; `Super` + `↓` | Enfocar la **siguiente** ventana |
| `Super` + `K` &nbsp;o&nbsp; `Super` + `↑` | Enfocar la ventana **anterior** |
| `Super` + `H` | Hacer el área maestra **más angosta** |
| `Super` + `L` | Hacer el área maestra **más ancha** |
| `Super` + `I` | Meter **una ventana más** en el área maestra |
| `Super` + `Shift` + `T` | Volver la ventana **flotante** (o devolverla al mosaico) |
| `Super` + `Shift` + `Enter` | Traer la ventana actual **al área maestra** (*zoom*) |

---

## 📐 Layouts

| Símbolo en la barra | Layout |
|---|---|
| `[]=` | **Mosaico**: área maestra + columna de ventanas (el inicial) |
| `"><>"` | **Flotante**: cada ventana se mueve y redimensiona a mano |
| `[M]` | **Monocle**: una sola ventana ocupando todo |

| Atajo | Qué hace |
|---|---|
| `Super` + `Space` | **Rotar** al layout siguiente o volver al anterior |
| `Super` + `F` | Ir directo a **monocle** |
| `Super` + `Shift` + `F` | **Pantalla completa real**, sin barra (video, juegos) |

> 📌 El layout **flotante** (`"><>"`) no tiene tecla propia: se llega rotando con `Super` + `Space`.

---

## 🔢 Tags (los 9 escritorios)

| Atajo | Qué hace |
|---|---|
| `Super` + `1` … `9` | **Ir** a ese tag |
| `Super` + `Shift` + `1` … `9` | **Mover** la ventana actual a ese tag |
| `Super` + `Ctrl` + `1` … `9` | **Ver dos tags a la vez** (el actual + ese) |
| `Super` + `Ctrl` + `Shift` + `1`…`9` | La ventana **aparece en ambos** tags sin moverla |
| `Super` + `Tab` | Volver al **tag anterior** |
| `Super` + `0` | Ver **los 9 tags a la vez** |

> 💡 **Teclado latam/es:** `Shift` + número produce `!"#$%&/()`. El instalador ya registró
> las dos variantes, así que `Super` + `Shift` + `1`…`9` funciona en los tres layouts de teclado.

**Idea de uso:** terminal en el tag 1, navegador en el 2, música en el 3, chat en el 4.

---

## 🖥️ Varios monitores

| Atajo | Qué hace |
|---|---|
| `Super` + `,` | Mover el foco al monitor de la **izquierda** |
| `Super` + `.` | Mover el foco al monitor de la **derecha** |
| `Super` + `Shift` + `<` | **Enviar la ventana** al monitor de la izquierda |
| `Super` + `Shift` + `>` | **Enviar la ventana** al monitor de la derecha |

> 💡 También están registrados `Super` + `Shift` + `;` y `Super` + `Shift` + `:` como equivalentes
> de `<` y `>`, porque en teclado latam/es `Shift` + coma/punto no produce esos símbolos.

---

## 📏 Gaps — ⚠️ desactivados por defecto

**dwl no trae gaps**: esa función viene del parche *vanitygaps*, igual que en dwm.
Por eso estas teclas están **comentadas** en `config.h` y **no hacen nada** todavía.

Si algún día aplicas el parche, descomenta el bloque en `~/dwl/config.h`, ejecuta `dwl-rebuild` y tendrás:

| Atajo | Qué haría |
|---|---|
| `Super` + `Ctrl` + `U` | **Aumentar** la separación entre ventanas |
| `Super` + `Ctrl` + `Shift` + `U` | **Disminuir** la separación |
| `Super` + `Ctrl` + `0` | **Activar / desactivar** gaps |
| `Super` + `Ctrl` + `Shift` + `=` | **Restablecer** los gaps a su valor inicial |

---

## 🔊 Teclas especiales (sin Super)

| Tecla | Qué hace |
|---|---|
| Subir volumen | +3 % |
| Bajar volumen | −3 % |
| Mute | Silenciar o restaurar |
| Brillo arriba | +5 % |
| Brillo abajo | −5 % |
| `Print` / `Impr Pant` | **Captura de pantalla** (grim) → se guarda en `~/Pictures` |

---

## 🚪 Salir y consolas

| Atajo | Qué hace |
|---|---|
| `Super` + `Shift` + `E` | **Cerrar la sesión de dwl** (vuelves a tuigreet) |
| `Ctrl` + `Alt` + `Backspace` | Cerrar la sesión (atajo alternativo) |
| `Ctrl` + `Alt` + `F1` … `F12` | Cambiar de **consola (tty)** |

> ⚠️ **No borres los `Ctrl` + `Alt` + `Fx` de tu `config.h`.**
> Si dwl se congela, son la única manera de salir a una consola para hacer `sudo reboot`.

---

## 🖱️ Ratón sobre las ventanas

| Acción | Efecto |
|---|---|
| `Super` + **clic izquierdo** y arrastrar | **Mover** la ventana |
| `Super` + **clic central** | Alternar ventana **flotante** |
| `Super` + **clic derecho** y arrastrar | **Redimensionar** la ventana |

---

## 🖱️ Ratón sobre la barra (dwlb)

| Acción | Efecto |
|---|---|
| **Clic izquierdo** sobre la **fecha/hora** | Abre un **calendario** (`cal -3`) en foot |
| **Clic central** en la zona de **estado** | Abre una **terminal** (foot) |
| **Clic** en los **números de tag** | Solo funciona si dwlb está en modo `-ipc` |

### ¿Y clicar los números de tag con el ratón?

Depende de cómo se compiló dwl. El instalador lo detecta solo y te lo dice al terminar:

| Si al instalar viste… | Entonces… |
|---|---|
| `dwl incluye el protocolo IPC: dwlb usara -ipc (clic en los tags funcional)` | ✅ **Sí** puedes clicar los tags |
| `dwl sin parche IPC: dwlb leera el estado por stdin (-no-ipc)` | ❌ No funcionan; usa `Super` + `1`…`9` |

Para comprobarlo ahora mismo:

```bash
pgrep -a dwlb
```

- `dwlb -ipc` → los clics en los tags **funcionan**
- `dwlb -no-ipc` → **no** funcionan

> Los clics del **estado** (calendario y terminal) funcionan **en los dos modos**, porque van
> incrustados en el texto que genera `/usr/local/bin/dwlb-status`.

---

## 🎨 Cambiar estos atajos

```bash
nano ~/dwl/config.h     # 1. busca la tecla y cámbiala
sudo make clean install # 2. recompila e instala
# 3. Super + Shift + E para salir, y vuelve a entrar
```

| Archivo | Qué se cambia ahí |
|---|---|
| `~/dwl/config.h` | **Atajos**, colores, reglas de ventanas, teclado |
| `~/.config/dwlb/config` | Fuente y colores de la **barra** (no hace falta recompilar) |
| `/usr/local/bin/dwlb-status` | Qué se muestra en la barra (CPU, RAM, volumen, batería, reloj) y sus clics |
| `~/.config/lf/lfrc` | Comportamiento del gestor de archivos `lf` |
| `/usr/local/bin/dwl-session` | Programas y variables al iniciar sesión |

---

## 🔗 Referencias

| Proyecto | Enlace |
|---|---|
| **dwlb** (la barra) | https://github.com/kolunmi/dwlb |
| **dwl** (el compositor) | https://codeberg.org/dwl/dwl |
| **lf** (gestor de archivos) | https://github.com/gokcehan/lf |

Manuales en tu terminal: `man 1 dwlb` · `man 1 foot` · `man 1 lf`

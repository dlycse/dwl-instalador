
==============================================================================
 ATAJOS DE TECLADO - dwl + dwlb
==============================================================================
  Lista completa de los atajos que deja configurados el instalador.
  "Super" es la tecla del logo de Windows (en teclados Mac es Command).

------------------------------------------------------------------------------
 SI ACABAS DE INSTALAR, CON ESTO YA ALCANZA
------------------------------------------------------------------------------

  Super+Enter.................. abrir una terminal (foot)
  Super+d...................... lanzador de programas (wmenu)
  Super+q...................... cerrar la ventana actual
  Super+r...................... gestor de archivos (lf)
  Super+b...................... navegador (Firefox)
  Super+Shift+e................ cerrar sesion (volver al login)
  Ctrl+Alt+F1.................. consola de emergencia si algo se congela

  Con esos siete ya puedes manejarte. El resto lo vas aprendiendo sobre la
  marcha.

------------------------------------------------------------------------------
 GLOSARIO RAPIDO
------------------------------------------------------------------------------

  tag.......................... un "escritorio virtual"; hay 9 y cada uno
                                guarda sus ventanas
  area maestra................. la ventana grande y principal del mosaico
  layout....................... la forma en que se reparten las ventanas
  monocle...................... una sola ventana ocupando toda la pantalla
  flotante..................... ventana fuera del mosaico; la mueves a mano
  barra........................ la linea de arriba (dwlb): tags, layout, CPU,
                                RAM, hora
  gaps......................... separacion entre ventanas (vienen
                                DESACTIVADOS)

  dwl es un gestor de ventanas en mosaico: no apila ventanas como Windows, las
  reparte automaticamente por la pantalla.

------------------------------------------------------------------------------
 PROGRAMAS
------------------------------------------------------------------------------

  Super+d...................... lanzador de aplicaciones (wmenu)
  Super+Enter.................. terminal (foot)
  Super+t...................... terminal (foot), atajo alternativo
  Super+b...................... navegador (Firefox)
  Super+r...................... gestor de archivos (lf), se abre dentro de
                                foot

------------------------------------------------------------------------------
 VENTANAS
------------------------------------------------------------------------------

  Super+q...................... cerrar la ventana enfocada
  Super+j...................... enfocar la siguiente ventana
  Super+Abajo.................. enfocar la siguiente ventana (igual que
                                Super+j)
  Super+k...................... enfocar la ventana anterior
  Super+Arriba................. enfocar la ventana anterior (igual que
                                Super+k)
  Super+h...................... achicar el area maestra
  Super+l...................... agrandar el area maestra
  Super+i...................... una ventana mas en el area maestra
  Super+Shift+t................ volver la ventana flotante (o devolverla al
                                mosaico)
  Super+Shift+Enter............ traer la ventana actual al area maestra (zoom)

------------------------------------------------------------------------------
 BARRA (dwlb)
------------------------------------------------------------------------------

  Super+w...................... ocultar o mostrar la barra
  Super+Shift+w................ mover la barra arriba o abajo

  La barra es dwlb (https://github.com/kolunmi/dwlb). Muestra los tags, el
  layout activo, CPU, RAM, volumen, bateria y la hora.

------------------------------------------------------------------------------
 LAYOUTS
------------------------------------------------------------------------------

  []=.......................... mosaico: area maestra + columna de ventanas
                                (el inicial)
  "><>"........................ flotante: cada ventana se mueve y redimensiona
                                a mano
  [M].......................... monocle: una sola ventana ocupando todo

  Super+Space.................. rotar al layout siguiente o volver al anterior
  Super+f...................... ir directo a monocle
  Super+Shift+f................ pantalla completa real, sin barra (video,
                                juegos)

    Nota: El simbolo del layout activo se ve en la barra. El layout flotante
    ("><>") no tiene tecla propia: se llega rotando con Super+Space.

------------------------------------------------------------------------------
 TAGS (los 9 escritorios)
------------------------------------------------------------------------------

  Super+1 ... 9................ ir a ese tag
  Super+Shift+1 ... 9.......... mover la ventana actual a ese tag
  Super+Ctrl+1 ... 9........... ver ese tag junto con el actual
  Super+Ctrl+Shift+1..9........ la ventana aparece en ambos tags sin moverla
  Super+Tab.................... volver al tag anterior
  Super+0...................... ver los 9 tags a la vez

    Nota: En teclado latam/es, Shift+numero produce !"#$%&/() . El instalador
    ya registro las dos variantes, asi que Super+Shift+1..9 funciona en los
    tres layouts de teclado.

  Idea de uso: terminal en el tag 1, navegador en el 2, musica en el 3, chat
  en el 4.

------------------------------------------------------------------------------
 MONITORES
------------------------------------------------------------------------------

  Super+,...................... enfocar el monitor de la izquierda
  Super+....................... enfocar el monitor de la derecha
  Super+Shift+<................ enviar la ventana al monitor de la izquierda
  Super+Shift+>................ enviar la ventana al monitor de la derecha

    Nota: Tambien estan registrados Super+Shift+; y Super+Shift+: como
    equivalentes de < y >, porque en teclado latam/es Shift+coma y Shift+punto
    no producen esos simbolos.

------------------------------------------------------------------------------
 GAPS - DESACTIVADOS POR DEFECTO
------------------------------------------------------------------------------

  dwl NO trae gaps: esa funcion viene del parche vanitygaps, igual que en dwm.
  Por eso estas teclas estan COMENTADAS en config.h y no hacen nada.

  Si algun dia aplicas el parche, descomenta el bloque en ~/dwl/config.h,
  ejecuta dwl-rebuild y tendras:

  Super+Ctrl+u................. aumentar la separacion entre ventanas
  Super+Ctrl+Shift+u........... disminuir la separacion
  Super+Ctrl+0................. activar o desactivar gaps
  Super+Ctrl+Shift+=........... restablecer los gaps a su valor inicial

------------------------------------------------------------------------------
 TECLAS ESPECIALES (sin Super)
------------------------------------------------------------------------------

  Subir volumen................ sube 3 %
  Bajar volumen................ baja 3 %
  Mute......................... silenciar o restaurar
  Brillo arriba................ sube 5 %
  Brillo abajo................. baja 5 %
  Print / Impr Pant............ captura de pantalla (grim) en ~/Pictures

------------------------------------------------------------------------------
 SALIR Y CONSOLAS
------------------------------------------------------------------------------

  Super+Shift+e................ cerrar la sesion de dwl (vuelves a tuigreet)
  Ctrl+Alt+Backspace........... cerrar la sesion (atajo alternativo)
  Ctrl+Alt+F1 ... F12.......... cambiar de consola (tty)

  AVISO: no borres los Ctrl+Alt+Fx de tu config.h. Si dwl se congela son la
  unica manera de salir a una consola para hacer 'sudo reboot'.

------------------------------------------------------------------------------
 RATON SOBRE LAS VENTANAS
------------------------------------------------------------------------------

  Super+clic izquierdo......... mover la ventana (arrastrando)
  Super+clic central........... alternar ventana flotante
  Super+clic derecho........... redimensionar la ventana (arrastrando)

------------------------------------------------------------------------------
 RATON SOBRE LA BARRA
------------------------------------------------------------------------------

  clic izquierdo en la fecha... abre un calendario (cal -3) en foot
  clic central en el estado.... abre una terminal (foot)
  clic en los numeros de tag... SOLO funciona si dwlb esta en modo -ipc

  Para saber en que modo esta corriendo tu barra:

        pgrep -a dwlb

  dwlb -ipc.................... los clics en los tags funcionan
  dwlb -no-ipc................. no funcionan; usa Super+1 ... 9

    Nota: Los clics del estado (calendario y terminal) funcionan en los dos
    modos, porque van incrustados en el texto que genera
    /usr/local/bin/dwlb-status.

  El instalador detecta el modo solo y te lo dice al terminar:
    - "dwl incluye el protocolo IPC: dwlb usara -ipc (clic en los tags
    funcional)"
    - "dwl sin parche IPC: dwlb leera el estado por stdin (-no-ipc)"

------------------------------------------------------------------------------
 CAMBIAR ESTOS ATAJOS
------------------------------------------------------------------------------

  Paso 1....................... editar ~/dwl/config.h y cambiar la tecla
  Paso 2....................... ejecutar dwl-rebuild (recompila e instala)
  Paso 3....................... Super+Shift+e para salir y volver a entrar

------------------------------------------------------------------------------
 ARCHIVOS PARA PERSONALIZAR
------------------------------------------------------------------------------

  ~/dwl/config.h............... atajos, colores, reglas de ventanas, teclado
  ~/.config/dwlb/config........ fuente y colores de la barra (sin recompilar)
  /usr/local/bin/dwlb-status... que se muestra en la barra y sus clics
  ~/.config/lf/lfrc............ comportamiento del gestor de archivos lf
  /usr/local/bin/dwl-session... programas y variables al iniciar sesion

------------------------------------------------------------------------------
 REFERENCIAS
------------------------------------------------------------------------------

  dwlb (la barra).............. https://github.com/kolunmi/dwlb
  dwl (compositor)............. https://codeberg.org/dwl/dwl
  lf (archivos)................ https://github.com/gokcehan/lf

  Manuales en tu terminal: man 1 dwlb | man 1 foot | man 1 lf

==============================================================================

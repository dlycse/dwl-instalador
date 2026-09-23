VERSION 0.5 (BETA) puede contener errores

SOLO PARA VOID LINUX. Minimo 20gb libres para que no tenga errores de almacenamiento

RECUERDA INSTALAR GIT con el siguiente comando

|sudo xbps-install -S git|

1. Clonar el repositorio
Copia y pega este comando en tu terminal para descargar todo el código a tu máquina:


git clone https://github.com/dlycse/dwl-instalador.git


2. Entrar a la carpeta
Una vez que termine la descarga, entra en el directorio que se acaba de crear:

cd dwl-instalador


3. Darle permisos de ejecución
Como es un script de instalación (.sh):


chmod +x install-dwl.sh


4. Ejecutar el instalador
Ahora, inicia el proceso de instalación:


./install-dwl.sh

Se recomienda reiniciar si instalaste un kernel nuevo, si no instalaste kernel nuevo puedes iniciar sesión apenas inicie lightdm (si lightdm falla y no reinicia con el boton "restart" ve a una tty con ctrl+alt+f1 y realiza un sudo reboot) 

para editar los atajos de teclado, ingresar a /home/USUARIO/dwl y dentro editar config.h, hacer un sudo make clean install y por ultimo un super+shift+e para cerrar la sesion y volver a iniciarlo

como navegador de archivos tenemos lf, es un navegador de archivos por terminal (solo pones lf en la terminal. super+e)  
https://github.com/gokcehan/lf

deje un Atajos.md en la carpeta dwm-instalador para que veas los atajos predeterminados lo puedes verificar con nano 

puedes cambiar el fondo de pantalla cambiandole el nombre a wallpaper.jpg en /Pictures. (dentro encuentras el wallpaper predeterminado puedes borrarlo o puedes cambiarle el nombre y al nuevo fondo de pantalla le cambias el nombre a wallpaper.jpg)

||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||


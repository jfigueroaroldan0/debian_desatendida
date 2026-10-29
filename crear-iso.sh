#!/bin/bash

# Autor: Jesús Figueroa Roldán
# Versión: 1
# Descripción: genera una ISO de Debian 13 con instalación desatendida
# Fecha creación: 23-10-2026


# Genera una ISO de Debian 13 con instalación desatendida (BIOS y UEFI)
# a partir de la ISO oficial, y si se indica la graba en un USB.
#
# Uso: sudo ./crear-iso.sh [ruta de la ISO oficial]
# preseed.cfg y particiones.sh deben estar en esta misma carpeta. Si no se
# indica la ISO, se busca debian-13.7.0-amd64-netinst.iso en esta carpeta.


# Colores

RESET="\e[0m"
ROJO="\e[31m"
VERDE="\e[32m"

# Variables

# ISO oficial: la indicada como argumento o la de esta carpeta. Se guarda la
# ruta absoluta porque el script se cambia a su propia carpeta
ISO="$(realpath -m "${1:-$(dirname "$0")/debian-13.7.0-amd64-netinst.iso}")"
ISO_NUEVA="debian-13-preseed.iso"
FICHEROS="preseed.cfg particiones.sh"
ESPERA=5
ENTRADA="Instalacion desatendida Jesus Figueroa Roldan"

# Dispositivo del USB (por ejemplo /dev/sdb). Vacío para no grabar
USB=""

# Funciones

# Comprueba que el script se ejecuta como root.
# Entrada: no necesita.
# Salida: no devuelve nada si es root; si no, muestra un error y sale con 1.

comprobar_root() {
  if [ "$EUID" -ne 0 ]; then
    echo -e "${ROJO}[-] Este script se debe ejecutar con permisos de root.${RESET}"
    exit 1
  fi
}

# Comprueba que existen la ISO oficial, preseed.cfg y particiones.sh.
# Entrada: no necesita (usa las variables ISO y FICHEROS).
# Salida: no devuelve nada si están todos; si falta alguno, muestra cuál y
# sale con 1.

comprobar_ficheros() {
  for f in "$ISO" $FICHEROS; do
    if [ ! -f "$f" ]; then
      echo -e "${ROJO}[-] No se encuentra el fichero $f.${RESET}"
      exit 1
    fi
  done
}

# Instala los paquetes necesarios para crear la ISO si no lo están.
# Entrada: no necesita.
# Salida: instala xorriso y cpio si faltan.

instalar_paquetes() {
  for p in xorriso cpio; do
    if ! dpkg -s $p &>/dev/null; then
      echo -e "${VERDE}[+] Instalando el paquete $p.${RESET}"
      apt install -y $p 1>/dev/null
    fi
  done
}

# Extrae el contenido de la ISO oficial y le da permisos de escritura.
# Entrada: no necesita (usa la variable ISO).
# Salida: crea la carpeta isofiles/ con el contenido de la ISO.

extraer_iso() {
  echo -e "${VERDE}[+] Extrayendo la imagen ISO.${RESET}"
  rm -rf isofiles/
  xorriso -osirrox on -indev "$ISO" -extract / isofiles/ 2>/dev/null
  chmod -R u+w isofiles/
}

# Mete preseed.cfg y particiones.sh dentro de los initrd del instalador
# (texto y gráfico), para que el instalador lea el preseed al arrancar.
# Entrada: no necesita (usa la variable FICHEROS).
# Salida: modifica los initrd.gz de isofiles/install.amd/.

aniadir_preseed() {
  for INITRD in isofiles/install.amd/initrd.gz isofiles/install.amd/gtk/initrd.gz; do
    echo -e "${VERDE}[+] Añadiendo el preseed a ${INITRD#isofiles/}.${RESET}"
    gunzip "$INITRD"
    ls $FICHEROS | cpio -H newc -o -A -F "${INITRD%.gz}" 2>/dev/null
    gzip "${INITRD%.gz}"
  done
}

# Añade la entrada de instalación desatendida como primera opción y por
# defecto del menú de arranque, en GRUB (UEFI) y en isolinux (BIOS).
# Entrada: no necesita (usa la variable ENTRADA como texto de la entrada).
# Salida: modifica grub.cfg, gtk.cfg y menu.cfg y crea desatendida.cfg.

menu_desatendido() {
  echo -e "${VERDE}[+] Añadiendo la entrada '$ENTRADA' al menú de arranque.${RESET}"
  # UEFI: primera entrada del menú de GRUB, la que arranca por defecto
  sed -i "0,/^menuentry/s//menuentry '$ENTRADA' {\n\
    set background_color=black\n\
    linux    \/install.amd\/vmlinuz vga=788 --- quiet\n\
    initrd   \/install.amd\/initrd.gz\n\
}\nmenuentry/" isofiles/boot/grub/grub.cfg
  # BIOS: entrada de isolinux, que pasa a ser la de por defecto
  cat > isofiles/isolinux/desatendida.cfg <<EOF
label desatendida
	menu label $ENTRADA
	menu default
	kernel /install.amd/vmlinuz
	append vga=788 initrd=/install.amd/initrd.gz --- quiet
EOF
  sed -i '/menu default/d; s/^default installgui/default desatendida/' isofiles/isolinux/gtk.cfg
  sed -i 's/^include gtk.cfg/include desatendida.cfg\ninclude gtk.cfg/' isofiles/isolinux/menu.cfg
}

# Hace que el menú de arranque arranque solo la entrada por defecto.
# Entrada: no necesita (usa la variable ESPERA, en segundos).
# Salida: fija el tiempo de espera en isolinux.cfg (BIOS) y grub.cfg (UEFI).

arranque_automatico() {
  echo -e "${VERDE}[+] Menú de arranque automático a los $ESPERA segundos.${RESET}"
  # BIOS
  sed -i "s/^timeout .*/timeout $((ESPERA * 10))/" isofiles/isolinux/isolinux.cfg
  # UEFI
  echo "set timeout=$ESPERA" >> isofiles/boot/grub/grub.cfg
}

# Vuelve a calcular las sumas MD5 de los ficheros de la ISO, porque los
# initrd y los menús han cambiado.
# Entrada: no necesita.
# Salida: sobrescribe isofiles/md5sum.txt.

regenerar_md5sum() {
  echo -e "${VERDE}[+] Regenerando el fichero md5sum.txt.${RESET}"
  cd isofiles/
  find . -type f ! -name md5sum.txt -print0 | xargs -0 md5sum > md5sum.txt
  cd ../
}

# Genera la ISO nueva, arrancable desde CD o USB en BIOS y UEFI.
# Entrada: no necesita (usa las variables ISO e ISO_NUEVA).
# Salida: crea el fichero ISO_NUEVA en la carpeta del script.

generar_iso() {
  echo -e "${VERDE}[+] Generando la imagen ISO $ISO_NUEVA.${RESET}"
  # Sector de arranque MBR de la ISO original, para que arranque desde USB
  dd if="$ISO" bs=1 count=432 of=mbr.bin 2>/dev/null
  xorriso -as mkisofs \
    -r -V "Debian 13 preseed" \
    -o "$ISO_NUEVA" \
    -J -joliet-long \
    -isohybrid-mbr mbr.bin \
    -b isolinux/isolinux.bin \
    -c isolinux/boot.cat \
    -boot-load-size 4 -boot-info-table -no-emul-boot \
    -eltorito-alt-boot \
    -e boot/grub/efi.img \
    -no-emul-boot -isohybrid-gpt-basdat \
    isofiles/ 2>/dev/null
}

# Graba la ISO nueva en el USB indicado, después de pedir confirmación.
# Entrada: no necesita (usa la variable USB; si está vacía no hace nada).
# Salida: escribe la ISO en el USB si se responde "s"; si el dispositivo no
# existe, muestra un error.

grabar_usb() {
  if [ -z "$USB" ]; then
    return
  fi
  if [ ! -b "$USB" ]; then
    echo -e "${ROJO}[-] No existe el dispositivo $USB.${RESET}"
    return
  fi
  lsblk -d -o NAME,SIZE,MODEL "$USB"
  read -p "Se borrará todo el contenido de $USB. ¿Continuar? (s/n): " RESP
  if [ "$RESP" = "s" ]; then
    echo -e "${VERDE}[+] Grabando la ISO en $USB.${RESET}"
    dd if="$ISO_NUEVA" of="$USB" bs=4M status=progress conv=fsync
  fi
}

# Borra los ficheros temporales usados para generar la ISO.
# Entrada: no necesita.
# Salida: elimina la carpeta isofiles/ y el fichero mbr.bin.

limpiar() {
  echo -e "${VERDE}[+] Limpieza y finalización.${RESET}"
  rm -rf isofiles/ mbr.bin
}

# Programa principal

cd "$(dirname "$0")"
comprobar_root
comprobar_ficheros
instalar_paquetes
extraer_iso
aniadir_preseed
menu_desatendido
arranque_automatico
regenerar_md5sum
generar_iso
limpiar
grabar_usb

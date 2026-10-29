#!/bin/bash

# Autor: Jesús Figueroa Roldán
# Versión: 1
# Fecha creación: 23-10-2026


# Genera una ISO de Debian 13 con instalación desatendida (BIOS y UEFI)
# a partir de la ISO oficial, y si se indica la graba en un USB.
#
# Uso: sudo ./crear-iso.sh [ruta de la ISO oficial]
# preseed.cfg y particiones.sh deben estar en esta misma carpeta. Si no se
# indica la ISO, se busca debian-13.7.0-amd64-netinst.iso en esta carpeta.


RESET="\e[0m"
ROJO="\e[31m"
VERDE="\e[32m"

# ISO oficial: la indicada como argumento o la de esta carpeta. Se guarda la
# ruta absoluta porque el script se cambia a su propia carpeta
ISO="$(realpath -m "${1:-$(dirname "$0")/debian-13.7.0-amd64-netinst.iso}")"
ISO_NUEVA="debian-13-preseed.iso"
FICHEROS="preseed.cfg particiones.sh"
ESPERA=5
ENTRADA="Instalacion desatendida Jesus Figueroa Roldan"

# Dispositivo del USB (por ejemplo /dev/sdb). Vacío para no grabar
USB=""

comprobar_root() {
  if [ "$EUID" -ne 0 ]; then
    echo -e "${ROJO}[-] Este script se debe ejecutar con permisos de root.${RESET}"
    exit 1
  fi
}

comprobar_ficheros() {
  for f in "$ISO" $FICHEROS; do
    if [ ! -f "$f" ]; then
      echo -e "${ROJO}[-] No se encuentra el fichero $f.${RESET}"
      exit 1
    fi
  done
}

instalar_paquetes() {
  for p in xorriso cpio; do
    if ! dpkg -s $p &>/dev/null; then
      echo -e "${VERDE}[+] Instalando el paquete $p.${RESET}"
      apt install -y $p 1>/dev/null
    fi
  done
}

extraer_iso() {
  echo -e "${VERDE}[+] Extrayendo la imagen ISO.${RESET}"
  rm -rf isofiles/
  xorriso -osirrox on -indev "$ISO" -extract / isofiles/ 2>/dev/null
  chmod -R u+w isofiles/
}

aniadir_preseed() {
  for INITRD in isofiles/install.amd/initrd.gz isofiles/install.amd/gtk/initrd.gz; do
    echo -e "${VERDE}[+] Añadiendo el preseed a ${INITRD#isofiles/}.${RESET}"
    gunzip "$INITRD"
    ls $FICHEROS | cpio -H newc -o -A -F "${INITRD%.gz}" 2>/dev/null
    gzip "${INITRD%.gz}"
  done
}

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

arranque_automatico() {
  echo -e "${VERDE}[+] Menú de arranque automático a los $ESPERA segundos.${RESET}"
  # BIOS
  sed -i "s/^timeout .*/timeout $((ESPERA * 10))/" isofiles/isolinux/isolinux.cfg
  # UEFI
  echo "set timeout=$ESPERA" >> isofiles/boot/grub/grub.cfg
}

regenerar_md5sum() {
  echo -e "${VERDE}[+] Regenerando el fichero md5sum.txt.${RESET}"
  cd isofiles/
  find . -type f ! -name md5sum.txt -print0 | xargs -0 md5sum > md5sum.txt
  cd ../
}

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

limpiar() {
  echo -e "${VERDE}[+] Limpieza y finalización.${RESET}"
  rm -rf isofiles/ mbr.bin
}

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

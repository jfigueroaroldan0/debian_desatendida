#!/bin/sh

# Autor: Jesús Figueroa Roldán
# Versión: 1
# Descripción: calcula el particionado según el tamaño del disco y la RAM
# Fecha creación: 23-10-2026


# Calcula el particionado según el tamaño del disco y la RAM del equipo y
# prepara la receta de partman.
#
#   Particiones:  EFI (FAT32, solo UEFI) y /boot (ext4)
#   LVM:          /, swap y /home
#
# Uso: no se ejecuta a mano. Lo lanza el instalador desde
# partman/early_command del preseed.


# Porcentajes del espacio LVM (/home se queda con el resto)
RAIZ_PORC=40
SWAP_PORC=10

# Tamaños en MB
EFI=256
BOOT=1024
RAIZ_MIN=10240
SWAP_MIN=1024
HOME_MIN=2048
RESERVA=200

RECETA=/tmp/receta
LOG=/var/log/particiones.log


# Disco del USB de instalación, para no instalar encima de él
USB=$(grep ' /cdrom ' /proc/mounts | cut -d' ' -f1 | sed 's/[0-9]*$//')

# Tipo de un disco: nvme, ssd, hdd (SATA) o virtio. El USB de instalación y
# los demás discos USB son usb. El kernel marca los discos duros con
# rotational=1 y los SSD con 0
tipo_disco() {
    NOMBRE=${1#/dev/}
    if [ "$1" = "$USB" ]; then echo usb; return; fi
    case "$(readlink -f /sys/block/$NOMBRE)" in
        */usb*) echo usb; return ;;
    esac
    case "$NOMBRE" in
        nvme*) echo nvme ;;
        vd*)   echo virtio ;;
        sd*)
            if [ "$(cat /sys/block/$NOMBRE/queue/rotational)" = "0" ]; then
                echo ssd
            else
                echo hdd
            fi ;;
        *)     echo otro ;;
    esac
}

# Busca primero entre los NVMe, si no hay entre los SSD, luego entre los
# discos duros y por último entre los virtio. Del primer tipo que tenga
# discos se queda con el más grande. Los discos USB nunca se eligen
for TIPO in nvme ssd hdd virtio otro; do
    for D in $(list-devices disk); do
        if [ "$(tipo_disco "$D")" != "$TIPO" ]; then continue; fi
        TAM=$(cat /sys/block/${D#/dev/}/size)
        if [ -z "$DISCO" ] || [ $TAM -gt $MAYOR ]; then
            DISCO=$D
            MAYOR=$TAM
        fi
    done
    if [ -n "$DISCO" ]; then break; fi
done

# Tamaño del disco y de la RAM
TOTAL=$(( $(cat /sys/block/${DISCO#/dev/}/size) / 2048 ))
RAM=$(( $(grep MemTotal /proc/meminfo | awk '{print $2}') / 1024 ))

# Reparto por porcentajes
LIBRE=$((TOTAL - EFI - BOOT - RESERVA))
RAIZ=$((LIBRE * RAIZ_PORC / 100))
SWAP=$((LIBRE * SWAP_PORC / 100))

# Límites: / con espacio para GNOME y swap no mayor que la RAM
if [ $RAIZ -lt $RAIZ_MIN ]; then RAIZ=$RAIZ_MIN; fi
if [ $SWAP -gt $RAM ]; then SWAP=$RAM; fi
if [ $SWAP -lt $SWAP_MIN ]; then SWAP=$SWAP_MIN; fi
HOME_TAM=$((LIBRE - RAIZ - SWAP))


# Receta de partman: la línea de EFI solo se usa con tabla GPT (UEFI)
cat > $RECETA <<EOF
receta ::
    $EFI $EFI $EFI fat32
        \$iflabel{ gpt } \$reusemethod{ }
        method{ efi } format{ } .
    $BOOT $BOOT $BOOT ext4
        \$primary{ } \$bootable{ }
        method{ format } format{ }
        use_filesystem{ } filesystem{ ext4 } mountpoint{ /boot } .
    $RAIZ $RAIZ $RAIZ ext4
        \$lvmok{ } lv_name{ raiz }
        method{ format } format{ }
        use_filesystem{ } filesystem{ ext4 } mountpoint{ / } .
    $SWAP $SWAP $SWAP linux-swap
        \$lvmok{ } lv_name{ swap }
        method{ swap } format{ } .
    $HOME_MIN $HOME_TAM 1000000000 ext4
        \$lvmok{ } lv_name{ home }
        method{ format } format{ }
        use_filesystem{ } filesystem{ ext4 } mountpoint{ /home } .
EOF


# Disco de instalación, receta y disco de GRUB
debconf-set partman-auto/disk "$DISCO"
debconf-set partman-auto/expert_recipe_file "$RECETA"
debconf-set grub-installer/bootdev "$DISCO"


# Registro (late_command lo copia al sistema instalado)
cat > $LOG <<EOF
Disco: $DISCO ($TOTAL MB)   USB: ${USB:-ninguno}   RAM: $RAM MB
EFI:   $EFI MB
/boot: $BOOT MB
/:     $RAIZ MB
swap:  $SWAP MB
/home: $HOME_TAM MB o más
EOF

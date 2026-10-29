#!/bin/sh
#
# Calcula el particionado según el tamaño del disco y la RAM del equipo.
# Se ejecuta desde partman/early_command del preseed.
#
#   Particiones:  EFI (FAT32, solo UEFI) y /boot (ext4)
#   LVM:          /, swap y /home


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

# Primer disco que no sea el USB
for D in $(list-devices disk); do
    if [ "$D" != "$USB" ]; then
        DISCO=$D
        break
    fi
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

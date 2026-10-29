# Instalación desatendida de Debian 13 (trixie)

Autor: Jesús Figueroa Roldán

Proyecto para instalar Debian 13 con escritorio GNOME sin intervención del
usuario, en equipos con BIOS o UEFI. El preseed se puede usar de dos formas:

- **Desde una ISO personalizada** (USB o máquina virtual), generada con `crear-iso.sh`.
- **Por HTTP**, sirviendo el preseed desde un servidor web.

## Ficheros

| Fichero | Función |
|---|---|
| `preseed.cfg` | Respuestas a todas las preguntas del instalador. |
| `particiones.sh` | Calcula el particionado según el disco y la RAM del equipo. |
| `crear-iso.sh` | Genera la ISO desatendida a partir de la ISO oficial. |

Las ISO no están en el repositorio porque pesan demasiado (`.gitignore` las
excluye). La oficial hay que descargarla, y `debian-13-preseed.iso` la genera
el script.

## Método 1: ISO personalizada

Primero descarga la ISO oficial netinst de Debian 13 (amd64) desde
<https://www.debian.org/CD/netinst/>.

La ISO oficial tiene que estar **sí o sí en la carpeta del proyecto**, junto a
`crear-iso.sh`, `preseed.cfg` y `particiones.sh`, y con el nombre
`debian-13.7.0-amd64-netinst.iso`. Después, desde esa carpeta:

```
sudo ./crear-iso.sh
```

La ISO nueva, `debian-13-preseed.iso`, se crea también en esa carpeta.

El script:

1. Instala `xorriso` y `cpio` si faltan.
2. Extrae la ISO oficial.
3. Mete `preseed.cfg` y `particiones.sh` dentro del initrd del instalador
   (el de texto y el gráfico). Así el instalador lee el preseed nada más arrancar.
4. Añade al menú de arranque la entrada **"Instalacion desatendida Jesus
   Figueroa Roldan"** como primera opción, tanto en GRUB (UEFI) como en
   isolinux (BIOS). Arranca el instalador en modo texto.
5. Pone el menú en arranque automático a los 5 segundos.
6. Regenera `md5sum.txt` y crea `debian-13-preseed.iso`, arrancable desde USB
   en BIOS y UEFI.
7. Si la variable `USB` del script tiene un dispositivo (por ejemplo
   `/dev/sdb`), graba la ISO en él después de pedir confirmación.

Con la ISO solo hay que arrancar el equipo: no hay que escribir nada.

### Crear el USB de instalación

La ISO generada es **híbrida**: sirve tanto para CD como para USB. Grabada
tal cual en un USB, este queda arrancable en los dos modos:

- **BIOS:** por el sector de arranque MBR copiado de la ISO oficial
  (`-isohybrid-mbr`).
- **UEFI:** por la partición EFI que lleva la ISO (`-e boot/grub/efi.img` y
  `-isohybrid-gpt-basdat`).

No hace falta Rufus ni ningún otro programa para hacerlo arrancable; basta con
copiar la ISO al USB byte a byte. Hay dos formas de hacerlo.

#### Desde el script

Pon el USB en la variable `USB` al principio de `crear-iso.sh` y ejecútalo:

```bash
# Dispositivo del USB (por ejemplo /dev/sdb). Vacío para no grabar
USB="/dev/sdb"
```

Al terminar de generar la ISO, el script:

1. Comprueba que el dispositivo existe.
2. Muestra su nombre, tamaño y modelo con `lsblk`, para comprobar que es el
   USB y no otro disco.
3. Pide confirmación: solo graba si se responde `s`.
4. Graba la ISO con `dd` y espera a que esté todo escrito (`conv=fsync`),
   así que al terminar se puede sacar el USB sin riesgo.

#### A mano

Con la ISO ya generada:

```
sudo dd if=debian-13-preseed.iso of=/dev/sdb bs=4M status=progress conv=fsync
```

Desde Windows se puede usar Rufus, eligiendo el modo **DD** cuando lo pregunte.

#### Elegir el dispositivo

Para saber qué dispositivo es el USB, ejecuta `lsblk` antes y después de
conectarlo: el que aparece nuevo es el USB. Hay que poner el disco entero
(`/dev/sdb`), no una partición (`/dev/sdb1`).

> **Atención:** grabar la ISO borra todo el contenido del dispositivo. Si se
> pone el disco equivocado, se pierde todo lo que tenga.

## Método 2: por HTTP

1. Sirve `preseed.cfg` y `particiones.sh` por HTTP. Basta con levantar un
   servidor web con Python desde la carpeta del proyecto:

   ```
   sudo python3 -m http.server 80
   ```

   Sirve los ficheros de la carpeta actual en el puerto 80 (hace falta `sudo`
   por ser un puerto menor de 1024). Se para con `Ctrl+C` al terminar la
   instalación. Con `ip a` se ve la IP del equipo, que es la que va en la URL.
2. Arranca el equipo con la ISO oficial de Debian y entra en
   **Advanced options → Automated install** (o **Graphical automated install**).
3. El instalador configura la red y pide la ubicación del fichero de
   preconfiguración. Escribe la **ruta completa del preseed**, no solo la IP:

   ```
   http://192.168.1.10/preseed.cfg
   ```

   (cambiando `192.168.1.10` por la IP del servidor).

A partir de ahí la instalación sigue sola. Esa entrada ya arranca con
`auto=true priority=critical`, que retrasa las preguntas de idioma y teclado
hasta que se ha descargado el preseed, así que las responde el propio preseed.

> **Importante:** si solo se escribe la IP (`192.168.1.10`), el instalador
> busca el preseed en `http://192.168.1.10/d-i/trixie/./preseed.cfg` y no lo
> encuentra. Hay que escribir siempre `http://IP/preseed.cfg`. Además,
> `particiones.sh` se descarga durante la instalación de la misma carpeta que
> el preseed, así que los dos tienen que estar juntos en el servidor.

## Qué configura el preseed

- **Idioma y teclado:** español, España, `es_ES.UTF-8`, teclado español.
- **Red:** DHCP en la primera interfaz con enlace. Equipo `debian`, sin dominio.
- **Firmware:** carga sin preguntar el firmware no libre que haga falta.
- **Mirror:** `deb.debian.org`, sin proxy.
- **Repositorios:** main, contrib, non-free, non-free-firmware, security y updates.
- **Usuarios:**
  - `root` con contraseña `root`.
  - `debian` con contraseña `debian`, en el grupo `sudo` y con sudo sin contraseña.
- **Zona horaria:** Europe/Madrid, reloj en UTC y hora por NTP.
- **Software:** sistema estándar, GNOME y servidor SSH, más:
  - Flatpak con el repositorio Flathub, visible en la aplicación Software de GNOME.
  - Utilidades: `sudo`, `curl`, `wget`, `vim`, `nano`, `htop`, `tree`, `git`,
    `zip`, `unzip`, `rsync`, `lsof`, `net-tools`, `bind9-dnsutils`, etc.
  - Firmware wifi: Intel, Realtek, Atheros, Broadcom y MediaTek.
- **Actualización:** `full-upgrade` al terminar, sin actualizaciones automáticas.
- **GRUB:** se instala en el mismo disco del sistema. En UEFI también se copia a
  la ruta genérica, por si el firmware pierde la entrada.
- **Final:** el equipo se apaga al terminar, para poder quitar el USB y que no
  vuelva a instalar.

Las contraseñas están cifradas en SHA-512 en el preseed. Para cambiarlas,
genera un hash nuevo con `mkpasswd -m sha-512` (paquete `whois`).

## Particionado

Lo hace `particiones.sh`, que se ejecuta justo antes del particionado
(`partman/early_command`).

### Disco elegido

El script elige **un solo disco** y instala todo en él: **el más rápido y, si
hay varios del mismo tipo, el más grande**. Paso a paso:

1. **Descarta los discos USB.** Tanto el USB de instalación (el que está
   montado en `/cdrom`) como cualquier otro disco USB conectado, por ejemplo
   un disco duro externo. Así nunca instala en un disco externo.
2. **Busca por tipo de disco, del más rápido al más lento:**

   | Orden | Tipo de disco | Nombre en el sistema |
   |---|---|---|
   | 1 | NVMe | `/dev/nvme0n1`, `/dev/nvme1n1`... |
   | 2 | SSD SATA | `/dev/sda`, `/dev/sdb`... |
   | 3 | Disco duro (HDD) SATA | `/dev/sda`, `/dev/sdb`... |
   | 4 | Virtio (máquinas virtuales) | `/dev/vda`, `/dev/vdb`... |
   | 5 | Otros (eMMC, etc.) | `/dev/mmcblk0`... |

   Primero mira si hay algún NVMe; si no hay, algún SSD; si no, algún disco
   duro, y así. Para separar los SSD de los discos duros SATA usa el valor
   que da el kernel en `/sys/block/sdX/queue/rotational`: `1` es un disco que
   gira (HDD) y `0` uno que no (SSD).
3. **Del primer tipo que tenga discos, se queda con el más grande.**

GRUB se instala en ese mismo disco. Los demás discos no se tocan: ni se
formatean ni se montan.

> **Con varios discos en BIOS:** el equipo arranca desde el disco que esté
> primero en el orden de arranque de la BIOS, que no tiene por qué ser el que
> ha elegido el script. Si al terminar sale "No bootable device", hay que
> poner el disco elegido el primero en el orden de arranque. En UEFI no pasa,
> porque el instalador registra la entrada de Debian en el firmware.

> **Atención:** borra el disco elegido entero, sin preguntar.

El disco que se ha elegido queda apuntado en `/var/log/particiones.log` del
sistema instalado.

#### Ejemplos

| Discos del equipo | Disco elegido | Por qué |
|---|---|---|
| NVMe 512 GB + HDD SATA 2 TB | NVMe 512 GB | el NVMe es más rápido, aunque sea más pequeño |
| SSD SATA 250 GB + HDD SATA 2 TB | SSD 250 GB | el SSD es más rápido que el HDD |
| SSD SATA 250 GB + SSD SATA 500 GB | SSD 500 GB | igual de rápidos: gana el más grande |
| HDD SATA 500 GB + HDD SATA 1 TB | HDD 1 TB | igual de rápidos: gana el más grande |
| NVMe 256 GB + NVMe 1 TB + HDD SATA 4 TB | NVMe 1 TB | los NVMe son los más rápidos, y de ellos el más grande |
| Virtio 20 GB + virtio 50 GB (máquina virtual) | virtio 50 GB | igual de rápidos: gana el más grande |
| HDD SATA 500 GB + SSD USB externo 1 TB | HDD 500 GB | los discos USB se descartan siempre |

En el caso típico de un equipo con un disco rápido para el sistema (NVMe o
SSD) y un disco duro grande para datos, el sistema se instala en el rápido y el
de datos se queda como estaba.

En una máquina virtual el tipo de disco depende de cómo se configure: en
VirtualBox suelen ser SATA (`sda`) y en KVM/virt-manager virtio (`vda`). Los
discos SATA virtuales suelen aparecer como HDD aunque estén en un SSD.

### Esquema

| Partición | Tamaño | Sistema | Montaje |
|---|---|---|---|
| EFI (solo UEFI) | 256 MB | FAT32 | `/boot/efi` |
| `/boot` | 1024 MB | ext4 | `/boot` |
| LVM `vg-debian` | resto del disco | — | — |

Dentro del grupo LVM `vg-debian`:

| Volumen | Tamaño | Sistema | Montaje |
|---|---|---|---|
| `raiz` | 40 % (mínimo 10 GB) | ext4 | `/` |
| `swap` | 10 %, nunca más que la RAM (mínimo 1 GB) | swap | — |
| `home` | el resto (mínimo 2 GB) | ext4 | `/home` |

Los porcentajes se calculan sobre el espacio libre: el disco menos EFI,
`/boot` y 200 MB de reserva. Se pueden cambiar con las variables
`RAIZ_PORC` y `SWAP_PORC` al principio de `particiones.sh`.

La partición EFI solo se crea en UEFI, porque el instalador usa tabla GPT. En
BIOS usa tabla MBR y se salta esa línea.

### Ejemplo

Disco de 100 GB y 4 GB de RAM:

| Volumen | Tamaño |
|---|---|
| `/` | ~39 GB (40 %) |
| swap | 4 GB (el 10 % serían ~10 GB, pero se limita a la RAM) |
| `/home` | ~55 GB |

Al terminar, el reparto se guarda en `/var/log/particiones.log` del sistema instalado.

## Resolución de problemas

- **"Falló la ejecución de la orden de preconfiguración" con código 2 (HTTP):**
  no se ha podido descargar `particiones.sh`. Comprueba que está en la misma
  carpeta que `preseed.cfg` en el servidor.
- **Ver qué está pasando:** durante la instalación, `Alt+F4` muestra el log del
  instalador y `Alt+F2` abre una consola.

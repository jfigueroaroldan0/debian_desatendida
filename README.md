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
copiar la ISO al USB byte a byte. Hay dos formas:

- **Desde el script:** pon el USB en la variable `USB` al principio de
  `crear-iso.sh` y ejecútalo. Al terminar de generar la ISO:
  1. Comprueba que el dispositivo existe.
  2. Muestra su nombre, tamaño y modelo con `lsblk`, para comprobar que es el
     USB y no otro disco.
  3. Pide confirmación: solo graba si se responde `s`.
  4. Graba la ISO con `dd` y espera a que esté todo escrito (`conv=fsync`),
     así que al terminar se puede sacar el USB sin riesgo.

  ```bash
  # Dispositivo del USB (por ejemplo /dev/sdb). Vacío para no grabar
  USB="/dev/sdb"
  ```

- **A mano**, con la ISO ya generada:

  ```
  sudo dd if=debian-13-preseed.iso of=/dev/sdb bs=4M status=progress conv=fsync
  ```

  Desde Windows se puede usar Rufus, eligiendo el modo **DD** cuando lo pregunte.

Para saber qué dispositivo es el USB, ejecuta `lsblk` antes y después de
conectarlo: el que aparece nuevo es el USB. Hay que poner el disco entero
(`/dev/sdb`), no una partición (`/dev/sdb1`).

> **Atención:** grabar la ISO borra todo el contenido del dispositivo. Si se
> pone el disco equivocado, se pierde todo lo que tenga.

## Método 2: por HTTP

1. Copia `preseed.cfg` y `particiones.sh` en **la misma carpeta** de un
   servidor web.
2. Arranca el equipo con la ISO oficial de Debian y entra en
   **Advanced options → Automated install** (o **Graphical automated install**).
3. El instalador configura la red y pide la ubicación del fichero de
   preconfiguración. Escribe la URL completa del preseed:

   ```
   http://IP/preseed.cfg
   ```

A partir de ahí la instalación sigue sola. Esa entrada ya arranca con
`auto=true priority=critical`, que retrasa las preguntas de idioma y teclado
hasta que se ha descargado el preseed, así que las responde el propio preseed.

`particiones.sh` no va dentro del preseed, así que se descarga durante la
instalación desde la misma carpeta que `preseed.cfg`. Por eso hay que escribir
la URL completa: con solo la IP, el instalador busca el preseed en
`/d-i/trixie/` y el script tendría que estar en esa carpeta.

### Nombre del equipo

Por HTTP la red se configura antes de descargar el preseed, así que el equipo
coge el nombre que le dé el servidor DHCP en vez de `debian`. Para forzarlo,
antes de arrancar la entrada **Automated install** pulsa `e` (UEFI) o `Tab`
(BIOS) y añade al final de la línea del kernel:

```
hostname=debian domain=
```

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

Usa el primer disco del equipo **que no sea el USB de instalación**. El USB lo
detecta por el dispositivo montado en `/cdrom`. GRUB se instala en ese mismo disco.

> **Atención:** borra el disco elegido entero, sin preguntar.

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

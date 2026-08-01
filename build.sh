#!/bin/bash
set -e

echo "=== [1/6] Instalando dependências de build ==="
sudo apt-get update
sudo apt-get install -y squashfs-tools xorriso genisoimage wget curl rsync unsquashfs

WORK_DIR="/tmp/iso_work"
mkdir -p "$WORK_DIR/extracted" "$WORK_DIR/rootfs" "$WORK_DIR/output"

ISO_URL="https://releases.ubuntu.com/24.04/xubuntu-24.04.1-desktop-amd64.iso"
ISO_NAME="base.iso"

echo "=== [2/6] Baixando ISO base ==="
if [ ! -f "$WORK_DIR/$ISO_NAME" ]; then
    wget -O "$WORK_DIR/$ISO_NAME" "$ISO_URL"
fi

echo "=== [3/6] Extraindo a ISO ==="
sudo xorriso -osirrox on -indev "$WORK_DIR/$ISO_NAME" -extract / "$WORK_DIR/extracted"
chmod -R +w "$WORK_DIR/extracted"

SFS_PATH=$(find "$WORK_DIR/extracted" -name "filesystem.squashfs" -o -name "airootfs.sfs" -quit)
if [ -z "$SFS_PATH" ]; then
    echo "Erro: Arquivo squashfs não encontrado!"
    exit 1
fi

echo "=== [4/6] Extraindo o sistema de arquivos (Rootfs) ==="
sudo unsquashfs -d "$WORK_DIR/rootfs" "$SFS_PATH"

echo "=== Aplicando customizações e identidade visual da CallieOS ==="
echo "callieos" | sudo tee "$WORK_DIR/rootfs/etc/hostname"
sudo cp /etc/resolv.conf "$WORK_DIR/rootfs/etc/resolv.conf"

sudo mkdir -p "$WORK_DIR/rootfs/usr/share/backgrounds/callie"
sudo mkdir -p "$WORK_DIR/rootfs/usr/share/pixmaps"
sudo mkdir -p "$WORK_DIR/rootfs/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml"

if [ -f "./assets/wallpaper1.png" ]; then
    sudo cp ./assets/wallpaper1.png "$WORK_DIR/rootfs/usr/share/backgrounds/callie/wallpaper1.png"
fi

if [ -f "./assets/wallpaper2.png" ]; then
    sudo cp ./assets/wallpaper2.png "$WORK_DIR/rootfs/usr/share/backgrounds/callie/wallpaper2.png"
fi

if [ -f "./assets/logo.png" ]; then
    sudo cp ./assets/logo.png "$WORK_DIR/rootfs/usr/share/pixmaps/CallieLogo.png"
fi

sudo tee "$WORK_DIR/rootfs/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml" > /dev/null << 'XFCEXML'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-desktop" version="1.0">
  <property name="backdrop" type="empty">
    <property name="screen0" type="empty">
      <property name="monitor0" type="empty">
        <property name="image-path" type="string" value="/usr/share/backgrounds/callie/wallpaper1.png"/>
        <property name="image-style" type="int" value="5"/>
      </property>
    </property>
  </property>
</channel>
XFCEXML

sudo chroot "$WORK_DIR/rootfs" /bin/bash <<EOF
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y fastfetch curl wget git steam lutris flatpak xfce4-goodies
apt-get clean
EOF

echo "=== [5/6] Recompactando o SquashFS ==="
sudo rm -f "$SFS_PATH"
sudo mksquashfs "$WORK_DIR/rootfs" "$SFS_PATH" -comp xz -b 1M -noappend

echo "=== [6/6] Gerando a nova ISO final da CallieOS ==="
cd "$WORK_DIR/extracted"

sudo xorriso -as mkisofs \
    -iso-level 3 \
    -full-iso9660-filenames \
    -volid "CallieOS_XFCE" \
    -eltorito-boot boot/grub/i386-pc/eltorito.img \
    -eltorito-catalog boot/grub/i386-pc/boot.cat \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    --eltorito-alt-boot \
    -e boot/grub/efi.img \
    -no-emul-boot \
    -output "$WORK_DIR/output/CallieOS-Mint-XFCE.iso" \
    .

echo "=== Sucesso! ISO gerada em: $WORK_DIR/output/CallieOS-Mint-XFCE.iso ==="
ls -lh "$WORK_DIR/output/CallieOS-Mint-XFCE.iso"

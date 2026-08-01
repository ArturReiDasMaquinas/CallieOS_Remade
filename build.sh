#!/bin/bash
set -e

echo "=== [1/6] Instalando dependências de build ==="
sudo apt-get update
sudo apt-get install -y squashfs-tools xorriso p7zip-full wget curl rsync

WORK_DIR="./iso_work"
mkdir -p "$WORK_DIR/extracted" "$WORK_DIR/rootfs" "$WORK_DIR/output"

echo "=== [2/6] Determinando e baixando a ISO base do Ubuntu 24.04 LTS dinamicamente ==="
BASE_URL="https://releases.ubuntu.com/24.04"
ISO_FILE=$(curl -s "$BASE_URL/" | grep -oE 'ubuntu-24.04([0-9.-]*)-desktop-amd64\.iso' | head -n 1)

if [ -z "$ISO_FILE" ]; then
    ISO_FILE="ubuntu-24.04-desktop-amd64.iso"
fi

ISO_URL="$BASE_URL/$ISO_FILE"
ISO_NAME="base.iso"

echo "Baixando de: $ISO_URL"
if [ ! -f "$WORK_DIR/$ISO_NAME" ]; then
    wget -O "$WORK_DIR/$ISO_NAME" "$ISO_URL"
fi

echo "=== [3/6] Extraindo a ISO com 7z ==="
sudo rm -rf "$WORK_DIR/extracted"/*
7z x "$WORK_DIR/$ISO_NAME" -o"$WORK_DIR/extracted" -y
sudo chmod -R +w "$WORK_DIR/extracted"

SFS_PATH=$(find "$WORK_DIR/extracted" -iname "*squashfs*" -o -iname "*.sfs" | head -n 1)

if [ -z "$SFS_PATH" ]; then
    echo "Erro: Arquivo squashfs não encontrado!"
    exit 1
fi

echo "Arquivo SquashFS encontrado em: $SFS_PATH"

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

# Instalando pacotes, Steam, Lutris e limpando listas
sudo chroot "$WORK_DIR/rootfs" /bin/bash <<EOF
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y xubuntu-desktop fastfetch curl wget git steam lutris flatpak xfce4-goodies
apt-get clean
rm -rf /var/lib/apt/lists/*
EOF

echo "=== [5/6] Criando Swap temporário e Recompactando o SquashFS sem risco de OOM ==="
# Cria 4GB de swap para garantir que o GitHub Actions não mate o processo por falta de RAM
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

sudo rm -f "$SFS_PATH"
# Usando lz4, bloco otimizado de 256k e sem checagem de duplicatas para poupar RAM ao máximo
sudo mksquashfs "$WORK_DIR/rootfs" "$SFS_PATH" -comp lz4 -b 256k -no-duplicates -no-xattrs -processors 2 -noappend

# Desativa o swap após terminar
sudo swapoff /swapfile
sudo rm -f /swapfile

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

cp "$WORK_DIR/output/CallieOS-Mint-XFCE.iso" "./CallieOS-Mint-XFCE.iso"

echo "=== Sucesso! ISO gerada e copiada para a raiz do repositório ==="
ls -lh ./CallieOS-Mint-XFCE.iso

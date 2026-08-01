#!/bin/bash
set -e

echo "=== [0/6] Limpeza agressiva de espaço no runner ==="
sudo docker image prune -a --force || true
sudo rm -rf /usr/local/lib/android
sudo rm -rf /opt/ghc
sudo rm -rf /opt/hostedtoolcache
sudo rm -rf /usr/share/dotnet
sudo rm -rf /usr/local/share/boost
sudo rm -rf /nix
df -h

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

# Seleciona automaticamente o maior .squashfs (sistema principal)
SFS_PATH=""
MAX_SIZE=0
while IFS= read -r file; do
    if [ -f "$file" ]; then
        SIZE=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null)
        if [ "$SIZE" -gt "$MAX_SIZE" ]; then
            MAX_SIZE="$SIZE"
            SFS_PATH="$file"
        fi
    fi
done < <(find "$WORK_DIR/extracted" -name "*.squashfs")

if [ -z "$SFS_PATH" ]; then
    echo "Erro: Nenhum arquivo squashfs foi encontrado na ISO!"
    exit 1
fi

echo "Arquivo SquashFS principal selecionado: $SFS_PATH"

echo "=== [4/6] Extraindo o sistema de arquivos (Rootfs) ==="
sudo unsquashfs -d "$WORK_DIR/rootfs" "$SFS_PATH"

# Remove o squashfs original e a ISO base para liberar gigabytes
sudo rm -f "$SFS_PATH"
sudo rm -f "$WORK_DIR/$ISO_NAME"

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

# Instalando pacotes e fazendo limpeza profunda de cache
sudo chroot "$WORK_DIR/rootfs" /bin/bash <<EOF
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y xubuntu-desktop fastfetch curl wget git steam lutris flatpak xfce4-goodies
apt-get clean
apt-get autoremove -y
rm -rf /var/lib/apt/lists/*
rm -rf /tmp/* /var/tmp/*
EOF

echo "=== [5/6] Criando 8GB de Swap e Recompactando com segurança máxima ==="
sudo fallocate -l 8G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

NEW_SFS_DIR=$(dirname "$SFS_PATH")
sudo mkdir -p "$NEW_SFS_DIR"

# Uso de -processors 1 e -no-recovery para zerar risco de estourar a RAM
sudo mksquashfs "$WORK_DIR/rootfs" "$SFS_PATH" -comp lz4 -b 256k -no-recovery -no-duplicates -no-xattrs -processors 1 -noappend

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

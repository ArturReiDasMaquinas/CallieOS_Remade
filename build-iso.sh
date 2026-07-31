#!/bin/bash
set -e

echo "=== [1/6] Instalando dependências de build ==="
sudo apt-get update
sudo apt-get install -y squashfs-tools xorriso genisoimage wget curl rsync unsquashfs

WORK_DIR="/tmp/iso_work"
mkdir -p "$WORK_DIR/extracted" "$WORK_DIR/rootfs" "$WORK_DIR/output"

# URL da ISO base (exemplo: Xubuntu 24.04 LTS ou Linux Mint XFCE base)
# Você pode substituir pelo link direto da ISO que preferir
ISO_URL="https://releases.ubuntu.com/24.04/xubuntu-24.04.1-desktop-amd64.iso"
ISO_NAME="base.iso"

echo "=== [2/6] Baixando ISO base ==="
if [ ! -f "$WORK_DIR/$ISO_NAME" ]; then
    wget -O "$WORK_DIR/$ISO_NAME" "$ISO_URL"
fi

echo "=== [3/6] Extraindo a ISO ==="
sudo xorriso -osirrox on -indev "$WORK_DIR/$ISO_NAME" -extract / "$WORK_DIR/extracted"
chmod -R +w "$WORK_DIR/extracted"

# Localizar o arquivo squashfs
SFS_PATH=$(find "$WORK_DIR/extracted" -name "filesystem.squashfs" -o -name "airootfs.sfs" -quit)
if [ -z "$SFS_PATH" ]; then
    echo "Erro: Arquivo squashfs não encontrado!"
    exit 1
fi

echo "=== [4/6] Extraindo o sistema de arquivos (Rootfs) ==="
sudo unsquashfs -d "$WORK_DIR/rootfs" "$SFS_PATH"

# ==========================================
# APLICAÇÃO DE CUSTOMIZAÇÕES DA CALLIEOS
# ==========================================
echo "=== Aplicando customizações da CallieOS ==="

# Definir hostname da live session
echo "callieos-live" | sudo tee "$WORK_DIR/rootfs/etc/hostname"

# Adicionar repositórios ou atualizar pacotes (opcional)
sudo cp /etc/resolv.conf "$WORK_DIR/rootfs/etc/resolv.conf"

# Exemplo de comandos executados via chroot para instalar ferramentas/temas
sudo chroot "$WORK_DIR/rootfs" /bin/bash <<EOF
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y neofetch htop git curl xfce4-goodies
# Adicione aqui mais comandos de personalização se desejar
apt-get clean
EOF

# Injetar wallpapers ou arquivos personalizados (se houver uma pasta 'assets' no repo)
if [ -d "./assets" ]; then
    sudo cp -r ./assets/* "$WORK_DIR/rootfs/usr/share/backgrounds/" 2>/dev/null || true
fi

# ==========================================
# RECOMPILAÇÃO DA ISO
# ==========================================
echo "=== [5/6] Recompactando o SquashFS ==="
sudo rm -f "$SFS_PATH"
sudo mksquashfs "$WORK_DIR/rootfs" "$SFS_PATH" -comp xz -b 1M -noappend

echo "=== [6/6] Gerando a nova ISO final da CallieOS ==="
cd "$WORK_DIR/extracted"

# Recriar a ISO bootável compatível com UEFI e Legacy BIOS
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

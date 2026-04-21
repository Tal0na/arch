#!/bin/bash
set -e

# Configurações de hardware (Ajuste conforme a VM)
DISCO="/dev/vda"
HOSTNAME="talona-vm"
USUARIO="talona"
SENHA="123"

# Configurar teclado para o nosso padrão
loadkeys br-abnt2

# Garantir que o relógio está certo para não dar erro no download dos pacotes
timedatectl set-ntp true

echo "--- Iniciando Instalação Arch KDE Minimal ---"

# 1. Preparação de Disco
wipefs -a "$DISCO"
parted -s "$DISCO" mklabel gpt
parted -s "$DISCO" mkpart primary fat32 1MiB 513MiB
parted -s "$DISCO" set 1 esp on
parted -s "$DISCO" mkpart primary ext4 513MiB 100%

mkfs.fat -F32 "${DISCO}1"
mkfs.ext4 -F "${DISCO}2"

# 2. Montagem
mount "${DISCO}2" /mnt
mount --mkdir "${DISCO}1" /mnt/boot

# 3. Pacstrap (Base + Drivers + KDE Minimal)
# Instalando apenas o essencial do Plasma para manter leve
echo "Baixando pacotes (isso pode demorar)..."
pacstrap -K /mnt \
    base base-devel linux linux-firmware \
    nano git networkmanager pipewire pipewire-pulse \
    limine efibootmgr \
    xorg-server \
    plasma-desktop sddm konsole dolphin \
    noto-fonts

# 4. Gerar FSTAB
genfstab -U /mnt >> /mnt/etc/fstab

# 5. Configuração Interna (Chroot)
echo "Entrando no sistema para configurações finais..."

arch-chroot /mnt /bin/bash <<EOF
    # Localização e Relógio
    ln -sf /usr/share/zoneinfo/America/Sao_Paulo /etc/localtime
    hwclock --systohc
    echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
    locale-gen
    echo "LANG=en_US.UTF-8" > /etc/locale.conf
    echo "$HOSTNAME" > /etc/hostname

    # Criação de Usuário
    useradd -m -G wheel "$USUARIO"
    echo "root:$SENHA" | chpasswd
    echo "$USUARIO:$SENHA" | chpasswd
    echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers

    # Habilitar Serviços (Rede e Interface Gráfica)
    systemctl enable NetworkManager
    systemctl enable sddm

    # Configuração do Limine (Bootloader)
    cp /usr/share/limine/BOOTX64.EFI /boot/

    # Pegar o UUID do disco para o boot
    UUID_RAIZ=\$(blkid -s UUID -o value ${DISCO}2)

    cat > /boot/limine.conf <<CFG
TIMEOUT=3
SERIAL=yes

:Arch Linux (KDE Minimal)
    PROTOCOL=linux
    KERNEL_PATH=boot:///vmlinuz-linux
    MODULE_PATH=boot:///initramfs-linux.img
    CMDLINE=root=UUID=\$UUID_RAIZ rw
CFG

    limine bios-install $DISCO
EOF

echo "--- Tudo pronto! ---"
echo "Agora é só desmontar e reiniciar: umount -R /mnt && reboot"

#!/usr/bin/env bash
# =============================================================================
#  install.sh — Instalador Arch Linux
#  Boot: UEFI | FS: ext4 | Bootloader: Limine | DE: KDE minimal
#  Uso: rode pelo live ISO do Arch
# =============================================================================

set -euo pipefail

# ─── Cores ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info()  { echo -e "${CYAN}[INFO]${RESET}  $*"; }
ok()    { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
err()   { echo -e "${RED}[ERRO]${RESET}  $*" >&2; exit 1; }

header() {
    echo -e "\n${BOLD}${BLUE}══════════════════════════════════════${RESET}"
    echo -e "${BOLD}${BLUE}  $*${RESET}"
    echo -e "${BOLD}${BLUE}══════════════════════════════════════${RESET}\n"
}

banner() {
    clear
    echo -e "${BOLD}${BLUE}"
    echo "  ████████╗ █████╗ ██╗      ██████╗ ███╗   ██╗  █████╗ "
    echo "     ██╔══╝██╔══██╗██║     ██╔═══██╗████╗  ██║ ██╔══██╗"
    echo "     ██║   ███████║██║     ██║   ██║██╔██╗ ██║ ███████║"
    echo "     ██║   ██╔══██║██║     ██║   ██║██║╚██╗██║ ██╔══██║"
    echo "     ██║   ██║  ██║███████╗╚██████╔╝██║ ╚████║ ██║  ██║"
    echo "     ╚═╝   ╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚═╝  ╚═══╝╚═╝  ╚═╝"
    echo -e "${RESET}${CYAN}                   arch installer${RESET}"
    echo
}

# =============================================================================
#  CONFIGURAÇÃO — edite aqui antes de rodar
# =============================================================================

DISK=""
HOSTNAME="arch"
USERNAME="tales"
TIMEZONE="America/Sao_Paulo"
LOCALE="pt_BR.UTF-8"
KEYMAP="br-abnt2"
LANG_EXTRA="en_US.UTF-8"

EXTRA_PACKAGES=(
    linux-headers
    efibootmgr
    networkmanager
    network-manager-applet
    pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber
    git curl wget
    htop btop
    neovim
    bash-completion
    reflector
    pacman-contrib
    # VM support
    virtualbox-guest-utils
    open-vm-tools
    # KDE minimal
    plasma-desktop
    plasma-pa
    plasma-nm
    dolphin
    konsole
    sddm
    xorg-server
    # Fontes
    ttf-jetbrains-mono-nerd
    noto-fonts
)

# =============================================================================
#  FUNÇÕES
# =============================================================================

check_uefi() {
    [[ -d /sys/firmware/efi ]] || err "Sistema não iniciou em modo UEFI. Use a ISO em modo UEFI."
    ok "Modo UEFI detectado."
}

check_internet() {
    info "Verificando conexão..."
    ping -c 1 archlinux.org &>/dev/null || err "Sem conexão com a internet."
    ok "Internet OK."
}

select_disk() {
    if [[ -n "$DISK" ]]; then
        info "Disco definido manualmente: $DISK"
        return
    fi

    header "Selecionar Disco"
    echo -e "${YELLOW}Discos disponíveis:${RESET}\n"
    lsblk -d -o NAME,SIZE,MODEL | grep -v "loop"
    echo
    read -rp "$(echo -e "${YELLOW}Digite o disco (ex: sda, nvme0n1, vda): ${RESET}")" DISK
    DISK="/dev/$DISK"

    [[ -b "$DISK" ]] || err "Disco $DISK não encontrado."

    echo -e "\n${RED}${BOLD}ATENÇÃO: $DISK será completamente apagado!${RESET}"
    read -rp "$(echo -e "${YELLOW}Confirmar? [s/N]: ${RESET}")" ans
    [[ "${ans,,}" == "s" ]] || { warn "Cancelado."; exit 0; }
}

partition_disk() {
    header "Particionando $DISK"

    if [[ "$DISK" == *"nvme"* ]] || [[ "$DISK" == *"mmcblk"* ]]; then
        PART_EFI="${DISK}p1"
        PART_ROOT="${DISK}p2"
    else
        PART_EFI="${DISK}1"
        PART_ROOT="${DISK}2"
    fi

    info "Criando tabela de partição GPT..."
    sgdisk --zap-all "$DISK"
    sgdisk -n 1:0:+512M -t 1:ef00 -c 1:"EFI"  "$DISK"
    sgdisk -n 2:0:0     -t 2:8300 -c 2:"ROOT" "$DISK"
    partprobe "$DISK"
    sleep 2

    ok "Partições criadas: EFI=$PART_EFI  ROOT=$PART_ROOT"
}

format_partitions() {
    header "Formatando Partições"
    info "Formatando EFI como FAT32..."
    mkfs.fat -F32 "$PART_EFI"
    info "Formatando ROOT como ext4..."
    mkfs.ext4 -F "$PART_ROOT"
    ok "Formatação concluída."
}

mount_partitions() {
    header "Montando Partições"
    mount "$PART_ROOT" /mnt
    mkdir -p /mnt/boot/efi
    mount "$PART_EFI" /mnt/boot/efi
    ok "Partições montadas."
}

install_base() {
    header "Instalando Sistema Base"

    info "Atualizando mirrors..."
    reflector --latest 10 --sort rate --country Brazil --protocol https \
        --save /etc/pacman.d/mirrorlist 2>/dev/null || warn "reflector falhou, continuando."

    info "Instalando pacotes base..."
    pacstrap -K /mnt base base-devel linux linux-firmware "${EXTRA_PACKAGES[@]}"
    ok "Sistema base instalado."
}

configure_system() {
    header "Configurando Sistema"

    info "Gerando fstab..."
    genfstab -U /mnt >> /mnt/etc/fstab

    info "Configurando timezone..."
    arch-chroot /mnt ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
    arch-chroot /mnt hwclock --systohc

    info "Configurando locale..."
    sed -i "s/^#${LOCALE}/${LOCALE}/" /mnt/etc/locale.gen
    sed -i "s/^#${LANG_EXTRA}/${LANG_EXTRA}/" /mnt/etc/locale.gen
    arch-chroot /mnt locale-gen
    echo "LANG=$LOCALE" > /mnt/etc/locale.conf
    echo "KEYMAP=$KEYMAP" > /mnt/etc/vconsole.conf

    info "Configurando hostname..."
    echo "$HOSTNAME" > /mnt/etc/hostname
    cat > /mnt/etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
EOF

    ok "Sistema configurado."
}

install_limine() {
    header "Instalando Limine Bootloader"

    arch-chroot /mnt pacman -S --noconfirm limine

    # Copiar EFI
    mkdir -p /mnt/boot/efi/EFI/BOOT
    cp /mnt/usr/share/limine/BOOTX64.EFI /mnt/boot/efi/EFI/BOOT/BOOTX64.EFI

    # Registrar entrada UEFI
    local disk_short
    disk_short=$(basename "$DISK")
    local part_num
    part_num=$(echo "$PART_EFI" | grep -o '[0-9]*$')

    efibootmgr \
        --create \
        --disk "$DISK" \
        --part "$part_num" \
        --label "Limine" \
        --loader "\\EFI\\BOOT\\BOOTX64.EFI" \
        --verbose

    # UUID da partição root
    ROOT_UUID=$(blkid -s UUID -o value "$PART_ROOT")

    # Configuração do Limine
    cat > /mnt/boot/efi/limine.conf <<EOF
timeout: 5

/Arch Linux
    protocol: linux
    kernel_path: boot():/vmlinuz-linux
    cmdline: root=UUID=${ROOT_UUID} rw quiet
    module_path: boot():/initramfs-linux.img

/Arch Linux (fallback)
    protocol: linux
    kernel_path: boot():/vmlinuz-linux
    cmdline: root=UUID=${ROOT_UUID} rw
    module_path: boot():/initramfs-linux-fallback.img
EOF

    # Copiar kernel e initramfs para a EFI também (garantia)
    cp /mnt/boot/vmlinuz-linux /mnt/boot/efi/
    cp /mnt/boot/initramfs-linux.img /mnt/boot/efi/
    cp /mnt/boot/initramfs-linux-fallback.img /mnt/boot/efi/

    ok "Limine instalado e registrado no UEFI."
}

create_user() {
    header "Criando Usuário"

    arch-chroot /mnt useradd -m -G wheel,audio,video,storage -s /bin/bash "$USERNAME"

    echo -e "\n${YELLOW}Senha para $USERNAME:${RESET}"
    arch-chroot /mnt passwd "$USERNAME"

    echo -e "\n${YELLOW}Senha para root:${RESET}"
    arch-chroot /mnt passwd root

    sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /mnt/etc/sudoers
    ok "Usuário $USERNAME criado."
}

enable_services() {
    header "Habilitando Serviços"

    arch-chroot /mnt systemctl enable NetworkManager
    arch-chroot /mnt systemctl enable sddm
    arch-chroot /mnt systemctl enable reflector.timer
    arch-chroot /mnt systemctl enable vboxservice  2>/dev/null || true
    arch-chroot /mnt systemctl enable vmtoolsd     2>/dev/null || true

    ok "Serviços habilitados."
}

# =============================================================================
#  MAIN
# =============================================================================

banner

[[ $EUID -eq 0 ]] || err "Execute como root (você está no live ISO)."

check_uefi
check_internet
select_disk
partition_disk
format_partitions
mount_partitions
install_base
configure_system
install_limine
create_user
enable_services

echo -e "\n${BOLD}${GREEN}══════════════════════════════════════${RESET}"
echo -e "${BOLD}${GREEN}  instalação concluída!${RESET}"
echo -e "${BOLD}${GREEN}══════════════════════════════════════${RESET}"
echo -e "\n  rode ${CYAN}umount -R /mnt${RESET} e depois ${CYAN}reboot${RESET}\n"

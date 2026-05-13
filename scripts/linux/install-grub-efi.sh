#!/usr/bin/env bash
# install-grub-efi.sh
#
# GRUB2 を UEFI/EFI 環境にインストール(または再インストール)し、
# UEFI ファームウェアにブートエントリを登録します。
#
# 使い方:
#   sudo bash scripts/linux/install-grub-efi.sh                       # /boot/efi がマウント済み前提
#   sudo bash scripts/linux/install-grub-efi.sh --bootloader-id ubuntu
#
# 補足:
#   - distro 推奨パッケージ(grub-efi-amd64-signed / grub2-efi-x64 等)が
#     入っていることを前提とします。
#   - インストール後、GRUB の設定ファイルも update-grub / grub-mkconfig で生成します。

set -euo pipefail

BOOTLOADER_ID=""
EFI_DIR="/boot/efi"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --bootloader-id) BOOTLOADER_ID="${2:?bootloader id required}"; shift 2;;
        --efi-dir)       EFI_DIR="${2:?efi dir required}"; shift 2;;
        -h|--help)
            sed -n '2,16p' "$0"
            exit 0;;
        *)
            echo "[error] 不明な引数: $1" >&2
            exit 2;;
    esac
done

if [[ $EUID -ne 0 ]]; then
    echo "[error] root 権限が必要です。sudo を付けて実行してください。" >&2
    exit 1
fi
if [[ ! -d /sys/firmware/efi ]]; then
    echo "[error] このシステムは UEFI モードで起動していません。" >&2
    exit 1
fi
if ! mountpoint -q "${EFI_DIR}"; then
    echo "[error] ESP が ${EFI_DIR} にマウントされていません。" >&2
    echo "        先に 'sudo mount /boot/efi' などでマウントしてください。" >&2
    exit 1
fi

# distro 検出して bootloader-id のデフォルトを決める
if [[ -z "${BOOTLOADER_ID}" ]]; then
    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        BOOTLOADER_ID="${ID:-grub}"
    else
        BOOTLOADER_ID="grub"
    fi
fi

# grub-install / grub2-install どちらかを採用
if command -v grub-install >/dev/null 2>&1; then
    GRUB_INSTALL=grub-install
elif command -v grub2-install >/dev/null 2>&1; then
    GRUB_INSTALL=grub2-install
else
    echo "[error] grub-install / grub2-install が見つかりません。" >&2
    echo "        Debian/Ubuntu: sudo apt install grub-efi-amd64-signed" >&2
    echo "        Fedora       : sudo dnf install grub2-efi-x64 grub2-efi-x64-modules" >&2
    echo "        Arch         : sudo pacman -S grub efibootmgr" >&2
    exit 1
fi

if command -v update-grub >/dev/null 2>&1; then
    GRUB_MKCONFIG="update-grub"
    GRUB_CFG_PATH=""
elif command -v grub-mkconfig >/dev/null 2>&1; then
    GRUB_MKCONFIG="grub-mkconfig"
    GRUB_CFG_PATH="/boot/grub/grub.cfg"
elif command -v grub2-mkconfig >/dev/null 2>&1; then
    GRUB_MKCONFIG="grub2-mkconfig"
    GRUB_CFG_PATH="/boot/grub2/grub.cfg"
else
    echo "[error] update-grub / grub-mkconfig が見つかりません。" >&2
    exit 1
fi

echo "[info] grub-install: ${GRUB_INSTALL}"
echo "[info] efi-dir     : ${EFI_DIR}"
echo "[info] bootloader  : ${BOOTLOADER_ID}"
echo "[info] grub-mkconf : ${GRUB_MKCONFIG} ${GRUB_CFG_PATH}"
echo

"${GRUB_INSTALL}" \
    --target=x86_64-efi \
    --efi-directory="${EFI_DIR}" \
    --bootloader-id="${BOOTLOADER_ID}" \
    --recheck

echo
if [[ -n "${GRUB_CFG_PATH}" ]]; then
    "${GRUB_MKCONFIG}" -o "${GRUB_CFG_PATH}"
else
    "${GRUB_MKCONFIG}"
fi

echo
echo "[ok] GRUB を ${EFI_DIR}/EFI/${BOOTLOADER_ID}/ にインストールしました。"
echo "     ブート順を最優先にする場合は scripts/linux/set-grub-first.sh を実行してください。"

#!/usr/bin/env bash
# restore-windows-boot-entry.sh
#
# remove-windows-boot-entry.sh で削除した Windows Boot Manager の
# UEFI NVRAM エントリを、保存しておいたバックアップ情報から再登録します。
#
# 使い方:
#   sudo bash scripts/linux/restore-windows-boot-entry.sh
#   sudo bash scripts/linux/restore-windows-boot-entry.sh --backup-dir /var/lib/dualboot
#   sudo bash scripts/linux/restore-windows-boot-entry.sh --dry-run

set -euo pipefail

DRY_RUN=0
BACKUP_DIR="/var/lib/dualboot"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)    DRY_RUN=1; shift;;
        --backup-dir) BACKUP_DIR="${2:?dir required}"; shift 2;;
        -h|--help)    sed -n '2,11p' "$0"; exit 0;;
        *) echo "[error] 不明な引数: $1" >&2; exit 2;;
    esac
done

if [[ $EUID -ne 0 ]]; then
    echo "[error] root 権限が必要です。" >&2
    exit 1
fi
if [[ ! -d /sys/firmware/efi ]]; then
    echo "[error] UEFI モードで起動していません。" >&2
    exit 1
fi
if ! command -v efibootmgr >/dev/null 2>&1; then
    echo "[error] efibootmgr が必要です。" >&2
    exit 1
fi

backup_file="${BACKUP_DIR}/windows-boot-entry.backup"
if [[ ! -f "${backup_file}" ]]; then
    echo "[error] バックアップファイルが見つかりません: ${backup_file}" >&2
    echo "        --backup-dir で指定するか、手動で再登録してください:" >&2
    echo "        sudo efibootmgr --create --disk /dev/<DISK> --part <PART> \\" >&2
    echo "             --label 'Windows Boot Manager' \\" >&2
    echo "             --loader '\\EFI\\Microsoft\\Boot\\bootmgfw.efi'" >&2
    exit 1
fi

DISK=""; PART=""; LABEL=""; LOADER=""
# shellcheck disable=SC1090
source "${backup_file}"

if [[ -z "${DISK}" || -z "${PART}" || -z "${LOADER}" ]]; then
    echo "[error] バックアップファイルに必要な情報が欠けています。" >&2
    cat "${backup_file}" >&2
    exit 1
fi
[[ -z "${LABEL}" ]] && LABEL="Windows Boot Manager"

echo "[info] 復元する内容:"
echo "       DISK   = ${DISK}"
echo "       PART   = ${PART}"
echo "       LABEL  = ${LABEL}"
echo "       LOADER = ${LOADER}"

if [[ ${DRY_RUN} -eq 1 ]]; then
    echo "[dry-run] 次のコマンドを実行する予定でした:"
    echo "          efibootmgr --create --disk ${DISK} --part ${PART} --label '${LABEL}' --loader '${LOADER}'"
    exit 0
fi

# 既に同名・同パスのエントリが居れば二重登録しない
if efibootmgr -v | grep -Ei 'windows boot manager|bootmgfw\.efi' >/dev/null; then
    echo "[info] 既に Windows Boot Manager 相当のエントリが存在するようです。"
    efibootmgr -v | grep -Ei 'windows boot manager|bootmgfw\.efi' | sed 's/^/       /'
    echo "       新規作成は行いません。必要なら efibootmgr で手動操作してください。"
    exit 0
fi

efibootmgr --create \
    --disk "${DISK}" \
    --part "${PART}" \
    --label "${LABEL}" \
    --loader "${LOADER}" >/dev/null

echo "[ok] Windows Boot Manager を NVRAM に再登録しました。"
echo
efibootmgr | grep -E '^(BootOrder|BootCurrent):' || true
echo
echo "BootOrder の中での位置を変えたい場合:"
echo "  Linux 最優先のまま : sudo bash scripts/linux/set-grub-first.sh"
echo "  Windows 最優先     : sudo bash scripts/linux/set-windows-first.sh"

#!/usr/bin/env bash
# remove-windows-boot-entry.sh
#
# UEFI NVRAM の Windows Boot Manager エントリ (BootXXXX) を削除します。
# ESP 上の \EFI\Microsoft\Boot\bootmgfw.efi ファイル自体は **削除しません**。
# 削除後の Windows 起動経路は GRUB のチェーンロード menuentry になります。
#
# 想定ユースケース:
#   * Windows Boot Manager が UEFI ブートメニューに居続けるのが嫌
#   * Windows Update を恒久停止している (例: ReviOS) ため再生成の心配がない
#   * GRUB から Windows を呼び出せれば十分
#
# 安全弁:
#   1. UEFI モードで起動しているか
#   2. ESP が /boot/efi にマウントされているか
#   3. \EFI\Microsoft\Boot\bootmgfw.efi が ESP に **存在する**(無いと delete は危険)
#   4. GRUB の grub.cfg に Windows をチェーンロードする menuentry がある
#      (--skip-grub-check で抑止可)
#   5. 削除前に復元用情報を BACKUP_DIR に書き出す
#
# 使い方:
#   sudo bash scripts/linux/remove-windows-boot-entry.sh                 # 自動検出
#   sudo bash scripts/linux/remove-windows-boot-entry.sh --boot-id 0000  # 明示指定
#   sudo bash scripts/linux/remove-windows-boot-entry.sh --dry-run       # 何も変更しない
#   sudo bash scripts/linux/remove-windows-boot-entry.sh --skip-grub-check
#   sudo bash scripts/linux/remove-windows-boot-entry.sh --backup-dir /var/lib/dualboot
#
# 復元したくなったら:
#   sudo bash scripts/linux/restore-windows-boot-entry.sh

set -euo pipefail

DRY_RUN=0
EXPLICIT_ID=""
SKIP_GRUB_CHECK=0
BACKUP_DIR="/var/lib/dualboot"
EFI_DIR="/boot/efi"
LOADER_REL='\EFI\Microsoft\Boot\bootmgfw.efi'
LOADER_FS_PATH="/boot/efi/EFI/Microsoft/Boot/bootmgfw.efi"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)          DRY_RUN=1; shift;;
        --boot-id)          EXPLICIT_ID="${2:?boot id required}"; shift 2;;
        --skip-grub-check)  SKIP_GRUB_CHECK=1; shift;;
        --backup-dir)       BACKUP_DIR="${2:?dir required}"; shift 2;;
        --efi-dir)          EFI_DIR="${2:?efi dir required}"
                            LOADER_FS_PATH="${EFI_DIR}/EFI/Microsoft/Boot/bootmgfw.efi"
                            shift 2;;
        -h|--help)          sed -n '2,30p' "$0"; exit 0;;
        *) echo "[error] 不明な引数: $1" >&2; exit 2;;
    esac
done

# --- 前提チェック ----------------------------------------------------------

if [[ $EUID -ne 0 ]]; then
    echo "[error] root 権限が必要です。sudo を付けて実行してください。" >&2
    exit 1
fi
if [[ ! -d /sys/firmware/efi ]]; then
    echo "[error] UEFI モードで起動していません。本スクリプトは UEFI 専用です。" >&2
    exit 1
fi
if ! command -v efibootmgr >/dev/null 2>&1; then
    echo "[error] efibootmgr が必要です。" >&2
    exit 1
fi
if ! mountpoint -q "${EFI_DIR}"; then
    echo "[error] ESP が ${EFI_DIR} にマウントされていません。" >&2
    echo "        sudo mount ${EFI_DIR}  などでマウント後、再実行してください。" >&2
    exit 1
fi
if [[ ! -f "${LOADER_FS_PATH}" ]]; then
    echo "[error] ${LOADER_FS_PATH} が見つかりません。" >&2
    echo "        Windows のブートローダ本体が無いと、削除後 Windows は起動できなくなります。" >&2
    echo "        中止します。" >&2
    exit 1
fi

# --- Windows Boot Manager の Boot ID を特定 ------------------------------

detect_windows_id() {
    efibootmgr -v \
        | awk '/^Boot[0-9A-Fa-f]{4}/ {
                id = substr($1, 5, 4);
                rest = $0;
                sub(/^Boot[0-9A-Fa-f]{4}\*?[ \t]+/, "", rest);
                print id "\t" rest;
              }' \
        | grep -Ei 'windows boot manager|bootmgfw\.efi' \
        | head -n1 \
        | awk '{print $1}'
}

if [[ -n "${EXPLICIT_ID}" ]]; then
    win_id="${EXPLICIT_ID}"
else
    win_id=$(detect_windows_id || true)
fi

if [[ -z "${win_id:-}" ]]; then
    echo "[info] Windows Boot Manager の UEFI エントリは見つかりませんでした。"
    echo "       既に削除されている可能性があります。何もしません。"
    exit 0
fi

win_line=$(efibootmgr -v | awk -v id="Boot${win_id}" '$1 ~ "^"id {sub("^"id"\\*?[ \t]+",""); print; exit}')
echo "[info] 削除対象: Boot${win_id}  ${win_line}"

# --- GRUB の Windows menuentry を確認 ------------------------------------

if [[ ${SKIP_GRUB_CHECK} -eq 0 ]]; then
    grub_cfg=""
    for cand in /boot/grub/grub.cfg /boot/grub2/grub.cfg /boot/efi/EFI/*/grub.cfg; do
        [[ -f "${cand}" ]] && grub_cfg="${cand}" && break
    done
    if [[ -z "${grub_cfg}" ]]; then
        echo "[error] grub.cfg が見つかりません。--skip-grub-check で強制実行できますが、" >&2
        echo "        その場合 Windows を起動する手段が一時的に失われます。" >&2
        exit 1
    fi
    if ! grep -qiE 'bootmgfw\.efi|Windows Boot Manager' "${grub_cfg}"; then
        echo "[error] ${grub_cfg} に Windows のチェーンロード menuentry が見つかりません。" >&2
        echo "        次を実行してから再試行してください:" >&2
        echo "          sudo apt install os-prober                   # 必要なら" >&2
        echo "          sudo sed -i 's/^#\\?GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub" >&2
        echo "          sudo update-grub  または  sudo grub-mkconfig -o ${grub_cfg}" >&2
        echo "        どうしても先に進めるには --skip-grub-check を付けてください。" >&2
        exit 1
    fi
    echo "[ok] ${grub_cfg} に Windows のチェーンロード menuentry を確認しました。"
fi

# --- 復元用バックアップを書き出す -----------------------------------------

esp_dev=$(findmnt -no SOURCE "${EFI_DIR}")
if [[ -z "${esp_dev}" ]]; then
    echo "[error] ESP デバイスを特定できませんでした。" >&2
    exit 1
fi
esp_base=$(basename "${esp_dev}")
disk_name=$(lsblk -no PKNAME "${esp_dev}" 2>/dev/null || true)
if [[ -z "${disk_name}" ]]; then
    echo "[error] ESP の親ディスクを特定できませんでした。" >&2
    exit 1
fi
disk_dev="/dev/${disk_name}"
part_num=""
if [[ -r "/sys/class/block/${esp_base}/partition" ]]; then
    part_num=$(cat "/sys/class/block/${esp_base}/partition")
fi
if [[ -z "${part_num}" ]]; then
    part_num=$(echo "${esp_base}" | sed -E 's/^.*[^0-9]([0-9]+)$/\1/')
fi

label=$(echo "${win_line}" | awk -F'\t' '{print $1}' | sed -E 's/[ \t]*HD\(.*//')
[[ -z "${label}" ]] && label="Windows Boot Manager"

mkdir -p "${BACKUP_DIR}"
backup_file="${BACKUP_DIR}/windows-boot-entry.backup"
ts=$(date -Iseconds)
{
    echo "# Windows Boot Manager UEFI entry backup"
    echo "# Created: ${ts}"
    echo "# Original entry line:"
    echo "#   Boot${win_id}* ${win_line}"
    echo "BOOT_ID=${win_id}"
    echo "DISK=${disk_dev}"
    echo "PART=${part_num}"
    echo "LABEL=${label}"
    echo "LOADER=${LOADER_REL}"
} > "${backup_file}"
chmod 0600 "${backup_file}"

echo "[ok] 復元情報を ${backup_file} に保存しました。"
echo "    ($(cat "${backup_file}" | grep -E '^[A-Z_]+=' | tr '\n' ' '))"

# --- 実行 -----------------------------------------------------------------

if [[ ${DRY_RUN} -eq 1 ]]; then
    echo "[dry-run] 次のコマンドを実行する予定でした:"
    echo "          efibootmgr -b ${win_id} -B"
    echo "          (バックアップは保存済み: ${backup_file})"
    exit 0
fi

if mountpoint -q /sys/firmware/efi/efivars; then
    if ! grep -q ' /sys/firmware/efi/efivars .* rw' /proc/mounts; then
        echo "[info] /sys/firmware/efi/efivars を rw で再マウントします。"
        mount -o remount,rw /sys/firmware/efi/efivars
    fi
fi

efibootmgr -b "${win_id}" -B >/dev/null
echo "[ok] Boot${win_id} (Windows Boot Manager) を NVRAM から削除しました。"
echo "     ESP 上の ${LOADER_REL} ファイルは温存されています。"
echo "     Windows は GRUB のメニューから起動してください。"
echo
echo "復元したくなったら:"
echo "  sudo bash scripts/linux/restore-windows-boot-entry.sh"
echo
efibootmgr | grep -E '^(BootOrder|BootCurrent):' || true

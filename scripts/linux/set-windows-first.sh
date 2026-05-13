#!/usr/bin/env bash
# set-windows-first.sh
#
# UEFI のブート順 (BootOrder) の先頭に Windows Boot Manager を配置します。
# set-grub-first.sh の対称版。Linux をメインに運用していて
# 一時的に / 機種の都合で Windows を最優先に戻したい場合に使用します。
#
# 使い方:
#   sudo bash scripts/linux/set-windows-first.sh                # 自動検出
#   sudo bash scripts/linux/set-windows-first.sh --boot-id 0000 # 明示的に指定
#   sudo bash scripts/linux/set-windows-first.sh --dry-run      # 変更せず表示のみ

set -euo pipefail

DRY_RUN=0
EXPLICIT_ID=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=1; shift;;
        --boot-id) EXPLICIT_ID="${2:?boot id required}"; shift 2;;
        -h|--help)
            sed -n '2,11p' "$0"
            exit 0;;
        *)
            echo "[error] 不明な引数: $1" >&2
            exit 2;;
    esac
done

if ! command -v efibootmgr >/dev/null 2>&1; then
    echo "[error] efibootmgr が必要です(apt/dnf/pacman で導入してください)。" >&2
    exit 1
fi
if [[ ! -d /sys/firmware/efi ]]; then
    echo "[error] UEFI モードで起動していません。本スクリプトは UEFI 環境専用です。" >&2
    exit 1
fi
if [[ $EUID -ne 0 ]]; then
    echo "[error] root 権限が必要です。sudo を付けて実行してください。" >&2
    exit 1
fi

current_order=$(efibootmgr | awk '/^BootOrder:/ {print $2}')
if [[ -z "${current_order}" ]]; then
    echo "[error] BootOrder が読み取れません。efibootmgr の出力を確認してください。" >&2
    exit 1
fi

detect_windows_id() {
    # description が "Windows Boot Manager" / path が bootmgfw.efi のものを優先
    efibootmgr -v \
        | awk '/^Boot[0-9A-Fa-f]{4}/ {
                id = substr($1, 5, 4);
                rest = $0;
                sub(/^Boot[0-9A-Fa-f]{4}\*?[ \t]+/, "", rest);
                print id "\t" rest;
              }' \
        | grep -Ei 'windows boot manager|bootmgfw\.efi|microsoft' \
        | head -n1 \
        | awk '{print $1}'
}

if [[ -n "${EXPLICIT_ID}" ]]; then
    win_id="${EXPLICIT_ID}"
else
    win_id=$(detect_windows_id || true)
fi

if [[ -z "${win_id:-}" ]]; then
    echo "[error] Windows Boot Manager のエントリを自動検出できませんでした。" >&2
    echo "        現在のエントリ一覧:" >&2
    efibootmgr -v | sed 's/^/        /' >&2
    echo "        該当する Boot ID を確認の上、--boot-id <ID> を指定して再実行してください。" >&2
    exit 1
fi

label=$(efibootmgr | awk -v id="Boot${win_id}" '$1 ~ "^"id {sub("^"id"\\*?[ \t]+",""); print; exit}')
echo "[info] Windows と判定したエントリ: Boot${win_id}  ${label}"

new_order=$(awk -v first="${win_id}" -v list="${current_order}" '
    BEGIN {
        n = split(list, a, ",");
        printf "%s", first;
        for (i = 1; i <= n; i++) {
            if (toupper(a[i]) != toupper(first)) printf ",%s", a[i];
        }
    }
')

echo "[info] 旧 BootOrder: ${current_order}"
echo "[info] 新 BootOrder: ${new_order}"

if [[ ${DRY_RUN} -eq 1 ]]; then
    echo "[dry-run] --dry-run が指定されたので変更は適用しません。"
    exit 0
fi

if mountpoint -q /sys/firmware/efi/efivars; then
    if ! grep -q ' /sys/firmware/efi/efivars .* rw' /proc/mounts; then
        echo "[info] /sys/firmware/efi/efivars を rw で再マウントします。"
        mount -o remount,rw /sys/firmware/efi/efivars
    fi
fi

efibootmgr -o "${new_order}" >/dev/null
echo "[ok] BootOrder を更新しました。次回起動時から Windows Boot Manager が最優先になります。"
echo "     Linux に戻すには: sudo bash scripts/linux/set-grub-first.sh"
echo
efibootmgr | grep -E '^(BootOrder|BootCurrent):' || true

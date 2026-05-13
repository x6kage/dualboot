#!/usr/bin/env bash
# set-grub-first.sh
#
# UEFI のブート順 (BootOrder) の先頭に GRUB を配置します。
# Windows Boot Manager 等の他エントリはその後ろに残ります。
#
# 使い方:
#   sudo bash scripts/linux/set-grub-first.sh                # 自動検出
#   sudo bash scripts/linux/set-grub-first.sh --boot-id 0001 # 明示的に指定
#   sudo bash scripts/linux/set-grub-first.sh --dry-run      # 変更せず表示のみ

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

# 1. 既存の BootOrder を取得
current_order=$(efibootmgr | awk '/^BootOrder:/ {print $2}')
if [[ -z "${current_order}" ]]; then
    echo "[error] BootOrder が読み取れません。efibootmgr の出力を確認してください。" >&2
    exit 1
fi

# 2. GRUB のエントリ ID を決定
detect_grub_id() {
    # 候補となるラベル(大文字小文字無視)。よくある distro 名と "GRUB" を含む。
    local pattern='ubuntu|debian|arch|fedora|manjaro|opensuse|suse|endeavour|pop|kali|mint|nixos|grub|linux boot manager|elementary|zorin|garuda'
    efibootmgr \
        | awk '/^Boot[0-9A-Fa-f]{4}/ {
                id = substr($1, 5, 4);
                rest = $0;
                sub(/^Boot[0-9A-Fa-f]{4}\*?[ \t]+/, "", rest);
                print id "\t" rest;
              }' \
        | grep -Eiv 'windows boot manager|microsoft' \
        | grep -Ei "${pattern}" \
        | head -n1 \
        | awk '{print $1}'
}

if [[ -n "${EXPLICIT_ID}" ]]; then
    grub_id="${EXPLICIT_ID}"
else
    grub_id=$(detect_grub_id || true)
fi

if [[ -z "${grub_id:-}" ]]; then
    echo "[error] GRUB の UEFI エントリを自動検出できませんでした。" >&2
    echo "        現在のエントリ一覧:" >&2
    efibootmgr | sed 's/^/        /' >&2
    echo "        該当する Boot ID を確認の上、--boot-id <ID> を指定して再実行してください。" >&2
    exit 1
fi

label=$(efibootmgr | awk -v id="Boot${grub_id}" '$1 ~ "^"id {sub("^"id"\\*?[ \t]+",""); print; exit}')
echo "[info] GRUB と判定したエントリ: Boot${grub_id}  ${label}"

# 3. 新しい BootOrder を組み立て(grub_id を先頭に、残りの順は維持)
new_order=$(awk -v first="${grub_id}" -v list="${current_order}" '
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

# 4. efivars が rw でマウントされているか保険
if mountpoint -q /sys/firmware/efi/efivars; then
    if ! grep -q ' /sys/firmware/efi/efivars .* rw' /proc/mounts; then
        echo "[info] /sys/firmware/efi/efivars を rw で再マウントします。"
        mount -o remount,rw /sys/firmware/efi/efivars
    fi
fi

efibootmgr -o "${new_order}" >/dev/null
echo "[ok] BootOrder を更新しました。次回起動時から GRUB が最優先になります。"
echo
efibootmgr | grep -E '^(BootOrder|BootCurrent):' || true

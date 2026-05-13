#!/usr/bin/env bash
# show-boot-order.sh
#
# 現在の UEFI ブート順 (BootOrder) と各エントリを見やすく表示します。
# 読み取り専用なので副作用はありません。
#
# 使い方:
#   sudo bash scripts/linux/show-boot-order.sh

set -euo pipefail

if ! command -v efibootmgr >/dev/null 2>&1; then
    echo "[error] efibootmgr が見つかりません。次でインストールしてください:" >&2
    echo "        Debian/Ubuntu: sudo apt install efibootmgr" >&2
    echo "        Fedora       : sudo dnf install efibootmgr" >&2
    echo "        Arch         : sudo pacman -S efibootmgr" >&2
    exit 1
fi

if [[ ! -d /sys/firmware/efi ]]; then
    echo "[error] このシステムは UEFI モードで起動していません(BIOS/Legacy モード)。" >&2
    echo "        efibootmgr / BootOrder は使えません。" >&2
    exit 1
fi

if [[ $EUID -ne 0 ]]; then
    echo "[error] root 権限が必要です。sudo を付けて実行してください。" >&2
    exit 1
fi

echo "=== UEFI ブートエントリ一覧 ==="
efibootmgr -v
echo

echo "=== 解説 ==="
order=$(efibootmgr | awk '/^BootOrder:/ {print $2}')
if [[ -z "${order}" ]]; then
    echo "BootOrder が読み取れませんでした。"
    exit 0
fi

echo "BootOrder の先頭から順に起動が試行されます。"
echo "現在の優先順位:"
i=1
IFS=',' read -ra entries <<< "${order}"
for id in "${entries[@]}"; do
    label=$(efibootmgr | awk -v id="Boot${id}" '$1 ~ "^"id {sub("^"id"\\*?[ \t]+",""); print; exit}')
    printf "  %2d. Boot%s  %s\n" "${i}" "${id}" "${label}"
    i=$((i+1))
done

current=$(efibootmgr | awk '/^BootCurrent:/ {print $2}')
if [[ -n "${current}" ]]; then
    echo
    echo "今このセッションで起動したのは: Boot${current}"
fi

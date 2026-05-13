#!/usr/bin/env bash
# repair-grub.sh
#
# Linux ライブ USB から chroot して GRUB を修復するための簡略化スクリプト。
# Windows Update で GRUB が消えた、grub-install をやり直したい、等のケースに使用します。
#
# 使い方:
#   sudo ROOT_PART=/dev/nvme0n1p5 ESP_PART=/dev/nvme0n1p1 \
#        bash scripts/linux/repair-grub.sh
#
# 引数(環境変数):
#   ROOT_PART  … Linux のルート(/)パーティション(必須)
#   ESP_PART   … EFI System Partition(必須・UEFI 環境)
#   BIOS=1     … レガシー BIOS / MBR の場合に指定。代わりに GRUB_DISK が必要。
#   GRUB_DISK  … BIOS 時、grub-install のターゲットディスク(例: /dev/sda)
#
# 内部で行うこと:
#   1. ROOT_PART を /mnt にマウント
#   2. ESP_PART を /mnt/boot/efi にマウント(UEFI のみ)
#   3. /dev /proc /sys /run を bind mount、UEFI なら efivars も
#   4. /etc/resolv.conf を chroot 内に複製(任意のネットワーク利用のため)
#   5. chroot して grub-install + update-grub
#   6. 後片付け(unmount)

set -euo pipefail

cleanup() {
    set +e
    for m in /mnt/run /mnt/sys/firmware/efi/efivars /mnt/sys /mnt/proc /mnt/dev/pts /mnt/dev /mnt/boot/efi /mnt; do
        if mountpoint -q "$m"; then
            umount -lf "$m" 2>/dev/null
        fi
    done
}
trap cleanup EXIT

if [[ $EUID -ne 0 ]]; then
    echo "[error] root 権限が必要です。sudo を付けて実行してください。" >&2
    exit 1
fi

ROOT_PART="${ROOT_PART:-}"
ESP_PART="${ESP_PART:-}"
BIOS="${BIOS:-0}"
GRUB_DISK="${GRUB_DISK:-}"

if [[ -z "${ROOT_PART}" ]]; then
    echo "[error] ROOT_PART が未指定です(例: ROOT_PART=/dev/nvme0n1p5)。" >&2
    echo "        手元のディスク構成は次で確認できます: lsblk -f" >&2
    exit 2
fi

if [[ "${BIOS}" != "1" && -z "${ESP_PART}" ]]; then
    echo "[error] UEFI モードでは ESP_PART が必須です(例: ESP_PART=/dev/nvme0n1p1)。" >&2
    exit 2
fi
if [[ "${BIOS}" == "1" && -z "${GRUB_DISK}" ]]; then
    echo "[error] BIOS=1 のときは GRUB_DISK が必要です(例: GRUB_DISK=/dev/sda)。" >&2
    exit 2
fi

echo "[info] ROOT_PART = ${ROOT_PART}"
[[ -n "${ESP_PART}"  ]] && echo "[info] ESP_PART  = ${ESP_PART}"
[[ "${BIOS}" == "1"  ]] && echo "[info] mode      = BIOS / MBR (target disk: ${GRUB_DISK})"
[[ "${BIOS}" != "1"  ]] && echo "[info] mode      = UEFI"

mount "${ROOT_PART}" /mnt
if [[ "${BIOS}" != "1" ]]; then
    mkdir -p /mnt/boot/efi
    mount "${ESP_PART}" /mnt/boot/efi
fi

mount --bind /dev      /mnt/dev
mount --bind /dev/pts  /mnt/dev/pts
mount --bind /proc     /mnt/proc
mount --bind /sys      /mnt/sys
mount --bind /run      /mnt/run
if [[ "${BIOS}" != "1" && -d /sys/firmware/efi/efivars ]]; then
    mkdir -p /mnt/sys/firmware/efi/efivars
    mount --bind /sys/firmware/efi/efivars /mnt/sys/firmware/efi/efivars
fi

# resolv.conf(任意)。失敗しても致命ではない。
if [[ -e /etc/resolv.conf && ! -L /mnt/etc/resolv.conf ]]; then
    cp -f /etc/resolv.conf /mnt/etc/resolv.conf 2>/dev/null || true
fi

# chroot 内で実行するスクリプトを生成
INNER=/mnt/tmp/_repair-grub-inner.sh
mkdir -p /mnt/tmp
cat >"${INNER}" <<'INNER_SH'
#!/usr/bin/env bash
set -euo pipefail

mode="${1:?}"
disk="${2:-}"

if command -v grub-install >/dev/null 2>&1; then
    GI=grub-install
else
    GI=grub2-install
fi

if [[ "${mode}" == "uefi" ]]; then
    BLID="grub"
    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        BLID="${ID:-grub}"
    fi
    "${GI}" --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id="${BLID}" --recheck
else
    "${GI}" --target=i386-pc --recheck "${disk}"
fi

if command -v update-grub >/dev/null 2>&1; then
    update-grub
elif command -v grub-mkconfig >/dev/null 2>&1; then
    grub-mkconfig -o /boot/grub/grub.cfg
elif command -v grub2-mkconfig >/dev/null 2>&1; then
    grub2-mkconfig -o /boot/grub2/grub.cfg
fi
INNER_SH
chmod +x "${INNER}"

if [[ "${BIOS}" == "1" ]]; then
    chroot /mnt /tmp/_repair-grub-inner.sh bios "${GRUB_DISK}"
else
    chroot /mnt /tmp/_repair-grub-inner.sh uefi
fi

rm -f "${INNER}"

echo
echo "[ok] GRUB を再インストールしました。"
echo "     再起動後、必要に応じて scripts/linux/set-grub-first.sh で UEFI ブート順を調整してください。"

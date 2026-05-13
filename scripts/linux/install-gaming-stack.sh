#!/usr/bin/env bash
# install-gaming-stack.sh
#
# Kali / Debian 系で Windows ゲームを動かすためのツール群を一括導入します。
# 冪等(何度実行しても同じ結果)。GPU ドライバは機種依存なので自動導入しません
# (現状のみ表示)。
#
# 何をするか:
#   1. dpkg --add-architecture i386 + apt update
#   2. apt: steam-installer / gamemode / mangohud / gamescope / vulkan ツール
#   3. Flathub を追加し、Lutris / Heroic / Bottles / ProtonUp-Qt / Flatseal を Flatpak で導入
#   4. 実行ユーザを gamemode グループへ追加
#   5. GPU 状況と次にやることを表示
#
# 使い方:
#   sudo bash scripts/linux/install-gaming-stack.sh
#   sudo bash scripts/linux/install-gaming-stack.sh --no-flatpak     # 既に Flatpak 環境がある人向け
#   sudo bash scripts/linux/install-gaming-stack.sh --skip-steam     # Steam は手動で入れたい人向け

set -euo pipefail

NO_FLATPAK=0
SKIP_STEAM=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-flatpak) NO_FLATPAK=1; shift;;
        --skip-steam) SKIP_STEAM=1; shift;;
        -h|--help)    sed -n '2,17p' "$0"; exit 0;;
        *) echo "[error] 不明な引数: $1" >&2; exit 2;;
    esac
done

if [[ $EUID -ne 0 ]]; then
    echo "[error] root 権限が必要です。sudo を付けて実行してください。" >&2
    exit 1
fi

# 実行ユーザ(sudo 経由なら $SUDO_USER)を覚える
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME=$(getent passwd "${TARGET_USER}" | cut -d: -f6)
if [[ -z "${TARGET_HOME}" || ! -d "${TARGET_HOME}" ]]; then
    echo "[warn] ユーザ ${TARGET_USER} のホームディレクトリが特定できません。Flatpak は --system で入れます。"
    TARGET_USER=""
fi

echo "==> 1) i386 アーキテクチャを有効化"
if dpkg --print-foreign-architectures | grep -q '^i386$'; then
    echo "    既に有効です。"
else
    dpkg --add-architecture i386
fi

echo "==> 2) apt update"
apt-get update -y

echo "==> 3) apt パッケージをインストール"
APT_PKGS=(
    gamemode mangohud gamescope
    vulkan-tools mesa-vulkan-drivers
    libvulkan1:i386 mesa-vulkan-drivers:i386
    libgl1-mesa-dri:i386 libgl1:i386
    fonts-wine
    flatpak
)
if [[ ${SKIP_STEAM} -eq 0 ]]; then
    APT_PKGS+=(steam-installer)
fi

DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${APT_PKGS[@]}"

echo "==> 4) ${TARGET_USER:-(N/A)} を gamemode グループに追加"
if [[ -n "${TARGET_USER}" ]] && getent group gamemode >/dev/null; then
    if id -nG "${TARGET_USER}" | tr ' ' '\n' | grep -qx gamemode; then
        echo "    既にメンバーです。"
    else
        usermod -aG gamemode "${TARGET_USER}"
        echo "    追加しました。次回ログイン時から有効になります。"
    fi
fi

if [[ ${NO_FLATPAK} -eq 0 ]]; then
    echo "==> 5) Flathub を追加"
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

    echo "==> 6) Flatpak でランチャ群を導入"
    FLATPAKS=(
        net.lutris.Lutris
        com.heroicgameslauncher.hgl
        com.usebottles.bottles
        net.davidotek.pupgui2
        com.github.tchx84.Flatseal
    )
    for f in "${FLATPAKS[@]}"; do
        flatpak install -y --noninteractive flathub "${f}" || \
            echo "[warn] ${f} の導入に失敗しました(既存の場合は無視可)。"
    done
else
    echo "==> 5-6) --no-flatpak のため Flatpak 群はスキップ"
fi

echo
echo "==> GPU 状況"
if command -v vulkaninfo >/dev/null 2>&1; then
    vulkaninfo --summary 2>/dev/null | sed -n '1,30p' | sed 's/^/    /' || true
else
    echo "    vulkaninfo が無いため確認できません。"
fi

echo
echo "==> 次のステップ"
cat <<EOF
    1) 一度ログアウト → ログインして 'gamemode' グループ反映を有効化
    2) Steam を起動してログイン
       Steam → 設定 → Compatibility:
         "Enable Steam Play for all other titles" を ON
    3) ProtonUp-Qt (Flatpak で導入済) を起動して Proton-GE 最新を Install
    4) ストア別の使い分け:
         Steam            → Steam + Proton(動かない時のみ Proton-GE)
         Epic/GOG/Amazon  → Heroic Games Launcher
         Battle.net 等    → Lutris
         単発の Win アプリ → Bottles
    5) ゲームの起動オプション(Steam 例):
         gamemoderun mangohud %command%
       低スペック機で 720p→1080p アップスケール:
         gamescope -W 1280 -H 720 -U -F fsr -- gamemoderun mangohud %command%

詳細は docs/10-windows-games-on-linux.md を参照してください。

NVIDIA dGPU 機の場合は別途:
    sudo apt install -y nvidia-driver nvidia-vulkan-icd nvidia-vulkan-icd:i386
    sudo systemctl reboot
EOF

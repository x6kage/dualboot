#!/usr/bin/env bash
# install-aagl-launchers.sh
#
# An Anime Game Launcher (AAGL) ファミリ + 周辺ツールを Flatpak で導入します。
# HoYoverse 系(Genshin / HSR / Honkai 3 / ZZZ)、Wuthering Waves、Endfield 等の
# 中華ガチャゲーを Linux で動かすための土台を整えます。
#
# 前提:
#   - 一般ユーザで実行(root 不要)。Flatpak が無ければ apt で入れます (この時だけ sudo を使用)。
#   - Flathub をユーザスコープで追加します。
#
# 何をするか:
#   1. flatpak が無ければ sudo apt install
#   2. Flathub をユーザスコープで追加
#   3. Bottles / Heroic / ProtonUp-Qt / Flatseal を導入
#   4. AAGL ファミリ(検出できたものだけ)を導入
#      - moe.launcher.an-anime-game-launcher (Genshin Impact)
#      - moe.launcher.the-honkers-railway-launcher (Honkai: Star Rail)
#      - moe.launcher.honkers-launcher (Honkai Impact 3rd)
#      - moe.launcher.sleepy-launcher (Zenless Zone Zero, あれば)
#      - moe.launcher.wavey-launcher (Wuthering Waves, あれば)
#   5. 次にやることを表示
#
# 使い方:
#   bash scripts/linux/install-aagl-launchers.sh
#   bash scripts/linux/install-aagl-launchers.sh --system    # システムスコープに入れる(sudo 必要)
#   bash scripts/linux/install-aagl-launchers.sh --skip-aagl # AAGL は入れず、周辺ツールだけ
#
# このスクリプトは何度実行しても安全(Flatpak の --if-not-exists / -y 任せ)。

set -euo pipefail

SCOPE="--user"
INSTALL_AAGL=1

while [[ $# -gt 0 ]]; do
    case "$1" in
        --system)    SCOPE="--system"; shift;;
        --user)      SCOPE="--user"; shift;;
        --skip-aagl) INSTALL_AAGL=0; shift;;
        -h|--help)   sed -n '2,28p' "$0"; exit 0;;
        *) echo "[error] 不明な引数: $1" >&2; exit 2;;
    esac
done

if [[ "${SCOPE}" == "--system" && $EUID -ne 0 ]]; then
    echo "[error] --system 指定時は sudo で実行してください。" >&2
    exit 1
fi

if ! command -v flatpak >/dev/null 2>&1; then
    echo "==> flatpak が見つからないので apt で導入します(sudo 要)。"
    if [[ $EUID -ne 0 ]]; then
        sudo apt-get update -y
        sudo apt-get install -y flatpak
    else
        apt-get update -y
        apt-get install -y flatpak
    fi
fi

echo "==> Flathub を ${SCOPE} スコープで追加"
flatpak ${SCOPE} remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

# 共通: 周辺ツール
COMMON_FLATPAKS=(
    com.usebottles.bottles
    com.heroicgameslauncher.hgl
    net.davidotek.pupgui2          # ProtonUp-Qt
    com.github.tchx84.Flatseal     # Flatpak 権限管理
)

# AAGL ファミリ。存在しない / 改名されたものは自動でスキップ
AAGL_CANDIDATES=(
    moe.launcher.an-anime-game-launcher          # Genshin Impact
    moe.launcher.the-honkers-railway-launcher    # Honkai: Star Rail
    moe.launcher.honkers-launcher                # Honkai Impact 3rd
    moe.launcher.sleepy-launcher                 # Zenless Zone Zero (改名の可能性)
    moe.launcher.wavey-launcher                  # Wuthering Waves (派生プロジェクト)
)

install_one() {
    local id="$1"
    if flatpak ${SCOPE} info "$id" >/dev/null 2>&1; then
        echo "    [-] $id は既にインストール済"
        return 0
    fi
    if flatpak ${SCOPE} remote-info flathub "$id" >/dev/null 2>&1; then
        flatpak ${SCOPE} install -y --noninteractive flathub "$id" \
            && echo "    [+] $id を導入" \
            || echo "    [!] $id の導入に失敗"
    else
        echo "    [.] $id は Flathub に存在しない/名称変更の可能性 -> スキップ"
    fi
}

echo "==> 周辺ツールを導入"
for id in "${COMMON_FLATPAKS[@]}"; do
    install_one "$id"
done

if [[ ${INSTALL_AAGL} -eq 1 ]]; then
    echo "==> AAGL ファミリを導入(存在するものだけ)"
    for id in "${AAGL_CANDIDATES[@]}"; do
        install_one "$id"
    done
else
    echo "==> --skip-aagl のため AAGL ファミリはスキップ"
fi

cat <<'EOF'

==> 次にやること

  1) ProtonUp-Qt を起動して Compatibility tool を更新
       - Heroic 用に **Proton-GE 8-32 以降**(Wuthering Waves 等で必要)
       - Steam 用にも同じ Proton-GE を入れておくと汎用性が高い

  2) HoYoverse 系 (Genshin / HSR / Honkai 3 / ZZZ)
       - 該当する an-anime-team ランチャを起動
       - 言語/サーバを選んでゲームをダウンロード
       - HoyoPlay 自体を入れる必要はなし

  3) Wuthering Waves / Endfield 等
       - 推奨: Heroic を起動 → Epic アカウントログイン → ゲームを Install
       - 非 Epic ルート: Bottles の Gaming テンプレートに公式ランチャを入れる

  4) XXMI Launcher (3DMigoto モッドフロントエンド) を使うなら
       - 該当 prefix(AAGL なら ~/.var/app/<id>/data/.../wine-prefix)に
         XXMI-Launcher-Setup.exe をインストール
       - 環境変数: WINEDLLOVERRIDES="dxgi=n,b"
       - Pre-launch hook で XXMI Loader を起動
       - 詳細は docs/11-hoyo-and-cn-gacha-on-linux.md

  5) Flatpak は sandbox。外部の Mods フォルダ等にアクセスできない場合は
     Flatseal で「ファイルシステム」権限を追加(~/Documents/Mods 等)

  6) アンチチートと TOS の注意は docs/10 / docs/11 を必読
       - HoYo / Kuro 公式は Linux サポート未表明
       - モッド利用は明確に TOS 違反(視覚モッドでも自己責任)

EOF

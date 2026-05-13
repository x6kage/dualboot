# 10. Windows 専用ゲームを Linux で動かす(Kali / Debian 系・2026 年版)

「Windows ゲームのために再起動しなくてよくなる」、つまり **Linux をメイン OS のまま Windows ストアのゲームを遊ぶ** ための実用ガイドです。Kali / Debian 系を前提にします。

---

## 1 行答え

> **Steam → Proton(必要なら Proton-GE)、Epic/GOG/Amazon → Heroic、Battle.net/Ubisoft Connect/野良インストーラ → Lutris、単発の Windows アプリ/ゲーム → Bottles。周辺は GameMode + MangoHud + Gamescope を入れておけば良い。**

「結局 Lutris?」への答えは **半分 Yes、半分 No**。Lutris は今でも強いが、Epic/GOG は Heroic に座を譲った、というのが 2026 年の現状です。

---

## 役割分担

| ツール | 主用途 | 立ち位置 |
| --- | --- | --- |
| **Steam + Proton** | Steam で買った Windows ゲーム全般 | Linux ゲーミングの土台。Steam Deck 効果で「だいたい動く」が現実に |
| **Proton-GE** (GloriousEggroll) | Steam の標準 Proton で動かないゲーム用カスタムビルド | `ProtonUp-Qt` で 1 クリック導入、Steam 設定でゲーム毎に切替 |
| **Heroic Games Launcher** | Epic Games Store / GOG / Amazon Prime Gaming | 2021 以降の新参だが、Epic/GOG では Lutris より楽。クラウドセーブ・ストアブラウズも内蔵 |
| **Lutris** | Battle.net、Ubisoft Connect、Origin、Riot、Roblox(野良)、レトロ、野良 Windows インストーラ | コミュニティ install script が膨大。「変な経路で売ってるやつ」はまだ Lutris が強い |
| **Bottles** | 単発の Windows アプリ/ゲーム、Wine prefix を綺麗に管理したい | Flatpak ファースト設計、UI が一番モダン。Wine 知識ゼロでも動く |
| **Wine + winetricks** | 既存 prefix のトラブルシュート | 上の GUI が裏でやっていることそのもの |

---

## 周辺ツール

| ツール | 役割 | 推奨度 |
| --- | --- | --- |
| **GameMode** (Feral) | ゲーム起動中だけ CPU/GPU governor を `performance` に。FPS が数% 上がる | ★★★ |
| **MangoHud** | 画面隅に FPS / CPU / GPU / 温度オーバレイ | ★★★ |
| **Gamescope** | SteamOS 由来の Wayland コンポジタ。フルスクリーン強制・解像度 upscale・FPS 制限。低スペック機/小画面で活躍 | ★★★ |
| **ProtonUp-Qt** | Proton-GE / Wine-GE の取得・更新を GUI で | ★★★ |
| **vkBasalt** | Reshade 風シェーダ(SMAA / CAS) | ★ |
| **Steam Tinker Launch** | 起動オプションを GUI で細かく操作 | ★ |

---

## クイックセットアップ

新スクリプトで一括導入:

```bash
sudo bash scripts/linux/install-gaming-stack.sh
```

何が走るかは下の「セットアップ詳細」を参照。終わったら一度ログアウト → ログインで `gamemode` グループ反映。

### セットアップ詳細(手で順を追いたい場合)

#### A. 32bit アーキ有効化 + システムパッケージ

```bash
sudo dpkg --add-architecture i386
sudo apt update
sudo apt install -y \
    steam-installer \
    gamemode mangohud gamescope \
    vulkan-tools mesa-vulkan-drivers \
    libvulkan1:i386 mesa-vulkan-drivers:i386 \
    libgl1-mesa-dri:i386 libgl1:i386 \
    fonts-wine
```

> Kali / Debian の `steam-installer` は Valve 公式の `.deb` を取りに行くシムです。直接 <https://store.steampowered.com/about/> から `.deb` を取って `sudo apt install ./steam_latest.deb` でも可。

#### B. GPU ドライバ

機種に応じて。**スクリプトは自動インストールしません**(誤った組合せで X が起動しなくなる事故を避けるため)。

- **Intel / AMD 内蔵 GPU**: `mesa-vulkan-drivers` 系で完結。何もしなくて良いことが多い。
- **AMD dGPU**: 同上。最新が欲しければ `mesa-amber` ではなく上流 mesa を `apt`。
- **NVIDIA**:
  ```bash
  sudo apt install -y nvidia-driver nvidia-vulkan-icd nvidia-vulkan-icd:i386
  sudo systemctl reboot
  ```
  Wayland セッションだとゲームによってはまだ問題があるので、ゲーム時は X11 セッションでログインする方が無難(2026 でも)。

確認:
```bash
vulkaninfo --summary | head -30
glxinfo -B | grep -E 'renderer|OpenGL version'
```

#### C. Flatpak でランチャ群

Debian/Kali 公式リポの Lutris / Heroic / Bottles はバージョンが古めなので **Flatpak 推奨**:

```bash
sudo apt install -y flatpak
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

flatpak install -y flathub net.lutris.Lutris
flatpak install -y flathub com.heroicgameslauncher.hgl
flatpak install -y flathub com.usebottles.bottles
flatpak install -y flathub net.davidotek.pupgui2          # ProtonUp-Qt
flatpak install -y flathub com.github.tchx84.Flatseal     # Flatpak 権限管理
```

Flatpak で入れたゲームから外部ディレクトリに保存したい場合は **Flatseal** で「ファイルシステム」アクセスを足してください。

#### D. Steam の初回設定

1. アプリメニューから Steam を起動 → ログイン。
2. `Steam → 設定 → Compatibility`:
   - **「Enable Steam Play for all other titles」を ON**
   - 使う Proton バージョン: 最新の `Proton 9.x` (Valve 公式) または `Proton-GE`(Proton-GE インストール後に出現)
3. ProtonUp-Qt を起動 → Compatibility tool: **Proton-GE** を最新に Install。Steam 再起動で選べるようになる。

#### E. ゲーム毎の起動オプション(Steam)

`ライブラリ → ゲーム右クリック → プロパティ → 起動オプション` に書く:

```
gamemoderun mangohud %command%
```

Gamescope を使うなら(低スペック / FSR upscale):

```
gamescope -W 1920 -H 1080 -r 60 -F fsr -- gamemoderun mangohud %command%
```

ボトルネック調査用の MangoHud フル表示:

```
MANGOHUD_CONFIG=cpu_temp,gpu_temp,frame_timing,vulkan_engine_version mangohud gamemoderun %command%
```

---

## ストア別: 何で動かすのが正解か

### Steam(Windows ゲーム含む)

→ **Steam + Proton** 一択。手間ゼロ。動かない場合のみ Proton-GE に切り替え。

### Epic Games Store

→ **Heroic Games Launcher**。
- ストアブラウズ・ライブラリ管理・購入後ダウンロード・クラウドセーブまで GUI で完結
- 内部的には `legendary` (CLI) を使っている
- Proton や Wine-GE を Heroic から直接選べる

### GOG

→ **Heroic** 一択。GOG Galaxy(Windows 公式)は Wine で動かすのが面倒だが、Heroic ならネイティブに対応。

### Amazon Prime Gaming(Luna 除く)

→ **Heroic**(`nile` バックエンドが組込み済)。

### Battle.net(Blizzard)

→ **Lutris**。
- Lutris で「Battle.net」と検索 → install script 実行
- Diablo IV / Overwatch 2 / WoW 等が動く(アンチチート許す範囲で)
- ProtonDB ならぬ **lutris.net** にゲーム毎の install script があるか確認

### Ubisoft Connect / Origin (EA App) / Riot Client

→ **Lutris** が今でも一番現実的。
- ただし EA App は **Heroic** にも対応(将来的にはこちらが伸びる)
- Riot Vanguard (League of Legends 2024〜) は **kernel-mode AC で動かない**

### itch.io / 野良の Windows インストーラ

→ **Bottles**(prefix を分けやすい)または **Lutris**(install script があれば)。
- 単発で 1 つだけなら Bottles の方が作業が綺麗

### レトロ(Win9x/Win XP 時代)

→ **Lutris**(DOSBox / ScummVM / PCem / 86Box 連携)、または素の **DOSBox-Staging** / **PCSX2** / **RPCS3** 等の専用エミュ。

---

## アンチチートの現実(2026 年)

これは **買う前に必ず確認**。一覧の最新は <https://areweanticheatyet.com/> を参照。

### Linux で動く側(対応パブリッシャー)

- **Easy Anti-Cheat (EAC)** — Proton 経由 Linux サポート可能、**パブリッシャーがオプトインしていれば動く**
  - 例: Apex Legends(時期により変動)、Dead by Daylight、Halo MCC、Forza Horizon 5、War Thunder
- **BattlEye** — 同上
  - 例: Tom Clancy's Rainbow Six Siege(時期による)、Squad、Arma III

### Linux で動かない側(2026 年現在)

- **Riot Vanguard**: League of Legends、Valorant ← kernel-mode、Linux 永久に対応見込み無し
- **BattlEye 未オプトイン**: PUBG、Fortnite Battle Royale、Destiny 2
- **その他独自 AC**: Call of Duty 系、Roblox 公式、Genshin Impact のスタートアップ判定
- **Easy Anti-Cheat 未オプトイン**: Fall Guys(復活予定との噂)

### 確認の手順(購入前 / 起動前)

1. **<https://www.protondb.com/>** にゲーム名 → Platinum/Gold/Silver/Bronze/Borked と必要 tweak を確認
2. **<https://areweanticheatyet.com/>** で AC ステータス確認
3. ゲーム個別の Proton-GE 必要バージョン / `WINEDLLOVERRIDES` をメモ

---

## 低スペック機 / GPU なし機での運用

iGPU(Intel UHD / AMD Vega 統合)機でも、軽めのゲームは普通に動きます。コツ:

### Gamescope で解像度を下げる + FSR でボケを軽減

Steam 起動オプション:
```
gamescope -W 1280 -H 720 -U -F fsr -- %command%
```
(`-U` = アップスケール、`-F fsr` = AMD FSR、`-W/-H` = 内部レンダ解像度)

これで **「内部 720p で描画 → 1080p に FSR upscale」** という、Steam Deck と同じトリックが使えます。

### CPU governor を performance 固定

`gamemoderun` を全部の起動オプションに入れる。`/etc/gamemode.ini` で:

```ini
[general]
softrealtime=auto
renice=10

[cpu]
park_cores=no
pin_cores=no

[gpu]
apply_gpu_optimisations=accept-responsibility
```

### サーマル

低スペック機は熱で thermal throttling しやすいので、`MangoHud` で `gpu_temp,cpu_temp` を常時表示。`tlp` でファン制御を `power` から `performance` に切替えることも検討:

```bash
sudo apt install -y tlp
sudo tlp start
sudo tlp-stat -t            # 温度確認
```

### お薦め:GPU なし機なら「軽量ゲーム」軸

Linux 上で GPU なし機が一番幸せなのは:
- 2D / pixel-art インディー(Stardew Valley / Hollow Knight / Celeste / Dead Cells)
- 古典 RPG / SLG / VN(MS-DOS / Win9x 系も Lutris で復活)
- ストラテジー(Civ VI 軽設定、StarCraft I/II の旧モード、Dwarf Fortress、Caves of Qud)
- ローグライク全般

**最新 AAA を快適に遊ぶのは諦め、ゲーム機 / クラウドゲーミング / 別 PC の Steam Remote Play / Moonlight (NVIDIA GameStream 互換) でストリームする**、というのも今っぽい解です。

---

## ゲーミング向け distro という選択

Kali はあくまで **セキュリティテスト用 distro** です。ゲームも動かせますが、本気でゲームが主目的なら **別パーティション** で:

| distro | 特徴 |
| --- | --- |
| **Bazzite** | Fedora Atomic ベース、SteamOS 風、Steam / Proton-GE 同梱、コンソールモードあり |
| **CachyOS** | Arch ベース、性能特化のカーネル / コンパイラフラグ、Proton 系全部入りオプション |
| **Nobara** | Fedora ベース、GloriousEggroll 自身が作っている。Proton-GE がデフォルトで入る |
| **Pop!_OS** | Ubuntu ベース、System76 製、NVIDIA 版がドライバ込みで配布されていてセットアップが速い |

「Kali はセキュリティ用、Bazzite はゲーム用、Windows は Office 用」のように **3 OS 構成** にするのも現代的(本リポジトリの GRUB 優先化スクリプトは 3 OS でも問題なく動きます)。

---

## チートシート

```bash
# よく使う Steam 起動オプション
gamemoderun mangohud %command%
gamescope -W 1920 -H 1080 -r 144 -- gamemoderun mangohud %command%
PROTON_LOG=1 %command%                          # ~/steam-<appid>.log を吐く
WINEDLLOVERRIDES="d3d11=n,b" %command%          # ネイティブ d3d11 を優先
PROTON_USE_WINED3D=1 %command%                  # DXVK/VKD3D ではなく WineD3D
DXVK_HUD=fps,frametimes,gpuload %command%       # DXVK 内蔵 HUD

# ProtonDB の判定が "Borked" のとき試す順
# 1) Proton 最新 → 2) Proton-GE 最新 → 3) Proton 7.0-6 → 4) Proton-GE 7-x
```

---

## 1 行まとめ

> **2026 年は Steam + Proton(と Proton-GE)で 8 割は終わる。残りは Heroic(Epic/GOG)と Lutris(Battle.net 等の野良経路)で拾う。Bottles は単発用。アンチチート対応ゲームは ProtonDB と areweanticheatyet で買う前に確認。GPU なし機は Gamescope の FSR で 720p→1080p upscale が現実解。**

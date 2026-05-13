# 11. HoyoPlay / Wuthering Waves / 中華ガチャゲー & XXMI Launcher を Linux で動かす

`docs/10-windows-games-on-linux.md` の発展編です。Steam にもない、独自ランチャを使うタイプの **HoYoverse 系・Kuro Games 系・Hypergryph 系・テンセント系の中華ガチャゲー** を、Linux で実用的に動かす方法と、3DMigoto 系モッドフロントエンドの **XXMI Launcher** のセットアップまでをまとめます。

> **重要な前提**: これらはどれも公式に Linux サポートを表明していません。動くのは「Wine/Proton 上で動作するように内部的に許容されている / 阻害されていない」状態の結果です。利用規約上はグレーで、特に **モッド利用は明確に TOS 違反** です。BAN 例は稀ですが「あり得る」と理解した上で進めてください。

---

## 1 行答え

> **HoYo 系 (Genshin/HSR/ZZZ/Honkai 3) → An Anime Game Launcher (AAGL) ファミリの Flatpak。Wuthering Waves → Steam + Proton(Steam 版あり)。Endfield・その他の独自ランチャゲー → Bottles の Gaming テンプレートに公式インストーラ。XXMI Launcher は同じ Wine prefix に入れ、`WINEDLLOVERRIDES="dxgi=n,b"` で 3DMigoto を hook。**

---

## なぜ動くのか(2026 年版・現状把握)

| 障壁 | 現状 |
| --- | --- |
| HoYo の `mhyprot2` カーネルアンチチート | **Wine 環境では条件付きで読み込まない** 設計に変更済(2023 頃〜)。結果として Wine/Proton で動く |
| Steam Deck 公式対応 | Genshin Impact / Honkai: Star Rail / Zenless Zone Zero は **Deck Verified**。HoYo 自身が暗黙に Linux ランタイムを認めている |
| Wuthering Waves の ACE (Anti-Cheat Expert) | Wine 上でユーザーモードで動作。Proton-GE 8-32 以降ほぼ問題なし |
| D3D11/D3D12 互換性 | DXVK / VKD3D-Proton が成熟して実用域 |
| ランチャ自体の挙動(自動更新、CDN ダウンロード、署名検証) | HoyoPlay / WuWa Launcher / Kuro 公式ランチャ全て Wine 上で正常動作 |

つまり 2026 時点では「動かない方が珍しい」状態。一方で **アップデート直後の数日間は動かなくなる** ことがあるので、Discord (an-anime-team / Heroic / Bottles) の状況を見ながらが無難。

---

## ストア / ゲーム別の最適解

### HoYoverse 系: Genshin / HSR / ZZZ / Honkai 3 / Tears of Themis

#### 推奨: An Anime Game Launcher (AAGL) ファミリ

`an-anime-team` が GitLab で開発・配布しているコミュニティランチャ群。**Wine prefix の管理、DXVK/VKD3D の選択、telemetry サーバの抑制、起動時のテレポート補正** までを自動化してくれます。HoyoPlay 自体を入れる必要はなく、HoyoPlay と同じ CDN から game data を直接ダウンロードします。

| ゲーム | Flatpak ID(目安) |
| --- | --- |
| Genshin Impact | `moe.launcher.an-anime-game-launcher` |
| Honkai: Star Rail | `moe.launcher.the-honkers-railway-launcher` |
| Honkai Impact 3rd | `moe.launcher.honkers-launcher` |
| Zenless Zone Zero | `moe.launcher.sleepy-launcher`(命名は更新されている可能性あり) |
| Tears of Themis | `moe.launcher.honkers-launcher` 系列の派生 |

```bash
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

flatpak install -y flathub moe.launcher.an-anime-game-launcher
flatpak install -y flathub moe.launcher.the-honkers-railway-launcher
flatpak install -y flathub moe.launcher.honkers-launcher
# ZZZ 等は名称が動いているので flathub で検索
flatpak search sleepy
flatpak search hoyo
```

起動 → 言語 / サーバ選択(グローバル / 中国大陸版を選べる)→ ゲームをダウンロード → プレイ。**初回ダウンロードが数十 GB あるので有線推奨**。

##### 設定で見ておくと良いところ

- **DXVK バージョン**: 2.x 系の最新(自動アップデートあり)
- **VKD3D-Proton**: ZZZ など D3D12 タイトルで効く
- **Wine Runner**: `wine-tkg-staging-tkg-fsync` 系、または `proton-ge` を選択
- **環境変数**: 必要に応じて
  ```
  DXVK_ASYNC=1                       # シェーダコンパイル中のスタッタ軽減(Mesa 23+ では不要)
  __GL_SHADER_DISK_CACHE_SKIP_CLEANUP=1
  ```
- **Discord Rich Presence**: AAGL 内蔵の機能で ON/OFF

#### 代替: HoyoPlay 自体を Bottles で動かす

AAGL がメンテされていない / 自分で更新タイミングをコントロールしたい場合:

1. `flatpak install -y flathub com.usebottles.bottles`
2. Bottles 起動 → 「ボトル新規作成」→ テンプレート: **Gaming**
3. Runner: **Soda** または **Caffe**(GE 系。新しい方を)
4. <https://hoyoplay.hoyoverse.com/> から `HoYoPlay.exe` をダウンロードし、Bottles の「Run executable」で実行
5. HoyoPlay の UI から好きなゲームを Install
6. Bottles の「依存関係」から `vcredist2019`, `dotnet48`, `corefonts` を導入しておく

性能・互換性は AAGL とほぼ同等。**問題発生時の調査は Bottles の方が見えやすい**(Wine prefix が `~/.var/app/com.usebottles.bottles/data/bottles/bottles/<name>/` に直接ある)。

### Wuthering Waves(鳴潮 / Kuro Games)

#### 推奨: Steam + Proton

WuWa は **Steam にグローバル版が出ています**(本リポジトリの一般方針と同じく、Steam にあれば常に Steam が最良)。手順は通常の Steam ゲームと同じ:

1. Steam を起動 → ストアで Wuthering Waves を Install
2. ゲーム右クリック → プロパティ → 互換性 → **「特定の Steam Play 互換性ツールの使用を強制する」を ON** → **Proton-GE 8-32 以降** を選択(無ければ ProtonUp-Qt で取得)
3. 起動オプション:
   ```
   gamemoderun mangohud %command%
   ```
4. モッド (XXMI / WWMI) を併用する場合は同じプロパティの起動オプションで:
   ```
   WINEDLLOVERRIDES="dxgi=n,b" gamemoderun mangohud %command%
   ```

ACE (Anti-Cheat Expert) は Proton-GE 環境で **動きます**(Kuro 公式が Linux 対応宣言したわけではないが、Proton 側で吸収)。

#### 代替 1: コミュニティ Flatpak (Wavey Launcher 系)

an-anime-team 派生の WuWa 専用 Flatpak。AAGL と同じ感覚で Wine prefix / DXVK / Proton を自動管理してくれます。

```bash
flatpak search wavey
flatpak install -y flathub moe.launcher.wavey-launcher    # 命名は派生プロジェクト次第
```

中国大陸版を入れたい / 公式ランチャの自動更新挙動を残したい場合は次の Bottles ルートと使い分け。

#### 代替 2: Bottles + Kuro 公式インストーラ

Steam を経由したくない / 中国大陸版 / PSN 連携等の特殊事情がある場合:

1. <https://wutheringwaves.kurogames.com/> から `Wuthering Waves Launcher.exe` を取得
2. `flatpak install -y flathub com.usebottles.bottles`
3. Bottles で「ボトル新規作成」→ テンプレート: **Gaming**、Runner: Soda / Caffe(GE 系)
4. ボトル内で「Run executable」→ 取得した `Wuthering Waves Launcher.exe`
5. ゲーム本体を Install → 通常通りプレイ
6. モッド使用時は Bottles の「環境変数」で `WINEDLLOVERRIDES=dxgi=n,b`

#### 代替 3: Heroic + Epic Games Store

WuWa は Epic にも 2024 後半から配信されています。**Epic ストアを使うことに抵抗がなければ** この経路でも動きます。手順は Heroic を入れて Epic ログイン → Install → Proton-GE を選択、で Steam 版とほぼ同等の体験になります。本リポジトリでは Steam 版を優先する立場ですが、Epic 経路を選ぶ自由は残しておきます。

### Arknights: Endfield(Hypergryph / 鷹角)

2025 後半〜2026 にグローバル本格展開。**HoYo よりアンチチートが緩い** ので動かしやすい部類。

| 経路 | 動かし方 | 推奨度 |
| --- | --- | --- |
| Steam(配信あれば) | Steam + Proton(または Proton-GE) | ★★★ |
| 公式ランチャ | Bottles の Gaming テンプレートに公式インストーラを入れる | ★★ |
| Epic | Heroic + Proton-GE(Epic を許容するなら) | ★ |

公式 Discord / r/Arknights で **「working on Steam Deck」** 報告があれば、Linux でもほぼ同じ状況と見て良い。

### その他の中華ガチャ系(参考一覧)

| ゲーム | 推奨経路 | 備考 |
| --- | --- | --- |
| Tower of Fantasy | Steam + Proton | Steam 配信あり、最も楽 |
| Snowbreak: Containment Zone | Steam + Proton | 同上 |
| Punishing: Gray Raven | Bottles + 公式ランチャ | Kuro Games 旧作 |
| Path to Nowhere | Bottles + 公式ランチャ | AISNO Games |
| Reverse: 1999 | Steam + Proton | グローバル版が Steam に |
| Blue Archive (PC 版) | Bottles + 公式ランチャ(Yostar) | NIKKE と同様 |
| NIKKE | Steam + Proton | Steam に来た |
| 原神(中国大陸版) | AAGL でサーバ切替、または Bottles + HoyoPlay 中国版 | データ互換性なし |

**「Steam にあれば常に Steam が最良、無ければ AAGL/Wavey 系 → Bottles + 公式 → (Epic を許容するなら Heroic+Epic)」** の順に検討、が定石。Epic ストアを使わない方針でも、HoYo / WuWa / Endfield / Steam 配信タイトルは全て他経路でカバーできます。

---

## XXMI Launcher (3DMigoto モッドフロントエンド)

### XXMI とは

`SilentNightSound/XXMI-Launcher` が代表的な実装で、3DMigoto ベースの各種 Model Importer を統一管理するフロントエンド:

- **GIMI** (Genshin Impact Model Importer)
- **SRMI** (Star Rail Model Importer)
- **ZZMI** (Zenless Zone Zero Model Importer)
- **WWMI** (Wuthering Waves Model Importer)
- **HIMI** (Honkai Impact 3 Model Importer)

各 Migoto は **DXGI / D3D11 を hook して描画コール時にモッドのモデル/テクスチャを差し込む** 仕組みです。

### Linux での動作原理

Linux 環境では DXVK が D3D11 → Vulkan 変換を担当しているため、構成は以下のようになります:

```
Game.exe
  ├─ dxgi.dll        ← 3DMigoto に置換(または preload)
  ├─ d3d11.dll       ← DXVK の wine d3d11(そのまま使う)
  └─ Vulkan          ← Mesa / NVIDIA Vulkan ICD
```

ポイント:

- `d3d11.dll` は **DXVK のまま使う**(モッドのために置き換える必要はない)
- `dxgi.dll` を **3DMigoto 本体に置き換え** → `WINEDLLOVERRIDES="dxgi=n,b"` で native (3DMigoto) → builtin (Wine) のフォールバック順
- XXMI Launcher 本体 (`.exe`) は **ゲームと同じ Wine prefix** に入れる

### 手順例: AAGL の Genshin に GIMI / XXMI を入れる

1. AAGL の prefix を特定:
   ```bash
   ls ~/.var/app/moe.launcher.an-anime-game-launcher/data/an-anime-game-launcher/game/wine-prefix
   # 例: /home/you/.var/app/moe.launcher.an-anime-game-launcher/data/an-anime-game-launcher/game/wine-prefix
   ```
2. `XXMI-Launcher-Setup.exe` を <https://github.com/SpectrumQT/XXMI-Launcher/releases> から取得
3. その prefix 内で実行:
   ```bash
   flatpak run --command=bash moe.launcher.an-anime-game-launcher
   # 以下、Flatpak のシェル内
   export WINEPREFIX="$XDG_DATA_HOME/an-anime-game-launcher/game/wine-prefix"
   wine /path/to/XXMI-Launcher-Setup.exe
   ```
4. XXMI Launcher を起動して `GIMI` を選択 → ゲームの実行ファイルパスを Genshin (`GenshinImpact.exe`) に設定
5. AAGL の **「設定 → 環境変数」** に追加:
   ```
   WINEDLLOVERRIDES=dxgi=n,b
   ```
6. AAGL の **「Pre-launch hook」**(または Bottles の「実行前コマンド」)に:
   ```bash
   wine "$WINEPREFIX/drive_c/Program Files/XXMI Launcher/XXMI Loader.exe" &
   ```
   が必要な場合あり(XXMI のバージョンによる)
7. AAGL でゲーム起動 → Migoto が常駐 → モッドフォルダ (`<game>/Mods/`) に `.ini` と `.buf` を入れる → ゲーム内で **F10** でリロード

### Lutris で扱う場合

Lutris は 1 ゲーム = 1 prefix のシンプルな構造なので XXMI と相性は良いです:

```bash
flatpak install -y flathub net.lutris.Lutris
# Lutris で「genshin」「xxmi」を検索
# install script があればそれを使う(コミュニティ提供)
```

Lutris install script は `WINEDLLOVERRIDES` の設定や 3DMigoto 配置まで自動でやってくれることがあります。

### モッド利用上の注意

- **HoYo TOS 違反**:視覚モッドのみであれば BAN 報告は極めて稀。ガチャ・戦闘ロジック書き換え系は即 BAN リスク。
- **WuWa の ACE はメモリ書き換え検知が HoYo より厳しめ**。Migoto 系の挙動は基本問題ないが、保証はない。
- **マルチプレイ要素**(深境螺旋・幻影戦・幻日のヨハネ等)では使わない方が無難。
- **アップデート直後**:Migoto がゲームの新バージョンに追従していない時期に強引に使うとクラッシュ → サーバ側ログにエラーが残る可能性。**新バージョン公開後 1 週間は様子見**。

---

## クイックセットアップ

```bash
sudo bash scripts/linux/install-aagl-launchers.sh
```

中身:

1. Flatpak / Flathub を確実化
2. `Bottles` / `Heroic` / `ProtonUp-Qt` を Flatpak で導入
3. AAGL ファミリ(Genshin / HSR / Honkai 3 / ZZZ)を Flatpak で導入(検出した分のみ)
4. ProtonUp-Qt から Proton-GE / Wine-GE 最新を取得することを案内

NVIDIA dGPU の場合は別途 `nvidia-driver` 系のセットアップが必要(`docs/10-windows-games-on-linux.md` 参照)。

---

## トラブルシュート集

| 症状 | 対処 |
| --- | --- |
| AAGL でゲームを起動しても画面が真っ黒 | DXVK バージョンを 1 つ上げる / 下げる。NVIDIA は `__GL_THREADED_OPTIMIZATIONS=0` を試す |
| HoYo 認証で「Anti-cheat error」 | mhyprot2 を残骸で参照しに行っている。AAGL の「設定 → 修復」で fix。または prefix を初期化 |
| WuWa で起動直後にクラッシュ | Proton-GE のバージョンを 8-32 以降に。`PROTON_USE_WINED3D=0` を確認 |
| Migoto を入れた瞬間ゲームが起動しない | `dxgi=n,b` の override が効いていない(DXVK 側の dxgi が当たっている)。`WINEDLLOVERRIDES="dxgi,d3dcompiler_47=n,b"` まで広げる |
| 中国大陸版を入れたい | AAGL の「サーバ選択」で `Bilibili / 米哈游` を選ぶ、または Bottles で中国版 HoyoPlay インストーラを使う |
| Flatpak だと外部の `Mods/` フォルダにアクセスできない | Flatseal でファイルシステム権限を `~/Documents/Mods` 等に追加 |
| FPS は出ているがスタッタが多い | `MANGOHUD_CONFIG=frame_timing` で frametime 確認 → DXVK_ASYNC=1 / Mesa 23+ なら自動。Vulkan ICD が NVIDIA 公式に切り替わっているか `vulkaninfo --summary` で確認 |
| HSR / ZZZ で D3D12 警告 | VKD3D-Proton をランナー側で更新。AAGL は内蔵バージョンを参照する |

---

## 1 行まとめ

> **2026 年は HoYo ゲーは AAGL ファミリ、WuWa は Steam + Proton-GE(無ければ Wavey Launcher / Bottles + Kuro 公式)、Endfield 等の新作は Steam か Bottles で公式ランチャ、が定石。XXMI Launcher は AAGL/Bottles/Steam Proton の prefix に同居させ `WINEDLLOVERRIDES="dxgi=n,b"` で 3DMigoto を hook。Epic は使わなくても何も困らない。モッドは TOS 違反である点は忘れずに。**

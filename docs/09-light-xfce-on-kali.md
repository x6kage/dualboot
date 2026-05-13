# 09. Kali デフォルトの Xfce を「ちょっと絞って」軽量に運用する

Kali Linux のデフォルトデスクトップ(Xfce4)は、CPU グラフ・メモリ・ネットワーク等の **パネルプラグインが標準で乗っていて軽い** という、低スペック機にも嬉しい構成になっています。dwm のような minimalist WM に乗り換えると `slstatus` を自分で書いて再ビルドする儀式が必要になりますが、Xfce のまま不要な要素を削るだけでもかなり軽くなり、応答性もキビキビします。

このドキュメントは、**Kali 既定の Xfce を保ったまま** 体感速度と省メモリを底上げする実用チューニング手順です。`docs/06-dwm-on-kali.md`(dwm 完全自作)の対になる pragmatic 路線。

---

## なぜ Xfce のままで十分か

| 項目 | dwm + 自前構築 | Kali 既定 Xfce |
| --- | --- | --- |
| アイドル時 RAM(目安) | 50–100 MB | 250–350 MB |
| 設定変更コスト | `config.h` 編集 → 再ビルド | GUI でクリック |
| パネルの CPU/メモリ/ネット表示 | `slstatus` を自前 | **既定で表示済み** |
| ターミナル分割・タブ | st + 自前パッチ or tmux | **Terminator** で全部 |
| Wi-Fi トレイ・電源管理・通知 | nm-applet 等を `~/.xinitrc` | **既定で動いている** |
| Kali 流儀との整合 | 自前 | **完全に整合** |

つまり「dwm の魅力 = 軽さ + キビキビ感」だけが目的なら、Xfce を絞るだけで十分到達できます。「ハック性・カスタマイズ性」が目的なら dwm のまま。

---

## チューニング手順(優先度順)

### 1. xfwm4 のコンポジタを切る(効果大)

`設定 → ウィンドウマネージャ(詳細) → コンポジタ`

- `Enable display compositing` を OFF
- 透過・影が要らないなら一番効きます。

CLI で:
```bash
xfconf-query -c xfwm4 -p /general/use_compositing -s false
```

ティアリングが気になるときだけ `picom` を控えめ設定(vsync 有効、fade 無効)で代替。

### 2. 重い常駐サービスを止める

```bash
sudo systemctl mask packagekit.service          # GUI パッケージ更新通知
sudo systemctl mask ModemManager.service        # モバイル通信なしなら
sudo systemctl mask cups.service cups.socket    # プリンタなしなら
sudo systemctl mask bluetooth.service           # Bluetooth 不要なら
sudo systemctl mask avahi-daemon.service        # mDNS 不要なら
sudo apt purge tracker3 tracker3-miners catfish # ファイル全文索引(地味に CPU を食う)
sudo apt autoremove --purge
```

> `mask` は `disable` より強く、依存関係から自動起動も止めます。戻したくなったら `sudo systemctl unmask ...`。

### 3. パネルプラグインを整える

Kali 既定でも CPU 等は出ていますが、自分の流儀で揃えると気持ちがいい。追加プラグイン:

```bash
sudo apt install -y \
    xfce4-cpugraph-plugin \
    xfce4-systemload-plugin \
    xfce4-netload-plugin \
    xfce4-sensors-plugin \
    xfce4-genmon-plugin \
    xfce4-pulseaudio-plugin
```

特に **`genmon`** は万能で、シェルスクリプトの出力をパネルに表示できます。例: SSH セッション数、未読メール、git ステータス、コンテナ稼働数、温度、何でも。

```bash
# ~/.local/bin/panel-cputemp.sh
#!/bin/sh
t=$(awk '{printf "%.0f", $1/1000}' /sys/class/thermal/thermal_zone0/temp)
printf '<txt> %s°C </txt>\n' "$t"
```
これを genmon プラグインの「コマンド」に登録、リフレッシュ 5 秒等にすると suckless 風のパネルが完成。

### 4. Thunar(ファイルマネージャ)のサムネイル抑制

`Thunar → 編集 → 設定 → 詳細 → サムネイル → ローカルファイルのみ` または `無効化`。動画フォルダを開いたときのフリーズが消えます。
ついでに `gvfs` の不要なバックエンドも:
```bash
sudo apt purge gvfs-backends
sudo apt install --no-install-recommends gvfs    # 最小限のみ
```
USB ストレージの自動マウントが必要なら `gvfs-backends` は残す。

### 5. セッション保存を切る

`設定 → セッションと起動 → 一般 → ログオフ時にセッションを保存する` を OFF。
毎回まっさらな状態でログインするので、起動ハングや「前回のクラッシュ画面」が出なくなります。

### 6. スタートアップアプリを掃除

`設定 → セッションと起動 → アプリケーションの自動起動` で、使わないものを OFF。よく不要なのは:
- `at-spi2`(アクセシビリティブリッジ。スクリーンリーダ不使用なら off)
- `blueman-applet`(BT 不使用)
- `xfce4-notes`、`xfce4-screensaver`(代替で `xss-lock + slock` を使うなら)

### 7. ログイン直後の `xfce4-screensaver` を `xss-lock + slock` に置換(任意)

`xfce4-screensaver` は意外と重い。代わりに:

```bash
sudo apt install -y xss-lock slock
```

「自動起動」に追加:
```
xss-lock -- slock
```

`xfce4-screensaver` は OFF にする。Mod+L バインドで `slock` 直叩きでも可。

### 8. 軽量テーマ(任意)

`設定 → 外観` で:
- スタイル: `Adwaita` / `Greybird-dark` 等の単色寄り
- アイコン: `elementary-Xfce-dark` などキャッシュが効くもの
- フォント: `monospace 10` / `Noto Sans CJK JP 10`

`設定 → ウィンドウマネージャ` のテーマも `Default-xhdpi` 等、影なしの軽いものに。

---

## Terminator を入れる(dwm + st の代わり)

タブ + 分割 + 同時入力 + キーバインドが揃った GTK ターミナル。1 枚の Terminator で「ターミナル多重起動」「tmux 的分割」のほとんどを賄えます。

```bash
sudo apt install -y terminator
```

`~/.config/terminator/config` の最小例:

```ini
[global_config]
  title_hide_sizetext = True
  always_split_with_profile = True
  enabled_plugins = LaunchpadCodeURLHandler, LaunchpadBugURLHandler, APTURLHandler, CustomCommandsMenu

[keybindings]
  split_horiz       = <Ctrl><Shift>o
  split_vert        = <Ctrl><Shift>e
  new_tab           = <Ctrl><Shift>t
  close_term        = <Ctrl><Shift>w
  next_tab          = <Ctrl><Shift>n
  prev_tab          = <Ctrl><Shift>p
  go_left           = <Alt>h
  go_down           = <Alt>j
  go_up             = <Alt>k
  go_right          = <Alt>l
  zoom_in           = <Ctrl>plus
  zoom_out          = <Ctrl>minus
  zoom_normal       = <Ctrl>0
  broadcast_all     = <Ctrl><Shift>a   # 全ペインに同時入力(複数ホスト ssh で便利)
  broadcast_off     = <Ctrl><Shift>x

[profiles]
  [[default]]
    font = monospace 10
    use_system_font = False
    scrollback_infinite = True
    cursor_blink = False
    show_titlebar = False
    background_type = transparent
    background_darkness = 0.92
    use_theme_colors = False
    foreground_color = "#dddddd"
    background_color = "#101010"
    palette = "#1d1f21:#cc6666:#b5bd68:#f0c674:#81a2be:#b294bb:#8abeb7:#c5c8c6:#666666:#d54e53:#b9ca4a:#e7c547:#7aa6da:#c397d8:#70c0b1:#eaeaea"
```

Xfce のキーボードショートカット (`設定 → キーボード → アプリケーションショートカットキー`) で:
- `Super + Return` → `terminator`
- `Super + d` → `xfce4-appfinder --collapsed`(dwm の dmenu 相当)

を割り当てると **dwm っぽい起動感**が Xfce の上で得られます。

---

## 「もう一段軽く」したくなったときの代替案

ここまでやって不満が出るほど低スペックな機種(RAM 2GB 未満等)の場合のみ検討:

| 代替 DE/WM | Xfce との差 | おすすめ度 |
| --- | --- | --- |
| **LXQt** | Qt ベースで Xfce と思想が近く、アイドル RAM がさらに 50–100MB 少ない。CPU モニタ等のパネルプラグインも揃う | ★★★ |
| **MATE** | GNOME 2 路線。機能は豊富だが Xfce より少し重い傾向。逆方向 | ★ |
| **IceWM** | パネル付き超軽量。タスクバー + メニュー + 時計の必要十分。設定はテキスト | ★★ |
| **Openbox + tint2 + conky** | 自前パネル組立。dwm よりは敷居低い | ★ |
| **dwm**(`docs/06`) | アイドル 50MB 台。儀式必須 | ★(別路線) |

LXQt にするだけでも体感が変わるので、Xfce を絞り切ってもまだ足りないと感じたら試してみる価値はあります。

```bash
sudo apt install -y lxqt-core lxqt-config lxqt-panel lxqt-qtplugin pcmanfm-qt
# ログイン画面で「セッション」を LXQt に変更
```

---

## チューニング前後の目安(参考値)

実機・ディスク・カーネル・常駐サービスで大きく変わりますが、目安として:

| 状態 | アイドル RAM | ログインからデスクトップまで |
| --- | --- | --- |
| Kali Xfce 初期状態 | 350–500 MB | 6–10 秒 |
| 上記 1〜6 を適用後 | 220–300 MB | 3–5 秒 |
| LXQt に乗り換え | 180–250 MB | 3–4 秒 |
| dwm + 最小常駐 | 60–120 MB | 1–2 秒 |

dwm でなければ得られないほどの軽さが必要かは、実際にチューニング後の Xfce で 1 週間使ってみて判断するのが現実的です。

---

## 1 行まとめ

> **Xfce はコンポジタ off + 索引系 mask + Thunar サムネイル抑制 + セッション保存 off + Terminator + Super キーバインドで、Kali 流儀のままほぼ dwm 級の応答性になる。CPU モニタ等のパネルプラグインが既に乗っているのが大きい。**

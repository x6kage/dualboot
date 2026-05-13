# 06. Kali に DWM(suckless Dynamic Window Manager)を入れる

GPU なし・低スペック機で Kali をメイン OS として運用する場合、デスクトップ環境を **DWM** にすると劇的に軽くなります。Xfce や GNOME と違って常駐サービスがほぼ無く、起動 1 秒・メモリ数十 MB レベルで使えます。

このドキュメントは「**Kali を最小構成で入れた直後の状態から、dwm で実用環境を立ち上げる**」までを最短で示します。

---

## 0. 前提と方針

- Kali のインストール時に **「Software selection」で Xfce 等を全部外す**(GUI なしの最小構成)。Xfce 入りで入れた後でも問題ないが、後述の「Xfce を残したまま並列導入」セクションを参照。
- DWM は **設定 = ソース修正 → 再コンパイル**(`config.h` を編集して `make install`)。これに抵抗があるなら **i3** や **bspwm** の方が向く。本ドキュメントは DWM のこの流儀を前提に進める。
- 構成:
  - **dwm**: タイル型 WM(本体)
  - **st**: suckless 製ターミナル
  - **dmenu**: アプリランチャ(`Mod+p`)
  - **slock**: スクリーンロック
  - **slstatus**: ステータスバー(画面右上の時刻・バッテリ・音量等)
  - **picom**: 透過/コンポジタ(任意。ティアリング解消)
  - **feh** または **xwallpaper**: 壁紙
  - **xinit**: `startx` で起動。ログインマネージャ無し運用が一番軽い

---

## 1. 必要パッケージのインストール

```bash
sudo apt update
sudo apt install -y --no-install-recommends \
    xorg xinit xserver-xorg-input-libinput \
    build-essential pkg-config git \
    libx11-dev libxinerama-dev libxft-dev libxrandr-dev \
    libxcb-res0-dev libfontconfig-dev \
    fonts-noto-cjk fonts-firacode \
    network-manager-gnome \
    pulseaudio pavucontrol \
    feh picom \
    firefox-esr \
    xclip xdotool maim
```

> Kali は `network-manager` 自体は最小構成でも入っていることが多いが、`nm-applet` (`network-manager-gnome`) はトレイ操作のため別途入れる。

ノートでバッテリ表示や明るさ調整が要るなら追加で:

```bash
sudo apt install -y acpi acpid xbacklight brightnessctl tlp tlp-rdw
sudo systemctl enable --now tlp
```

---

## 2. suckless 系をソースから入れる

Kali (Debian) のパッケージ版は古いことが多いので、`~/src/` にクローンしてビルドする方が後悔しません。

```bash
mkdir -p ~/src && cd ~/src
git clone https://git.suckless.org/dwm
git clone https://git.suckless.org/st
git clone https://git.suckless.org/dmenu
git clone https://git.suckless.org/slock
git clone https://git.suckless.org/slstatus

for d in dwm st dmenu slock slstatus; do
  ( cd "$d" && cp -n config.def.h config.h && sudo make clean install )
done
```

> `cp -n` は既存の `config.h` を保護するため。再ビルドする時は `config.h` を直接編集してから `sudo make clean install`。

### dwm の最小カスタマイズ例(`~/src/dwm/config.h`)

よく変える 3 箇所:

```c
/* フォント(CJK は Noto Sans CJK JP を fallback に) */
static const char *fonts[]          = { "monospace:size=10", "Noto Sans CJK JP:size=10" };

/* MOD キー: Mod1Mask=Alt, Mod4Mask=Win/Super 推奨 */
#define MODKEY Mod4Mask

/* ターミナル: st */
static const char *termcmd[]  = { "st", NULL };
```

変えたら `cd ~/src/dwm && sudo make clean install`。

---

## 3. `~/.xinitrc` を書いて `startx` で起動

```bash
cat > ~/.xinitrc <<'EOF'
#!/bin/sh
# キーボードレイアウト(必要に応じて)
setxkbmap -layout jp

# 壁紙(ファイルが無ければスキップされる)
feh --bg-fill ~/Pictures/wallpaper.jpg 2>/dev/null

# コンポジタ(ティアリング軽減、不要なら #)
picom -b

# ネットワークマネージャのトレイ
nm-applet &

# ステータスバー
slstatus &

# 最後に dwm を exec(これが終わると X セッションが終わる)
exec dwm
EOF
chmod +x ~/.xinitrc
```

tty(Ctrl+Alt+F2 など)でログインして:

```bash
startx
```

`Mod+p`(Super+p)で dmenu、`Mod+Shift+Enter` で st が起動すれば成功。

### 自動 startx(任意)

`~/.bash_profile` に以下を追加すると、tty1 でログイン直後に自動で X を起動します。

```bash
if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
    exec startx
fi
```

---

## 4. ステータスバーの中身を変える

`slstatus` は `~/src/slstatus/config.h` で表示項目を選びます。例(時刻・CPU 温度・音量・バッテリ・ネットワーク・日時):

```c
static const struct arg args[] = {
    /* function format          argument */
    { run_command, " %s",       "iwgetid -r" },
    { temp,        " %s°C ",   "/sys/class/thermal/thermal_zone0/temp" },
    { cpu_perc,    " CPU %s%% ", NULL },
    { ram_perc,    " RAM %s%% ", NULL },
    { battery_perc," BAT %s%% ", "BAT0" },
    { datetime,    " %s ",      "%Y-%m-%d %H:%M" },
};
```

変更したら `cd ~/src/slstatus && sudo make clean install` → `pkill slstatus && slstatus &`。

---

## 5. よく使うパッチ(任意)

DWM は **パッチ前提の設計** で、公式リポジトリにユーザコミュニティのパッチが豊富です。<https://dwm.suckless.org/patches/> から取得して `patch -p1 < xxx.diff` で適用 → 再ビルド。

低スペック機で QoL が上がるパッチ例:

| パッチ | 効果 |
| --- | --- |
| `pertag` | タグ(ワークスペース)毎にレイアウト/マスタ比率を保持 |
| `gaplessgrid` | グリッドレイアウトを追加 |
| `attachbottom` / `attachaside` | 新規ウィンドウの挿入位置を調整 |
| `systray` | dwm のバーにシステムトレイ(nm-applet 等)を表示 |
| `restartsig` | `Mod+Shift+r` で再起動(再ログイン無しで設定反映) |
| `vanitygaps` | ウィンドウ間に隙間 |

> 複数パッチを当てると衝突しやすいので、`git diff` を読みながら手作業マージを覚悟する。

---

## 6. Office / 文書まわり(GPU なし機での実用)

| 用途 | 軽量寄りの選択 |
| --- | --- |
| Word / Excel / PowerPoint 互換 | **OnlyOffice Desktop** が LibreOffice より軽量で MS 互換も良好。`apt install onlyoffice-desktopeditors`(リポジトリ追加要、または `.deb` 直入れ) |
| ブラウザで Office 365 | Firefox ESR で十分。ChromeOS 並みに完結する |
| PDF | `zathura` (vim キーバインド)。`apt install zathura zathura-pdf-poppler` |
| 画像ビューア | `feh`、`sxiv` |
| ファイルマネージャ | CLI で `ranger` または `lf`。GUI が必要なら `pcmanfm` |
| メモ・ノート | `vim` / `neovim`、または `obsidian` (重め)、`logseq` |

**完全な Office 互換性が必要なときだけ Windows 側に再起動** という運用にすれば、Office プリインの価値も活きます。

---

## 7. Xfce を残したまま dwm を並列導入する場合

最小インストールにし損ねた場合、ログインマネージャ (lightdm 等) のセッション一覧に dwm を出すには:

```bash
sudo tee /usr/share/xsessions/dwm.desktop >/dev/null <<'EOF'
[Desktop Entry]
Name=dwm
Comment=Dynamic Window Manager
Exec=dwm
Type=Application
EOF
```

ログイン画面の歯車アイコンで「dwm」を選んでログインすれば、`/etc/X11/Xsession.d/` 経由のスクリプトが走ったあと dwm が起動します。`~/.xprofile`(`.xinitrc` ではない)に `nm-applet &` 等の常駐を書く必要があります。

---

## 8. トラブルシューティング

| 症状 | 対処 |
| --- | --- |
| `startx` で「server died」「no screens found」 | `Xorg.0.log` を確認(`/var/log/Xorg.0.log`)。GPU ドライバの `xserver-xorg-video-*` 不足が多い。Intel/AMD 内蔵なら `xserver-xorg-video-intel` / `-amdgpu` |
| 日本語入力が効かない | `fcitx5-mozc` を入れて `~/.xprofile` に `export GTK_IM_MODULE=fcitx; export QT_IM_MODULE=fcitx; export XMODIFIERS=@im=fcitx; fcitx5 -d &` |
| `Mod+p` で dmenu が出ない | `which dmenu_run` を確認。`config.h` の `dmenucmd` が指すパスが正しいか。`sudo make install` でビルド産物が `/usr/local/bin` に入っているか |
| バッテリ表示が `slstatus` で 0 % | `BAT0` ではなく `BAT1` の機種がある。`ls /sys/class/power_supply/` を見て名前を合わせる |
| 画面がティアリングする | `picom -b` を有効に。`~/.config/picom.conf` に `vsync = true;` |
| dwm を再起動したい | restartsig パッチを当てて `Mod+Shift+r`。当てない場合は `pkill -USR1 dwm` 系では再起動できないので、`exec dwm` を `~/.xinitrc` で `while :; do dwm; done` のループにし、`pkill dwm` で再起動する手もある |

---

## 9. 1 行まとめ

> **「最小 Kali + xorg + dwm + st + dmenu + slstatus + nm-applet」までを `~/.xinitrc` 1 枚で起動できるようにすると、GPU なし低スペック機が一気に実用機になる。Office 互換が必要なときだけ Windows に再起動。**

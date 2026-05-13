# dualboot

WindowsとLinuxのデュアルブート構築、ならびに **GRUB2 を Windows Boot Manager より優先** させる作業を簡略化するためのドキュメントとヘルパースクリプト集です。

想定する典型シナリオ:

> **Office 等がプリインストールされた Windows 機に Kali Linux(または他の distro)を追加し、Linux をメイン OS に、Windows は温存してたまに使う形にしたい。GPU なし低スペック機ではデスクトップに DWM を使って徹底的に軽量化したい。**

UEFIファームウェアに直接 GRUB2 を第一候補として登録する方法を中心に扱い、Windows Boot Manager の正しい扱い方(消すと何が起きるか / 優先度を下げるだけで十分なこと)、Kali を入れる際の Office 温存手順、DWM での実用環境構築までをひと通りカバーします。

## 構成

```
.
├── README.md                            … 本ファイル(概要とクイックスタート)
├── docs/
│   ├── 01-dualboot-setup.md             … デュアルブート構築の基礎(BIOS/UEFI、パーティション設計、OSインストール順)
│   ├── 02-grub-priority.md              … GRUB2 を Windows Boot Manager より優先する 4 つの方法と推奨手順
│   ├── 03-troubleshooting.md            … GRUB が出ない / Windows Update で書き換えられた等の復旧
│   ├── 04-keep-windows-add-kali.md      … Office プリイン Windows を残したまま Kali を追加する手順(Linux メイン推奨)
│   ├── 05-windows-boot-manager-faq.md   … 「Windows Boot Manager を消したら Windows は起動できない?」FAQ
│   ├── 06-dwm-on-kali.md                … Kali に DWM(suckless)で最小デスクトップを構築(ハック志向)
│   ├── 07-remove-windows-boot-entry.md  … Windows Boot Manager の UEFI エントリを完全削除し GRUB chainload で起動する
│   ├── 08-bootloader-comparison.md      … 2026 年時点の Linux ブートローダ比較(GRUB2 / sd-boot / EFISTUB+UKI / Limine / rEFInd)
│   ├── 09-light-xfce-on-kali.md         … Kali 既定の Xfce をチューニングして軽量運用 + Terminator(実用志向・推奨)
│   ├── 10-windows-games-on-linux.md     … Windows 専用ゲームを Linux で動かす(Steam+Proton / Heroic / Lutris / Bottles / アンチチート)
│   └── 11-hoyo-and-cn-gacha-on-linux.md … HoyoPlay / Wuthering Waves / 中華ガチャゲー & XXMI Launcher を Linux で動かす
└── scripts/
    ├── linux/
    │   ├── show-boot-order.sh           … 現在の UEFI ブート順を表示
    │   ├── set-grub-first.sh            … GRUB を UEFI ブート順の先頭に設定(Linux メイン用・推奨)
    │   ├── set-windows-first.sh         … Windows Boot Manager を UEFI ブート順の先頭に戻す(対称版)
    │   ├── remove-windows-boot-entry.sh … Windows Boot Manager の NVRAM エントリを削除(bootmgfw.efi は温存)
    │   ├── restore-windows-boot-entry.sh… 上記の復元
    │   ├── install-grub-efi.sh          … GRUB2(EFI)を /boot/efi にインストール
    │   ├── repair-grub.sh               … chroot 不要の最小限の GRUB 修復
    │   ├── install-gaming-stack.sh      … Steam / Lutris / Heroic / Bottles / GameMode / MangoHud / Gamescope を一括導入(Flatpak 併用、冪等)
    │   └── install-aagl-launchers.sh    … An Anime Game Launcher 一族 (Genshin/HSR/Honkai 3/ZZZ/WuWa) + Bottles + Heroic を Flatpak で一括導入
    └── windows/
        ├── show-boot-order.bat          … bcdedit で現在のブート順を表示
        ├── set-grub-first.bat           … bcdedit で GRUB(\EFI\<distro>\grubx64.efi)を Windows よりも優先
        └── set-grub-first.ps1           … 上記 bat の本体(PowerShell)
```

## クイックスタート

> 前提: UEFI システム / GPT ディスク / Linux と Windows は既に同一マシンにインストール済み(または `docs/01-dualboot-setup.md` / `docs/04-keep-windows-add-kali.md` の手順でこれからインストールする)。

### 【推奨】Linux をメインに(GRUB を最優先)

```bash
sudo bash scripts/linux/show-boot-order.sh
sudo bash scripts/linux/set-grub-first.sh
```

`set-grub-first.sh` は `efibootmgr` のラッパーで、GRUB(または `ubuntu` / `debian` / `kali` / `arch` / `fedora` 等のディストリ名のエントリ)を検出し、UEFI のブート順 (`BootOrder`) の先頭に並び替えます。Windows Boot Manager は2番目以降に残るため、GRUB から `Windows Boot Manager` を選択することで従来どおり起動できます。

### Windows をメインに戻したい場合

業務都合で一時的に Windows をメインに戻すなら:

```bash
sudo bash scripts/linux/set-windows-first.sh
```

または Windows 側の管理者コマンドプロンプトで:

```bat
scripts\windows\show-boot-order.bat
scripts\windows\set-grub-first.bat        :: ※ 用途に合わせて自分で書き換え可
```

### Windows Update で GRUB が消えた場合

```bash
sudo bash scripts/linux/repair-grub.sh
sudo bash scripts/linux/set-grub-first.sh
```

詳細は `docs/03-troubleshooting.md` を参照してください。

### 「Windows Boot Manager を消したら Windows は壊れる?」

短答: **「UEFI のエントリ」を消すだけなら壊れない(GRUB から chainload で起動できる/再登録で復活)。「ESP 上のファイル」を消すと壊れる。優先度を下げるだけなら何も消す必要はない。** 詳しくは `docs/05-windows-boot-manager-faq.md`。

### Windows Update を恒久停止している環境(ReviOS 等)で UEFI エントリを完全削除したい

```bash
sudo bash scripts/linux/remove-windows-boot-entry.sh --dry-run    # まず確認
sudo bash scripts/linux/remove-windows-boot-entry.sh              # 本実行
```

スクリプトが `bootmgfw.efi` の存在と GRUB の Windows menuentry を確認し、復元情報をバックアップしてから NVRAM の `Boot####` を削除します。Windows は GRUB のメニューから chainload で起動できます。詳細・ファームウェア quirks への対処は `docs/07-remove-windows-boot-entry.md` 参照。

### Windows ゲームを Linux 側で遊びたい(Steam / Epic / GOG / Battle.net 等)

```bash
sudo bash scripts/linux/install-gaming-stack.sh
```

i386 アーキ有効化 → Steam・GameMode・MangoHud・Gamescope を apt で導入 → Flathub 追加 → Lutris / Heroic / Bottles / ProtonUp-Qt を Flatpak で導入、までを一括で行います(冪等)。ストア別の使い分け(Steam → Proton、Epic/GOG → Heroic、Battle.net → Lutris、単発 → Bottles)とアンチチート対応の現実、低スペック機向け Gamescope の使い方は `docs/10-windows-games-on-linux.md` を参照。

### HoyoPlay / Wuthering Waves / 中華ガチャ系を Linux で遊びたい

```bash
bash scripts/linux/install-aagl-launchers.sh
```

Flathub から An Anime Game Launcher ファミリ(Genshin / HSR / Honkai 3 / ZZZ / WuWa 系)と Bottles / Heroic / ProtonUp-Qt を Flatpak で一括導入(ユーザスコープ、冪等)。HoyoPlay 自体は AAGL が内包。XXMI Launcher(GIMI / SRMI / ZZMI / WWMI など 3DMigoto モッドフロントエンド)を同じ Wine prefix に同居させる手順、Wuthering Waves を Heroic+Epic 経由で動かす手順、アンチチート/TOS の注意は `docs/11-hoyo-and-cn-gacha-on-linux.md` を参照。

## 注意

- 本リポジトリのスクリプトはあくまで **作業の簡略化** が目的です。実行前にディスク構成・ESP(EFI System Partition)のマウント先を必ず確認してください。
- レガシー BIOS / MBR 環境では `efibootmgr` は使えません。`docs/02-grub-priority.md` の「BIOS/MBR の場合」を参照してください。
- BitLocker が有効な Windows ではブートローダ変更時に回復キーを求められることがあります。事前にキーを控えておいてください(`docs/04-keep-windows-add-kali.md` 0.2 節)。

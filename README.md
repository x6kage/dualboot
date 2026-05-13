# dualboot

WindowsとLinuxのデュアルブート構築、ならびに **GRUB2 を Windows Boot Manager より優先** させる作業を簡略化するための、ドキュメントとヘルパースクリプト集です。

UEFIファームウェアに直接 GRUB2 を第一候補として登録する方法を中心に扱い、bootloaderの差し替えやGRUB破損時の復旧までをひと通りカバーします。

## 構成

```
.
├── README.md                       … 本ファイル(概要とクイックスタート)
├── docs/
│   ├── 01-dualboot-setup.md        … デュアルブート構築手順(BIOS/UEFI、パーティション設計、OSインストール順)
│   ├── 02-grub-priority.md         … GRUB2 を Windows Boot Manager より優先する方法の比較と推奨手順
│   └── 03-troubleshooting.md       … GRUB が出ない・Windows Update で書き換えられた等の復旧
├── scripts/
│   ├── linux/
│   │   ├── show-boot-order.sh      … 現在の UEFI ブート順を表示
│   │   ├── set-grub-first.sh       … GRUB を UEFI ブート順の先頭に設定
│   │   ├── install-grub-efi.sh     … GRUB2(EFI)を /boot/efi にインストール
│   │   └── repair-grub.sh          … chroot 不要の最小限の GRUB 修復
│   └── windows/
│       ├── show-boot-order.bat     … bcdedit で現在のブート順を表示
│       └── set-grub-first.bat      … bcdedit で GRUB(\EFI\<distro>\grubx64.efi)を Windows よりも優先
```

## クイックスタート

> 前提: UEFI システム / GPT ディスク / Linux と Windows は既に同一マシンにインストール済み(または `docs/01-dualboot-setup.md` の手順でこれからインストールする)。

### Linux 側で GRUB を最優先にする(推奨)

```bash
sudo bash scripts/linux/show-boot-order.sh
sudo bash scripts/linux/set-grub-first.sh
```

`set-grub-first.sh` は `efibootmgr` のラッパーで、GRUB(または `ubuntu` / `debian` / `arch` 等のディストリ名のエントリ)を検出し、UEFI のブート順 (`BootOrder`) の先頭に並び替えます。Windows Boot Manager は2番目以降に残るため、GRUB から `Windows Boot Manager` を選択することで従来どおり起動できます。

### Windows 側から GRUB を最優先にする

管理者権限の **コマンドプロンプト** で:

```bat
scripts\windows\show-boot-order.bat
scripts\windows\set-grub-first.bat
```

`set-grub-first.bat` は `bcdedit /enum firmware` から GRUB のファームウェアエントリを抽出し、`bcdedit /set {fwbootmgr} displayorder <GUID> /addfirst` を実行します。

### Windows Update で GRUB が消えた場合

```bash
sudo bash scripts/linux/repair-grub.sh
sudo bash scripts/linux/set-grub-first.sh
```

詳細は `docs/03-troubleshooting.md` を参照してください。

## 注意

- 本リポジトリのスクリプトはあくまで **作業の簡略化** が目的です。実行前にディスク構成・ESP(EFI System Partition)のマウント先を必ず確認してください。
- レガシー BIOS / MBR 環境では `efibootmgr` は使えません。`docs/02-grub-priority.md` の「BIOS/MBR の場合」を参照してください。
- BitLocker が有効な Windows ではブートローダ変更時に回復キーを求められることがあります。事前にキーを控えておいてください。

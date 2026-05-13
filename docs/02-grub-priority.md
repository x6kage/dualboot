# 02. GRUB2 を Windows Boot Manager より優先させる方法

UEFI システムでは、PC の電源投入時に **UEFI ファームウェア自身が `BootOrder` 変数の先頭にあるブートエントリを起動** します。GRUB を「優先」させるとは、要するにこの `BootOrder` の先頭を `Windows Boot Manager`(`bootmgfw.efi`)から GRUB のエントリ(`grubx64.efi` / `shimx64.efi`)に変更することです。

ここでは、簡単な方法から「絶対に上書きされたくない」場合の堅牢な方法まで、4 つのアプローチを比較します。

---

## 方法の比較

| # | 方法 | 難易度 | 永続性 | 主な用途 |
| --- | --- | --- | --- | --- |
| A | Linux で `efibootmgr -o` でブート順を変更 | ★☆☆ | △(Windows Update で戻ることあり) | **基本はこれ。最も簡単。** |
| B | Windows で `bcdedit /set {fwbootmgr} displayorder ... /addfirst` | ★☆☆ | △(同上) | Linux に入れない時の応急処置 |
| C | Windows の `bootmgfw.efi` を GRUB の `grubx64.efi` で **上書き** | ★★☆ | ◎ | UEFI 設定がリセットされる機種、頑なに Windows を最優先にする機種で有効 |
| D | rEFInd / systemd-boot を ESP に入れて第一ブートにする | ★★☆ | ○ | 見た目重視 / 多 OS / Mac |

> 本リポジトリの `scripts/linux/set-grub-first.sh` は **方法 A**、`scripts/windows/set-grub-first.bat` は **方法 B** を実行します。
> 方法 C は手作業手順をこのドキュメントの末尾に記載します(自動化は **意図的に** 行いません。誤操作で Windows が起動できなくなる可能性があるため)。

---

## 方法 A: Linux 側で `efibootmgr` を使う(推奨)

### 仕組み

UEFI ファームウェアは NVRAM に以下の変数を持っています。

- `Boot0000`, `Boot0001`, …: 各ブートエントリ(EFI バイナリへのパス + ラベル)
- `BootOrder`: ファームウェアが試行する順序(例: `0001,0000,2001`)
- `BootCurrent`: 今このセッションで起動した番号

`efibootmgr -o 0001,0000,2001` のように、**`BootOrder` の先頭に GRUB の番号** を置けば次回以降 GRUB が先に起動します。

### 手順(手動)

```bash
sudo efibootmgr -v
# Boot0000* Windows Boot Manager
# Boot0001* ubuntu
# BootOrder: 0000,0001,...

sudo efibootmgr -o 0001,0000     # ubuntu を先頭に
sudo efibootmgr                   # 確認
```

### 手順(本リポジトリの簡略化スクリプト)

```bash
sudo bash scripts/linux/show-boot-order.sh
sudo bash scripts/linux/set-grub-first.sh
```

GRUB のラベルは distro により `ubuntu`, `debian`, `arch`, `fedora`, `manjaro`, `opensuse`, `GRUB`, `Linux Boot Manager` など様々ですが、スクリプトはこれらを含むエントリを自動検出します。

### 注意

- 一部の OEM ファームウェア(古めの ASUS / HP など)は **再起動するたびに `Windows Boot Manager` を最優先に戻す** バグ的挙動を持ちます。これに当たった場合は方法 C を検討してください。
- Windows のメジャーアップデート(機能更新)後、Windows が再び `BootOrder` の先頭に来ることがあります。再度スクリプトを流せば直ります。

---

## 方法 B: Windows 側で `bcdedit` を使う

Linux 環境にすぐ入れない、もしくは Windows に居る間に修正したい場合の方法です。

### 手順(手動)

**管理者権限のコマンドプロンプト** で:

```bat
bcdedit /enum firmware
```

出力から GRUB のエントリ(`description` が `ubuntu` などになっているブロック)の `identifier`(GUID 形式)を控えます。例:

```
Firmware Application (101fffff)
identifier              {a1b2c3d4-...-............}
description             ubuntu
```

そのうえで:

```bat
bcdedit /set "{fwbootmgr}" displayorder "{a1b2c3d4-...-............}" /addfirst
```

### 手順(本リポジトリの簡略化スクリプト)

管理者の **コマンドプロンプト** で:

```bat
scripts\windows\show-boot-order.bat
scripts\windows\set-grub-first.bat
```

`set-grub-first.bat` は `bcdedit /enum firmware` をパースし、`ubuntu / debian / arch / fedora / manjaro / opensuse / grub / linux` のいずれかを含むエントリを GRUB と判定して先頭に追加します。

> Windows の `bcdedit /set {fwbootmgr} ...` は、内部的には UEFI の `BootOrder` 変数を書き換えています。つまり方法 A と方法 B は **同じものを別側から触っている** だけです。

---

## 方法 C: `bootmgfw.efi` を `grubx64.efi` で上書きする

ファームウェアが頑なに `\EFI\Microsoft\Boot\bootmgfw.efi` を最優先しようとする機種(ベンダーが Windows ロゴ取得の都合で UEFI 仕様を逸脱しているケース)で使う最終手段です。**「Windows Boot Manager のフリをする GRUB」** を ESP に置きます。

### 概念

- ESP の `\EFI\Microsoft\Boot\bootmgfw.efi` を **退避** したうえで、GRUB の EFI バイナリ(`\EFI\<distro>\grubx64.efi`)で置き換える。
- ファームウェアが Windows Boot Manager を起動しているつもりで GRUB が立ち上がる。
- GRUB のメニューから Windows を起動する場合、退避先の `bootmgfw.efi.bak` を chainload するように `40_custom` を書く。

### 手順(慎重に)

```bash
# 1. ESP をマウント(通常 /boot/efi)
sudo mount /boot/efi 2>/dev/null || true
ls /boot/efi/EFI/Microsoft/Boot/bootmgfw.efi   # 存在確認

# 2. バックアップ
sudo cp /boot/efi/EFI/Microsoft/Boot/bootmgfw.efi \
        /boot/efi/EFI/Microsoft/Boot/bootmgfw.efi.bak

# 3. GRUB の EFI バイナリで置き換え(ディストリ名は環境に合わせる)
sudo cp /boot/efi/EFI/ubuntu/grubx64.efi \
        /boot/efi/EFI/Microsoft/Boot/bootmgfw.efi
```

### GRUB から Windows を起動できるようにする

`/etc/grub.d/40_custom` に以下を追記:

```bash
menuentry "Windows Boot Manager (chainload bootmgfw.efi.bak)" {
    insmod part_gpt
    insmod fat
    insmod chain
    search --no-floppy --fs-uuid --set=root <ESP の UUID>
    chainloader /EFI/Microsoft/Boot/bootmgfw.efi.bak
}
```

`<ESP の UUID>` は次で確認:

```bash
sudo blkid | grep -i vfat
```

最後に:

```bash
sudo update-grub        # Debian/Ubuntu
# または
sudo grub-mkconfig -o /boot/grub/grub.cfg
```

### 注意・リスク

- **Windows の機能更新 (Feature Update) が `bootmgfw.efi` を上書きすることがあります。** その場合、上の手順 2–3 を再実行してください(スクリプト化はしていません。Windows 更新の有無を見ずに実行するとバックアップを破壊する可能性があるためです)。
- BitLocker が有効な場合、Windows のブートローダ差し替えで **回復キーを要求** されます。事前に回復キーを必ず控えること。
- Secure Boot 環境では署名済 `shimx64.efi` を使う必要があります(`grubx64.efi` 単体だと弾かれます)。

---

## 方法 D: rEFInd / systemd-boot に切り替える

GRUB をやめて、別のブートマネージャ(`rEFInd` や `systemd-boot`)を ESP に入れて第一ブートにする方法です。

- **rEFInd**: 自動検出が強力で、GUI が綺麗。マルチ OS 環境で人気。
- **systemd-boot**: Arch / Fedora 系で増えている。極めてシンプル。

導入後の優先度設定は方法 A / B と同じく `efibootmgr` または `bcdedit` で行います。

---

## まとめ:どれを選ぶか

```
通常のユーザ ─→ A(efibootmgr) ─→ 戻ってしまう ─→ C(bootmgfw 差し替え)
                                       └→ それでも嫌 ─→ D(rEFInd)
Linux に入れない ─→ B(bcdedit)
```

90% のケースは **方法 A だけで十分** です。
本リポジトリの `scripts/linux/set-grub-first.sh` を一発実行すれば終わります。

```bash
sudo bash scripts/linux/set-grub-first.sh
```

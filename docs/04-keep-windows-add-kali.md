# 04. Windows を残したまま Kali Linux を追加する(プリイン Office 機向け)

OEM プリイン Windows(Office、ベンダー製ドライバ・ユーティリティ等)を **温存** したまま、空き容量に Kali Linux を追加し、デュアルブートにする手順です。
**Windows は再インストールしません。** 既存の C: パーティションを縮小して未割り当て領域を作り、そこに Kali を入れます。

**本ガイドのデフォルト方針: Linux (Kali) をメイン OS にする。** Windows は Office や OEM 専用ツール用に温存し、必要なときだけ GRUB から呼び出します。Windows ゲームは Linux 側で Steam (Proton) / Lutris で動くので、ゲームのために Windows を起動する必要は基本ありません。

運用パターン:

- **【推奨】パターン B: Linux メイン**(GPU なし・低スペック・開発機・通常用途)。`scripts/linux/set-grub-first.sh` で GRUB を UEFI の最優先に。Windows は GRUB のメニューから `Windows Boot Manager` を選んで起動。
- **パターン A: Windows メイン**(参考)。GRUB は入れるが UEFI ブート順は Windows のまま。Linux 起動時は F11/F12 のワンタイムブートメニュー、または BCD 経由。Windows でしか動かない業務アプリが主軸の機種向け。

---

## 0. 事前確認(壊さないために最重要)

### 0.1 ストレージとリカバリ領域の把握

Windows 側で:

```bat
diskpart
DISKPART> list disk
DISKPART> select disk 0
DISKPART> list partition
DISKPART> exit
```

代表的な OEM 機のレイアウト:

```
Partition 1   System      (FAT32 ESP, 100–500MB)        ← 残す。Linux と共有
Partition 2   Reserved    (MSR, 16MB)                    ← 残す
Partition 3   Primary     (NTFS C:, 残り大部分)          ← ここを縮める
Partition 4   Recovery    (NTFS, 数百MB〜十数GB)         ← 残す。消すと工場出荷リセット不可
```

**Recovery と System / MSR は絶対に削除・移動しないこと。** OEM 個別のリカバリツールが動かなくなります。

### 0.2 BitLocker の確認(暗号化されているなら必須)

```bat
manage-bde -status C:
```

- `Conversion Status: Fully Encrypted` で `Protection Status: Protection On` の場合は **暗号化されています**。
- パーティション操作前に **必ず回復キーを控える**:
  - 個人アカウント: <https://aka.ms/myrecoverykey>
  - 職場/学校アカウント: 管理者へ
  - 自宅で OneDrive 同期されているはず: 上の URL から取得
- 作業時の安全策として、ブート構成変更直前に **保護を一時停止** :
  ```bat
  manage-bde -protectors -disable C:
  ```
  これで再起動時の回復キー入力を回避できます(再有効化を忘れずに)。

### 0.3 Windows 側の必須準備

管理者コマンドプロンプトで:

```bat
powercfg /h off                   :: 高速スタートアップを無効化
chkdsk C: /f                      :: NTFS の整合性チェック(再起動が必要)
```

> **高速スタートアップを無効化しないと**、シャットダウンしてもカーネル状態を NTFS にキャッシュしたまま終了するため、(1) UEFI のブート順設定が無視される、(2) Linux から NTFS をマウントすると壊れる可能性、の 2 つの事故が起きます。**デュアルブート時は必須**。

### 0.4 バックアップ

最低限:

- ドキュメント・写真・ライセンスキー(Office、ベンダー製アプリのキー)
- ブラウザのブックマーク・パスワード
- 可能ならシステムイメージ(`コントロールパネル → バックアップと復元 (Windows 7)` から作成)

---

## 1. C: の縮小(未割り当て領域を作る)

Windows の `diskmgmt.msc`(ディスクの管理)で C: を右クリック → **ボリュームの縮小**。

- Kali には最低 40GB、できれば **80GB〜150GB** を未割り当てに残す。
- 縮小可能サイズが少ない場合の原因は通常 **ページファイル / 休止ファイル / システム保護 / 移動不可ファイル** 。次を行うと縮小可能量が増えます:
  ```bat
  powercfg /h off
  ```
  ```
  システムのプロパティ → システムの保護 → 構成 → 削除
  仮想メモリ → 自動管理を外して「ページングファイルなし」(後で戻す)
  ```
  最後に **デフラグ**(`dfrgui.exe`)。SSD の場合は不要だが TRIM を発行するのでやって損はない。
- それでも縮まないときは Linux Live USB から `gparted` で縮める方が成功率が高い(**ただし NTFS の整合性が事前に必須**。0.3 の `chkdsk` は必ず)。

---

## 2. UEFI 設定

| 項目 | 推奨 |
| --- | --- |
| Boot Mode | **UEFI**(CSM/Legacy 無効) |
| Secure Boot | **有効のままで OK**(Kali は signed shim を持つ) |
| Fast Boot (UEFI) | 無効(USB ブートを確実に) |
| TPM | そのまま(BitLocker 維持のため) |

---

## 3. Kali のインストール

1. **Kali Linux Installer Image** を <https://www.kali.org/get-kali/> からダウンロードし、`balenaEtcher` 等で USB に書き込む。Live イメージでもインストールはできるが、専用 Installer の方が低スペック機で安定。
2. PC を再起動し、ワンタイムブートメニュー(F11/F12 等)から **UEFI: USB ...** を選択。
3. インストーラの言語・キーボード・ネットワーク・ユーザを設定。
4. **パーティション設定で「手動」を選択**(自動だと Windows ごと消える危険があるため):
   - 既存の **EFI System Partition (FAT32, 100–500MB)** を選び:
     - 「使用方法」→ **EFI System Partition**
     - 「マウントポイント」→ `/boot/efi`
     - **再フォーマットしない**(Use as: do not format)
   - 未割り当て領域に新規パーティションを作成:
     - `/`(ルート): 30GB+、ext4、bootable フラグ不要
     - `/home`: 残り、ext4
     - swap: RAM が 8GB 未満なら同サイズ、それ以上なら zram(後述)で代替してもよい
   - **Windows の C: / Recovery / MSR には触らない**(変更フラグが付いていないことを必ず確認)
5. ソフトウェア選択:
   - **GPU なし低スペック機**: ここで **何も選ばない**(後で dwm 等を入れる)
   - **通常**: Xfce(既定)で問題なし
6. ブートローダ:
   - 「GRUB をインストールしますか?」→ Yes
   - インストール先 → **ディスク全体**(例 `/dev/nvme0n1`、`/dev/sda` 等)。**パーティション単体ではなくディスクを選ぶ。**
7. インストール完了 → 再起動 → USB を抜く。

GRUB のメニューに **Kali GNU/Linux** と **Windows Boot Manager** が両方並べば成功です。出ない場合は次:

```bash
sudo apt install -y os-prober
sudo sed -i 's/^#\?GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
sudo update-grub
```

---

## 4. ブート順の運用

### 【推奨】パターン B: Linux をメインに

Kali のインストーラが GRUB を入れた直後は、たいていの機種で GRUB が `BootOrder` の先頭になっています。念のため明示的に最優先に固定:

```bash
sudo bash scripts/linux/show-boot-order.sh        # 現状確認
sudo bash scripts/linux/set-grub-first.sh         # GRUB を BootOrder の先頭に
```

これで電源 ON → GRUB メニュー → 既定で Kali、必要なときだけ `Windows Boot Manager` を選ぶ運用になります。

> Windows の機能更新 (Feature Update) 後に `BootOrder` が Windows 側に戻る機種があります。Linux に戻れたら再度 `set-grub-first.sh` を流せば直ります。これでも戻ってしまう頑固な機種は `docs/02-grub-priority.md` の **方法 C(`bootmgfw.efi` 差し替え)** を検討。

### パターン A: Windows をメインに(必要な場合のみ)

業務アプリの都合等で Windows をメインにする選択もあります。その場合は逆向きのスクリプトで `BootOrder` の先頭を Windows に戻します:

```bash
sudo bash scripts/linux/set-windows-first.sh
```

Windows に戻したあと、Linux を起動したいときは:

- 起動時に F11/F12 等で **ワンタイムブートメニュー**から GRUB(distro 名)を選ぶ、または
- Windows の BCD に Linux エントリを追加(`bcdedit /create /d "Linux" /application bootsector` 系)。設定の手間に見合わないため、ワンタイムブートメニュー運用を推奨。
- **EasyBCD / Grub2Win** などの GUI ツールで Linux エントリを Windows のメニューに足すこともできる。

---

## 5. 動作確認チェックリスト

- [ ] GRUB に Linux と Windows の両方が出る
- [ ] Linux を起動できる、ネット接続できる、`/home` が存在する
- [ ] Windows を起動できる、Office が起動する、ライセンスが有効のまま
- [ ] BitLocker を再有効化した(0.2 で停止した場合):
      `manage-bde -protectors -enable C:`
- [ ] Windows の高速スタートアップが無効のまま(`powercfg /a` で確認)
- [ ] 複数回再起動して、設定したブート順がリセットされない

ここまで通れば構築完了です。

---

## 6. よくあるハマりどころ

| 症状 | 原因 / 対処 |
| --- | --- |
| Kali インストール後、再起動するとそのまま Windows が起動する | UEFI が頑なに Windows 優先(`docs/02-grub-priority.md` 参照)。`set-grub-first.sh` で改善しないなら **方法 C(`bootmgfw.efi` 差し替え)** を検討 |
| Windows Update 後、GRUB が消えた | `scripts/linux/repair-grub.sh` でライブ USB から修復 |
| Windows がブート時に毎回 BitLocker 回復キーを聞く | ブート構成変更を BitLocker が検知。**Windows 起動後に `manage-bde -protectors -enable C:` で TPM/PCR 値を再シール** すると以後出なくなる |
| Office が「ライセンス認証してください」と出る | Microsoft アカウントでサインイン。OEM デジタルライセンスはハードウェアに紐付くので、再認証は通る |
| Linux で Wi-Fi が動かない | Realtek 等のドライバ未対応。**有線で起動して `apt install firmware-linux firmware-realtek` 系を入れる**。それでも駄目な機種は kernel メーリングリストや `linux-hardware.org` で機種を検索 |
| GPU なし機で Xorg が重い | 既定 DE をやめて **dwm** にすると劇的に軽くなる。`docs/06-dwm-on-kali.md` 参照 |

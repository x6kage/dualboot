# 07. Windows Boot Manager の UEFI エントリを完全に消す(GRUB chainload で起動)

「Windows Boot Manager が UEFI のブートメニュー / `BootOrder` の先頭に居座って『俺が唯一の OS』面してくる」のが嫌で、**順序の入れ替えではなく根本的にエントリ自体を消したい** 場合の手順とスクリプトです。

## 前提と狙い

- ESP 上の `\EFI\Microsoft\Boot\bootmgfw.efi` ファイルは **温存** する
- UEFI NVRAM の `Boot####` エントリ(description が `Windows Boot Manager` のもの)だけを削除する
- Windows は **GRUB のメニューからチェーンロードで起動** する
  - `os-prober` が生成するエントリは `chainloader /EFI/Microsoft/Boot/bootmgfw.efi` を直接呼ぶので、NVRAM エントリには **依存していません**
- 結果: ファームウェアのブートメニュー (F11/F12) からは「Windows」が消え、UEFI Boot Override も Linux (GRUB) しか出なくなる

## なぜこれが「恒久的」に効くのか

`Boot####` 変数は **誰かが `EfiSetVariable` を呼ばない限り再生成されません**。代表的な再生成タイミングと、本ガイドが想定するケース:

| 再生成のトリガ | 通常 | ReviOS / Update 停止環境 |
| --- | --- | --- |
| Windows Update (累積更新・機能更新) で `bootmgr` が再配置される | あり得る | **無効化済み → 起こらない** |
| Windows のインプレース修復 / 回復オプション (`bcdboot` 自動実行) | 自分で起動しない限りなし | 同上 |
| `bcdedit /set ...` を Windows で手動実行 | 自分次第 | 自分次第 |
| OEM ファームウェアが起動毎に ESP をスキャンしてエントリ自動生成 | 一部古めの HP / ASUS で稀に発生 | 機種依存。当たったら後述 |

つまり **「ReviOS で Windows Update を完全停止」+「自分で `bcdboot` を打たない」** という条件が揃えば、エントリ削除は実質的に恒久措置になります。本リポジトリのスクリプトはこの前提を活用します。

> なお、Windows のライセンス・認証状態は NVRAM のブートエントリとは無関係です。Office 認証を含めて何も影響を受けません(`docs/05-windows-boot-manager-faq.md` 参照)。

## 手順(スクリプト)

### 1. 事前確認

GRUB メニューから Windows が起動できることを **先に確認** してください。これは必須です(エントリ削除後の唯一の起動経路になるので)。

```bash
sudo cat /boot/grub/grub.cfg | grep -A4 -iE 'windows boot manager|bootmgfw'
```

`chainloader /EFI/Microsoft/Boot/bootmgfw.efi` を含む menuentry が見えれば OK。出てこない場合:

```bash
sudo apt install -y os-prober
sudo sed -i 's/^#\?GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
sudo update-grub
```

念のため一度 GRUB から実際に Windows を起動して、ログイン画面まで到達できることを確認してから戻ってきてください。

### 2. 削除(まずは dry-run)

```bash
sudo bash scripts/linux/remove-windows-boot-entry.sh --dry-run
```

スクリプトは以下を順にチェックします:

1. UEFI モードで起動しているか
2. ESP が `/boot/efi` にマウントされているか
3. **`bootmgfw.efi` が ESP に存在するか**(無ければ拒否)
4. `grub.cfg` に Windows のチェーンロード menuentry が **居るか**(無ければ拒否、`--skip-grub-check` で抑止可)
5. 削除対象の `Boot####` を自動検出
6. 復元用バックアップを `/var/lib/dualboot/windows-boot-entry.backup` に保存

問題がなければ本実行:

```bash
sudo bash scripts/linux/remove-windows-boot-entry.sh
```

実行例の出力:

```
[ok] /boot/grub/grub.cfg に Windows のチェーンロード menuentry を確認しました。
[info] 削除対象: Boot0000  Windows Boot Manager  HD(1,GPT,...)/File(\EFI\Microsoft\Boot\bootmgfw.efi)
[ok] 復元情報を /var/lib/dualboot/windows-boot-entry.backup に保存しました。
[ok] Boot0000 (Windows Boot Manager) を NVRAM から削除しました。
     ESP 上の \EFI\Microsoft\Boot\bootmgfw.efi ファイルは温存されています。
     Windows は GRUB のメニューから起動してください。
```

`efibootmgr` 出力からも `Windows Boot Manager` の行が消え、UEFI のブートメニューにも出なくなります。

### 3. 復元(必要になったら)

```bash
sudo bash scripts/linux/restore-windows-boot-entry.sh
```

バックアップから `efibootmgr --create` を組み立てて再登録します。`--dry-run` 対応。

手動で復元する場合は次の 1 行(値はバックアップファイルの内容で置換):

```bash
sudo efibootmgr --create \
    --disk /dev/nvme0n1 --part 1 \
    --label "Windows Boot Manager" \
    --loader '\EFI\Microsoft\Boot\bootmgfw.efi'
```

## ファームウェアが勝手にエントリを再生成する機種への対処

稀に、**ファームウェア自身** が「ESP に `bootmgfw.efi` を見つけたら自動でエントリを作る」挙動の機種があります(古め HP / ASUS の一部)。この場合、削除しても次回起動時にゾンビのように `Windows Boot Manager` が NVRAM に復活します。

対処は **「ファームウェアに `bootmgfw.efi` の正規パスを発見させない」** こと。`\EFI\Microsoft\Boot\` ディレクトリをリネームして GRUB 側のチェーンロード先も合わせます:

```bash
# 1. ESP マウント確認
mountpoint /boot/efi
ls /boot/efi/EFI/Microsoft/Boot/bootmgfw.efi

# 2. ディレクトリをリネーム(*だけ*変える、ファイル名は保持)
sudo mv /boot/efi/EFI/Microsoft /boot/efi/EFI/Microsoft.bak

# 3. GRUB のチェーンロード先を更新するため /etc/grub.d/40_custom に直書き
sudo tee -a /etc/grub.d/40_custom >/dev/null <<EOF

menuentry "Windows (chainload Microsoft.bak/Boot/bootmgfw.efi)" {
    insmod part_gpt
    insmod fat
    insmod chain
    search --no-floppy --fs-uuid --set=root $(blkid -s UUID -o value $(findmnt -no SOURCE /boot/efi))
    chainloader /EFI/Microsoft.bak/Boot/bootmgfw.efi
}
EOF

# 4. os-prober は元のパスを見つけられないので止めておく(自動生成の重複/復活を防ぐ)
sudo sed -i 's/^#\?GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=true/' /etc/default/grub

# 5. GRUB 再生成
sudo update-grub

# 6. NVRAM エントリも削除
sudo bash scripts/linux/remove-windows-boot-entry.sh --skip-grub-check
```

これでファームウェアからは Windows のブートローダが「存在しない」ように見え、自動再登録も止まります。GRUB の `40_custom` で書いた menuentry 経由でのみ Windows が起動できる状態。

> 戻したくなったら `sudo mv /boot/efi/EFI/Microsoft.bak /boot/efi/EFI/Microsoft && sudo update-grub` で原状復帰し、`restore-windows-boot-entry.sh` を実行。

## 注意事項

- **BitLocker が有効な場合**:NVRAM のブート構成変更で BitLocker が PCR 値の変化を検知し、次回 Windows 起動時に **回復キーを要求** されます。事前に <https://aka.ms/myrecoverykey> で回復キーを控えるか、Windows 上で `manage-bde -protectors -disable C:` で一時停止してから作業してください。ReviOS の通常運用では BitLocker は無効が一般的なので問題にならないことが多いです。
- **Windows のメジャーアップデート** (機能更新) は `bootmgr` を再配置するときに `Boot####` を作り直します。ReviOS で Update 停止していれば発生しませんが、何らかの理由で Update を流した場合は本スクリプトを再実行してください(冪等です)。
- **Windows の修復オプション**(回復ドライブ等)を起動した場合、自動修復が `bootmgfw.efi` 周辺を作り直してエントリも作成し得ます。実行後は `efibootmgr -v` で確認し、必要なら再削除を。
- **Secure Boot** との関係:NVRAM エントリは Secure Boot とは独立。エントリを消しても Secure Boot 状態は変わりません。
- **`BootCurrent` が 0000 のまま**:今このセッションで起動したのが Windows Boot Manager 経由 (= `BootCurrent=0000`) だと、削除後も `BootCurrent` 表示は `0000` のまま残りますが、これは「現在実行中のエントリ番号」の記録なので問題ありません。次回起動時には新しい `BootCurrent`(GRUB のもの)になります。

## 1 行まとめ

> **`bootmgfw.efi` は残したまま `Boot####` だけを `efibootmgr -B` で削除 → GRUB のチェーンロードで Windows 起動 → ReviOS で Update 停止しているなら復活しない。`remove-windows-boot-entry.sh` が安全弁付きで一発実行する。**

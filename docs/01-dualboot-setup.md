# 01. Windows / Linux デュアルブート構築手順

ここでは、1台の PC に Windows と Linux を共存させる際の **推奨構成** と **手順** を、UEFI / GPT 環境を前提にまとめます。レガシー BIOS / MBR の差分は最後に補足します。

---

## 1. 事前準備

### 1.1 必要なもの

- 8GB 以上の USB メモリ × 2(Windows 用、Linux 用)
- インターネット接続
- 重要データのバックアップ(**必須**。デュアルブート構築時はパーティション操作を伴うため、最悪のケースを想定する)
- 利用したい Linux ディストリビューションの ISO(Ubuntu / Fedora / Arch など)
- Windows のインストールメディア(プリインストール機の場合は回復ドライブ)

### 1.2 BIOS/UEFI 設定の確認

UEFI 設定画面 (機種により F2 / F10 / Del キー) で以下を確認・変更します。

| 項目 | 推奨値 | 備考 |
| --- | --- | --- |
| Boot Mode | **UEFI** (CSM/Legacy 無効) | GRUB と Windows の混在を単純化するため |
| Secure Boot | **無効**(または Linux 側で署名済 shim を使う) | Ubuntu / Fedora は有効のままでも可 |
| Fast Boot (UEFI) | 無効 | USB ブートとブート順変更を確実にするため |
| Windows Fast Startup | **無効**(後述) | NTFS の整合性、ブート順保持のため必須 |

### 1.3 Windows の高速スタートアップを無効化

Windows 起動中に管理者権限のコマンドプロンプトで:

```bat
powercfg /h off
```

または「コントロールパネル」→「電源オプション」→「電源ボタンの動作を選択する」→「現在利用可能ではない設定を変更します」→「高速スタートアップを有効にする」のチェックを外します。

> **理由**: 高速スタートアップが有効だとシャットダウン時にカーネル状態を NTFS にキャッシュしたまま終了するため、Linux 側から NTFS をマウントするとデータ破損のリスクがあり、また UEFI のブート順設定が無視されることがあります。

---

## 2. 推奨パーティション構成(GPT)

> ディスク全体を Linux/Windows で共有する例です。SSD 1台、容量 1TB を想定。

| # | パーティション | サイズ目安 | フォーマット | マウント / 用途 |
| --- | --- | --- | --- | --- |
| 1 | EFI System Partition (ESP) | 512 MB | FAT32 | `/boot/efi`(共有) |
| 2 | Microsoft Reserved (MSR) | 16 MB | (MSR) | Windows 用予約 |
| 3 | Windows (C:) | 200–400 GB | NTFS | Windows のシステム領域 |
| 4 | Windows データ | 任意 | NTFS / exFAT | 共有データ用(任意) |
| 5 | Linux `/` | 50–100 GB | ext4 / btrfs | Linux ルート |
| 6 | Linux `/home` | 残り | ext4 / btrfs | ユーザデータ |
| 7 | swap (必要なら) | RAM と同程度 | linux-swap | スワップ(zswap/zram で代替可) |

### ポイント

- **ESP はひとつだけ**にすること。Windows と Linux が共有する。
- ESP のサイズは 300MB だと将来の更新で詰まることがあるため **512MB 以上** を強く推奨。
- Linux と Windows の **データ共有** は、別途 NTFS / exFAT 領域を切ると安全。Linux の ext4 を Windows から書くのは現実的ではない。

---

## 3. インストール順序(重要)

> **必ず Windows → Linux の順** にインストールしてください。
>
> Windows は他 OS のブートエントリを上書きする傾向がある一方、Linux のインストーラ(GRUB)は Windows のブートエントリを検出して `os-prober` 経由で GRUB メニューに自動追加してくれます。

### 3.1 Windows のインストール

1. Windows USB から起動。
2. パーティション設定画面で、上記表の **#3 (Windows C:) として割り当てる領域だけ** を作成。残りはあえて未割り当てのままにする。
   - 自動でディスク全体を使われると、後で Linux 用領域を切り出すのが面倒(縮小は可能だが移動は不可)。
3. インストール完了後、Windows を一度起動して **OOBE 完了** と **Windows Update** を済ませ、**高速スタートアップを無効化**(2.3)。

### 3.2 Linux のインストール

1. Linux のインストール USB から起動。
2. インストーラのパーティション設定で:
   - 既存の ESP は **再フォーマットせず**、`/boot/efi` としてマウント(マウントポイント指定のみ)。
   - 未割り当て領域に Linux 用パーティションを作成(表の #5–7)。
3. ブートローダのインストール先は **ディスク全体(例: `/dev/nvme0n1`)** を選択。GRUB が ESP 上の `\EFI\<distro>\grubx64.efi` に配置され、UEFI に登録される。
4. インストール完了後、再起動。GRUB のメニューが表示され、Linux と `Windows Boot Manager` の両方が並ぶことを確認。

> Linux インストーラで GRUB が Windows を見つけてくれない場合は、インストール後に以下を実行:
>
> ```bash
> sudo apt install os-prober            # Debian/Ubuntu の場合
> sudo sed -i 's/^#\?GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
> sudo update-grub
> ```

---

## 4. インストール後の確認

```bash
# UEFI のブートエントリ一覧を見る
sudo efibootmgr -v

# 例:
# BootOrder: 0001,0000,2001,2002
# Boot0000* Windows Boot Manager  HD(...)/File(\EFI\Microsoft\Boot\bootmgfw.efi)
# Boot0001* ubuntu                HD(...)/File(\EFI\ubuntu\shimx64.efi)
```

`BootOrder` の **先頭** に GRUB(上の例では `0001` = `ubuntu`)が来ていれば、起動時に GRUB が表示されます。Windows Boot Manager が先頭になっている場合、本リポジトリの `scripts/linux/set-grub-first.sh` で並び替えてください。詳細な仕組みと比較は `docs/02-grub-priority.md` を参照。

---

## 5. レガシー BIOS / MBR の場合(参考)

- パーティションテーブルは MBR、ESP は不要。
- Windows → Linux の順は同じ。GRUB は MBR(ディスク先頭)にインストールされ、ここから両 OS をチェインロードします。
- `efibootmgr` は使えません。GRUB を優先させたい場合は単純に Linux 側 GRUB を MBR に再インストールします:
  ```bash
  sudo grub-install /dev/sda
  sudo update-grub
  ```
- Windows Update がブートセクタを書き換えてしまった場合は、`scripts/linux/repair-grub.sh` の MBR 用ブロックを参照してください。

---

## 6. 次のステップ

- GRUB を確実に最優先にする → [`02-grub-priority.md`](./02-grub-priority.md)
- 起動しない / GRUB が出ない → [`03-troubleshooting.md`](./03-troubleshooting.md)

# 03. トラブルシューティング

デュアルブート構築後に出やすい症状と対処をまとめます。

---

## A. GRUB のメニューが表示されず、いきなり Windows が起動する

### 原因の切り分け

1. UEFI のブート順が `Windows Boot Manager` 先頭になっている (最も多い)
2. Windows の **高速スタートアップ** が有効で、UEFI のブート順設定を無視して前回値に戻している
3. 一部 OEM ファームウェアが起動毎に Windows Boot Manager を強制で先頭に戻している

### 対処

```bash
# 1. ブート順を確認
sudo bash scripts/linux/show-boot-order.sh

# 2. GRUB を先頭に
sudo bash scripts/linux/set-grub-first.sh

# 3. Windows の高速スタートアップを無効化(Windows 側で1回だけ)
#    管理者コマンドプロンプトで:
#       powercfg /h off
```

それでも戻ってしまう場合は `docs/02-grub-priority.md` の **方法 C** を検討。

---

## B. Windows Update 後に GRUB が消えた / 起動しなくなった

Windows のメジャーアップデートが ESP の構造や `BootOrder` を書き換えてしまうケース。

### 対処

Linux ライブ USB から起動して chroot し、GRUB を再インストールします。本リポジトリの `repair-grub.sh` を使う場合:

```bash
# 1. ライブ USB から起動

# 2. 自分のディスク・パーティションを確認
lsblk -f
# 例:
#   nvme0n1
#     ├─nvme0n1p1  vfat        ESP(/boot/efi)
#     ├─nvme0n1p2                MSR
#     ├─nvme0n1p3  ntfs         Windows
#     └─nvme0n1p5  ext4         Linux /

# 3. 修復スクリプトを ROOT_PART, ESP_PART を指定して実行
sudo ROOT_PART=/dev/nvme0n1p5 ESP_PART=/dev/nvme0n1p1 \
     bash scripts/linux/repair-grub.sh

# 4. 再起動後、ブート順を再設定
sudo bash scripts/linux/set-grub-first.sh
```

スクリプトは内部で `mount → bind /dev /proc /sys /sys/firmware/efi/efivars → chroot → grub-install → update-grub` を順に行います。

---

## C. GRUB メニューに Windows が出てこない

```bash
# os-prober をインストール(なければ)
sudo apt install os-prober          # Debian/Ubuntu
sudo dnf install os-prober          # Fedora
sudo pacman -S os-prober            # Arch

# os-prober を有効化
sudo sed -i 's/^#\?GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub

# GRUB 設定再生成
sudo update-grub                    # Debian/Ubuntu
# または
sudo grub-mkconfig -o /boot/grub/grub.cfg
```

それでも出ない場合は、Windows が **高速スタートアップ有効のままシャットダウン** され NTFS が hibernate 状態になっている可能性があります。Windows を一度起動して **完全シャットダウン** (Shift + シャットダウン) してから再度 `update-grub` を実行してください。

---

## D. `efibootmgr` が `Could not set BootOrder: ...` で失敗する

### よくある原因

- ライブ USB を **BIOS/Legacy モード** で起動している → UEFI モードで起動し直す
- `/sys/firmware/efi/efivars` が **read-only** でマウントされている
  ```bash
  sudo mount -o remount,rw /sys/firmware/efi/efivars
  ```
- ファームウェアが NVRAM 書込みをサポートしていない / 不安定

ライブ USB で作業する場合、`bash scripts/linux/repair-grub.sh` 内では `efivarfs` を bind mount しているので失敗しにくくなっています。

---

## E. BitLocker で回復キーを聞かれた

ブートローダ差し替えや UEFI 設定変更で、BitLocker が「ブート構成が変わった」と検知して回復キーを要求します。

- **作業前に** Microsoft アカウントの [https://aka.ms/myrecoverykey](https://aka.ms/myrecoverykey) または企業のキー保管庫から回復キーを控える。
- 入力後、Windows 上で:
  ```bat
  manage-bde -protectors -disable C:
  ```
  で BitLocker を一時停止してから作業すると、その後ブート時の回復キー要求は出ません(再有効化を忘れずに)。

---

## F. Secure Boot 有効環境で GRUB が起動しない

- Ubuntu / Fedora / openSUSE などは署名済の `shimx64.efi` を経由するため Secure Boot 有効でも起動できます。
- Arch / 自前ビルドの GRUB の場合は、`shim` + 自分の鍵を MOK (Machine Owner Key) に登録するか、Secure Boot を無効化する必要があります。

```bash
sudo mokutil --sb-state    # 現在の状態確認
```

---

## さらに困ったとき

- `sudo efibootmgr -v` の **完全な出力**
- `lsblk -f` の出力
- 使っている distro と GRUB のバージョン (`grub-install --version`)

これらをメモしておくと、フォーラムで質問するときも、次回の自分が同じ作業をするときも非常に役立ちます。

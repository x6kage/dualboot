# 05. Windows Boot Manager の FAQ — 「消したら Windows は起動できなくなる?」

結論から言うと、**「Windows Boot Manager」と呼ばれているもの自体が 2 つある** ので、何を消したかで挙動が変わります。

---

## 0. そもそも何があるか

UEFI 環境の Windows ブート構造はおおまかに 4 階層です。

```
[1] UEFI ファームウェア NVRAM
      ├─ BootOrder = 0001,0000,2001,...
      └─ Boot0000  = "Windows Boot Manager" → \EFI\Microsoft\Boot\bootmgfw.efi に飛べ
[2] ESP (FAT32, /dev/nvme0n1p1 等)
      └─ \EFI\Microsoft\Boot\bootmgfw.efi      ← 実体ファイル(EFI アプリ)
                          \BCD                 ← Windows の起動設定データベース
[3] BCD が指す Winload
      └─ C:\Windows\system32\winload.efi
[4] Windows カーネル (ntoskrnl.exe) → ユーザランド
```

「Windows Boot Manager を消す」と言ったとき、人が指しているのは普通 **[1] か [2]** のどちらかです。

---

## 1. ケース別:何が起きる / どう直す

### A. UEFI のブートエントリ (`Boot0000` 等) だけを消した

```bash
sudo efibootmgr -b 0000 -B        # ← これをやった状態
```

**起こること**:

- ファームウェアの起動メニューから **Windows Boot Manager の選択肢が消える**。
- `BootOrder` の先頭にあったとしても、エントリ自体が無いので飛べない。
- ただし、**ESP 上の `bootmgfw.efi` ファイルは無傷** なので、GRUB の chainload からは起動できる:
  ```
  menuentry "Windows" {
      insmod chain
      search --no-floppy --fs-uuid --set=root <ESP の UUID>
      chainloader /EFI/Microsoft/Boot/bootmgfw.efi
  }
  ```
- ファームウェアの「Boot Override」「Boot Menu」(F11/F12 等)からも、機種により `bootmgfw.efi` を直接ピックアップできる場合がある。

**直し方**(再登録):

```bash
# /dev/sdX, -p N は ESP のディスク・パーティション番号に置き換え
sudo efibootmgr --create \
    --disk /dev/nvme0n1 --part 1 \
    --label "Windows Boot Manager" \
    --loader '\EFI\Microsoft\Boot\bootmgfw.efi'
```

または Windows のインストール USB の修復オプションから自動修復でも復活します。

> **要するに**: NVRAM のエントリだけ消しても **Windows は壊れていない**。GRUB から起動できるし、上のコマンド一発で復活する。

### B. ESP 上の `bootmgfw.efi` ファイルを消した / 上書きした

これは深刻です。

**起こること**:

- 上の [2] の実体が無いので、UEFI も GRUB の chainload も Windows を起動できない。
- C: の Windows 自体は無傷だが、起動経路が断絶している。

**直し方**:

1. **Windows インストール USB から起動** → 修復オプション → コマンドプロンプト
2. ESP に文字を割り当ててブートファイルを再生成:
   ```bat
   diskpart
   DISKPART> list disk
   DISKPART> select disk 0
   DISKPART> list partition
   DISKPART> select partition 1            :: ESP
   DISKPART> assign letter=S
   DISKPART> exit
   bcdboot C:\Windows /s S: /f UEFI /l ja-JP
   ```
   `bcdboot` が `\EFI\Microsoft\Boot\bootmgfw.efi` と BCD を作り直してくれる。

> **要するに**: ESP 上のファイルを消してしまうと、**Windows のインストールメディアが必要**。事前準備の意味でも 1 本作っておくのを推奨。

### C. C: の Windows そのものを消した

復旧不可。クリーンインストール必須。

---

## 2. では「優先度を下げる」のと「消す」の違いは?

| 操作 | コマンド例 | 効果 |
| --- | --- | --- |
| **優先度を下げる**(推奨) | `efibootmgr -o 0001,0000` | Windows Boot Manager は残るが、`BootOrder` の先頭は GRUB(0001)。Windows は GRUB から、または UEFI メニューから選べる |
| **無効化する**(中間) | `efibootmgr -A -b 0000` | `Boot0000` の Active フラグを落とす。`BootOrder` から無視されるが、エントリ自体は残る。`-a` で再有効化可 |
| **エントリを消す**(注意) | `efibootmgr -B -b 0000` | `Boot0000` の NVRAM 変数自体を削除。本記事 1.A の状態。直すには再登録 |
| **ファイルを消す**(危険) | `rm /boot/efi/EFI/Microsoft/Boot/bootmgfw.efi` | 1.B の状態。インストールメディア無しでは詰む |

**Windows を残しておきたいなら、必要なのはほぼ常に「優先度を下げる」だけ** です。`set-grub-first.sh` がやっていることがそれです。

---

## 3. 「Windows Boot Manager を消す = Windows ライセンスが消える」ではない

よくある誤解ですが、

- Windows のライセンス情報(プロダクトキー、デジタルライセンス、Office のライセンス)は **C: 内、または UEFI ファームウェアの ACPI MSDM テーブル、または Microsoft アカウント** に紐付いています。
- ブートマネージャを消したり差し替えたりしても、これらは **一切影響を受けません**。
- 起動さえ復旧すれば、ライセンスはそのまま残ります。

ただし **C: パーティションそのものを潰すと当然消える** ので、デュアルブート構築中の **パーティション操作** が一番の事故ポイントです。

---

## 4. パターン別:どこまで触ってよいかの早見表

| やりたいこと | 触ってよい範囲 | 推奨スクリプト |
| --- | --- | --- |
| Linux をメインにしたい | `BootOrder` の並び替えだけ | `scripts/linux/set-grub-first.sh` |
| Windows をメインに戻したい | 同上 | `scripts/linux/set-windows-first.sh` |
| GRUB を完全に無くして Windows 単独に戻したい | GRUB のエントリだけ削除 + `bootmgfw.efi` を `Boot0000` に再登録 | `efibootmgr -b <GRUB id> -B` + `bcdboot C:\Windows /s S: /f UEFI` |
| Windows を完全に消して Linux 専用にしたい | 全パーティションを再構築 | この場合はクリーンインストールの方が早い |

---

## 5. 1 行まとめ

> **Windows Boot Manager の「UEFI エントリ」を消しても Windows は壊れない(GRUB から起動できる/再登録で復活)。「ESP 上のファイル」を消すと壊れる。「優先度を下げる」だけなら何も消さなくていい。**

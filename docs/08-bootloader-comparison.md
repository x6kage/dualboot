# 08. 2026 年時点の Linux ブートローダ比較 — GRUB2 以外の選択肢

「GRUB2 で実用上困っていないけど、もっとモダン/軽量なものはないのか?」という問いに対する、2026 年時点での比較と推奨です。

## 1 行答え

> **シンプル/モダン/軽量が欲しいなら `systemd-boot` (UEFI 環境)、究極の最小は `EFISTUB + UKI`、新興本命は `Limine`。ただし Debian/Kali を素のまま運用 + Windows デュアルブート(自動検出)なら GRUB2 が今でも最楽。**

---

## 比較表

| ブートローダ | 立ち位置 | 強み | 弱み | 向いてる人 |
|---|---|---|---|---|
| **GRUB2** | 各 distro の既定。鉄板 | 機能豊富、BIOS/UEFI 両対応、`os-prober` の Windows 自動検出が他を圧倒、Secure Boot シム成熟 | 設定が複雑(`grub.cfg` は機械生成必須)、コードベース巨大、起動が重い | 大半のユーザ、デュアルブート、Kali を素のまま使う人 |
| **systemd-boot** (旧 gummiboot, `sd-boot`) | Arch (archinstall 既定)、Pop!_OS、Fedora Silverblue 系、openSUSE MicroOS で標準採用が拡大 | 極めて軽量、設定はプレーンテキスト 4-5 行、UKI ネイティブ、`bootctl` で管理、起動が速い | UEFI 専用 (BIOS 不可)、複雑な分岐は無理、Windows 自動検出は手動で `windows.conf` 1 枚書く必要 | UEFI 機 + シンプル志向、suckless 美学を bootloader にも |
| **EFISTUB + UKI** (Unified Kernel Image) | Fedora が UKI を本気で推進中、Arch ユーザ層に広がる | そもそもブートローダを持たない。kernel + initramfs + cmdline + microcode を 1 つの署名済 PE/EFI に固める | 複数カーネル切り替えに `efibootmgr` 操作、Secure Boot 署名運用が必要、Windows との chainload は別途必要 | 最小主義の極致、ホームラボ、Secure Boot を真面目にやる人 |
| **Limine** | 2020 年代の新興 | C で書かれモダン、BIOS+UEFI 両対応、設定は INI 風、コードが読める量、活発開発 | 採用 distro が少なく自前管理になりがち、知見が GRUB ほど蓄積していない | 新しい物好き、自前で全部組みたい人 |
| **rEFInd** | UEFI 環境のグラフィカル選択画面、Mac/Hackintosh、多 OS 環境 | 自動検出が極めて強力(Windows・macOS・各 Linux を勝手に並べる)、見た目綺麗、GRUB の上に乗せても可 | ディストリ標準ではない、設定の中身は意外と複雑 | 多 OS マシン、Mac、見た目重視 |
| **Clover / OpenCore** | Hackintosh 専用 | macOS 起動 | 一般 Linux には不要 | Hackintosh 民 |
| **Syslinux / extlinux / isolinux** | ライブ USB / 組込み中心 | 軽量、超シンプル | 常用 Linux のブートには非力 | ライブ USB 作成 |
| **U-Boot** | ARM/組込み | 組込みのデファクト | x86 の常用ではない | RasPi / 組込み |
| **LILO / ELILO** | **終了**(2015 年に開発停止) | — | — | 過去の遺物 |

---

## ケース別の推奨

### ケース A: Kali / Debian 系 + Windows デュアルブート(本リポジトリの想定)
**→ GRUB2 一択。** Kali の installer・`update-initramfs`・`os-prober`・shim による Secure Boot サポートが全部 GRUB 前提で固まっています。`bootctl` で sd-boot に乗り換えはできますが、Kali の `linux-image-*` パッケージ更新と噛み合わせの面倒を抱えるので得るものが少ない。
本リポジトリの `set-grub-first.sh` / `remove-windows-boot-entry.sh` 等もそのまま使えます。

### ケース B: Arch 系・Fedora・自前メンテで最小環境にしたい(dwm 機など)
**→ systemd-boot が今のモダン解。** 設定はこれだけ:

```ini
# /boot/loader/loader.conf
default arch.conf
timeout 3

# /boot/loader/entries/arch.conf
title   Arch Linux
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options root=UUID=xxxx rw

# /boot/loader/entries/windows.conf   ← 手動で書く(Windows デュアルブート時)
title   Windows
efi     /EFI/Microsoft/Boot/bootmgfw.efi
```

GRUB の `grub.cfg`(数百行の生成物)と比べて圧倒的に把握しやすい。Windows のチェーンロードもこの 3 行で終わり。

導入(Arch の例):

```bash
sudo bootctl install
# kernel-install / mkinitcpio が自動でエントリ更新を担う構成にする
```

### ケース C: Secure Boot を本気でやりつつ最小構成
**→ EFISTUB + UKI(Unified Kernel Image)。**
kernel + initramfs + cmdline を 1 つの `.efi` にまとめて自分の鍵で署名し、`efibootmgr` で UEFI に登録。中間層がゼロです。

- Fedora: `dracut --uefi --kver $(uname -r) -f`
- Arch: `mkinitcpio` の `default.preset` で `default_uki` を有効化
- 署名: `sbsign --key MOK.key --cert MOK.crt --output signed.efi unsigned.efi`

複数 OS / 複数カーネルが必要なら sd-boot を上に被せる構成が無難(sd-boot は UKI を `/efi/EFI/Linux/*.efi` から自動検出する)。

### ケース D: GRUB の重さ・複雑さが嫌、新しい物好き、BIOS 環境もある
**→ Limine。** 2026 年時点でも「sd-boot より柔軟、GRUB より軽量」の中間枠として元気。BIOS 環境にも対応するのが sd-boot にない強み。Arch のユーザリポジトリに `limine` パッケージあり、`limine bios-install` / EFI 用は ESP に `BOOTX64.EFI` を配置。

設定例(`/boot/limine.conf`):

```ini
TIMEOUT=3

:Linux
    PROTOCOL=linux
    KERNEL_PATH=boot():/vmlinuz-linux
    MODULE_PATH=boot():/initramfs-linux.img
    KERNEL_CMDLINE=root=UUID=xxxx rw

:Windows
    PROTOCOL=efi_chainload
    IMAGE_PATH=boot():/EFI/Microsoft/Boot/bootmgfw.efi
```

### ケース E: 多 OS で見た目も欲しい / Mac 環境
**→ rEFInd。** インストール後ほぼノー設定で Windows・macOS・複数の Linux を全部並べてくれる。

```bash
sudo apt install refind
sudo refind-install
```

---

## GRUB を捨てる前に必ずチェックすべき点

1. **distro のパッケージ連携**:カーネル更新時にブートローダの設定を **誰が** 更新するか。GRUB は `update-grub` フックが各 distro に組み込まれている。sd-boot は systemd の `kernel-install` が肩代わりするが、Debian/Kali だと `kernel-install` の hook を別途仕込む必要あり。
2. **Secure Boot**:GRUB は signed shim の経路が確立済。sd-boot も Fedora/Arch では shim 経由可能。Debian/Kali の公式 shim は GRUB しか想定していないので、sd-boot に変えると **自前 MOK (Machine Owner Key)** での運用になる。
3. **Windows 自動検出**:GRUB の `os-prober` レベルの全自動はない。sd-boot/Limine では Windows エントリを 3 行書くだけだが、書く必要はある。本リポジトリの `docs/07-remove-windows-boot-entry.md` の chainload エントリも distro 横断ではない。
4. **BIOS 環境**:sd-boot は使えない。BIOS が混じるなら GRUB か Limine か syslinux。
5. **回復手段**:GRUB は壊れても `sudo grub-install` 一発で大体直る。sd-boot は `bootctl install` で再配置できるが、手で `loader/entries/*.conf` を書き直す必要があるケースがある。事前に内容をバックアップしておく。

---

## 1 行まとめ(再掲)

> **「とりあえず動く最善」は GRUB2、「設定が手で読める」は systemd-boot、「中間層ゼロ」は EFISTUB + UKI、「BIOS も含めて新しいの」は Limine、「多 OS で綺麗」は rEFInd。Debian/Kali + Windows のデュアルブートなら GRUB2 を据え置くのが最も摩擦少。**

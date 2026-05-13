@echo off
rem ============================================================
rem  show-boot-order.bat
rem
rem  Windows から、現在の UEFI ブート順 (BootOrder) を表示します。
rem  内部的には bcdedit /enum {fwbootmgr} を使います。
rem
rem  使い方: 管理者権限のコマンドプロンプトで実行
rem      scripts\windows\show-boot-order.bat
rem ============================================================

setlocal

rem 管理者権限チェック
net session >nul 2>&1
if errorlevel 1 (
    echo [error] このスクリプトは管理者権限のコマンドプロンプトで実行してください。
    exit /b 1
)

rem UEFI / BIOS 判定: bcdedit /enum {fwbootmgr} は UEFI でのみ動作する。
bcdedit /enum "{fwbootmgr}" >nul 2>&1
if errorlevel 1 (
    echo [error] このシステムは UEFI モードで起動していません(BIOS/Legacy)。
    echo         本スクリプトは UEFI 環境専用です。
    exit /b 1
)

echo === Firmware Boot Manager (UEFI) ===
bcdedit /enum "{fwbootmgr}"
echo.
echo === All Firmware Entries ===
bcdedit /enum firmware

echo.
echo [info] displayorder の左側ほど優先度が高いです。
echo        GRUB を最優先にしたい場合は scripts\windows\set-grub-first.bat を実行してください。

endlocal

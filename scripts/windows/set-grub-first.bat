@echo off
rem ============================================================
rem  set-grub-first.bat
rem
rem  Windows 上から、UEFI のファームウェアブート順 (BootOrder) の
rem  先頭に GRUB のエントリを配置します。Windows Boot Manager は
rem  先頭から押し出されますが、エントリ自体は残ります。
rem
rem  内部では PowerShell に処理を委譲し、bcdedit /enum firmware の
rem  出力から "ubuntu / debian / arch / fedora / manjaro / opensuse /
rem  grub / linux" 等を含むエントリを GRUB と判定し、
rem  bcdedit /set {fwbootmgr} displayorder <GUID> /addfirst
rem  を実行します。
rem
rem  使い方:
rem      管理者権限のコマンドプロンプトで:
rem          scripts\windows\set-grub-first.bat            … 自動検出して適用
rem          scripts\windows\set-grub-first.bat --dry-run  … 変更せず確認
rem          scripts\windows\set-grub-first.bat --guid {xxxxxxxx-...-............}
rem ============================================================

setlocal

net session >nul 2>&1
if errorlevel 1 (
    echo [error] このスクリプトは管理者権限のコマンドプロンプトで実行してください。
    exit /b 1
)

bcdedit /enum "{fwbootmgr}" >nul 2>&1
if errorlevel 1 (
    echo [error] このシステムは UEFI モードで起動していません。
    exit /b 1
)

set "PSARGS="
:parse
if "%~1"=="" goto run
if /I "%~1"=="--dry-run" (
    set "PSARGS=%PSARGS% -DryRun"
    shift
    goto parse
)
if /I "%~1"=="--guid" (
    set "PSARGS=%PSARGS% -Guid '%~2'"
    shift
    shift
    goto parse
)
echo [error] 不明な引数: %~1
exit /b 2

:run
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0set-grub-first.ps1" %PSARGS%
exit /b %errorlevel%

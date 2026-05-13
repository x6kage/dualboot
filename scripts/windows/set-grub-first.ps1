<#
.SYNOPSIS
    UEFI のブート順 (BootOrder) の先頭に GRUB のエントリを配置します。

.DESCRIPTION
    bcdedit /enum firmware の出力から、Linux ディストリビューションを示す
    description (ubuntu / debian / arch / fedora / manjaro / opensuse / grub /
    linux 等) を持つファームウェアエントリを GRUB と判定し、

        bcdedit /set "{fwbootmgr}" displayorder "<GUID>" /addfirst

    を実行します。

.PARAMETER DryRun
    検出だけ行い、bcdedit による変更は適用しません。

.PARAMETER Guid
    自動検出を行わず、指定の GUID を先頭に追加します。

.NOTES
    管理者権限の PowerShell / コマンドプロンプトから実行してください。
#>

[CmdletBinding()]
param(
    [switch]$DryRun,
    [string]$Guid
)

$ErrorActionPreference = 'Stop'

function Test-Admin {
    $current = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($current)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
    Write-Error "管理者権限で実行してください。"
    exit 1
}

# UEFI 判定
$null = & bcdedit /enum "{fwbootmgr}" 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Error "このシステムは UEFI モードで起動していません(BIOS/Legacy)。"
    exit 1
}

function Get-FirmwareEntries {
    $raw = & bcdedit /enum firmware
    $entries = @()
    $current = $null
    foreach ($line in $raw) {
        if ($line -match '^\s*$') {
            if ($current) { $entries += [pscustomobject]$current; $current = $null }
            continue
        }
        if ($line -match '^[A-Z].*\(\w+\)\s*$' -or $line -match '^-{3,}') {
            if ($current) { $entries += [pscustomobject]$current; $current = $null }
            $current = @{ Header = $line.Trim(); Identifier = $null; Description = $null; Path = $null }
            continue
        }
        if (-not $current) { $current = @{ Header = ''; Identifier = $null; Description = $null; Path = $null } }
        if ($line -match '^\s*identifier\s+(\{[0-9a-fA-F\-]+\})') {
            $current.Identifier = $matches[1]
        } elseif ($line -match '^\s*description\s+(.+?)\s*$') {
            $current.Description = $matches[1]
        } elseif ($line -match '^\s*path\s+(.+?)\s*$') {
            $current.Path = $matches[1]
        }
    }
    if ($current) { $entries += [pscustomobject]$current }
    return $entries | Where-Object { $_.Identifier }
}

function Find-GrubGuid {
    param([object[]]$Entries)
    $pattern = 'ubuntu|debian|arch|fedora|manjaro|opensuse|suse|endeavour|pop|kali|mint|nixos|grub|elementary|zorin|garuda|linux'
    $exclude = 'windows boot manager|microsoft'
    $candidates = $Entries | Where-Object {
        $_.Description -and
        ($_.Description -imatch $pattern) -and
        (-not ($_.Description -imatch $exclude))
    }
    if (-not $candidates) {
        # description ではなく path 側に grubx64.efi / shimx64.efi があるパターン
        $candidates = $Entries | Where-Object {
            $_.Path -and ($_.Path -imatch 'grubx64\.efi|shimx64\.efi|grub\.efi')
        }
    }
    return $candidates | Select-Object -First 1
}

function Get-CurrentDisplayOrder {
    $raw = & bcdedit /enum "{fwbootmgr}"
    foreach ($line in $raw) {
        if ($line -match '^\s*displayorder\s+(\{[0-9a-fA-F\-]+\})') {
            $first = $matches[1]
            $rest = $raw | Where-Object { $_ -match '^\s+(\{[0-9a-fA-F\-]+\})\s*$' } | ForEach-Object {
                ($_ -split '\s+' | Where-Object { $_ -match '^\{' })[0]
            }
            return ,@($first) + $rest
        }
    }
    return @()
}

$entries = Get-FirmwareEntries

if ($Guid) {
    $target = $entries | Where-Object { $_.Identifier -ieq $Guid } | Select-Object -First 1
    if (-not $target) {
        Write-Error "指定された GUID $Guid が UEFI ブートエントリに見つかりません。"
        exit 1
    }
} else {
    $target = Find-GrubGuid -Entries $entries
    if (-not $target) {
        Write-Host "[error] GRUB のファームウェアエントリを自動検出できませんでした。" -ForegroundColor Red
        Write-Host "        現在のエントリ一覧(description / path):"
        $entries | Format-Table Identifier, Description, Path -AutoSize | Out-Host
        Write-Host "        該当する GUID を確認の上、--guid {xxxxxxxx-...} を指定して再実行してください。"
        exit 1
    }
}

Write-Host "[info] GRUB と判定したエントリ:"
Write-Host ("       identifier  : {0}" -f $target.Identifier)
Write-Host ("       description : {0}" -f $target.Description)
if ($target.Path) {
    Write-Host ("       path        : {0}" -f $target.Path)
}

$currentOrder = Get-CurrentDisplayOrder
if ($currentOrder.Count -gt 0) {
    Write-Host "[info] 旧 displayorder:"
    $i = 1
    foreach ($g in $currentOrder) {
        $desc = ($entries | Where-Object { $_.Identifier -ieq $g } | Select-Object -First 1).Description
        Write-Host ("        {0}. {1}  {2}" -f $i, $g, $desc)
        $i++
    }
}

if ($DryRun) {
    Write-Host "[dry-run] --dry-run が指定されたので変更は適用しません。" -ForegroundColor Yellow
    exit 0
}

& bcdedit /set "{fwbootmgr}" displayorder $target.Identifier /addfirst | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Error "bcdedit /set ... /addfirst に失敗しました(終了コード: $LASTEXITCODE)。"
    exit $LASTEXITCODE
}

Write-Host "[ok] displayorder の先頭に GRUB を追加しました。" -ForegroundColor Green
Write-Host "[info] 新しい displayorder:"
& bcdedit /enum "{fwbootmgr}" | Where-Object { $_ -match 'displayorder|^\s+\{' } | ForEach-Object { "        $_" }

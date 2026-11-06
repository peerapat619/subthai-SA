<#
    GTA San Andreas (Classic) - Thai subtitle uninstaller
    ---------------------------------------------------
    Replays thai_backup_<stamp>\restore.json written by INSTALL.ps1:

        files that existed before are copied back
        files the installer added are deleted

    Usage:
        .\UNINSTALL.ps1                              newest backup in the game folder
        .\UNINSTALL.ps1 -Backup "..\thai_backup_20261030_120000"
        .\UNINSTALL.ps1 -GamePath "D:\Games\GTA San Andreas"
#>

param(
    [string]$GamePath = '',
    [string]$Backup = ''
)

$ErrorActionPreference = 'Stop'

function Write-Head($text) { Write-Host ''; Write-Host $text -ForegroundColor Cyan }
function Write-Ok($text)   { Write-Host "  [ok]   $text" -ForegroundColor Green }
function Write-Warn2($text){ Write-Host "  [warn] $text" -ForegroundColor Yellow }

# Accepts a folder, a path to gta-sa.exe, a quoted path, or nothing at all.
function Resolve-GamePath {
    param([string]$Path)
    if (-not $Path) { return $null }
    $Path = $Path.Trim().Trim('"').Trim("'").Trim()
    if (-not $Path) { return $null }
    if (Test-Path -LiteralPath $Path -PathType Leaf) { $Path = Split-Path -Parent $Path }
    if (Test-Path -LiteralPath (Join-Path $Path 'gta-sa.exe')) {
        return (Resolve-Path -LiteralPath $Path).Path
    }
    return $null
}

function Find-Game {
    param([string]$Given)

    $hit = Resolve-GamePath $Given
    if ($hit) { return $hit }

    $candidates = New-Object System.Collections.Generic.List[string]
    $candidates.Add((Get-Location).Path)
    $candidates.Add((Split-Path -Parent $PSScriptRoot))
    $candidates.Add((Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))

    $steamRoots = New-Object System.Collections.Generic.List[string]
    foreach ($key in @('HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'HKLM:\SOFTWARE\Valve\Steam')) {
        try {
            $steam = (Get-ItemProperty -Path $key -ErrorAction Stop).SteamPath
            if ($steam) { $steamRoots.Add(($steam -replace '/', '\')) }
        } catch { }
    }
    foreach ($sr in $steamRoots) {
        $candidates.Add((Join-Path $sr 'steamapps\common\Grand Theft Auto San Andreas'))
        $vdf = Join-Path $sr 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf) {
            foreach ($m in (Select-String -LiteralPath $vdf -Pattern '"path"\s+"([^"]+)"' -AllMatches).Matches) {
                $lib = $m.Groups[1].Value -replace '\\\\', '\'
                $candidates.Add((Join-Path $lib 'steamapps\common\Grand Theft Auto San Andreas'))
            }
        }
    }

    foreach ($key in @('HKLM:\SOFTWARE\WOW6432Node\Rockstar Games\GTA San Andreas',
                       'HKLM:\SOFTWARE\Rockstar Games\GTA San Andreas',
                       'HKCU:\Software\Rockstar Games\GTA San Andreas')) {
        try {
            $props = Get-ItemProperty -Path $key -ErrorAction Stop
            foreach ($name in @('InstallFolder', 'InstallDir', 'InstallLocation', 'Path')) {
                if ($props.$name) { $candidates.Add($props.$name) }
            }
        } catch { }
    }

    foreach ($c in $candidates) {
        $hit = Resolve-GamePath $c
        if ($hit) { return $hit }
    }

    # last resort: a backup folder is a strong hint, so look for it directly
    foreach ($drive in (Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
        if ($drive.Root -notmatch '^[A-Za-z]:\\$') { continue }
        foreach ($dir in (Get-ChildItem -LiteralPath $drive.Root -Directory -ErrorAction SilentlyContinue)) {
            if ($dir.Name -notmatch '(?i)gta|san.?andreas|rockstar|game') { continue }
            foreach ($sub in @($dir) + @(Get-ChildItem -LiteralPath $dir.FullName -Directory -ErrorAction SilentlyContinue)) {
                $hit = Resolve-GamePath $sub.FullName
                if ($hit) { return $hit }
            }
        }
    }
    return $null
}

Write-Head 'GTASA Thai subtitles - uninstaller'
$game = Find-Game -Given $GamePath
if (-not $game) {
    $typed = Read-Host 'Paste the full path of your GTA San Andreas folder (or of gta-sa.exe)'
    if ($typed) { $game = Find-Game -Given $typed }
}
if (-not $game) { throw 'Could not find gta-sa.exe.' }
Write-Ok "game folder: $game"

if (-not $Backup) {
    $found = Get-ChildItem -Path $game -Directory -Filter 'thai_backup_*' -ErrorAction SilentlyContinue |
        Where-Object { Test-Path (Join-Path $_.FullName 'restore.json') } |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $found) { throw "No thai_backup_* folder with restore.json in $game." }
    $Backup = $found.FullName
}
Write-Ok "backup: $Backup"

if (Get-Process -Name 'gta-sa' -ErrorAction SilentlyContinue) {
    throw 'GTA San Andreas is running. Close the game and run the uninstaller again.'
}

$restoreFile = Join-Path $Backup 'restore.json'
if (-not (Test-Path $restoreFile)) { throw "$restoreFile is missing." }

# Windows PowerShell 5.1 hands back a JSON array as one object, PowerShell 7 as
# many - accept both shapes.
$parsed = Get-Content $restoreFile -Raw -Encoding UTF8 | ConvertFrom-Json
if ($parsed -is [System.Array]) { $items = $parsed } else { $items = @($parsed) }
if ($items.Count -eq 0) { throw "$restoreFile lists no files." }

$restored = 0
$removed = 0
foreach ($item in $items) {
    $target = Join-Path $game $item.path
    if ($item.existed) {
        $copy = Join-Path $Backup $item.path
        if (Test-Path -LiteralPath $copy) {
            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
            Copy-Item -LiteralPath $copy -Destination $target -Force
            $restored++
        } else {
            Write-Warn2 "no copy of $($item.path) in the backup"
        }
    } elseif (Test-Path -LiteralPath $target) {
        Remove-Item -LiteralPath $target -Force
        $removed++
    }
}

Write-Head 'Done'
Write-Host "  restored: $restored file(s)"
Write-Host "  removed : $removed file(s) the installer added"
Write-Host '  The game is back to its original text.'
Write-Host ''
Write-Host "  The backup folder was left in place: $Backup"
Write-Host '  Delete it yourself once the game runs in English again.'
Write-Host ''

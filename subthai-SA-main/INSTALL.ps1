<#
    GTA San Andreas (Classic) - Thai subtitle installer
    --------------------------------------------------
    Copies the Thai localisation payload into a GTA San Andreas install:

        vorbisFile.dll            Ultimate ASI Loader (the stock file is backed up)
        scripts\GTASA.WidescreenFix.asi/.ini
                                  width/aspect fix (bundled in v1.0.2)
        EasyGXT.SA.asi            swaps GXT strings, switches the text buffer to UTF-8
                                  (patched in v1.0.1: no "<key> missing" fallback)
        EasyFont.SA.asi           draws text with a real TrueType font
        charlesvercetti_mods\...  plugin configuration, fonts and the 16,615-row gxt.csv

    Every file that already exists is copied to thai_backup_<stamp>\ first, together
    with restore.json, which UNINSTALL.ps1 replays to put the install back exactly.

    Usage:
        .\INSTALL.ps1                       detect the game, install
        .\INSTALL.ps1 -GamePath "D:\Games\GTA San Andreas"
        .\INSTALL.ps1 -DryRun               report only, touch nothing
        .\INSTALL.ps1 -Force                install even on a Steam (NewSteam) exe
#>

param(
    [string]$GamePath = '',
    [switch]$Force,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$stamp   = Get-Date -Format 'yyyyMMdd_HHmmss'
$root    = $PSScriptRoot
$payload = Join-Path $root 'payload'
$manifestPath = Join-Path $root 'manifest.json'

$STEAM_EXE_SIZE = 5971456   # NewSteam 2014 build: EasyFont/EasyGXT crash it
$EXPECTED_ROWS  = 16615

function Write-Head($text) { Write-Host ''; Write-Host $text -ForegroundColor Cyan }
function Write-Ok($text)   { Write-Host "  [ok]   $text" -ForegroundColor Green }
function Write-Warn2($text){ Write-Host "  [warn] $text" -ForegroundColor Yellow }
function Write-Err2($text) { Write-Host "  [FAIL] $text" -ForegroundColor Red }

# ------------------------------------------------------------------ prerequisites
if (-not (Test-Path $payload))      { throw "The 'payload' folder is missing next to INSTALL.ps1 - extract the whole zip first." }
if (-not (Test-Path $manifestPath)) { throw "payload\manifest.json is missing - the zip is incomplete." }
$manifest = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json

# ------------------------------------------------------------------ find the game
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
    $candidates.Add((Split-Path -Parent $root))
    $candidates.Add((Split-Path -Parent (Split-Path -Parent $root)))

    # Steam: the install path from the registry, then every extra library drive
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

    # retail / Rockstar social club installs
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

    # usual suspects
    foreach ($p in @("${env:ProgramFiles(x86)}\Rockstar Games\GTA San Andreas",
                     "$env:ProgramFiles\Rockstar Games\GTA San Andreas",
                     "$env:SystemDrive\Games\GTA San Andreas",
                     "$env:SystemDrive\GTA San Andreas",
                     "$env:SystemDrive\GTA_SA")) {
        $candidates.Add($p)
    }

    foreach ($c in $candidates) {
        $hit = Resolve-GamePath $c
        if ($hit) { return $hit }
    }

    # last resort: a shallow look at the top of every fixed drive
    foreach ($drive in (Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
        if ($drive.Root -notmatch '^[A-Za-z]:\\$') { continue }
        foreach ($dir in (Get-ChildItem -LiteralPath $drive.Root -Directory -ErrorAction SilentlyContinue)) {
            if ($dir.Name -notmatch '(?i)gta|san.?andreas|rockstar|game') { continue }
            $hit = Resolve-GamePath $dir.FullName
            if ($hit) { return $hit }
            foreach ($sub in (Get-ChildItem -LiteralPath $dir.FullName -Directory -ErrorAction SilentlyContinue)) {
                $hit = Resolve-GamePath $sub.FullName
                if ($hit) { return $hit }
            }
        }
    }
    return $null
}

Write-Head 'GTASA Thai subtitles - installer'
$game = Find-Game -Given $GamePath
if (-not $game) {
    Write-Warn2 'gta-sa.exe was not found automatically.'
    $typed = Read-Host 'Paste the full path of your GTA San Andreas folder (or of gta-sa.exe)'
    if ($typed) { $game = Find-Game -Given $typed }
}
if (-not $game) { throw 'Could not find gta-sa.exe. Run this with -GamePath "<folder with gta-sa.exe>".' }
Write-Ok "game folder: $game"

# ------------------------------------------------------------------ exe check
$exe = Join-Path $game 'gta-sa.exe'
$exeSize = (Get-Item $exe).Length
if ($exeSize -eq $STEAM_EXE_SIZE) {
    Write-Warn2 'This is the Steam (NewSteam 2014) gta-sa.exe.'
    Write-Warn2 'EasyFont and EasyGXT crash that build at startup.'
    Write-Warn2 'Downgrade gta-sa.exe to 1.0 US first (see README_TH.txt), or re-run with -Force.'
    if (-not $Force) { throw 'Aborted: the game executable is not 1.0 US.' }
} else {
    Write-Ok ("gta-sa.exe looks compatible ({0:N0} bytes)" -f $exeSize)
}

# ------------------------------------------------------------------ payload list
$files = @($manifest.files.PSObject.Properties)
if (-not $files.Count) { throw 'manifest.json lists no files.' }

Write-Head 'Checking the payload'
$bad = 0
foreach ($entry in $files) {
    $src = Join-Path $payload $entry.Name
    if (-not (Test-Path -LiteralPath $src)) { Write-Err2 "missing $($entry.Name)"; $bad++; continue }
    $hash = (Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash
    if ($hash -ne $entry.Value.sha256) { Write-Err2 "corrupt $($entry.Name) (hash mismatch)"; $bad++ }
}
if ($bad -gt 0) { throw "$bad payload file(s) are missing or corrupt. Extract the zip again." }
Write-Ok ("{0} files verified against manifest.json" -f $files.Count)

# ------------------------------------------------------------------ csv sanity
$csvName = 'charlesvercetti_mods\EasyGXT\gxt.csv'
$csvPath = Join-Path $payload $csvName
$bytes   = [System.IO.File]::ReadAllBytes($csvPath)
if ($bytes.Length -lt 2 -or $bytes[0] -ne 0xFF -or $bytes[1] -ne 0xFE) {
    throw 'gxt.csv is not UTF-16 LE with a BOM - EasyGXT would misread it.'
}
$text = [System.Text.Encoding]::Unicode.GetString($bytes)
if (-not $text.StartsWith('sep=')) { throw 'gxt.csv does not start with a sep= line.' }
$rows = ([regex]::Matches($text, "`r`n")).Count - 2   # sep= line + header row
if ($rows -lt $EXPECTED_ROWS) { throw "gxt.csv has $rows rows, expected at least $EXPECTED_ROWS." }
Write-Ok ("gxt.csv: UTF-16 LE, {0:N0} rows" -f $rows)

if ($DryRun) {
    Write-Head 'Dry run - nothing was written'
    foreach ($entry in $files) { Write-Host "  would copy $($entry.Name)" }
    return
}

# ------------------------------------------------------------------ preflight
if (Get-Process -Name 'gta-sa' -ErrorAction SilentlyContinue) {
    throw 'GTA San Andreas is running. Close the game and run the installer again.'
}
try {
    $probe = Join-Path $game ('.thai_write_probe_' + $stamp)
    [System.IO.File]::WriteAllText($probe, 'x')
    Remove-Item -LiteralPath $probe -Force
} catch {
    throw "Cannot write to $game. A retail copy under Program Files needs an administrator PowerShell (right-click > Run as administrator)."
}

# ------------------------------------------------------------------ backup + copy
$backup = Join-Path $game ("thai_backup_" + $stamp)
Write-Head "Backing up to $(Split-Path -Leaf $backup)"
New-Item -ItemType Directory -Path $backup -Force | Out-Null
$restore = @()

foreach ($entry in $files) {
    $rel = $entry.Name
    $target = Join-Path $game $rel
    $existed = Test-Path -LiteralPath $target
    $restore += [pscustomobject]@{ path = $rel; existed = [bool]$existed }
    if ($existed) {
        $copy = Join-Path $backup $rel
        New-Item -ItemType Directory -Path (Split-Path -Parent $copy) -Force | Out-Null
        Copy-Item -LiteralPath $target -Destination $copy -Force
    }
    $dir = Split-Path -Parent $target
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Copy-Item -LiteralPath (Join-Path $payload $rel) -Destination $target -Force
}
$restore | ConvertTo-Json -Depth 4 | Set-Content -Path (Join-Path $backup 'restore.json') -Encoding UTF8
Write-Ok ("{0} files placed, {1} of them had an old version" -f $files.Count, ($restore | Where-Object { $_.existed }).Count)

# ------------------------------------------------------------------ verify install
Write-Head 'Verifying the install'
$ok = $true
foreach ($plugin in @('EasyGXT.SA.asi', 'EasyFont.SA.asi', 'vorbisFile.dll')) {
    if (Test-Path -LiteralPath (Join-Path $game $plugin)) { Write-Ok $plugin }
    else { Write-Err2 "$plugin is not in the game folder"; $ok = $false }
}
$wsAsi = Join-Path $game 'scripts\GTASA.WidescreenFix.asi'
if (Test-Path -LiteralPath $wsAsi) { Write-Ok 'scripts\GTASA.WidescreenFix.asi (widescreen fix)' }
else { Write-Err2 'scripts\GTASA.WidescreenFix.asi is missing'; $ok = $false }
$mlIni = Join-Path $game 'modloader\modloader.ini'
$mlIgnore = ''
if (Test-Path -LiteralPath $mlIni) { $mlIgnore = Get-Content -LiteralPath $mlIni -Raw }
foreach ($dupe in @('modloader\WidescreenFix\GTASA.WidescreenFix.asi',
                    'GTASA.WidescreenFix.asi',
                    'GTASA.WidescreenFix.dll')) {
    if (Test-Path -LiteralPath (Join-Path $game $dupe)) {
        if ($dupe -like 'modloader\*' -and $mlIgnore -match '(?im)^\s*WidescreenFix\s*$') {
            Write-Ok "$dupe is installed but switched off in modloader.ini"
        } else {
            Write-Warn2 "another WidescreenFix copy is present ($dupe) - keep only one, or it loads twice."
        }
        break
    }
}
# v1.0.1 fix: the packaged plugin no longer carries the "%s missing" fallback
$gxtAsiPath = Join-Path $game 'EasyGXT.SA.asi'
$gxtAsiText = [System.Text.Encoding]::GetEncoding(28591).GetString(
    [System.IO.File]::ReadAllBytes($gxtAsiPath))
if ($gxtAsiText -like '*%s missing*') {
    Write-Warn2 'EasyGXT.SA.asi still prints "<key> missing" - reinstall with this package.'
} else {
    Write-Ok 'EasyGXT.SA.asi: "missing" fallback disabled (v1.0.1 fix)'
}
if (Test-Path -LiteralPath (Join-Path $game 'EasyFont.SA.asi.disabled')) {
    Write-Warn2 'EasyFont.SA.asi.disabled was left over from an earlier attempt - the new EasyFont.SA.asi wins, but you can delete the .disabled copy.'
}
$ini = Join-Path $game 'charlesvercetti_mods\EasyGXT\easygxt.ini'
$iniText = Get-Content -LiteralPath $ini -Raw
if ($iniText -match 'Enable\s*=\s*1') { Write-Ok 'easygxt.ini: Enable=1' }
else { Write-Err2 'easygxt.ini does not enable the plugin'; $ok = $false }
if ($iniText -match 'SACharEncoding\s*=\s*2') { Write-Ok 'easygxt.ini: SACharEncoding=2 (UTF-8)' }
else { Write-Err2 'easygxt.ini is not set to UTF-8'; $ok = $false }
if ($iniText -match 'GxtCsvPath\s*=\s*charlesvercetti_mods\\EasyGXT\\gxt\.csv') { Write-Ok 'easygxt.ini: gxt.csv path' }
else { Write-Warn2 'easygxt.ini points somewhere else than charlesvercetti_mods\EasyGXT\gxt.csv' }

# v1.0.5: EasyFont polls one hotkey and rebuilds every font when it is pressed.
# 162 = VK_LCONTROL, which made each Ctrl press look like a short freeze.
# 0 (or -1) leaves the poll disabled; it does not change how fonts look.
$ttf = Join-Path $game 'charlesvercetti_mods\EasyFont\font_ttf.ini'
$ttfText = Get-Content -LiteralPath $ttf -Raw
if ($ttfText -match '(?m)^\s*ReloadKey\s*=\s*(0|-1)\s*$') {
    Write-Ok 'font_ttf.ini: ReloadKey disabled (no Ctrl reload hitch)'
} else {
    $rm = [regex]::Match($ttfText, '(?m)^\s*ReloadKey\s*=\s*(\S+)')
    $rv = 'missing'
    if ($rm.Success) { $rv = $rm.Groups[1].Value }
    Write-Err2 "font_ttf.ini still binds ReloadKey=$rv - that key reloads every font and feels like a freeze."
    $ok = $false
}

Write-Head 'Done'
if ($ok) {
    Write-Host '  Start the game. Menus, help text and subtitles should now be Thai.' -ForegroundColor Green
} else {
    Write-Host '  The install finished but a check failed - see the lines marked FAIL.' -ForegroundColor Yellow
}
Write-Host ''
Write-Host "  backup   : $backup"
Write-Host "  uninstall: .\UNINSTALL.ps1 -GamePath `"$game`""
Write-Host ''

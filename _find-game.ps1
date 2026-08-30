# Prints the Bigfoot Win64 directory, or nothing if it cannot be found.
$ErrorActionPreference = 'SilentlyContinue'

# Manual override wins - for non-Steam installs, or a second copy of the game.
if ($env:BIGFOOT_DIR -and (Test-Path (Join-Path $env:BIGFOOT_DIR 'Bigfoot-Win64-Shipping.exe'))) {
    Write-Output $env:BIGFOOT_DIR; exit
}
$libs = @()
$steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -Name SteamPath).SteamPath
if ($steam) {
    $steam = $steam -replace '/', '\'
    $libs += $steam
    $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
    if (Test-Path $vdf) {
        foreach ($m in [regex]::Matches((Get-Content $vdf -Raw), '"path"\s*"([^"]+)"')) {
            # libraryfolders.vdf escapes its separators, so a path arrives as
            # X:\\SteamLibrary. -replace takes a regex, so the pattern needs two
            # escaped backslashes to match two literal ones. The old '\\' matched
            # a single backslash and replaced it with itself, leaving the doubled
            # separator in the path that every script downstream then used.
            $libs += $m.Groups[1].Value -replace '\\\\', '\'
        }
    }
}
# a running game beats any guess
$proc = Get-Process 'Bigfoot-Win64-Shipping' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($proc -and $proc.Path) { Write-Output (Split-Path $proc.Path -Parent); exit }
foreach ($l in $libs) {
    $p = Join-Path $l 'steamapps\common\BigfootContent\Bigfoot\Binaries\Win64'
    if (Test-Path (Join-Path $p 'Bigfoot-Win64-Shipping.exe')) { Write-Output $p; exit }
}

# Created by FajkPes with assistance from ChatGPT Codex and Claude Code.

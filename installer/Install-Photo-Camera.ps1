#requires -Version 5.1
param([string]$GamePath, [string]$SteamPath)

$ErrorActionPreference = 'Stop'
$modName = 'VHOLUMEPhotoCamera'
$exeName = 'VHOLUME-Win64-Shipping.exe'
$modZip = Join-Path $PSScriptRoot 'VHOLUME-Photo-Camera.zip'
$loaderZip = Join-Path $PSScriptRoot 'UE4SS_v3.0.1-1011-gb50986bd.zip'
$modHash = 'C1B05BDA328E3651140AEA24BD3CA8FDD65A6C29C120EB6D84D5640A07BFACA7'
$loaderHash = 'AA181789DC7226BCEC94F13F054FF10477D7383321FFB98DBC3666A159B182A8'
$loaderDllHash = '2AD348BF2025BD26B2AA63B478D9813AFBD4E656C9BCFB3FDF6752C4D285F298'

function Find-GameBin([string]$path) {
    if ([string]::IsNullOrWhiteSpace($path)) { return }
    $path = $path.Trim().Trim('"')
    if (!(Test-Path -LiteralPath $path -PathType Container)) { return }
    foreach ($bin in $path, (Join-Path $path 'VHOLUME\Binaries\Win64')) {
        $exe = Get-Item -LiteralPath (Join-Path $bin $exeName) -ErrorAction SilentlyContinue
        if ($exe -and !$exe.PSIsContainer) { return $exe.DirectoryName }
    }
}

function Find-SteamGames {
    if ($SteamPath) { $steamRoots = @($SteamPath) }
    else {
        $userSteam = Get-ItemProperty -LiteralPath 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue
        $machineSteam = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' -ErrorAction SilentlyContinue
        $steamRoots = @($userSteam.SteamPath, $machineSteam.InstallPath)
        if (${env:ProgramFiles(x86)}) { $steamRoots += Join-Path ${env:ProgramFiles(x86)} 'Steam' }
    }
    $libraries = @($steamRoots | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) })
    foreach ($root in $steamRoots) {
        if (!$root -or !(Test-Path -LiteralPath $root -PathType Container)) { continue }
        $vdf = Join-Path $root 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf -PathType Leaf) {
            foreach ($match in [regex]::Matches((Get-Content -LiteralPath $vdf -Raw), '"path"\s*"([^"]+)"')) {
                $libraries += $match.Groups[1].Value.Replace('\\','\')
            }
        }
    }
    foreach ($library in ($libraries | Sort-Object -Unique)) {
        if (!(Test-Path -LiteralPath $library -PathType Container)) { continue }
        $manifest = Join-Path $library 'steamapps\appmanifest_4131730.acf'
        if (!(Test-Path -LiteralPath $manifest -PathType Leaf)) { continue }
        if ((Get-Content -LiteralPath $manifest -Raw) -match '"installdir"\s*"([^"]+)"') {
            $folder = $Matches[1]
            if ($folder -notmatch '[\\/:]' -and $folder -notin '.', '..') {
                Find-GameBin (Join-Path $library "steamapps\common\$folder")
            }
        }
    }
}

function Assert-GameClosed {
    if (Get-Process -Name 'VHOLUME', 'VHOLUME-Win64-Shipping' -ErrorAction SilentlyContinue) {
        throw 'Close VHOLUME, then run the installer again.'
    }
}

function Assert-Archive([string]$path, [string]$expected) {
    if (!(Test-Path -LiteralPath $path -PathType Leaf) -or (Get-FileHash -LiteralPath $path).Hash -ne $expected) {
        throw "Missing or damaged package: $([IO.Path]::GetFileName($path)). Extract a fresh copy of the installer ZIP."
    }
}

function Remove-StagingDirectory([string]$parent, [string]$name) {
    $expected = [IO.Path]::GetFullPath((Join-Path $parent $name))
    $directory = Get-Item -LiteralPath $expected -Force -ErrorAction SilentlyContinue
    if (!$directory) { return }
    if ($directory.FullName -ne $expected -or !$directory.PSIsContainer -or
            ($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
            (Get-ChildItem -LiteralPath $expected -Recurse -Force -Attributes ReparsePoint)) {
        Write-Warning "Left staging directory in place: $expected"
        return
    }
    Remove-Item -LiteralPath $expected -Recurse -Force
}

if (!$GamePath) {
    $gameBins = @(Find-SteamGames | Sort-Object -Unique)
    if ($gameBins.Count -eq 1) { $GamePath = $gameBins[0] }
    else {
        if ($gameBins) { Write-Host ($gameBins -join [Environment]::NewLine) }
        $GamePath = Read-Host 'Enter the VHOLUME installation folder from Steam'
    }
}
$bin = Find-GameBin $GamePath
if (!$bin) { throw "Could not find $exeName. In Steam, open VHOLUME > Manage > Browse local files to find the folder." }
Assert-GameClosed

function Install-PhotoCamera([string]$bin) {
    $loader = Join-Path $bin 'ue4ss'
    $mods = Join-Path $loader 'Mods'
    $destination = Join-Path $mods $modName
    $proxy = Join-Path $bin 'dwmapi.dll'
    $core = Join-Path $loader 'UE4SS.dll'
    foreach ($path in $loader, $mods, $destination) {
        $item = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        if ($item -and (!$item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint))) {
            throw "Use the manual installation steps for this custom mod path: $path"
        }
    }
    $existingLoader = (Test-Path -LiteralPath $proxy -PathType Leaf) -and (Test-Path -LiteralPath $core -PathType Leaf)
    if (!$existingLoader -and ((Test-Path -LiteralPath $proxy) -or (Test-Path -LiteralPath $core) -or
            (Test-Path -LiteralPath (Join-Path $bin 'UE4SS.dll')) -or (Test-Path -LiteralPath (Join-Path $bin 'xinput1_3.dll')))) {
        throw "Found a partial or custom UE4SS installation in $bin. Use the manual install steps for this setup."
    }
    Write-Host "Installing Photo Camera in $bin"
    if ($existingLoader) {
        Write-Host 'Using your existing UE4SS installation.'
        if ((Get-FileHash -LiteralPath $core).Hash -ne $loaderDllHash) {
            Write-Warning 'Your UE4SS build differs from the tested build 3.0.1-1011-gb50986bd.'
        }
    }
    Assert-Archive $modZip $modHash
    if (!$existingLoader) { Assert-Archive $loaderZip $loaderHash }

    $id = [Guid]::NewGuid().ToString('N')
    $tempParent = [IO.Path]::GetTempPath()
    $tempName = "VHOLUMEPhotoCamera-$id"
    $temp = Join-Path $tempParent $tempName
    $pendingName = ".PhotoCamera-install-$id"
    $pending = Join-Path $loader $pendingName
    $backup = Join-Path $loader "PhotoCamera-backup-$(Get-Date -Format yyyyMMdd-HHmmss)-$($id.Substring(0,8))"
    $created = @()
    $movedOld = $false
    try {
        Expand-Archive -LiteralPath $modZip -DestinationPath (Join-Path $temp 'mod')
        $source = Join-Path $temp "mod\ue4ss\Mods\$modName"
        if (!(Test-Path -LiteralPath (Join-Path $source 'enabled.txt') -PathType Leaf) -or
                !(Test-Path -LiteralPath (Join-Path $source 'Scripts\main.lua') -PathType Leaf)) {
            throw 'The Photo Camera archive is missing its entry point.'
        }
        if (!$existingLoader) { Expand-Archive -LiteralPath $loaderZip -DestinationPath (Join-Path $temp 'loader') }
        Assert-GameClosed
        [IO.Directory]::CreateDirectory($mods) | Out-Null
        Copy-Item -LiteralPath $source -Destination $pending -Recurse
        if (!$existingLoader) {
            foreach ($name in 'ue4ss\UE4SS.dll','ue4ss\LICENSE','ue4ss\UE4SS-settings.ini','dwmapi.dll') {
                $target = Join-Path $bin $name
                if ($name -in 'ue4ss\LICENSE','ue4ss\UE4SS-settings.ini' -and (Test-Path -LiteralPath $target -PathType Leaf)) { continue }
                $temporary = "$target.photo-$id"
                try {
                    [IO.File]::Copy((Join-Path $temp "loader\$name"), $temporary)
                    [IO.File]::Move($temporary, $target)
                    $created += $target
                } finally { [IO.File]::Delete($temporary) }
            }
        }
        if (Test-Path -LiteralPath $destination) {
            [IO.Directory]::Move($destination, $backup)
            $movedOld = $true
        }
        [IO.Directory]::Move($pending, $destination)
    } catch {
        if ($movedOld) { [IO.Directory]::Move($backup, $destination) }
        foreach ($file in $created) { [IO.File]::Delete($file) }
        throw
    } finally {
        Remove-StagingDirectory $loader $pendingName
        Remove-StagingDirectory $tempParent $tempName
    }

    if ($movedOld) { Write-Host "Previous Photo Camera backed up to $backup" }
    Write-Host 'Installed. Start VHOLUME, enter a level, and press 5 to open Photo Studio.'
}
$mutex = [Threading.Mutex]::new($false, 'Local\VHOLUMEPhotoCameraInstaller')
$ownsMutex = $false
try {
    try { $ownsMutex = $mutex.WaitOne(0) }
    catch [Threading.AbandonedMutexException] { $ownsMutex = $true }
    if (!$ownsMutex) { throw 'Photo Camera installer is already running.' }
    Install-PhotoCamera $bin
} finally {
    if ($ownsMutex) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}

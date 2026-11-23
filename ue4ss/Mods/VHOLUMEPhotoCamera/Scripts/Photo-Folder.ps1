#requires -Version 5.1
param(
    [ValidateSet('Choose','Prepare','Open')][string]$Action,
    [Parameter(Mandatory=$true)][string]$InitialPathBase64,
    [string]$ResultPathBase64
)
$ErrorActionPreference = 'Stop'
$encoding = New-Object Text.UTF8Encoding($false)
$initial = [IO.Path]::GetFullPath($encoding.GetString([Convert]::FromBase64String($InitialPathBase64)).Replace('/','\'))
$result = if ($ResultPathBase64) { $encoding.GetString([Convert]::FromBase64String($ResultPathBase64)) }
function Test-OutputFolder([string]$path) {
    [IO.Directory]::CreateDirectory($path) | Out-Null
    $probe = Join-Path $path ('.photo-camera-' + [Guid]::NewGuid().ToString('N') + '.tmp')
    $stream = [IO.File]::Open($probe,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try { $stream.WriteByte(0) } finally { $stream.Dispose(); [IO.File]::Delete($probe) }
}
try {
    switch ($Action) {
        'Choose' {
            Add-Type -AssemblyName System.Windows.Forms
            [Windows.Forms.Application]::EnableVisualStyles()
            $dialog = New-Object Windows.Forms.FolderBrowserDialog
            $owner = New-Object Windows.Forms.Form
            try {
                $owner.TopMost = $true
                $owner.ShowInTaskbar = $false
                $owner.Opacity = 0
                $owner.Show()
                $dialog.Description = 'Choose where VHOLUME Photo Camera saves photos'
                $dialog.SelectedPath = $initial
                $dialog.ShowNewFolderButton = $true
                if ($dialog.ShowDialog($owner) -eq [Windows.Forms.DialogResult]::OK) {
                    $selected = [IO.Path]::GetFullPath($dialog.SelectedPath)
                    Test-OutputFolder $selected
                    $answer = "OK`n$selected"
                } else { $answer = 'CANCELLED' }
            } finally { $dialog.Dispose(); $owner.Dispose() }
            [IO.File]::WriteAllText($result + '.tmp',$answer,$encoding)
            [IO.File]::Move($result + '.tmp',$result)
        }
        'Prepare' { Test-OutputFolder $initial }
        'Open' {
            Test-OutputFolder $initial
            # Shell.Application.Open can silently ignore slash-normalized paths.
            # Launch Explorer directly, then acknowledge the actual folder window.
            $launch = New-Object Diagnostics.ProcessStartInfo
            $launch.FileName = Join-Path $env:WINDIR 'explorer.exe'
            $launch.Arguments = '"' + $initial.TrimEnd('\') + '"'
            $launch.UseShellExecute = $true
            $launch.WindowStyle = [Diagnostics.ProcessWindowStyle]::Normal
            [Diagnostics.Process]::Start($launch) | Out-Null
            $shell = New-Object -ComObject Shell.Application
            try {
                $opened = $false
                for ($attempt=0; $attempt -lt 40 -and !$opened; $attempt++) {
                    foreach ($window in @($shell.Windows())) {
                        try {
                            $location = [IO.Path]::GetFullPath($window.Document.Folder.Self.Path).TrimEnd('\')
                            if ($location -eq $initial.TrimEnd('\')) { $opened=$true; break }
                        } catch { }
                    }
                    if (!$opened) { Start-Sleep -Milliseconds 100 }
                }
                if (!$opened) { throw 'Explorer did not open the requested photo folder.' }
            } finally { [Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null }
            if ($result) {
                [IO.File]::WriteAllText($result + '.tmp','OPENED',$encoding)
                [IO.File]::Move($result + '.tmp',$result)
            }
        }
    }
} catch {
    Write-Error -ErrorAction Continue $_
    if ($result) {
        [IO.File]::WriteAllText($result + '.tmp','ERROR',$encoding)
        [IO.File]::Move($result + '.tmp',$result)
    }
    exit 1
}

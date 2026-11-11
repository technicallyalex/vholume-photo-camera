#requires -Version 5.1
param(
    [ValidateSet('Choose','Prepare','Open')][string]$Action,
    [Parameter(Mandatory=$true)][string]$InitialPathBase64,
    [string]$ResultPathBase64
)
$ErrorActionPreference = 'Stop'
$encoding = New-Object Text.UTF8Encoding($false)
$initial = $encoding.GetString([Convert]::FromBase64String($InitialPathBase64))
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
            $shell = New-Object -ComObject Shell.Application
            try { $shell.Open($initial) } finally { [Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null }
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

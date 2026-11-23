$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$destination = Join-Path $root 'ue4ss/Mods/VHOLUMEPhotoCamera/Tools'
[IO.Directory]::CreateDirectory($destination) | Out-Null
$compiler = Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
& $compiler /nologo /target:winexe /platform:x64 /optimize+ /r:System.IO.Compression.dll "/out:$destination/PhotoCameraDng.exe" (Join-Path $PSScriptRoot 'LinearDng.cs')
if ($LASTEXITCODE -ne 0) { throw 'DNG converter compilation failed.' }
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'LICENSE.txt') -Destination (Join-Path $destination 'DNG-LICENSE.txt')

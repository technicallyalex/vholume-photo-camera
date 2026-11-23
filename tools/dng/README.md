# Linear DNG converter

This MIT-licensed helper converts the mod's scene-linear, ZIP16 half-float OpenEXR render into a lossless float32 LinearRaw DNG. It runs outside the game process and does not require the Adobe SDK. Windows uses the built-in .NET Framework; Linux uses a bundled native x86-64 executable from the same source.

To rebuild from the repository or extracted manual package, open PowerShell in this directory and run `./Build.ps1`. The script uses the .NET Framework compiler included with Windows and writes `ue4ss/Mods/VHOLUMEPhotoCamera/Tools/PhotoCameraDng.exe` under the package root. Copy that helper and its license with the complete mod.

The job is a UTF-8 key/value file, passed as one Base64-encoded absolute filename. Input, destination, and reply paths are also UTF-8 Base64. The game uses unique job names, cancellation markers, progress percentages, and an atomic completion reply. The worker streams 16-row blocks through a bounded queue using up to four fast lossless compression workers, closes the HDR input before replying, and never overwrites an existing destination.

DNG uses Rec.709/sRGB primaries, D65 white balance, an embedded color profile, and standard exposure/lens metadata. A power-of-two scale and BaselineExposure keep the original half-float HDR values exactly representable. Focus, blur, motion, and rendered exposure remain baked in; this is rendered linear RGB, not sensor mosaic data. Film simulation and artificial grain are excluded by the capture pipeline.

Specification: https://www.adobe.com/support/downloads/dng/dng_sdk.html

This product includes DNG technology under license by Adobe.

The game keeps an eight-photo disk-backed FIFO with one converter process at a time. The queue journal and job metadata recover after a restart; native GPU targets are not kept alive while photos wait.

## Linux build

Build with .NET SDK 10, clang, and zlib development headers on Linux: `sh tools/dng/Build-Linux.sh` from the repository. This creates a self-contained Native AOT executable and copies its runtime license notices. Release binaries target Ubuntu 22.04 or newer x86-64; end users do not need the SDK or a .NET runtime. The Proton bridge maps Windows paths to the host and passes `--job-data` with the Base64-encoded UTF-8 job body. A `control` field identifies the original job for progress, cancellation and the exclusive worker lock. This keeps recovery and cancellation tied to the same job across game restarts.

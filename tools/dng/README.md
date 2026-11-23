# Linear DNG converter

This MIT-licensed Windows helper converts the mod's scene-linear, ZIP16 half-float OpenEXR render into a lossless float32 LinearRaw DNG. It runs outside the game process using the Windows .NET Framework and does not require the Adobe SDK.

To rebuild from the repository or extracted manual package, open PowerShell in this directory and run `./Build.ps1`. The script uses the .NET Framework compiler included with Windows and writes `ue4ss/Mods/VHOLUMEPhotoCamera/Tools/PhotoCameraDng.exe` under the package root. Copy that helper and its license with the complete mod.

The job is a UTF-8 key/value file, passed as one Base64-encoded absolute filename. Input, destination, and reply paths are also UTF-8 Base64. The game uses unique job names, cancellation markers, progress percentages, and an atomic completion reply. The worker streams 16-row blocks, closes the HDR input before replying, and never overwrites an existing destination.

DNG uses Rec.709/sRGB primaries, D65 white balance, an embedded color profile, and standard exposure/lens metadata. A power-of-two scale and BaselineExposure keep the original half-float HDR values exactly representable. Focus, blur, motion, and rendered exposure remain baked in; this is rendered linear RGB, not sensor mosaic data. Film simulation and artificial grain are excluded by the capture pipeline.

Specification: https://www.adobe.com/support/downloads/dng/dng_sdk.html

This product includes DNG technology under license by Adobe.

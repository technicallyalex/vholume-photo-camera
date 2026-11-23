# VHOLUME Photo Camera v1.0.3 - Full-resolution RAW photography

Release candidate v1.0.3-rc.1. Prepared for approval; not published.

Keep taking photos while RAW files save. A disk-backed queue holds up to eight photos, shows progress in the finder and Studio, and recovers interrupted saves on the next launch. Each photo keeps its own settings. A failed conversion does not stop the rest of the queue.

- Full-image rendering at the selected aspect ratio and resolution, up to a 7680-pixel long edge, without cropping the viewfinder screenshot.
- PNG with the film look and ISO grain, linear HDR EXR, or lossless linear DNG for Camera Raw / Lightroom workflows. Save any combination. DNG records aperture, shutter speed, ISO, focal length and capture time.
- Faster DNG conversion: the earlier test converted an identical 8K square source in about 8 seconds versus 50 seconds before optimization. Rendering/export time is additional; results vary by hardware. Fast compression can produce slightly larger files while preserving the same HDR pixels.
- Dedicated photo rendering, plus an optional temporary game-resolution method that restores the original running resolution, display mode and saved video-setting values. Recovery retries if a restore request fails.
- Clear defaults: 5 enters camera mode, 6 opens Studio, and right-click opens the finder from either. Dedicated mouse-wheel modifier controls and the controller layout remain available.
- Consistent Studio navigation and spacing, output settings, and working Open Folder feedback. Ctrl remains available to the game's slide action.

## Downloads planned

| Platform | Build | Package |
| --- | --- | --- |
| Windows | v1.0.3 after approval | Installer and manual ZIP |
| Linux / Proton | v1.0.2-linux.2, unchanged | Existing experimental installer package |

The new capture and RAW queue features are Windows-only in this release. The existing Linux build remains a separate download with its original contents and testing status.

## Editing and compatibility

DNG and EXR contain rendered HDR data before the film look and artificial grain. Focus blur, depth of field, motion and rendered exposure are already part of the image. These files are not sensor RAW. Camera Raw and independent image readers were tested; Lightroom itself, physical controllers, Steam Input mappings and live Linux/Steam Deck gameplay remain unverified.

The game still renders and exports one frame at a time. Queue capacity bounds waiting work; it is not an unlimited burst buffer. Large captures need sufficient GPU memory and disk space. Dedicated render is recommended for 6K/8K; temporary 6K/8K game-window requests could not be applied on the tested setup and canceled cleanly.

## Credits

Camera RAW support was inspired by [NewBarkTownKris](https://github.com/NewBarkTownKris) and their [Denshattack! Photo Camera](https://github.com/NewBarkTownKris/denshattack-photo-camera).

This product includes DNG technology under license by Adobe.

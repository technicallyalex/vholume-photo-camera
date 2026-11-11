# VHOLUME Photo Camera v1.0.2 - Camera Controls Overhaul

A complete camera controls overhaul, with a dedicated controller layout and controls using modifier keys and the scroll wheel for the camera's core functions. Adjust settings directly from the viewfinder, with the relevant shortcuts shown beside each setting.

| Platform | Current build | Download | Testing |
| --- | --- | --- | --- |
| **Windows** | **v1.0.2** | [Windows installer](https://github.com/technicallyalex/vholume-photo-camera/releases/download/v1.0.2/VHOLUME-Photo-Camera-v1.0.2-Windows-Installer.zip) / [Windows manual ZIP](https://github.com/technicallyalex/vholume-photo-camera/releases/download/v1.0.2/VHOLUME-Photo-Camera-v1.0.2-Windows-Manual.zip) | Released; in-game Windows checks |
| **Linux / Proton** | **v1.0.2-linux.2** | [Linux installer package](https://github.com/technicallyalex/vholume-photo-camera/releases/download/v1.0.2/VHOLUME-Photo-Camera-v1.0.2-linux.2-Linux-Proton.zip) | Experimental; automated Ubuntu installer/helper checks |

Linux gameplay, graphics, camera audio, Steam Deck behavior, and physical controller/Steam Input mapping remain unverified. [Linux setup and QA details](https://github.com/technicallyalex/vholume-photo-camera/blob/main/LINUX.md). The Windows packages retain the original v1.0.2 contents. [Checksums for all packages](https://github.com/technicallyalex/vholume-photo-camera/releases/download/v1.0.2/SHA256SUMS.txt).

- Dedicated controller controls for shooting, autofocus, manual focus, exposure, lens selection, and Studio navigation.
- A scroll wheel control system for focus, aperture, shutter speed, ISO, lenses, film looks, aspect ratio, and exposure mode, with editable letter-key modifiers and fine-focus adjustment.
- Camera input priority preserves movement, mouse look, and Ctrl sliding while camera controls are active.
- Game, Manual, Aperture Priority, and Shutter Priority modes, plus Auto ISO with adjustable limits.
- ISO-driven film grain and slow-shutter captures that blend camera movement into the photo.
- A shaded LCD, clearer panel text, and fixed left/right sidebars, including at 16:9.
- Lens DOF multipliers from 1x to 8x, a thirds grid, and new 21:9 and 65:24 formats.
- A selectable screenshot folder in Photo Studio.

**Windows:** close the game, extract the Windows installer ZIP, and run **Install Photo Camera.cmd**. **Linux:** extract the Linux package, run **python3 install-linux.py**, then apply its printed Steam launch option. Both installers detect Steam libraries and back up an existing Photo Camera installation. Use the dated backup or an earlier release to switch back.

Tested with VHOLUME Steam build **26455274** and UE4SS **3.0.1-1011-gb50986bd**. Physical controller hardware and Steam Input mappings remain unverified. Motion capture sample density depends on game frame rate.

[Controls and settings](https://github.com/technicallyalex/vholume-photo-camera/blob/main/GUIDE.md)

![Photo Studio](https://raw.githubusercontent.com/technicallyalex/vholume-photo-camera/v1.0.2/examples/photo-studio.png)

![Optical viewfinder](https://raw.githubusercontent.com/technicallyalex/vholume-photo-camera/v1.0.2/examples/viewfinder-optical.png)

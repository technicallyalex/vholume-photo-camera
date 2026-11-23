# VHOLUME Photo Camera v1.0.3-alpha.2 - Capture preview

- Full-frame scene rendering replaces the HUD screenshot crop for every photo.
- PNG, linear HDR EXR, and paired PNG + EXR output under Studio > Photos > Output Settings.
- EXR retains floating-point highlight data before tone mapping, without film grading or artificial grain. Optics, depth of field, exposure, and camera motion remain rendered.
- Image long-edge presets from 1280 to 7680 pixels, plus game resolution. Exact selected aspect ratio and portrait orientation are preserved; the panel shows actual output dimensions.
- Dedicated render keeps gameplay resolution unchanged. Switch game resolution temporarily changes the game window and restores both the original running viewport/display mode and the original video-setting values. Capture completion waits for restoration. Cancellation and export failure trigger cleanup too.
- Small JSON sidecars record photo settings.
- Existing 5 camera / 6 Studio / right-click finder / Enter Studio controls are retained.

This is a local Windows preview. Published Windows and Linux downloads are unchanged. See QA.txt in the build folder for verified cases and remaining limits.

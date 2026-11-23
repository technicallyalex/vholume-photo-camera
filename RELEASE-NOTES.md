# VHOLUME Photo Camera v1.0.3-alpha.4 - DNG capture preview

- Adds lossless linear HDR DNG for Lightroom and Photoshop / Camera Raw. Save DNG alone or with PNG, EXR, or both.
- Records shutter speed, aperture, ISO, focal length, and capture date in DNG metadata.
- Preserves the HDR render before the tone curve, film simulation, and artificial grain. Lossless float32 storage preserves source half-float RGB values through a recorded power-of-two exposure scale.
- Includes an MIT-licensed converter, its source, and build instructions. No Adobe SDK or third-party runtime is bundled.
- Converts in the background with progress feedback. Cancellation and conversion failures clean up unfinished files. Temporary game resolution is restored before conversion.

Rendered DNG is not sensor RAW: focus blur, depth of field, motion, and rendered exposure remain baked in. Adobe's initial rendering may differ from the film-look PNG. HDR editing cannot undo rendered effects.

Local Windows preview only; not published. Public Windows and Linux packages remain unchanged. Physical controller hardware and live Linux/Proton DNG use were not tested.

This product includes DNG technology under license by Adobe.

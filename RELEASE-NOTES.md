# VHOLUME Photo Camera v1.1 - A complete photography toolkit

## Dedicated controller and scrollwheel controls

A complete camera controls overhaul puts core functions on a dedicated controller layout and modifier-plus-scrollwheel controls. Move and aim normally while adjusting focus, aperture, shutter speed, ISO, lenses, film looks, framing and exposure mode. Shortcuts appear beside each viewfinder setting and follow the active input device. Letter modifiers can be rebound; Ctrl remains available for sliding.

Defaults are **5** for camera mode, **6** for Photo Studio, **right-click / LT** for the finder, **left-click / RT** for the shutter, and **middle-click / A** for single-shot AF. Studio supports controller navigation.

## Full-resolution PNG, EXR and DNG photography

Photos render directly at the selected aspect ratio and resolution, up to a **7680-pixel long edge**, including 6K and 8K. Save finished PNGs, scene-linear HDR EXRs, lossless linear DNGs, or any combination. DNG includes ISO, aperture, shutter speed, focal length and capture time for external RAW editing workflows.

Dedicated render keeps gameplay resolution unchanged. The optional temporary-resolution method restores the original resolution and display mode after capture, cancellation or failure. Choose and open a custom photo folder from Studio.

## Keep shooting while RAW files save

An **eight-photo background queue** saves DNGs while you take more photos after each frame has rendered and exported. Every photo retains its own settings. Captured frames keep saving with the finder lowered, camera stowed, Studio open or game paused. Interrupted queues recover on the next launch; failed conversions do not stop later photos. Progress appears in the finder and Studio.

## Exposure, Auto ISO and camera motion

**Game, Manual, Aperture Priority and Shutter Priority** modes offer a choice between the game's normal brightness and physical exposure controls. Auto ISO supports a configurable range and preferred minimum shutter in Aperture Priority. Settings span **f/1.0-f/16**, **8 s-1/32000 s**, and **ISO 100-6400**. Grain strength and size follow ISO across all eleven generic film looks.

Move or pan during exposures of **1/15 s or slower** to create intentional camera-motion effects. Manual focus, fine focus, single-shot AF and a **1x-8x DOF blur multiplier** provide further control over the image. Eight focal lengths from **16 to 600 mm** have distinct lens models and optional zoom-aware sensitivity scaling.

## Optical finder and refined Studio

The finder combines a shaded LCD, segmented values, an EV scale above the frame, focus lamps beside the LCD, and fixed sidebars. Keybinds are integrated into setting labels. Four reticle styles, a thirds guide, portrait rotation and seven aspect ratios include **21:9** and **65:24 panoramic** framing.

Studio uses consistent panels and rotating low-poly icons for Photos, Lens, Film, Frame, Exposure and Subjects. Five subject poses, placement controls, generic film names and synthesized mechanical camera sounds complete the toolkit.

## Windows and Linux together

Separate **Windows installer**, **Windows manual**, and **Linux/Proton installer** downloads offer matching camera, capture and background RAW-saving features. Linux includes a native DNG converter built from the same source as Windows, with no .NET installation needed. Existing installs are backed up by the installers.

Windows capture and recovery were tested in-game, including 6K/8K. Linux passed automated native converter, queue, installer and shared camera checks on Ubuntu 22.04 and 24.04. Live Proton gameplay, Linux GPU capture, Steam Deck and physical controller/Steam Input mappings remain unverified, so Linux is experimental.

## RAW editing notes

EXR and DNG contain rendered HDR RGB before film grading and artificial grain. Focus blur, depth of field, motion and rendered exposure are baked in; these are not sensor-mosaic RAW files. Their usable highlight range comes from the HDR render. Rendering and source export still take time; the queue overlaps conversion. Dedicated render is recommended for 6K/8K. Camera Raw was tested; Lightroom itself was not.

## Credits

Thank you to [NewBarkTownKris](https://github.com/NewBarkTownKris), whose [Denshattack! Photo Camera](https://github.com/NewBarkTownKris/denshattack-photo-camera) inspired the idea for camera RAW support.

This product includes DNG technology under license by Adobe.

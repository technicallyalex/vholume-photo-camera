# VHOLUME Photo Camera Guide

**Version 1.0.3-alpha.4** / Windows capture preview

A complete camera controls overhaul introduces a dedicated controller layout and controls using modifier keys and the scroll wheel for focus, exposure, lenses, film looks, and framing. Shortcuts appear beside their settings in the viewfinder. See [Keyboard and mouse](#keyboard-and-mouse) and [Controller](#controller) for the layouts.

## Install and switch back

Close VHOLUME. Extract the installer ZIP and run **Install Photo Camera.cmd**. It detects the Steam installation and moves any existing Photo Camera folder into a dated backup next to the UE4SS Mods folder.

For a manual install, back up the existing mod outside **Mods**. Copy **VHOLUMEPhotoCamera** from the manual ZIP's **ue4ss\Mods** into the game's **VHOLUME\Binaries\Win64\ue4ss\Mods**. This update replaces the existing Photo Camera mod.

To switch back, close the game, move the current **VHOLUMEPhotoCamera** folder out of **Mods**, then move the dated backup into **Mods** and rename it **VHOLUMEPhotoCamera**. You can also reinstall any earlier build from its ZIP. This preview saves bindings in **VHOLUMEPhotoCamera.keys.controls-preview**. On first use it restores every keybind to its default while retaining exposure options and aim-scaling preferences. Previous binding profiles remain available for switching back. Later changes made in Keybinds save normally.

## Optical finder

The raised finder reserves space on both sides for camera readouts, including at 16:9. At 1920 x 1080, the 3:2 frame is 1380 x 920 pixels and the 16:9 frame is 1440 x 810 pixels. A thin exposure scale is centered above the image with an amber pointer. The recessed LCD shows mode, shutter, aperture, ISO, and lens, with segmented numerals and shaded glass. Focus lamps sit at the bottom-left beside the LCD. Film and aspect information stay in the left sidebar; focus distance, subject distance, focus controls, and the lens blur multiplier stay in the matching right sidebar. Small muted labels sit above larger values, with controls grouped separately.

Shortcuts appear directly in the labels for their settings and switch with the active input device. Keyboard labels reflect customized bindings. Hold a wheel modifier or controller shoulder button to highlight the settings it adjusts. Photo Studio's Frame card offers the new Optical reticle alongside Square, Circle, and None.

Toggle the rule-of-thirds guide using **Frame > Thirds Grid** in Photo Studio. In Studio, **LB / RB** move controller focus between buttons and **A** activates the focused button.

Under **Lens > DOF Multiplier**, select **1x**, **2x**, **4x**, or **8x** to exaggerate out-of-focus lens blur. **1x** preserves the baseline. Higher multipliers widen the rendering aperture and allow larger blur kernels while keeping the displayed aperture, exposure, and focus distance unchanged. DOF must be enabled for the multiplier to take effect. The choice saves with the camera settings and works in every exposure mode.

The Frame card offers **21:9 Ultrawide** and **65:24 Panoramic** alongside the existing formats, with matching rotating frame models. Both can rotate into portrait orientation. Captures preserve the selected ratio; wider ratios have shorter frames so the sidebars remain beside the image. The HUD is excluded from saved photos.

## Screenshot folder

In Photo Studio, select **Photos > Choose Folder** to open the Windows folder chooser. The chosen folder is checked for write access and saved for future sessions. **Open Folder** opens the current destination in Explorer and confirms that the folder opened. **Reset Folder** restores the game's screenshot directory. Selecting the Photos card with Enter or controller A opens Output Settings; folder actions have their own buttons. Instant photos and motion exposures both use this destination. Canceling the chooser keeps the previous folder.

The Exposure card has a rotating low-poly +/- model. The exposure settings show a short hint for the hovered or focused control, with the selected mode as the default.

## Full-resolution photos and HDR output

Open **Studio > Photos > Output Settings**. Choose **PNG**, **EXR**, **DNG**, or any combination of these formats. PNG includes the selected film simulation and ISO grain. EXR is a 16-bit floating-point linear HDR image before the tone curve, with film grading and artificial grain removed. Focus, aperture, DOF multiplier, exposure, and intentional camera motion remain rendered into the image; those effects cannot be undone as if this were sensor RAW data. A small JSON sidecar records the capture settings.

Use an editor that supports OpenEXR. Interpret the EXR as linear sRGB / Rec.709 primaries with a D65 white point; apply a display transform or tone mapping for viewing. An unprocessed EXR can look different from the PNG. Exposure and highlight adjustments can use values above display white. HDR outputs come directly from the scene render; they are not reconstructed from PNG. [Unreal HDR capture and export](https://dev.epicgames.com/documentation/en-us/unreal-engine/python-api/class/ImageWriteBlueprintLibrary?application_version=5.4)

**DNG** is a losslessly compressed, scene-linear RGB file using the openly documented DNG format. Open it in Lightroom or Photoshop / Camera Raw to use familiar RAW exposure, white-balance, and highlight controls. It includes capture date, aperture, shutter speed, ISO, and focal length. Film simulation and artificial grain are excluded. The included converter is open source under the MIT license; its source and build instructions are in the manual package's **source/DNG** folder. Windows uses the built-in .NET Framework; no separate converter download is needed.

This is **rendered linear DNG**, not sensor RAW. Focus blur, DOF, motion, and the rendered exposure are already part of its pixels. Its available highlight range comes from the HDR render. A power-of-two normalization recorded in Baseline Exposure preserves all source half-float RGB values in lossless float32 data. Adobe may apply its own initial rendering, so the DNG can look different from the PNG; edit its exposure and tone as needed. PNG retains the selected film look. DNG can be saved alone, with PNG, with EXR, or with both. During conversion the finder shows progress; lowering the finder cancels and cleans up the unfinished outputs. Gameplay resolution is restored before conversion begins.

[Adobe DNG specification and tools](https://www.adobe.com/support/downloads/dng/dng_sdk.html). This product includes DNG technology under license by Adobe.

**Resolution / Long Edge** offers the game's resolution or 1280, 1920, 2560, 3840, 5760, and 7680 pixels. The exact dimensions appear below the controls. They are rounded down slightly when needed to preserve the exact aspect ratio, including 21:9, 65:24, and portrait orientations. Game resolution uses the game viewport's full long edge, not the smaller viewfinder rectangle. Every photo is rendered directly at its output size; no capture is cropped from the HUD screenshot or enlarged from a smaller screenshot.

**Dedicated render** is recommended. It renders only the photo at the chosen size, keeping gameplay resolution unchanged. **Switch game resolution** temporarily switches the live game to a window at the photo dimensions, captures, then restores the original running resolution and display mode. It also restores the original video-setting values, which can differ from the current window when launch overrides are in use. The mod does not save or confirm video settings. Capture completion waits for the original viewport to return. Cancellation, menus, and save errors also trigger restoration. Failed restore requests remain queued for retry; another photo cannot start until restoration finishes. Both the viewport dimensions and running display mode are verified before completion. If a requested window size cannot be applied, the shot is canceled; select Dedicated render for sizes your display cannot accommodate.

Native PNG + EXR capture passed at 5760 x 3240, 5760 x 3840, 7680 x 4320, 7680 x 5120, and 7680 x 7680. Independent PNG and EXR readers decoded the files and checked dimensions, finite float16 pixel data, and opaque alpha. Temporary 6K/8K game windows could not be applied on the tested setup; both attempts canceled cleanly and restored the original video state. Use Dedicated render for those sizes.

Large captures require more GPU memory and preparation time. This is a Windows preview. The existing Linux/Proton package has not been updated for these capture features.

## Exposure

Press **5** for camera mode or **6** for Photo Studio. **6** can open Studio even when the camera is stowed. Controller **View** retains its existing Studio entry. Select **Exposure > Edit Exposure** to change exposure settings.

| Mode | You set | The camera sets |
| --- | --- | --- |
| **Game** | Aperture for depth of field and ISO for grain. Shutter speed is display-only. | VHOLUME sets exposure as usual. |
| **M** | Aperture, shutter speed, and ISO | ISO if Auto ISO is enabled |
| **A** | Aperture and ISO if Auto ISO is off | Shutter speed and optional Auto ISO |
| **S** | Shutter speed and ISO if Auto ISO is off | Aperture and optional Auto ISO |

Game mode is the default. In M, A, and S, a wider aperture, slower shutter, or higher ISO brightens the image. Available settings cover f/1.0 to f/16, 8 seconds to 1/32000 second, and ISO 100 to 6400 in roughly one-third-stop steps. [Unreal Engine exposure documentation](https://dev.epicgames.com/documentation/en-us/unreal-engine/auto-exposure-in-unreal-engine)

Enable **Auto ISO** to set minimum and maximum sensitivity. Aperture Priority prefers the configured minimum shutter speed and can slow down after reaching the ISO ceiling. The viewfinder marks camera-set values **AUTO** and shows exposure error in EV. Film looks set preview and PNG color and tone; EXR and DNG remain ungraded. The actual ISO determines grain strength and size, including with the Neutral look.

### Intentional camera motion

Raise the finder in **M** or **S** and set the shutter to **1/15 s or slower**. **Alt + wheel down** or **LB + D-pad left** slows the shutter. **A** also records motion when it meters a shutter speed in that range.

Press **left-click** or **RT** once, then walk or pan while the finder shows **EXPOSING**. The mod locks focus and exposure at the start and blends scene samples as the camera moves. The completed photo saves in the selected output formats. Lower the finder or stow the camera to cancel an exposure. Game mode and faster shutter speeds use a single-frame scene render after a short preparation period.

Motion captures keep the selected aspect ratio and use the resolution selected in Output Settings. Sample density depends on the game's frame rate. [Unreal Engine scene capture documentation](https://dev.epicgames.com/documentation/en-us/unreal-engine/rendering-components-in-unreal-engine)

## Keyboard and mouse

**5** toggles camera mode without opening Studio. **6** opens Studio or goes back one level. Right-click raises or lowers the finder while using the camera; from Studio it always opens the finder, including when Studio was opened from the raised finder. Left-click takes a photo. Middle-click runs single-shot autofocus. **F** switches AF/MF. **Enter** selects the focused Studio control or uses the selected card. The regular camera shortcuts remain available.

| Hold while scrolling | Adjust |
| --- | --- |
| Nothing | Manual focus |
| **Shift** | Fine manual focus |
| **Ctrl** | Aperture |
| **Alt** | Shutter speed |
| **Ctrl + Alt** | Manual ISO |
| **R** | Lens |
| **U** | Exposure mode |
| **Y** | Frame ratio |
| **T** | Film look |

The wheel chords apply with the finder raised. Change the four letter-key modifiers in **Keybinds > Wheel**. **Ctrl**, **Alt**, and their combination adjust aperture, shutter speed, and ISO. Use either **Shift** key for fine focus. In Studio, **Tab** navigates controls.

A dedicated Enhanced Input context gives camera controls priority while the finder is raised. Movement and mouse-look mappings remain available, including movement remaps. The camera context is removed when the finder lowers, Studio or a game menu opens, the camera is stowed, or the level changes. Held camera keys must be released before their game actions can resume.

**Ctrl** continues to reach the game for sliding while the finder is raised. **Ctrl + wheel** also adjusts aperture. LCD values keep padding around their edges and shrink to fit narrow portrait frames.

## Controller

The layout uses Xbox-style labels. The left stick moves and the right stick aims.

| Input | Action |
| --- | --- |
| **View / LT / RT** | Equip or stow / raise or lower finder / take photo |
| **A / X / B / Y** | Single-shot AF / AF or MF / depth of field / Photo Studio |
| **L3** | Toggle slow walk in solo play |
| **D-pad Left/Right / Up / Down** | Previous or next lens / exposure mode / frame ratio |
| **LB + D-pad Left/Right / Up/Down** | Slower or faster shutter / close or open aperture |
| **RB + D-pad Left/Right / Up/Down** | Focus nearer or farther / raise or lower manual ISO |
| **RB + A / B / X / Y** | Hold for fine focus / toggle Auto ISO / next film look / rotate frame |
| **Studio D-pad / A / B** | Navigate or adjust / select / back |
| **Subject placement RT / LT / D-pad Left/Right / Up / X** | Place / finish / rotate / change pose / undo |

The game's normal pause control still opens its menu. Photos save in **%LOCALAPPDATA%\VHOLUME\Saved\Screenshots\Windows**.

## Compatibility and testing

Tested with VHOLUME Steam build **26455274** and UE4SS **3.0.1-1011-gb50986bd**. Native checks covered exposure modes, Auto ISO, motion captures, input mapping restoration, panoramic output, the Studio UI, and stronger DOF. Offline checks covered 84 landscape/portrait finder layouts, exact crop ratios, settings compatibility, and renderer restoration.

Controller logic was exercised with simulated button states. Physical controller detection and Steam Input mappings remain unverified. Motion capture sample density depends on game frame rate.

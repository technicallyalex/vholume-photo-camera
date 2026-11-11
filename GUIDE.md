# VHOLUME Photo Camera Guide

**Version 1.0.2** · Windows

A complete camera controls overhaul introduces a dedicated controller layout and modifier + scrollwheel controls for focus, exposure, lenses, film looks, and framing. Shortcuts appear beside their settings in the viewfinder. See [Keyboard and mouse](#keyboard-and-mouse) and [Controller](#controller) for the layouts.

## Install and switch back

Close VHOLUME. Extract the installer ZIP and run **Install Photo Camera.cmd**. It detects the Steam installation and moves any existing Photo Camera folder into a dated backup next to the UE4SS Mods folder.

For a manual install, back up the existing mod outside **Mods**. Copy **VHOLUMEPhotoCamera** from the manual ZIP’s **ue4ss\Mods** into the game’s **VHOLUME\Binaries\Win64\ue4ss\Mods**. This update replaces the existing Photo Camera mod.

To switch back, close the game, move the current **VHOLUMEPhotoCamera** folder out of **Mods**, then move the dated backup into **Mods** and rename it **VHOLUMEPhotoCamera**. You can also reinstall any earlier build from its ZIP. This version saves keybinds and options in **VHOLUMEPhotoCamera.keys.input-preview** and imports compatible settings from earlier previews or the stable build on first use.

## Optical finder

The raised finder reserves space on both sides for camera readouts, including at 16:9. At 1920 × 1080, the 3:2 frame is 1380 × 920 pixels and the 16:9 frame is 1440 × 810 pixels. A thin exposure scale is centered above the image with an amber pointer. The recessed LCD shows mode, shutter, aperture, ISO, and lens, with segmented numerals and shaded glass. Focus lamps sit at the bottom-left beside the LCD. Film and aspect information stay in the left sidebar; focus distance, subject distance, focus controls, and the lens blur multiplier stay in the matching right sidebar. Small muted labels sit above larger values, with controls grouped separately.

Shortcuts appear directly in the labels for their settings and switch with the active input device. Keyboard labels reflect customized bindings. Hold a wheel modifier or controller shoulder button to highlight the settings it adjusts. Photo Studio’s Frame card offers the new Optical reticle alongside Square, Circle, and None.

Toggle the rule-of-thirds guide using **Frame → Thirds Grid** in Photo Studio. In Studio, **LB / RB** move controller focus between buttons and **A** activates the focused button.

Under **Lens → DOF Multiplier**, select **1x**, **2x**, **4x**, or **8x** to exaggerate out-of-focus lens blur. **1x** preserves the baseline. Higher multipliers widen the rendering aperture and allow larger blur kernels while keeping the displayed aperture, exposure, and focus distance unchanged. DOF must be enabled for the multiplier to take effect. The choice saves with the camera settings and works in every exposure mode.

The Frame card offers **21:9 Ultrawide** and **65:24 Panoramic** alongside the existing formats, with matching rotating frame models. Both can rotate into portrait orientation. Captures preserve the selected ratio; wider ratios have shorter frames so the sidebars remain beside the image. The HUD is excluded from saved photos.

## Screenshot folder

In Photo Studio, select **Photos → Choose Folder** to open the Windows folder chooser. The chosen folder is checked for write access and saved for future sessions. **Open Folder** opens the current destination, and **Use Default** restores the game's screenshot directory. Instant photos and motion exposures both use this destination. Canceling the chooser keeps the previous folder.

The Exposure card has a rotating low-poly +/− model. The exposure settings show a short hint for the hovered or focused control, with the selected mode as the default.

## Exposure

Press **5** or **controller View** to equip the camera and open Photo Studio. Select **Exposure → Edit Exposure**.

| Mode | You set | The camera sets |
| --- | --- | --- |
| **Game** | Aperture for depth of field and ISO for grain. Shutter speed is display-only. | VHOLUME sets exposure as usual. |
| **M** | Aperture, shutter speed, and ISO | ISO if Auto ISO is enabled |
| **A** | Aperture and ISO if Auto ISO is off | Shutter speed and optional Auto ISO |
| **S** | Shutter speed and ISO if Auto ISO is off | Aperture and optional Auto ISO |

Game mode is the default. In M, A, and S, a wider aperture, slower shutter, or higher ISO brightens the image. Available settings cover f/1.0 to f/16, 8 seconds to 1/32000 second, and ISO 100 to 6400 in roughly one-third-stop steps. [Unreal Engine exposure documentation](https://dev.epicgames.com/documentation/en-us/unreal-engine/auto-exposure-in-unreal-engine)

Enable **Auto ISO** to set minimum and maximum sensitivity. Aperture Priority prefers the configured minimum shutter speed and can slow down after reaching the ISO ceiling. The viewfinder marks camera-set values **AUTO** and shows exposure error in EV. Film looks set color and tone. The actual ISO determines grain strength and size, including with the Neutral look.

### Intentional camera motion

Raise the finder in **M** or **S** and set the shutter to **1/15 s or slower**. **Alt + wheel down** or **LB + D-pad left** slows the shutter. **A** also records motion when it meters a shutter speed in that range.

Press **left-click** or **RT** once, then walk or pan while the finder shows **EXPOSING**. The mod locks focus and exposure at the start and blends scene samples as the camera moves. The completed photo saves as one PNG. Lower the finder or stow the camera to cancel an exposure. Game mode and faster shutter speeds use the instant capture path.

Motion captures keep the selected aspect ratio and use up to 3840 pixels along the longer edge. Sample density depends on the game’s frame rate. [Unreal Engine scene capture documentation](https://dev.epicgames.com/documentation/en-us/unreal-engine/rendering-components-in-unreal-engine)

## Keyboard and mouse

Right-click raises or lowers the finder. Left-click takes a photo. Middle-click runs single-shot autofocus. **F** switches AF/MF. **4** opens Studio or goes back one level. The regular camera shortcuts remain available.

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

The wheel chords apply with the finder raised. Change the four letter-key modifiers in **Keybinds → Wheel**. **Ctrl**, **Alt**, and their combination adjust aperture, shutter speed, and ISO. Use either **Shift** key for fine focus. In Studio, **Tab** navigates controls.

A dedicated Enhanced Input context gives camera controls priority while the finder is raised. Movement and mouse-look mappings remain available, including movement remaps. The camera context is removed when the finder lowers, Studio or a game menu opens, the camera is stowed, or the level changes. Held camera keys must be released before their game actions can resume.

**Ctrl** continues to reach the game for sliding while the finder is raised. **Ctrl + wheel** also adjusts aperture. LCD values keep padding around their edges and shrink to fit narrow portrait frames.

## Controller

The layout uses Xbox-style labels. The left stick moves and the right stick aims.

| Input | Action |
| --- | --- |
| **View / LT / RT** | Equip or stow / raise or lower finder / take photo |
| **A / X / B / Y** | Single-shot AF / AF or MF / depth of field / Photo Studio |
| **L3** | Toggle slow walk in solo play |
| **D-pad ← → / ↑ / ↓** | Previous or next lens / exposure mode / frame ratio |
| **LB + D-pad ← → / ↑ ↓** | Slower or faster shutter / close or open aperture |
| **RB + D-pad ← → / ↑ ↓** | Focus nearer or farther / raise or lower manual ISO |
| **RB + A / B / X / Y** | Hold for fine focus / toggle Auto ISO / next film look / rotate frame |
| **Studio D-pad / A / B** | Navigate or adjust / select / back |
| **Subject placement RT / LT / D-pad ← → / ↑ / X** | Place / finish / rotate / change pose / undo |

The game’s normal pause control still opens its menu. Photos save in **%LOCALAPPDATA%\VHOLUME\Saved\Screenshots\Windows**.

## Compatibility and testing

Tested with VHOLUME Steam build **26455274** and UE4SS **3.0.1-1011-gb50986bd**. Native checks covered exposure modes, Auto ISO, motion captures, input mapping restoration, panoramic output, the Studio UI, and stronger DOF. Offline checks covered 84 landscape/portrait finder layouts, exact crop ratios, settings compatibility, and renderer restoration.

Controller logic was exercised with simulated button states. Physical controller detection and Steam Input mappings remain unverified. Motion capture sample density depends on game frame rate.

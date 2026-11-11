# VHOLUME Photo Camera Optical Finder Preview

**Version 1.1.0-alpha.6** · Windows · Separate preview build

## Install and switch back

Close VHOLUME. Extract the preview installer ZIP and run **Install Finder Preview.cmd**. It detects the Steam installation and moves any existing Photo Camera folder into a dated backup next to the UE4SS Mods folder.

For a manual install, back up the existing mod outside **Mods**. Copy **VHOLUMEPhotoCamera** from the manual ZIP’s **ue4ss\Mods** into the game’s **VHOLUME\Binaries\Win64\ue4ss\Mods**. This build uses the same mod slot as the stable release.

To switch back, close the game, move the current **VHOLUMEPhotoCamera** folder out of **Mods**, then move the dated backup into **Mods** and rename it **VHOLUMEPhotoCamera**. You can also reinstall any earlier build from its ZIP. This preview saves keybinds, aim scaling, and Auto ISO options in **VHOLUMEPhotoCamera.keys.finder-preview** and reads compatible settings from the exposure preview or stable build until it has its own settings.

## Optical finder

The raised finder shows a larger, centered capture area. At 1920 × 1080, the 3:2 frame is 1428 × 952 pixels. A slim exposure meter above the image has a smoothly moving marker. The bottom LCD shows mode, shutter, aperture, ISO, and lens, with segmented camera numerals. Larger focus lamps sit just below the center reticle. Focus controls sit beside the LCD or below it on narrower screens. Aspect and film readouts move below the image when the side margins are narrow.

Shortcuts appear directly in the labels for their settings and switch with the active input device. Keyboard labels reflect customized bindings. Hold a wheel modifier or controller shoulder button to highlight the settings it adjusts. Photo Studio’s Frame card offers the new Optical reticle alongside Square, Circle, and None.

Toggle the rule-of-thirds guide using **Frame → Thirds Grid** in Photo Studio. In Studio, **LB / RB** move controller focus between buttons and **A** activates the focused button.

Under **Exposure → Edit Exposure**, select **Depth of field strength** for natural **1x**, stronger **2x**, or exaggerated **4x** lens blur. The selected aperture still determines exposure. The strength option changes the rendering aperture used for blur. Grid and DOF strength choices save with the preview settings.

## Screenshot folder

In Photo Studio, select **Photos → Choose Folder** to open the Windows folder chooser. The chosen folder is checked for write access and saved for future sessions. **Open Folder** opens the current destination, and **Use Default** restores the game's screenshot directory. Instant photos and motion exposures both use this destination. Canceling the chooser keeps the previous folder.

Exposure uses a camera-style +/− icon. The exposure settings show a short hint for the hovered or focused control, with the selected mode as the default.

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
| **Tab** | Lens |
| **Tab + Ctrl** | Exposure mode |
| **Tab + Alt** | Frame ratio |
| **Tab + Shift** | Film look |

The wheel chords apply with the finder raised. In Studio, **Tab** still navigates controls. **Tab**, **Ctrl**, and **Alt** have fixed roles in the preview’s wheel controls. Use either **Shift** key for the fine-focus binding.

The existing Tab chords can also trigger the leaderboard, Steam overlay, and Windows app switching. Use the bracket keys for lenses and the Studio cards for film and aspect ratio while testing this preview. Changes to binding defaults and game input consumption are awaiting review.

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

## Preview validation

Alpha.2 calibrates the exposure scale to VHOLUME’s baked lighting. In a live Steam session, the default Manual settings measured −0.26 EV in the test scene. Two saved photos at the same aperture and shutter speed confirmed that ISO 200 rendered brighter than ISO 100.

Live checks also covered the Game exposure path, both priority modes, the minimum and maximum Auto ISO limits, and Aperture Priority’s slower shutter at the ISO ceiling. Simulated controller button states exercised Studio navigation, finder activation, exposure adjustments, Auto ISO, capture, and stowing. Physical controller detection and Steam Input mapping remain unverified.

Alpha.3 saved sharp stationary and blurred panning photos at one second, a two-second portrait photo, and a 1/250 s instant photo in a live Steam session. Cancelling a running exposure left no photo or partial file.

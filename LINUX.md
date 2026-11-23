# VHOLUME Photo Camera - Linux / Proton

**1.0.3-rc.2** / Feature parity with the Windows release candidate

This package runs the Windows Steam edition of VHOLUME through Proton. It includes the camera mod, the same UE4SS loader bundled with the Windows release, a Linux installer, a native screenshot-folder helper, and a bundled native Linux DNG converter. Python **3.9 or newer** is required. No root access or PowerShell installation is needed.

**Status:** experimental compatibility build. Automated Ubuntu checks cover installation, rollback, real Proton-style drive symlinks, native file locking, folder-helper protocol, Lua 5.4 integration, launcher cleanup, and archive integrity. [View the Linux QA runs](https://github.com/technicallyalex/vholume-photo-camera/actions/workflows/linux-qa.yml). A live Linux/Steam Deck gameplay session, camera sound playback, physical controller/Steam Input mapping, and desktop GUI integration have not been verified.

## Install

1. Install VHOLUME in Steam and launch it once using Proton, then close it.
2. Extract the Linux ZIP into a folder. Open a terminal there and run:

   ```sh
   python3 install-linux.py
   ```

   Steam's regular installation, additional Steam libraries, and the usual Flatpak Steam location are detected automatically. If no unique installation is found, use the directory shown by **Steam > VHOLUME > Manage > Browse local files**:

   ```sh
   python3 install-linux.py --game-path "/path/to/steamapps/common/VHOLUME"
   ```

3. Copy the **complete launch option printed by the installer** into **Steam > VHOLUME > Properties > General > Launch Options**. It looks like:

   ```text
   python3 '/path/to/VHOLUME/VHOLUME/Binaries/Win64/ue4ss/Mods/VHOLUMEPhotoCamera/Proton/bridge.py' %command%
   ```

   The launcher starts the Linux folder and background DNG helpers and adds `dwmapi=n,b` to `WINEDLLOVERRIDES` while preserving other DLL overrides. Existing launch options should be integrated with this wrapper rather than discarded. This launch option is required for both loading UE4SS and preparing screenshot folders.

4. Start the game normally through Steam. Press **5** for camera mode or **6 / controller View** for Photo Studio; **right-click / LT** raises the finder and **left-click / RT** takes a photo.

Use `--dry-run` to check installation inputs without writing game files. For a custom Proton prefix, pass `--prefix "/path/to/compatdata/4131730/pfx"`. The launcher prefers Steam's `STEAM_COMPAT_DATA_PATH` when it is available.

## Photos and desktop integration

The default photo location is inside VHOLUME's Proton prefix:

```text
<Steam library>/steamapps/compatdata/4131730/pfx/drive_c/users/steamuser/AppData/Local/VHOLUME/Saved/Screenshots/Windows
```

**Studio > Photos > Choose Folder** uses **Zenity** or **KDialog** to select a Linux folder. Install either using your distribution's package manager if neither is available. If both are missing, default-folder captures still work and the menu gives a clear message. **Open Folder** uses `xdg-open` or `gio`. Selected folders are converted through the current Proton prefix's drive mappings, including the usual Z: mapping to the Linux filesystem.

With Flatpak Steam, the game, selected photo directory, desktop tools, and Python must be accessible within Steam's sandbox. The installer does not change Flatpak permissions. Standard desktop Steam is the simplest first test environment.

## Camera controls

The dedicated controller layout and controls using modifier keys and the scroll wheel are shared with Windows. Scroll to focus, **Shift + wheel** for fine focus, **Ctrl + wheel** for aperture, **Alt + wheel** for shutter, and **Ctrl + Alt + wheel** for ISO. Hold **R / T / Y / U** with the wheel for lenses / film / aspect / exposure mode. Letter modifiers are editable in **Studio > Keybinds > Wheel**. Ctrl still reaches the game's slide action.

**LT / RT** raise the finder / shoot. **A / X / B / Y** activate single-shot autofocus / AF-MF / DOF / Studio. D-pad and shoulder combinations adjust the camera. See the [full controls guide](https://github.com/technicallyalex/vholume-photo-camera/blob/main/GUIDE.md) for the complete layout.

Exposure modes, Auto ISO, motion captures, 1x to 8x lens blur, film looks, subject placement, and all seven aspect ratios use the released camera implementation. Camera cues retain the release's synthesized audio; Proton's media playback still needs an in-game check.

## Backups and switching back

Installing over an existing mod moves the entire old mod into a dated **PhotoCamera-backup-...** directory next to `ue4ss/Mods`. Existing UE4SS files and user settings are preserved. To restore, close the game, move the current `VHOLUMEPhotoCamera` folder outside `Mods`, then move the chosen backup into `Mods` and name it `VHOLUMEPhotoCamera`. Remove the Linux launch wrapper if switching back to a package that does not use it.

The installed launch option is also saved in `ue4ss/PhotoCamera-Linux-Launch-Options.txt`. The Windows release retains its original contents and has separate installer and manual downloads on the same release page.

## Capture and RAW parity

This candidate includes the same camera controls, exposure modes, Auto ISO, ISO grain, focus, DOF multiplier, motion exposures, subjects, framing, and output options as Windows. Choose PNG, linear HDR EXR, lossless linear DNG, or any combination. All seven aspect ratios and every output size through 6K/8K are available. Dedicated render is recommended for large photos; temporary game-resolution capture includes the same restoration and failure recovery logic.

An eight-photo disk-backed queue lets you keep shooting after each frame has rendered and exported. The active native converter can finish after the game exits; waiting jobs recover next launch. Each photo retains its own settings. Lowering the finder does not interrupt queued saves. The native Linux converter is compiled from the same open-source C# implementation as Windows and is included in the package; users do not need Wine .NET, a .NET SDK, or Python image packages. The required launch wrapper must remain enabled for folder actions and new DNG jobs.

The camera Lua scripts and assets are identical across platforms except for the two host adapters that launch helpers and handle photo folders. Automated Linux tests cover the actual native converter, exact HDR pixels, metadata, cancellation, duplicate-worker locks, prefix paths, queue recovery, and installation. These checks run without the proprietary game or a GPU; they do not establish live Proton gameplay compatibility.

## Upstream references

- [VHOLUME Steam system requirements](https://store.steampowered.com/app/4131730/VHOLUME/)
- [Valve Proton launch configuration](https://github.com/ValveSoftware/Proton#runtime-config-options)
- [UE4SS installation structure](https://docs.ue4ss.com/dev/installation-guide.html)
- [UE4SS maintainer discussion of Proton DLL overrides](https://github.com/UE4SS-RE/RE-UE4SS/issues/1189)

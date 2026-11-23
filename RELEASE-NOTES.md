# VHOLUME Photo Camera v1.0.3-alpha.5 - Faster background DNG saving

- An exposed frame now saves independently of the viewfinder. Lowering it, stowing the camera, opening Studio, and pausing leave saving active. An unfinished long exposure can still be canceled.
- Faster lossless DNG conversion uses bulk pixel writes, efficient checksums, and up to four compression workers with bounded memory.
- The same 7680 x 7680 HDR input converted in 8.3 seconds versus 49.6 seconds with alpha.4 on the test system, about six times faster. This measures conversion, excluding in-game rendering and HDR export. Timing varies by hardware.
- Fast compression preserves the same HDR pixels and camera metadata. The benchmark file grew from 219 MB to 248 MB; image quality and dynamic range are unchanged.
- Conversion errors still clean up unfinished outputs. Completion no longer accesses a destroyed viewfinder UI after the camera is stowed.

Local Windows preview only; not published. Public Windows and Linux packages remain unchanged. Wait for saving to finish before exiting the game.

This product includes DNG technology under license by Adobe.

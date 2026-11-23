# VHOLUME Photo Camera v1.0.3-alpha.3 - Capture and UI QA preview

- Verified paired PNG + EXR output at 6K and 8K, including 7680 x 5120 and the largest square frame, 7680 x 7680.
- Verified resolution and display-mode restoration after finder cancellation, stowing, pausing, blocked output, allocation failure, and resolution-settling timeout.
- Restore failures remain queued for retry. New captures wait until recovery completes, and matching viewport dimensions alone no longer hide an incorrect display mode.
- Fixed Open Folder: canonical Windows paths, direct Explorer launch, and confirmation from the requested folder window. Error/timeout messages replace premature success notices.
- Unified Studio page headings, spacing, footer buttons, and help text. Photos card selection opens Output Settings; folder actions have explicit buttons.
- Exposure arrows adjust modes and Auto ISO consistently. Keybinds show controller-aware navigation hints. Film text identifies EXR as an ungraded output, and saving feedback names the selected format.
- Reviewed Studio, Output, Exposure, Keybinds, controller hints, and the finder at 1920 x 1080, 1280 x 720, and 960 x 1280.

Dedicated render supports the tested 6K/8K sizes. Temporary 6K/8K game-window requests could not be applied on this setup; they canceled cleanly and restored the original video state. Use Dedicated render for these sizes.

Local Windows preview only; not published. The public Windows and Linux packages remain unchanged. Physical controller hardware and exhaustive fullscreen/multi-monitor combinations were not tested.

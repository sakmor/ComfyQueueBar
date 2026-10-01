# Interface screenshots

`queue-light.png` and `queue-dark.png` are native captures of the same `QueuePopover` SwiftUI view shipped in the app, at its actual 360 × 600 point dimensions (720 × 1200 pixels on the capture machine's Retina display).

The captures use compile-time-only demonstration fixtures: one running job, one waiting job, one completed clip, and 70% progress for a KSampler node. These are illustrative data, not a record of a live generation. No external workflow, user endpoint, or private queue data is included.

Recreate on a Mac with a logged-in graphical session:

```sh
bash scripts/capture-screenshots.sh
```

The capture program renders the panel in an AppKit window, then exports its native bitmap. It uses the real controls and layout, not an AI-generated interface. The `DOCUMENTATION_SCREENSHOT` build excludes HTTP requests, timers, and preference reads. That flag is never enabled by the production build script.

Exact pixel dimensions depend on the Mac display scale. Source images are included under the repository's MIT license.

## macOS desktop context

`desktop-menubar.png` is a cropped native macOS desktop capture taken with `screencapture` on 2026-10-01. `desktop-menubar-annotated.png` adds only a highlight, arrow, and English callout. The desktop wallpaper and menu bar were captured from macOS; they were not generated. Personal windows, filenames, widgets, and screen-sharing details were excluded from the published crop.

The documentation demo displays the real `QueuePopover` view beneath a native `NSStatusItem` with the same template icon and job count used by the production app. Its window wrapper is for documentation capture; the production app uses SwiftUI `MenuBarExtra`. The demonstration job data is fixed, and no server requests are made.

To prepare a similar desktop capture:

```sh
bash scripts/capture-screenshots.sh --desktop-demo
```

Quit an existing production instance first to avoid duplicate icons. Capture the display containing the panel using macOS screenshot controls, or `screencapture -D DISPLAY_NUMBER -x OUTPUT.png`. Display numbering depends on your setup. Review the image and crop out all private content before publishing. Use **Quit** in the demo panel to close it, then reopen the production app.

The system wallpaper, macOS interface elements, and third-party menu bar marks remain the property of their respective owners and appear only as incidental operating-system context. The screenshot is not a redistribution of those assets as standalone brand artwork. The repository's MIT license covers its own code, icon, and added annotations.

The v1.4.0 light/dark captures show the restrained native list design and recent completion history. Connection and automatic update controls now live in the gear popover.

`settings.png` captures the native server and notification settings at 360 × 480 points. The documentation build excludes Sparkle update controls. Public screenshots remain English; localized layouts are checked separately without publishing their captures. Media thumbnails are placeholders in these fixtures because network access is disabled.

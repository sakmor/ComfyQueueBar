# Interface screenshots

`queue-light.png` and `queue-dark.png` are native captures of the same `QueuePopover` SwiftUI view shipped in the app, at its actual 360 × 540 point dimensions (720 × 1080 pixels on the capture machine's Retina display).

The captures use compile-time-only demonstration fixtures: one running job, one waiting job, and 70% progress for a KSampler node. These are illustrative data, not a record of a live generation. No external workflow, user endpoint, or private queue data is included.

Recreate on a Mac with a logged-in graphical session:

```sh
bash scripts/capture-screenshots.sh
```

The capture program renders the panel in an AppKit window, then exports its native bitmap. It uses the real controls and layout, not an AI-generated interface. The `DOCUMENTATION_SCREENSHOT` build excludes HTTP requests, timers, and preference reads. That flag is never enabled by the production build script.

Exact pixel dimensions depend on the Mac display scale. Source images are included under the repository's MIT license.

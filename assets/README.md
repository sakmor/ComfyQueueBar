# Brand assets

`app-icon.png` is the original transparent raster artwork for ComfyQueueBar, created with OpenAI's built-in image generation tool on 2026-10-01 for this project. It is included under the repository's MIT license. No external brand image or ComfyUI logo was used as an input.

The build script derives the macOS `.icns` sizes from this file using `sips` and `iconutil`; the full-color icon is also shown in the panel header. A separate code-drawn template mark uses three queue rows and a separate play marker in the menu bar, where monochrome contrast matters.

## Generation prompt

> Use case: logo-brand. Asset type: macOS application icon for ComfyQueueBar, a native ComfyUI queue monitor. Create one polished 1024x1024 square app icon. A deep indigo rounded-square macOS tile, centered sculptural stack of three floating rounded rectangular queue cards, subtle dimensional soft edges. Rear cards muted lavender; front card luminous cyan with a simple bold white right-facing play triangle and a small green active status dot. Clean understated premium utility design, high contrast and readable at 32 pixels, deliberate simple silhouette, balanced wide padding. Straight-on slight isometric depth, subtle soft studio light. No text, no letters, no numbers, no branding borrowed from other apps, no UI screenshot, no extra objects. Outside the rounded-square tile genuinely transparent.

The returned source is 1254 × 1254 RGBA; the build downsamples it to the required icon sizes and preserves transparency.

# App icon

The app icon uses the same SF Symbol as the normal menu bar icon:
`gauge.with.dots.needle.33percent`.

It is rendered directly with AppKit in monochrome graphite on a transparent
background. `app-icon.png` is the 1024 × 1024 preview; `../Resources/AppIcon.icns`
contains the standard macOS sizes from 16 × 16 through 512 × 512 at 1× and 2×.

Regenerate both files on macOS from the repository root:

```sh
swift Scripts/generate-app-icon.swift
```

`Scripts/build-app.sh` includes the ICNS file in the app bundle.

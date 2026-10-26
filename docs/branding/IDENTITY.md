# VITALIS identity

The new mark replaces the V monogram with a softly squared dialogue loop around a small central core. Its open notch suggests conversation; the enclosed core suggests self-contained local intelligence. It follows the app's clean, minimal teal direction.

Concepts considered: a conversation knot, a sheltered spark and a thought seed. The sheltered-spark direction was selected for its clear silhouette and small-size readability. The image-generation master is checked in at `assets/brand/vitalis-symbol.png`; no third-party logo was used as a reference. This is an original visual direction, not a claim of trademark clearance.

Android exports retain the mark's alpha, use the documented 108dp adaptive canvas and fit the complete symbol into the central 66dp safe area. Foreground and monochrome share the same silhouette; the background is warm off-white. Windows uses the same mark on a rounded backplate with 16–256px ICO frames.

Run `tool/export_brand_icons.ps1` with ImageMagick installed to reproduce launcher exports. It touches only the declared icon assets. The Windows resource is exported when the official Windows runner exists.

Reference: [Android adaptive icon guidance](https://developer.android.com/develop/ui/compose/system/icon_design_adaptive).

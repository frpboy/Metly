# Test font assets

Test-only fonts so golden-image tests render readable text on any machine.
The app itself loads Poppins at runtime via `google_fonts`; these committed
binaries are never shipped in the app.

- `Poppins-Regular.ttf`, `Poppins-SemiBold.ttf` - Poppins by Indian Type
  Foundry, SIL Open Font License 1.1 (`Poppins-OFL.txt`), from
  google/fonts (ofl/poppins).
- `MaterialIcons-Regular.otf` - Material Icons font from the Flutter SDK,
  Apache License 2.0 (`MaterialIcons-LICENSE.txt`).

# Stage Translator Pro

Snap a chord sheet, pick your key, and read every chord in movable-do solfège:
`Bm [la]`, `G [fa]`, `A [so]`, `C [ti♭]`.

## Project layout

```
lib/
  main.dart                      app + theme
  core/                          pure Dart, unit-tested, no Flutter imports
    solfege_engine.dart          chords -> syllables, transposing, key detection
    layout_rebuilder.dart        OCR boxes -> aligned text, two-column sheets
  services/
    ocr_service.dart             ML Kit wrapper (the only ML Kit code)
    pdf_exporter.dart            PDF + native share sheet
  data/
    sheet.dart                   saved-sheet model (JSON)
    library_repository.dart      one JSON file per sheet, offline
  ui/
    library_screen.dart          home: saved sheets, search, delete
    scan_screen.dart             camera + gallery
    review_screen.dart           fix OCR text, confirm keys
    sheet_screen.dart            live sheet: change Doh, edit, save, share
    key_picker.dart, sheet_style.dart
assets/fonts/                    DejaVu Sans Mono + licence
test/
  solfege_engine_test.dart
  layout_rebuilder_test.dart
```

## Setup

You need Flutter 3.24 or newer (`flutter --version`).

1. Create the native shells, then copy these files over them:

   ```bash
   flutter create --org com.yourname stage_translator
   # copy lib/, test/, assets/ and pubspec.yaml from this folder into it
   cd stage_translator
   flutter pub get
   ```

   If `pub get` complains about versions, run
   `flutter pub upgrade --major-versions` to pull the latest compatible ones.
   One thing to know: `share_plus` 11+ renamed `Share.shareXFiles` to
   `SharePlus.instance.share(ShareParams(files: [...]))`. The code here targets 10.x.

2. **Android**: in `android/app/build.gradle` (or `build.gradle.kts`) set
   `minSdk = 24` inside `defaultConfig`.

3. **iOS**: in `ios/Podfile` set `platform :ios, '15.5'`, then add these to
   `ios/Runner/Info.plist`:

   ```xml
   <key>NSCameraUsageDescription</key>
   <string>Used to photograph chord sheets.</string>
   <key>NSPhotoLibraryUsageDescription</key>
   <string>Used to pick a photo of a chord sheet.</string>
   ```

4. Run the tests, then the app on a real phone (ML Kit needs a device or an
   arm64 simulator):

   ```bash
   flutter test
   flutter run
   ```

## How the translation works

- **Doh is always the performance key.** The syllable depends only on a
  chord's distance from Doh, so moving a song changes the letters but never
  the syllables.
- **Two keys.** "Written in" is the sheet's own key (auto-detected, editable).
  "Doh =" is the key you play in. Letters are rewritten into Doh's key:
  a D sheet played with Doh = F# shows `F# [do]  D#m [la]  B [fa]  C# [so]`.
  Turn off *Transpose letters to Doh* to keep the printed letters.
- **Short syllables with sharps and flats.** `do re mi fa so la ti`, plus
  `#` or `♭` for notes outside the scale: in C, F# is `fa#`, Bb is `ti♭`,
  Eb is `mi♭`; in D, a C chord is `ti♭`. The chord's spelling decides,
  so A# in C is `la#` and Bb in C is `ti♭`.
- **Bundled font.** DejaVu Sans Mono (free licence, in `assets/fonts`) is used
  in the app and the PDF because it draws `♭` at the same width as a letter.
- **Only chord lines are touched.** A line is a chord line when at least 60%
  of its words are chords, so lyrics and labels like "BRIDGE 1" stay as they are.
- **Edits survive key changes.** Changing Doh strips the labels, moves the
  letters and labels them again, so hand-typed notes and spacing are kept.

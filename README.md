# Tenter

An Android-first companion for the M-VAVE FM-1 running LOOM-8, with local recording, editable chunk ranges, and USB sample transfer.

## Current prototype

- Record mono 44.1 kHz WAV audio from the phone microphone or stereo 44.1 kHz output from the FM-1 USB audio input.
- Keep audio and sample metadata locally on the device.
- Listen to full recordings and preview individual chunks.
- Define named in/out ranges on each recording; range edits are saved locally.
- Export a full WAV or crop a selected range to a new WAV file; optional peak normalization leaves the source untouched.
- Connect to the FM-1 over USB-MIDI SysEx; sample-bank contents are read only when requested.
- Remove user samples from the instrument (factory entries are protected).
- Select named chunk ranges and append them as LOOM-8 samples while preserving the bank already on the instrument.

The sample cards and editor draw min/max envelopes from the actual WAV frames. USB audio capture requires Android to expose the FM-1 as a USB audio input. The app peak-normalizes each USB take by default; LOOM-8 Setup > USB AUDIO = FULL also avoids the master-knob-dependent recording level. The app sends MIDI Start/Stop (Setup CLOCK must be set to receive). It stops after eight seconds of silence once audio has been heard, with a 30-minute hard limit; set the song's LOOP to off for a single pass. USB transfer and `.loom8` backup/restore still need validation with a physical FM-1/LOOM-8 connection.

## Development

```sh
devenv shell -- flutter pub get
devenv shell -- flutter run
devenv shell -- flutter test
devenv shell -- flutter build apk --debug
```

The devenv Android SDK includes API 34–36 and Build Tools 36.0.0, as required by the current Flutter plugins. `compileSdk` 36 is a build-time requirement; `minSdk` remains 24 (Android 7.0), so this does not require Android 36 on the phone. Record permission is requested when recording starts. The app stores captures in its private application documents directory, so no broad storage permission is needed.

## LOOM-8 integration notes

LOOM-8 exposes sample-bank and project backup operations over USB-MIDI System Exclusive, not ordinary file copy. Its browser implementation is in the upstream project:

- `app/web/samples/loom_samples.js` — WAV conversion and the 32-slot user sample bank format.
- `app/web/backup/extras.js` — sample-bank section used by the `.loom8` backup flow.
- `docs/MANUAL.md` — the Samples and backup instructions.

Connect from the LOOM-8 tab with a USB-C OTG adapter. Connecting checks the MIDI link without downloading sample data; tap **Read sample list** when you want to inspect or remove user entries. Then select chunks in a recording and tap **Send to LOOM-8**. The app reads and preserves the existing sample bank, converts each range to the LOOM-8 IMA ADPCM/checkpoint format, writes the bank over SysEx, and verifies the returned entry count. Removing a user entry shifts later user slot numbers, so back up projects first. Sample flash writes briefly silence the instrument; keep the cable connected until completion. Close other MIDI apps if connection fails.

The Backups tab saves/restores the three projects and presets plus the `LSMP` sample-bank section in a `.loom8` file. Restore replaces projects/presets, waits for confirmation on the FM-1, then restores samples. Older backup files without `LSMP` leave the instrument's current samples alone. USB output capture records the FM-1's stereo master through Android's USB Audio Class input; it is a live recording, not the offline backup renderer from the export webpage.

The code is split by domain under `lib/models`, `lib/data`, `lib/screens`, `lib/services`, `lib/widgets`, `lib/ui`, and `lib/utils`.

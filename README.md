# Tenter

An Android-first companion for the M-VAVE FM-1 running LOOM-8, with local recording, editable chunk ranges, and USB sample transfer.

## Current prototype

- Record mono 44.1 kHz WAV audio from the phone microphone.
- Keep audio and sample metadata locally on the device.
- Listen to full recordings and preview individual chunks.
- Define named in/out ranges on each recording; range edits are saved locally.
- Connect to the FM-1 over USB-MIDI SysEx and list the samples currently in its bank.
- Remove user samples from the instrument (factory entries are protected).
- Select named chunk ranges and append them as LOOM-8 samples while preserving the bank already on the instrument.

The sample cards and editor now draw min/max envelopes from the actual WAV frames. Pulling device samples into the phone library and recording the LOOM-8 audio are not implemented yet. USB transfers and `.loom8` backups build and are tested, but the backup/restore protocol still needs validation with a physical FM-1/LOOM-8 connection.

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

Connect from the LOOM-8 tab with a USB-C OTG adapter; that tab lists the device's current bank and lets you remove user entries. Then select chunks in a recording and tap **Send to LOOM-8**. The app reads and preserves the existing sample bank, converts each range to the LOOM-8 IMA ADPCM/checkpoint format, writes the bank over SysEx, and verifies the returned entry count. Removing a user entry shifts later user slot numbers, so back up projects first. Sample flash writes briefly silence the instrument; keep the cable connected until completion. Close other MIDI apps if connection fails.

The Backups tab saves/restores the three projects and presets plus the `LSMP` sample-bank section in a `.loom8` file. Restore replaces projects/presets, waits for confirmation on the FM-1, then restores samples. Older backup files without `LSMP` leave the instrument's current samples alone. Capturing LOOM-8 USB audio is a separate Android USB Audio Class task; the recorder currently captures the phone's microphone input only.

The code is split by domain under `lib/models`, `lib/data`, `lib/screens`, `lib/services`, `lib/widgets`, `lib/ui`, and `lib/utils`.

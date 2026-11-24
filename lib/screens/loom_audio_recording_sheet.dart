import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../services/loom_midi_service.dart';
import '../services/wav_exporter.dart';
import '../ui/app_theme.dart';
import '../utils/formatters.dart';
import '../widgets/app_components.dart';
import 'recording_sheet.dart';

class LoomAudioRecordSheet extends StatefulWidget {
  const LoomAudioRecordSheet({super.key});

  @override
  State<LoomAudioRecordSheet> createState() => _LoomAudioRecordSheetState();
}

class _LoomAudioRecordSheetState extends State<LoomAudioRecordSheet> {
  static const _silenceStop = Duration(seconds: 8);
  static const _maxTake = Duration(minutes: 30);
  static const _signalThresholdDb = -60.0;

  final AudioRecorder _recorder = AudioRecorder();
  final Stopwatch _clock = Stopwatch();
  Timer? _uiTimer;
  Timer? _maxTimer;
  StreamSubscription<Amplitude>? _amplitudeSubscription;
  List<InputDevice> _usbInputs = const [];
  InputDevice? _selectedDevice;
  DateTime? _lastSignalAt;
  String? _path;
  String? _error;
  int _elapsedMs = 0;
  bool _loadingDevices = true;
  bool _recording = false;
  bool _busy = false;
  bool _finishing = false;
  bool _heardSignal = false;
  bool _normalizeCapture = true;

  @override
  void initState() {
    super.initState();
    _loadUsbInputs();
  }

  @override
  void dispose() {
    _uiTimer?.cancel();
    _maxTimer?.cancel();
    _amplitudeSubscription?.cancel();
    if (_recording) unawaited(_recorder.stop());
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _loadUsbInputs() async {
    setState(() {
      _loadingDevices = true;
      _error = null;
    });
    try {
      final devices = await _recorder.listInputDevices();
      final usbDevices = devices.where(_looksLikeLoomAudio).toList();
      if (!mounted) return;
      setState(() {
        _usbInputs = usbDevices;
        if (_selectedDevice == null ||
            !usbDevices.any((device) => device.id == _selectedDevice!.id)) {
          _selectedDevice = usbDevices.isEmpty ? null : usbDevices.first;
        }
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not list USB audio inputs: $error');
      }
    } finally {
      if (mounted) setState(() => _loadingDevices = false);
    }
  }

  bool _looksLikeLoomAudio(InputDevice device) {
    final label = device.label.toLowerCase();
    return label.contains('usb') ||
        label.contains('loom') ||
        label.contains('fm-1') ||
        label.contains('fm1') ||
        label.contains('m-vave');
  }

  Future<void> _start() async {
    final device = _selectedDevice;
    if (device == null) {
      setState(
        () => _error = 'No LOOM-8 USB audio input is available. Reconnect the FM-1 and refresh devices.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!await _recorder.hasPermission()) {
        throw Exception('Microphone/audio capture permission is required.');
      }
      final directory = await getApplicationDocumentsDirectory();
      final folder = Directory('${directory.path}/samples');
      await folder.create(recursive: true);
      _path =
          '${folder.path}/loom_usb_${DateTime.now().millisecondsSinceEpoch}.wav';
      await _recorder.start(
        RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 44100,
          numChannels: 2,
          device: device,
          autoGain: false,
          echoCancel: false,
          noiseSuppress: false,
        ),
        path: _path!,
      );
      _clock
        ..reset()
        ..start();
      _lastSignalAt = null;
      _heardSignal = false;
      _uiTimer = Timer.periodic(const Duration(milliseconds: 150), (_) {
        if (!mounted) return;
        setState(() => _elapsedMs = _clock.elapsedMilliseconds);
      });
      _maxTimer = Timer(_maxTake, () => _finish(autoStopped: true));
      _amplitudeSubscription = _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 250))
          .listen(
            _monitorLevel,
            onError: (Object error) {
              if (mounted) {
                setState(() => _error = 'Audio level monitor failed: $error');
              }
            },
          );
      setState(() => _recording = true);
      try {
        LoomMidiService.instance.sendTransportStart();
      } catch (error) {
        if (mounted) {
          setState(
            () => _error =
                'Recording started, but MIDI Start was not sent: $error. Start playback on the FM-1 manually.',
          );
        }
      }
    } catch (error) {
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _monitorLevel(Amplitude amplitude) {
    if (!_recording || _finishing) return;
    final now = DateTime.now();
    if (amplitude.current > _signalThresholdDb) {
      _heardSignal = true;
      _lastSignalAt = now;
      return;
    }
    final lastSignal = _lastSignalAt;
    if (_heardSignal &&
        lastSignal != null &&
        now.difference(lastSignal) >= _silenceStop) {
      unawaited(_finish(autoStopped: true));
    }
  }

  Future<void> _finish({bool autoStopped = false}) async {
    if (!_recording || _finishing) return;
    _finishing = true;
    _busy = true;
    if (mounted) setState(() {});
    _uiTimer?.cancel();
    _maxTimer?.cancel();
    await _amplitudeSubscription?.cancel();
    try {
      final path = await _recorder.stop();
      try {
        LoomMidiService.instance.sendTransportStop();
      } catch (_) {
        // The audio take is already stopped; a disconnected MIDI link needs no further action.
      }
      _clock.stop();
      final duration = _clock.elapsedMilliseconds;
      if (path != null && _normalizeCapture) {
        try {
          final normalized = await WavExporter.cropToWav(path: path);
          await File(path).writeAsBytes(normalized, flush: true);
        } catch (error) {
          if (mounted) {
            setState(
              () => _error = 'Recording saved without normalization: $error',
            );
          }
        }
      }
      if (path == null || duration < 250) {
        if (path != null) {
          await File(path).delete().catchError((_) => File(path));
        }
        if (mounted) {
          setState(() {
            _recording = false;
            _busy = false;
            _error = 'The USB recording was too short to keep.';
          });
        }
        return;
      }
      if (mounted) {
        setState(() {
          _recording = false;
          _busy = false;
          _elapsedMs = duration;
        });
        if (autoStopped) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('USB recording stopped automatically.'),
            ),
          );
        }
        Navigator.of(context).pop(RecordedAudio(path, duration));
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _recording = false;
          _busy = false;
          _error = 'Could not save USB audio: $error';
        });
      }
    } finally {
      _finishing = false;
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_recording && !_busy,
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        15,
        20,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.line,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 22),
            const SectionEyebrow('FM-1 USB AUDIO'),
            const SizedBox(height: 9),
            Text(
              _recording ? 'Recording the output…' : 'Capture LOOM-8.',
              style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 7),
            Text(
              _recording
                  ? 'Select PLAY SONG with LOOP off on the FM-1. The app sends MIDI Start/Stop; it auto-stops after ${_silenceStop.inSeconds}s of silence or at the ${_maxTake.inMinutes}-minute safety limit.'
                  : 'Stereo WAV · 44.1 kHz · FM-1 USB audio. Playback start/stop uses MIDI CLOCK=receive.',
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 12,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 18),
            if (_loadingDevices)
              const LinearProgressIndicator(color: AppColors.accent)
            else if (_usbInputs.isEmpty)
              const InfoStrip(
                icon: Icons.usb_off_rounded,
                text: 'Android has not exposed a USB audio input. Reconnect the FM-1 with a USB-C OTG adapter, make sure USB AUDIO is enabled in LOOM-8, then refresh.',
              )
            else ...[
              const Text(
                'INPUT DEVICE',
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<InputDevice>(
                initialValue: _selectedDevice,
                isExpanded: true,
                dropdownColor: AppColors.panelRaised,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppColors.panel,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.line),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.line),
                  ),
                ),
                items: _usbInputs
                    .map(
                      (device) => DropdownMenuItem(
                        value: device,
                        child: Text(
                          device.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: _recording || _busy
                    ? null
                    : (device) => setState(() => _selectedDevice = device),
              ),
            ],
            if (!_recording) ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _normalizeCapture,
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _normalizeCapture = value),
                activeThumbColor: AppColors.accent,
                title: const Text('Normalize captured level'),
                subtitle: const Text(
                  'Peak-normalizes the WAV for playback; the FM-1 is unchanged.',
                  style: TextStyle(color: AppColors.muted, fontSize: 10),
                ),
              ),
              const InfoStrip(
                icon: Icons.volume_up_rounded,
                text: 'LOOM-8 Setup > USB AUDIO may be set to follows MASTER. Choose FULL for a stronger capture; this app can normalize the saved WAV.',
              ),
            ],
            if (_recording) ...[
              const SizedBox(height: 18),
              Center(
                child: Container(
                  height: 100,
                  width: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.record.withValues(alpha: .13),
                    border: Border.all(color: AppColors.record, width: 2),
                  ),
                  child: Center(
                    child: Text(
                      formatDuration(_elapsedMs),
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(color: AppColors.record, fontSize: 12),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy || (!_recording && _usbInputs.isEmpty)
                    ? null
                    : (_recording ? () => _finish() : _start),
                style: FilledButton.styleFrom(
                  backgroundColor: _recording
                      ? AppColors.record
                      : AppColors.accent,
                  foregroundColor: AppColors.ink,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                icon: Icon(
                  _recording
                      ? Icons.stop_rounded
                      : Icons.fiber_manual_record_rounded,
                ),
                label: Text(
                  _busy
                      ? 'PLEASE WAIT…'
                      : (_recording ? 'STOP & SAVE' : 'RECORD USB AUDIO'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    letterSpacing: .7,
                  ),
                ),
              ),
            ),
            if (!_recording)
              Row(
                children: [
                  TextButton(
                    onPressed: _busy ? null : _loadUsbInputs,
                    child: const Text('Refresh inputs'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _busy ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
          ],
        ),
      ),
    ),
  );
}

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../ui/app_theme.dart';
import '../utils/formatters.dart';
import '../widgets/app_components.dart';

class RecordedAudio {
  const RecordedAudio(this.path, this.durationMs);
  final String path;
  final int durationMs;
}

class RecordingSheet extends StatefulWidget {
  const RecordingSheet({super.key});
  @override
  State<RecordingSheet> createState() => _RecordingSheetState();
}

class _RecordingSheetState extends State<RecordingSheet> {
  final AudioRecorder _recorder = AudioRecorder();
  Timer? _timer;
  DateTime? _startedAt;
  String? _path;
  String? _error;
  int _elapsed = 0;
  bool _recording = false;
  bool _busy = false;

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!await _recorder.hasPermission()) {
        throw Exception('Microphone permission is required to record.');
      }
      final directory = await getApplicationDocumentsDirectory();
      final folder = Directory('${directory.path}/samples');
      await folder.create(recursive: true);
      _path =
          '${folder.path}/capture_${DateTime.now().millisecondsSinceEpoch}.wav';
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 44100,
          numChannels: 1,
        ),
        path: _path!,
      );
      _startedAt = DateTime.now();
      _timer = Timer.periodic(const Duration(milliseconds: 150), (_) {
        if (!mounted || _startedAt == null) return;
        setState(
          () =>
              _elapsed = DateTime.now().difference(_startedAt!).inMilliseconds,
        );
      });
      setState(() => _recording = true);
    } catch (error) {
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finish() async {
    if (!_recording) return;
    setState(() => _busy = true);
    _timer?.cancel();
    try {
      final path = await _recorder.stop();
      final duration = _startedAt == null
          ? _elapsed
          : DateTime.now().difference(_startedAt!).inMilliseconds;
      if (path == null || duration < 250) {
        if (path != null) {
          await File(path).delete().catchError((_) => File(path));
        }
        setState(() => _error = 'Recording was too short. Try again.');
      } else {
        if (mounted) {
          Navigator.of(context).pop(RecordedAudio(path, duration));
        }
      }
    } catch (error) {
      setState(() => _error = 'Could not save this recording: $error');
    } finally {
      if (mounted) {
        setState(() {
          _recording = false;
          _busy = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(22, 16, 22, 24 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.line,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(height: 24),
          const SectionEyebrow('LOCAL AUDIO CAPTURE'),
          const SizedBox(height: 12),
          Text(
            _recording ? 'Listening…' : 'Ready when you are.',
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            _recording
                ? 'Keep going. Tap stop when you have it.'
                : 'Mono WAV · 44.1 kHz · saved on this device',
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 28),
          Container(
            height: 118,
            width: 118,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _recording
                  ? const Color(0xFF472B28)
                  : AppColors.mint.withValues(alpha: .1),
              border: Border.all(
                color: _recording
                    ? const Color(0xFFDA7666)
                    : AppColors.mint.withValues(alpha: .35),
                width: 1.5,
              ),
            ),
            child: Center(
              child: _recording
                  ? Text(
                      formatDuration(_elapsed),
                      style: const TextStyle(
                        fontFeatures: [FontFeature.tabularFigures()],
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  : const Icon(
                      Icons.mic_none_rounded,
                      size: 42,
                      color: AppColors.mint,
                    ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFFF8F7F), fontSize: 12),
            ),
          ],
          const SizedBox(height: 26),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _recording
                    ? const Color(0xFFDA7666)
                    : AppColors.mint,
                foregroundColor: AppColors.ink,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: _busy ? null : (_recording ? _finish : _start),
              icon: Icon(
                _recording
                    ? Icons.stop_rounded
                    : Icons.fiber_manual_record_rounded,
              ),
              label: Text(
                _busy
                    ? 'PLEASE WAIT…'
                    : (_recording ? 'STOP & SAVE' : 'START RECORDING'),
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
          if (!_recording)
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Cancel',
                style: TextStyle(color: AppColors.muted),
              ),
            ),
        ],
      ),
    );
  }
}

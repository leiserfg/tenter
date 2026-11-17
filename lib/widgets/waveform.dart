import 'package:flutter/material.dart';

import '../models/sample.dart';
import '../ui/app_theme.dart';
import '../utils/wav_waveform.dart';

class Waveform extends StatefulWidget {
  const Waveform({
    super.key,
    required this.height,
    this.filePath,
    this.chunks = const [],
    this.selectedChunkId,
    this.playhead,
  });

  final double height;
  final String? filePath;
  final List<SampleChunk> chunks;
  final String? selectedChunkId;
  final double? playhead;

  @override
  State<Waveform> createState() => _WaveformState();
}

class _WaveformState extends State<Waveform> {
  late Future<List<WaveformPoint>?> _waveform;

  @override
  void initState() {
    super.initState();
    _waveform = _loadWaveform(widget.filePath);
  }

  @override
  void didUpdateWidget(covariant Waveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.filePath != oldWidget.filePath) {
      _waveform = _loadWaveform(widget.filePath);
    }
  }

  Future<List<WaveformPoint>?> _loadWaveform(String? path) async {
    if (path == null) return null;
    try {
      return await WavWaveform.load(path);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: widget.height,
    width: double.infinity,
    child: FutureBuilder<List<WaveformPoint>?>(
      future: _waveform,
      builder: (context, snapshot) => CustomPaint(
        painter: _WavePainter(
          snapshot.data,
          widget.chunks,
          widget.selectedChunkId,
          widget.playhead,
        ),
      ),
    ),
  );
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.points, this.chunks, this.selectedChunkId, this.playhead)
    : chunksSignature = chunks
          .map((chunk) => '${chunk.id}:${chunk.start}:${chunk.end}')
          .join('|');

  final List<WaveformPoint>? points;
  final List<SampleChunk> chunks;
  final String? selectedChunkId;
  final String chunksSignature;
  final double? playhead;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..strokeCap = StrokeCap.round;
    for (final chunk in chunks) {
      paint.color = chunk.id == selectedChunkId
          ? AppColors.accent.withValues(alpha: .13)
          : AppColors.trackOne.withValues(alpha: .08);
      canvas.drawRect(
        Rect.fromLTRB(
          chunk.start.clamp(0, 1) * size.width,
          0,
          chunk.end.clamp(0, 1) * size.width,
          size.height,
        ),
        paint,
      );
    }

    final waveform = points;
    final center = size.height / 2;
    if (waveform == null || waveform.isEmpty) {
      paint
        ..color = AppColors.muted.withValues(alpha: .35)
        ..strokeWidth = 1;
      canvas.drawLine(Offset(0, center), Offset(size.width, center), paint);
    } else {
      paint.color = AppColors.accent.withValues(alpha: .82);
      paint.strokeWidth = (size.width / waveform.length * .72).clamp(1.0, 4.0);
      for (var i = 0; i < waveform.length; i++) {
        final point = waveform[i];
        final x = (i + .5) * size.width / waveform.length;
        final top = center - point.maximum.clamp(-1.0, 1.0) * center;
        final bottom = center - point.minimum.clamp(-1.0, 1.0) * center;
        if ((bottom - top).abs() < 1) {
          canvas.drawLine(
            Offset(x, center - .5),
            Offset(x, center + .5),
            paint,
          );
        } else {
          canvas.drawLine(Offset(x, top), Offset(x, bottom), paint);
        }
      }
    }

    paint
      ..color = AppColors.trackOne
      ..strokeWidth = 1.4;
    for (final chunk in chunks) {
      for (final boundary in [chunk.start, chunk.end]) {
        final x = boundary.clamp(0, 1) * size.width;
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      }
    }
    if (playhead != null) {
      paint
        ..color = AppColors.paper
        ..strokeWidth = 1.5;
      final x = playhead!.clamp(0, 1) * size.width;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter oldDelegate) =>
      !identical(points, oldDelegate.points) ||
      chunksSignature != oldDelegate.chunksSignature ||
      selectedChunkId != oldDelegate.selectedChunkId ||
      playhead != oldDelegate.playhead;
}

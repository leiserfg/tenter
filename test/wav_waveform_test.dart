import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tenter/utils/wav_waveform.dart';

void main() {
  test('computes the displayed envelope from the WAV samples', () async {
    final directory = await Directory.systemTemp.createTemp('waveform-');
    try {
      final file = File('${directory.path}/envelope.wav');
      await file.writeAsBytes(_makeWav());
      final points = await WavWaveform.load(file.path, bins: 4);

      expect(points, hasLength(4));
      expect(points[0].minimum, 0);
      expect(points[0].maximum, 0);
      expect(points[1].minimum, 0);
      expect(points[1].maximum, 0);
      expect(points[2].maximum, greaterThan(.99));
      expect(points[2].minimum, lessThan(-.99));
      expect(points[3].maximum, greaterThan(.99));
    } finally {
      await directory.delete(recursive: true);
    }
  });
}

Uint8List _makeWav() {
  const sampleRate = 44100;
  const frames = 400;
  final dataBytes = frames * 2;
  final bytes = Uint8List(44 + dataBytes);
  final view = ByteData.sublistView(bytes);
  bytes.setRange(0, 4, 'RIFF'.codeUnits);
  view.setUint32(4, bytes.length - 8, Endian.little);
  bytes.setRange(8, 12, 'WAVE'.codeUnits);
  bytes.setRange(12, 16, 'fmt '.codeUnits);
  view.setUint32(16, 16, Endian.little);
  view.setUint16(20, 1, Endian.little);
  view.setUint16(22, 1, Endian.little);
  view.setUint32(24, sampleRate, Endian.little);
  view.setUint32(28, sampleRate * 2, Endian.little);
  view.setUint16(32, 2, Endian.little);
  view.setUint16(34, 16, Endian.little);
  bytes.setRange(36, 40, 'data'.codeUnits);
  view.setUint32(40, dataBytes, Endian.little);
  for (var i = 200; i < frames; i++) {
    view.setInt16(
      44 + i * 2,
      (18000 * math.sin(i * .15)).round(),
      Endian.little,
    );
  }
  return bytes;
}

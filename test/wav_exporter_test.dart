import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tenter/services/wav_exporter.dart';

void main() {
  test(
    'crops the selected range and normalizes only the exported copy',
    () async {
      final directory = await Directory.systemTemp.createTemp('wav-export-');
      try {
        final source = File('${directory.path}/source.wav');
        await source.writeAsBytes(_makeQuietWav());
        final cropped = await WavExporter.cropToWav(
          path: source.path,
          start: .5,
          end: 1,
        );
        final view = ByteData.sublistView(cropped);
        expect(view.getUint32(40, Endian.little), 100);
        expect(view.getInt16(44, Endian.little), 30000);
        expect(view.getInt16(44 + 2 * 49, Endian.little), 30000);

        final original = await source.readAsBytes();
        expect(
          ByteData.sublistView(original).getInt16(44 + 2 * 50, Endian.little),
          1000,
        );
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );
}

Uint8List _makeQuietWav() {
  const frames = 100;
  const dataLength = frames * 2;
  final bytes = Uint8List(44 + dataLength);
  final view = ByteData.sublistView(bytes);
  bytes.setRange(0, 4, 'RIFF'.codeUnits);
  view.setUint32(4, bytes.length - 8, Endian.little);
  bytes.setRange(8, 12, 'WAVE'.codeUnits);
  bytes.setRange(12, 16, 'fmt '.codeUnits);
  view.setUint32(16, 16, Endian.little);
  view.setUint16(20, 1, Endian.little);
  view.setUint16(22, 1, Endian.little);
  view.setUint32(24, 44100, Endian.little);
  view.setUint32(28, 88200, Endian.little);
  view.setUint16(32, 2, Endian.little);
  view.setUint16(34, 16, Endian.little);
  bytes.setRange(36, 40, 'data'.codeUnits);
  view.setUint32(40, dataLength, Endian.little);
  for (var i = 50; i < frames; i++) {
    view.setInt16(44 + i * 2, 1000, Endian.little);
  }
  return bytes;
}

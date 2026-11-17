import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tenter/models/sample.dart';
import 'package:tenter/services/loom_sample_bank.dart';

void main() {
  group('LOOM-8 sample bank format', () {
    test('7-bit SysEx packing round-trips arbitrary bytes', () {
      final bytes = Uint8List.fromList(
        List<int>.generate(519, (index) => (index * 71 + 129) & 0xff),
      );
      expect(
        LoomSampleBankBuilder.unpack7(LoomSampleBankBuilder.pack7(bytes)),
        bytes,
      );
    });

    test('turns the selected WAV range into a bank sample', () async {
      final directory = await Directory.systemTemp.createTemp('tenter-wav-');
      try {
        final wavFile = File('${directory.path}/recording.wav');
        await wavFile.writeAsBytes(_makePcmWav(4410, 44100));
        final sample = Sample(
          id: 'recording',
          name: 'Room tone',
          path: wavFile.path,
          createdAt: DateTime.utc(2025),
          durationMs: 100,
          chunks: [
            SampleChunk(id: 'middle', name: 'Middle', start: .25, end: .75),
          ],
        );
        final clips = await LoomSampleBankBuilder.clipsFromRecording(
          sample,
          sample.chunks,
        );
        expect(clips.single.name, 'Middle');
        expect(clips.single.samples.length, 2206);
        final bank = LoomSampleBankBuilder.buildBank(newSamples: clips);
        LoomSampleBankBuilder.validateBank(bank);
        expect(LoomSampleBankBuilder.sampleCount(bank), 1);
      } finally {
        await directory.delete(recursive: true);
      }
    });

    test(
      'builds a verifiable v3 bank and appends without dropping old entries',
      () {
        final pcm = Float64List.fromList(
          List<double>.generate(22050, (index) => .45 * math.sin(index * .04)),
        );
        final first = LoomSampleBankBuilder.buildBank(
          newSamples: [
            LoomPcmSource(name: 'Glass tap', samples: pcm, sampleRate: 22050),
          ],
        );
        LoomSampleBankBuilder.validateBank(first);
        expect(LoomSampleBankBuilder.sampleCount(first), 1);
        expect(first[4], 3);

        final second = LoomSampleBankBuilder.buildBank(
          existingImage: first,
          newSamples: [
            LoomPcmSource(name: 'Kick hit', samples: pcm, sampleRate: 22050),
          ],
        );
        LoomSampleBankBuilder.validateBank(second);
        expect(LoomSampleBankBuilder.sampleCount(second), 2);
        String entryName(int offset) => String.fromCharCodes(
          second.sublist(offset, offset + 12).takeWhile((byte) => byte != 0),
        );
        expect(entryName(64), 'glass tap');
        expect(entryName(104), 'kick hit');

        final remaining = LoomSampleBankBuilder.withoutUserSample(second, 1)!;
        final samples = LoomSampleBankBuilder.inspectBank(remaining);
        expect(samples, hasLength(1));
        expect(samples.single.name, 'kick hit');
        expect(samples.single.userSlot, 1);
        expect(LoomSampleBankBuilder.withoutUserSample(remaining, 1), isNull);
      },
    );
  });
}

Uint8List _makePcmWav(int frameCount, int sampleRate) {
  final audioBytes = frameCount * 2;
  final bytes = Uint8List(44 + audioBytes);
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
  view.setUint32(40, audioBytes, Endian.little);
  for (var i = 0; i < frameCount; i++) {
    view.setInt16(
      44 + i * 2,
      (20000 * math.sin(i * .05)).round(),
      Endian.little,
    );
  }
  return bytes;
}

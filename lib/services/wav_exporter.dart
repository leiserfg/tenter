import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

class WavExporter {
  /// Crops a captured PCM16 WAV to a normalized time range and returns a fresh WAV.
  /// Normalization only affects the exported copy, never the saved source recording.
  static Future<Uint8List> cropToWav({
    required String path,
    double start = 0,
    double end = 1,
    bool normalize = true,
  }) async {
    final input = await File(path).readAsBytes();
    if (input.length < 12 ||
        String.fromCharCodes(input.sublist(0, 4)) != 'RIFF' ||
        String.fromCharCodes(input.sublist(8, 12)) != 'WAVE') {
      throw const FormatException('This recording is not a WAV file.');
    }

    final view = ByteData.sublistView(input);
    int? format;
    int? channels;
    int? sampleRate;
    int? bits;
    int? dataOffset;
    int? dataLength;
    var offset = 12;
    while (offset + 8 <= input.length) {
      final id = String.fromCharCodes(input.sublist(offset, offset + 4));
      final length = view.getUint32(offset + 4, Endian.little);
      final body = offset + 8;
      if (body + length > input.length) break;
      if (id == 'fmt ' && length >= 16) {
        format = view.getUint16(body, Endian.little);
        channels = view.getUint16(body + 2, Endian.little);
        sampleRate = view.getUint32(body + 4, Endian.little);
        bits = view.getUint16(body + 14, Endian.little);
        if (format == 0xfffe && length >= 26) {
          format = view.getUint16(body + 24, Endian.little);
        }
      } else if (id == 'data' && dataOffset == null) {
        dataOffset = body;
        dataLength = length;
      }
      offset = body + length + (length & 1);
    }

    if (format != 1 ||
        bits != 16 ||
        channels == null ||
        channels < 1 ||
        sampleRate == null ||
        dataOffset == null ||
        dataLength == null) {
      throw const FormatException(
        'Export currently supports PCM16 WAV recordings.',
      );
    }
    final frameSize = channels * 2;
    final frames = math.min(dataLength, input.length - dataOffset) ~/ frameSize;
    if (frames == 0) throw const FormatException('This WAV contains no audio.');
    final from = (frames * start.clamp(0.0, 1.0)).floor().clamp(0, frames);
    final until = (frames * end.clamp(0.0, 1.0)).ceil().clamp(from, frames);
    if (until <= from) {
      throw const FormatException('Choose a non-empty range to save.');
    }

    final selectedFrames = until - from;
    final dataBytes = selectedFrames * frameSize;
    final samples = Int16List(selectedFrames * channels);
    var peak = 0;
    for (var i = 0; i < samples.length; i++) {
      final sourceOffset = dataOffset + from * frameSize + i * 2;
      final value = view.getInt16(sourceOffset, Endian.little);
      samples[i] = value;
      peak = math.max(peak, value.abs());
    }
    if (normalize && peak >= 64) {
      final gain = 30000 / peak;
      for (var i = 0; i < samples.length; i++) {
        samples[i] = (samples[i] * gain).round().clamp(-32768, 32767);
      }
    }

    final result = Uint8List(44 + dataBytes);
    final out = ByteData.sublistView(result);
    result.setRange(0, 4, 'RIFF'.codeUnits);
    out.setUint32(4, result.length - 8, Endian.little);
    result.setRange(8, 12, 'WAVE'.codeUnits);
    result.setRange(12, 16, 'fmt '.codeUnits);
    out.setUint32(16, 16, Endian.little);
    out.setUint16(20, 1, Endian.little);
    out.setUint16(22, channels, Endian.little);
    out.setUint32(24, sampleRate, Endian.little);
    out.setUint32(28, sampleRate * frameSize, Endian.little);
    out.setUint16(32, frameSize, Endian.little);
    out.setUint16(34, 16, Endian.little);
    result.setRange(36, 40, 'data'.codeUnits);
    out.setUint32(40, dataBytes, Endian.little);
    for (var i = 0; i < samples.length; i++) {
      out.setInt16(44 + i * 2, samples[i], Endian.little);
    }
    return result;
  }
}

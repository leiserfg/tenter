import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

class WaveformPoint {
  const WaveformPoint(this.minimum, this.maximum);

  final double minimum;
  final double maximum;
}

/// Loads a compact min/max envelope from a recording's real WAV frames.
class WavWaveform {
  static final Map<String, Future<List<WaveformPoint>>> _cache = {};

  static Future<List<WaveformPoint>> load(String path, {int bins = 128}) =>
      _cache.putIfAbsent('$path:$bins', () => _read(path, bins: bins));

  static Future<List<WaveformPoint>> _read(
    String path, {
    required int bins,
  }) async {
    final bytes = await File(path).readAsBytes();
    if (bytes.length < 12 ||
        String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF' ||
        String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') {
      throw const FormatException('Not a RIFF/WAVE recording.');
    }

    final view = ByteData.sublistView(bytes);
    int? format;
    int? channels;
    int? sampleRate;
    int? bitsPerSample;
    int? dataOffset;
    int? dataLength;
    var offset = 12;
    while (offset + 8 <= bytes.length) {
      final id = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final length = view.getUint32(offset + 4, Endian.little);
      final body = offset + 8;
      if (body + length > bytes.length) break;
      if (id == 'fmt ' && length >= 16) {
        format = view.getUint16(body, Endian.little);
        channels = view.getUint16(body + 2, Endian.little);
        sampleRate = view.getUint32(body + 4, Endian.little);
        bitsPerSample = view.getUint16(body + 14, Endian.little);
        if (format == 0xfffe && length >= 26) {
          format = view.getUint16(body + 24, Endian.little);
        }
      } else if (id == 'data' && dataOffset == null) {
        dataOffset = body;
        dataLength = length;
      }
      offset = body + length + (length & 1);
    }

    if (format == null ||
        channels == null ||
        sampleRate == null ||
        bitsPerSample == null ||
        dataOffset == null ||
        dataLength == null ||
        channels < 1) {
      throw const FormatException(
        'WAV is missing audio data or format information.',
      );
    }
    final width = bitsPerSample ~/ 8;
    final supportedPcm = format == 1 && [8, 16, 24, 32].contains(bitsPerSample);
    final supportedFloat = format == 3 && [32, 64].contains(bitsPerSample);
    if (width == 0 || (!supportedPcm && !supportedFloat)) {
      throw FormatException(
        'Unsupported WAV format: $bitsPerSample-bit audio.',
      );
    }

    final frameSize = width * channels;
    final frameCount =
        math.min(dataLength, bytes.length - dataOffset) ~/ frameSize;
    if (frameCount == 0) return const [];
    final binCount = math.min(bins, frameCount);
    final mins = List<double>.filled(binCount, double.infinity);
    final maxes = List<double>.filled(binCount, double.negativeInfinity);
    var peak = 0.0;

    for (var frame = 0; frame < frameCount; frame++) {
      var mono = 0.0;
      for (var channel = 0; channel < channels; channel++) {
        final at = dataOffset + frame * frameSize + channel * width;
        mono += _readValue(bytes, view, at, width, bitsPerSample, format);
      }
      mono = (mono / channels).clamp(-1.0, 1.0).toDouble();
      final bin = math.min(binCount - 1, frame * binCount ~/ frameCount);
      if (mono < mins[bin]) mins[bin] = mono;
      if (mono > maxes[bin]) maxes[bin] = mono;
      peak = math.max(peak, mono.abs());
    }

    final scale = peak > 1e-9 ? 1 / peak : 1.0;
    return List<WaveformPoint>.generate(binCount, (index) {
      return WaveformPoint(
        (mins[index] * scale).clamp(-1.0, 1.0).toDouble(),
        (maxes[index] * scale).clamp(-1.0, 1.0).toDouble(),
      );
    }, growable: false);
  }

  static double _readValue(
    Uint8List bytes,
    ByteData view,
    int offset,
    int width,
    int bits,
    int format,
  ) {
    if (format == 3) {
      return bits == 32
          ? view.getFloat32(offset, Endian.little)
          : view.getFloat64(offset, Endian.little);
    }
    if (bits == 8) return (bytes[offset] - 128) / 128;
    if (bits == 16) return view.getInt16(offset, Endian.little) / 32768;
    if (bits == 24) {
      var value =
          bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16);
      if ((value & 0x800000) != 0) value -= 0x1000000;
      return value / 8388608;
    }
    return view.getInt32(offset, Endian.little) / 2147483648;
  }
}

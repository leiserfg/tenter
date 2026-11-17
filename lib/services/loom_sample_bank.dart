import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../models/sample.dart';

class LoomBankSampleInfo {
  const LoomBankSampleInfo({
    required this.name,
    required this.length,
    required this.sampleRate,
    required this.flags,
    required this.userSlot,
  });

  final String name;
  final int length;
  final int sampleRate;
  final int flags;
  final int? userSlot;

  bool get isFactory => userSlot == null;
  double get durationSeconds => length / sampleRate;
}

class LoomPcmSource {
  const LoomPcmSource({
    required this.name,
    required this.samples,
    required this.sampleRate,
    this.rootNote = 60,
    this.loopStart = 0,
    this.loopEnd = 0,
    this.bars = 0,
    this.flags = 0,
  });

  final String name;
  final Float64List samples;
  final int sampleRate;
  final int rootNote;
  final int loopStart;
  final int loopEnd;
  final int bars;
  final int flags;
}

/// Builds the exact LOOM-8 user sample-bank image (LSMP v3) and its SysEx pages.
/// The format and command framing mirror fm1-loom's loom_samples.js/sampleio.py.
class LoomSampleBankBuilder {
  static const int bankHeaderSize = 2048;
  static const int bankSize = 0x1B000 + 0x17000 + 0x4000;
  static const int maxDataSize = bankSize - bankHeaderSize;
  static const int userSlots = 32;
  static const int factorySlots = 12;
  static const int entryStart = 64;
  static const int entrySize = 40;
  static const int bankVersion = 3;
  static const int checkpointBlock = 128;
  static const int bankMagic = 0x504D534C;
  static const List<int> rates = [22050, 16000, 11025];
  static const List<int> _regionSizes = [0x1B000, 0x17000, 0x4000];
  static const List<int> _stepTable = [
    7,
    8,
    9,
    10,
    11,
    12,
    13,
    14,
    16,
    17,
    19,
    21,
    23,
    25,
    28,
    31,
    34,
    37,
    41,
    45,
    50,
    55,
    60,
    66,
    73,
    80,
    88,
    97,
    107,
    118,
    130,
    143,
    157,
    173,
    190,
    209,
    230,
    253,
    279,
    307,
    337,
    371,
    408,
    449,
    494,
    544,
    598,
    658,
    724,
    796,
    876,
    963,
    1060,
    1166,
    1282,
    1411,
    1552,
    1707,
    1878,
    2066,
    2272,
    2499,
    2749,
    3024,
    3327,
    3660,
    4026,
    4428,
    4871,
    5358,
    5894,
    6484,
    7132,
    7845,
    8630,
    9493,
    10442,
    11487,
    12635,
    13899,
    15289,
    16818,
    18500,
    20350,
    22385,
    24623,
    27086,
    29794,
    32767,
  ];
  static const List<int> _indexAdjust = [-1, -1, -1, -1, 2, 4, 6, 8];
  static const List<double> _emphasis = [
    .0517 / 1.0196,
    -.21 / 1.0196,
    1.3362 / 1.0196,
    -.21 / 1.0196,
    .0517 / 1.0196,
  ];

  /// Read a recording and turn each marked range into an independent sample.
  static Future<List<LoomPcmSource>> clipsFromRecording(
    Sample sample,
    List<SampleChunk> chunks,
  ) async {
    if (chunks.isEmpty) {
      throw const FormatException('Select at least one chunk.');
    }
    final wav = _readWav(await _readFile(sample.path));
    final output = <LoomPcmSource>[];
    for (final chunk in chunks) {
      var start = (wav.samples.length * chunk.start).floor();
      var end = (wav.samples.length * chunk.end).ceil();
      start = start.clamp(0, wav.samples.length);
      end = end.clamp(start, wav.samples.length);
      if (end <= start) {
        throw FormatException('${chunk.name} is too short to send.');
      }
      output.add(
        LoomPcmSource(
          name: chunk.name,
          samples: Float64List.fromList(wav.samples.sublist(start, end)),
          sampleRate: wav.sampleRate,
        ),
      );
    }
    return output;
  }

  static Future<Uint8List> _readFile(String path) => File(path).readAsBytes();

  /// Merge new chunk samples with the bank currently on the FM-1.
  /// Existing samples (including LOOM-8 factory entries) are retained byte-for-byte.
  static Uint8List buildBank({
    Uint8List? existingImage,
    required List<LoomPcmSource> newSamples,
  }) {
    final kept = existingImage == null
        ? <_BankEntry>[]
        : _parseBank(existingImage);
    if (newSamples.isEmpty && kept.isEmpty) {
      throw const FormatException('There are no samples to send.');
    }
    final userCount = kept.where((entry) => (entry.flags & 1) == 0).length;
    if (userCount + newSamples.length > userSlots) {
      throw FormatException(
        'The LOOM-8 has $userCount user samples; sending ${newSamples.length} more would exceed its $userSlots user slots. Remove samples on the device first.',
      );
    }

    Object? lastError;
    for (final rate in rates) {
      try {
        final entries = [
          ...kept,
          ...newSamples.map((sample) => _BankEntry.fromPcm(sample, rate)),
        ];
        return _buildAtRate(entries);
      } on _TooLong catch (error) {
        lastError = error;
      }
    }
    throw FormatException(
      'The selected chunks do not fit in the LOOM-8 sample bank, even at 11.025 kHz. ${lastError ?? ''}',
    );
  }

  static List<LoomBankSampleInfo> inspectBank(Uint8List image) {
    final entries = _parseBank(image);
    var userSlot = 0;
    return entries.map((entry) {
      final isFactory = (entry.flags & 1) != 0;
      if (!isFactory) userSlot++;
      return LoomBankSampleInfo(
        name: entry.name,
        length: entry.length,
        sampleRate: entry.sampleRate,
        flags: entry.flags,
        userSlot: isFactory ? null : userSlot,
      );
    }).toList();
  }

  /// Rebuild the bank without a user sample. Returns null when no entries remain.
  static Uint8List? withoutUserSample(Uint8List image, int userSlot) {
    if (userSlot < 1 || userSlot > userSlots) {
      throw RangeError.range(userSlot, 1, userSlots, 'userSlot');
    }
    final entries = _parseBank(image);
    final users = entries.where((entry) => (entry.flags & 1) == 0).toList();
    if (userSlot > users.length) {
      throw StateError('User sample $userSlot does not exist on the LOOM-8.');
    }
    entries.remove(users[userSlot - 1]);
    if (entries.isEmpty) return null;
    return _buildAtRate(entries);
  }

  static Uint8List emptyBank() {
    final header = Uint8List(bankHeaderSize);
    final view = ByteData.sublistView(header);
    view.setUint32(0, bankMagic, Endian.little);
    view.setUint16(4, bankVersion, Endian.little);
    view.setUint32(16, bankSize, Endian.little);
    return header;
  }

  static int sampleCount(Uint8List image) {
    if (image.length < 7) {
      throw const FormatException('Invalid LOOM-8 sample bank.');
    }
    return image[6];
  }

  static int bankDataLength(Uint8List header) {
    if (header.length < 12) {
      throw const FormatException('LOOM-8 returned a short bank header.');
    }
    return ByteData.sublistView(header).getUint32(8, Endian.little);
  }

  static void validateBank(Uint8List image) {
    if (image.length < bankHeaderSize) {
      throw const FormatException('LOOM-8 returned a short sample bank.');
    }
    final data = ByteData.sublistView(image);
    final version = data.getUint16(4, Endian.little);
    final count = image[6];
    final dataLength = data.getUint32(8, Endian.little);
    if (data.getUint32(0, Endian.little) != bankMagic ||
        (version != 2 && version != 3) ||
        count > userSlots + factorySlots ||
        dataLength > maxDataSize ||
        data.getUint32(16, Endian.little) != bankSize ||
        image.length != bankHeaderSize + dataLength) {
      throw const FormatException(
        'LOOM-8 returned an invalid sample-bank header.',
      );
    }
    final actualCrc = crc32(Uint8List.sublistView(image, bankHeaderSize));
    if (actualCrc != data.getUint32(12, Endian.little)) {
      throw const FormatException(
        'The sample bank failed its CRC check. Try reading it again.',
      );
    }
  }

  static List<List<int>> uploadFrames(Uint8List image) {
    validateBank(image);
    final frames = <List<int>>[
      [11, 0],
    ];
    for (var offset = bankHeaderSize; offset < image.length; offset += 256) {
      final end = math.min(offset + 256, image.length);
      frames.add([
        12,
        0,
        offset & 0x7f,
        (offset >> 7) & 0x7f,
        (offset >> 14) & 0x7f,
        ...pack7(Uint8List.sublistView(image, offset, end)),
      ]);
    }
    final header = Uint8List.sublistView(image, 0, bankHeaderSize);
    final usedHeaderBytes = entryStart + (userSlots + factorySlots) * entrySize;
    final partCount = (usedHeaderBytes + 319) ~/ 320;
    for (var part = 0; part < partCount; part++) {
      final start = part * 320;
      final end = math.min(start + 320, bankHeaderSize);
      frames.add([
        16,
        0,
        part,
        ...pack7(Uint8List.sublistView(header, start, end)),
      ]);
    }
    frames.add([13, 0]);
    return frames;
  }

  static Uint8List pack7(Uint8List bytes) {
    final out = <int>[];
    for (var offset = 0; offset < bytes.length; offset += 7) {
      final count = math.min(7, bytes.length - offset);
      var highBits = 0;
      for (var j = 0; j < count; j++) {
        highBits |= ((bytes[offset + j] >> 7) & 1) << j;
      }
      out.add(highBits);
      for (var j = 0; j < count; j++) {
        out.add(bytes[offset + j] & 0x7f);
      }
    }
    return Uint8List.fromList(out);
  }

  static Uint8List unpack7(List<int> bytes) {
    final out = <int>[];
    for (var offset = 0; offset < bytes.length;) {
      final highBits = bytes[offset++];
      for (var bit = 0; bit < 7 && offset < bytes.length; bit++) {
        out.add(bytes[offset++] | (((highBits >> bit) & 1) << 7));
      }
    }
    return Uint8List.fromList(out);
  }

  static int crc32(List<int> bytes) {
    var crc = 0xffffffff;
    for (final byte in bytes) {
      crc ^= byte & 0xff;
      for (var bit = 0; bit < 8; bit++) {
        crc = (crc & 1) == 1 ? 0xedb88320 ^ (crc >> 1) : crc >> 1;
      }
    }
    return (crc ^ 0xffffffff) & 0xffffffff;
  }

  static Uint8List _buildAtRate(List<_BankEntry> entries) {
    final userCount = entries.where((entry) => (entry.flags & 1) == 0).length;
    final factoryCount = entries.length - userCount;
    if (entries.isEmpty ||
        userCount > userSlots ||
        factoryCount > factorySlots) {
      throw const FormatException('The sample bank has too many entries.');
    }
    final blobs = entries.map((entry) => entry.blob()).toList();
    final padding = List<int>.filled(blobs.length, 0);
    late List<_Placement> positions;
    late int end;
    Uint8List image = Uint8List(0);
    for (var attempt = 0; attempt < 4096; attempt++) {
      final placement = _place(blobs, padding);
      positions = placement.positions;
      end = placement.end;
      image = Uint8List(end)..fillRange(0, end, 0xff);
      for (var i = 0; i < blobs.length; i++) {
        image.setRange(
          positions[i].checkpointOffset,
          positions[i].checkpointOffset + blobs[i].checkpoints.length,
          blobs[i].checkpoints,
        );
        image.setRange(
          positions[i].adpcmOffset,
          positions[i].adpcmOffset + blobs[i].adpcm.length,
          blobs[i].adpcm,
        );
      }
      final mark = _findReservedMark(image, end);
      if (mark == null) break;
      var index = -1;
      for (var i = 0; i < positions.length; i++) {
        final position = positions[i];
        if (position.checkpointOffset <= mark &&
            mark < position.adpcmOffset + blobs[i].adpcm.length) {
          index = i;
          break;
        }
      }
      if (index < 0) {
        throw const FormatException(
          'Could not move the reserved flash marker out of the samples.',
        );
      }
      padding[index] += 4;
      if (attempt == 4095) throw const _TooLong();
    }

    final dataBytes = Uint8List.sublistView(image, bankHeaderSize);
    final header = Uint8List(bankHeaderSize);
    final view = ByteData.sublistView(header);
    view.setUint32(0, bankMagic, Endian.little);
    view.setUint16(4, bankVersion, Endian.little);
    header[6] = entries.length;
    header[7] = 0;
    view.setUint32(8, dataBytes.length, Endian.little);
    view.setUint32(12, crc32(dataBytes), Endian.little);
    view.setUint32(16, bankSize, Endian.little);

    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final offset = entryStart + i * entrySize;
      final name = _cleanName(entry.name);
      for (var j = 0; j < name.length; j++) {
        header[offset + j] = name.codeUnitAt(j);
      }
      view.setUint32(offset + 12, positions[i].adpcmOffset, Endian.little);
      view.setUint32(offset + 16, positions[i].checkpointOffset, Endian.little);
      view.setUint32(offset + 20, blobs[i].length, Endian.little);
      view.setUint32(offset + 24, entry.loopStart, Endian.little);
      view.setUint32(offset + 28, entry.loopEnd, Endian.little);
      header[offset + 32] = entry.rootNote.clamp(0, 127);
      header[offset + 33] = entry.flags;
      header[offset + 34] = entry.bars.clamp(0, 16);
      view.setUint16(offset + 36, entry.sampleRate, Endian.little);
    }
    final result = Uint8List(end);
    result.setRange(0, bankHeaderSize, header);
    result.setRange(bankHeaderSize, end, dataBytes);
    return result;
  }

  static List<_BankEntry> _parseBank(Uint8List image) {
    validateBank(image);
    final data = ByteData.sublistView(image);
    final version = data.getUint16(4, Endian.little);
    final count = image[6];
    final entries = <_BankEntry>[];
    for (var i = 0; i < count; i++) {
      final offset = entryStart + i * entrySize;
      var nameEnd = offset;
      while (nameEnd < offset + 12 && image[nameEnd] != 0) {
        nameEnd++;
      }
      final name = String.fromCharCodes(image.sublist(offset, nameEnd));
      final adpcmOffset = data.getUint32(offset + 12, Endian.little);
      final checkpointOffset = data.getUint32(offset + 16, Endian.little);
      final length = data.getUint32(offset + 20, Endian.little);
      final loopStart = data.getUint32(offset + 24, Endian.little);
      final loopEnd = data.getUint32(offset + 28, Endian.little);
      final rootNote = image[offset + 32];
      final flags = image[offset + 33];
      final bars = image[offset + 34];
      final sampleRate = data.getUint16(offset + 36, Endian.little);
      final blockSize = version == 2 ? 64 : checkpointBlock;
      final checkpointLength = ((length + blockSize - 1) ~/ blockSize) * 4;
      final adpcmLength = (length + 1) ~/ 2;
      if (length == 0 ||
          checkpointOffset + checkpointLength > image.length ||
          adpcmOffset + adpcmLength > image.length ||
          sampleRate < 4000 ||
          sampleRate > 48000) {
        throw FormatException(
          'Invalid sample entry "$name" in the device bank.',
        );
      }
      var checkpoints = Uint8List.sublistView(
        image,
        checkpointOffset,
        checkpointOffset + checkpointLength,
      );
      if (version == 2) {
        final converted = Uint8List(
          ((length + checkpointBlock - 1) ~/ checkpointBlock) * 4,
        );
        for (var block = 0; block < converted.length ~/ 4; block++) {
          converted.setRange(block * 4, block * 4 + 4, checkpoints, block * 8);
        }
        checkpoints = converted;
      }
      entries.add(
        _BankEntry.kept(
          name: name,
          length: length,
          checkpoints: checkpoints,
          adpcm: Uint8List.sublistView(
            image,
            adpcmOffset,
            adpcmOffset + adpcmLength,
          ),
          loopStart: loopEnd > loopStart ? loopStart : 0,
          loopEnd: loopEnd > loopStart ? loopEnd : 0,
          rootNote: rootNote,
          flags: flags,
          bars: bars,
          sampleRate: sampleRate,
        ),
      );
    }
    return entries;
  }

  static _PlacementResult _place(List<_SampleBlob> blobs, List<int> padding) {
    final starts = <int>[0];
    for (final size in _regionSizes) {
      starts.add(starts.last + size);
    }
    var cursor = bankHeaderSize;
    final positions = <_Placement>[];
    for (var i = 0; i < blobs.length; i++) {
      final blob = blobs[i];
      cursor = (cursor + padding[i] + 3) & ~3;
      late int checkpointOffset;
      late int adpcmOffset;
      while (true) {
        final checkpointRegion = _regionOf(cursor, starts);
        if (checkpointRegion >= _regionSizes.length) throw const _TooLong();
        if (cursor + blob.checkpoints.length > starts[checkpointRegion + 1]) {
          cursor = starts[checkpointRegion + 1];
          continue;
        }
        adpcmOffset = cursor + blob.checkpoints.length;
        final adpcmRegion = adpcmOffset < bankSize
            ? _regionOf(adpcmOffset, starts)
            : _regionSizes.length;
        final endRegion = math.min(adpcmRegion + 2, starts.length - 1);
        if (adpcmRegion >= _regionSizes.length ||
            adpcmOffset + blob.adpcm.length > starts[endRegion]) {
          if (adpcmRegion + 1 >= _regionSizes.length) throw const _TooLong();
          cursor = starts[adpcmRegion + 1];
          continue;
        }
        checkpointOffset = cursor;
        break;
      }
      positions.add(_Placement(checkpointOffset, adpcmOffset));
      cursor = adpcmOffset + blob.adpcm.length;
    }
    if (cursor > bankSize) throw const _TooLong();
    return _PlacementResult(positions, cursor);
  }

  static int _regionOf(int virtualOffset, List<int> starts) {
    for (var i = 0; i < _regionSizes.length; i++) {
      if (starts[i] <= virtualOffset && virtualOffset < starts[i + 1]) return i;
    }
    return _regionSizes.length;
  }

  static int? _findReservedMark(Uint8List image, int end) {
    final starts = <int>[0];
    for (final size in _regionSizes) {
      starts.add(starts.last + size);
    }
    for (final region in [1, 2]) {
      for (var sector = 0; sector < _regionSizes[region]; sector += 0x1000) {
        final offset = starts[region] + sector + 0xf06;
        if (offset + 2 <= end &&
            image[offset] == 0x41 &&
            image[offset + 1] == 0x54) {
          return offset;
        }
      }
    }
    return null;
  }

  static String _cleanName(String name) {
    final lower = name.toLowerCase().replaceAll('_', ' ');
    final safe = lower.codeUnits
        .where(
          (code) =>
              (code >= 97 && code <= 122) ||
              (code >= 48 && code <= 57) ||
              code == 32 ||
              code == 46 ||
              code == 45,
        )
        .map(String.fromCharCode)
        .join()
        .trim();
    return (safe.isEmpty ? 'sample' : safe).substring(
      0,
      math.min(safe.isEmpty ? 6 : safe.length, 11),
    );
  }

  static Float64List _resample(
    Float64List input,
    int sourceRate,
    int targetRate,
  ) {
    if (sourceRate == targetRate) return input;
    if (input.length <= 1) return Float64List(0);
    var filtered = input;
    if (targetRate < sourceRate) {
      final cutoff = .45 * targetRate / sourceRate;
      final half = (8 / cutoff).ceil();
      final taps = half * 2 + 1;
      final kernel = Float64List(taps);
      var sum = 0.0;
      for (var i = 0; i < taps; i++) {
        final t = i - half;
        final x = 2 * cutoff * t;
        final sinc = x == 0 ? 1.0 : math.sin(math.pi * x) / (math.pi * x);
        final window =
            .42 -
            .5 * math.cos(2 * math.pi * i / (taps - 1)) +
            .08 * math.cos(4 * math.pi * i / (taps - 1));
        kernel[i] = 2 * cutoff * sinc * window;
        sum += kernel[i];
      }
      for (var i = 0; i < taps; i++) {
        kernel[i] /= sum;
      }
      filtered = _convolveSame(input, kernel);
    }
    final outputLength = ((filtered.length - 1) * targetRate / sourceRate)
        .ceil();
    final output = Float64List(outputLength);
    final last = filtered.length - 1;
    for (var i = 0; i < outputLength; i++) {
      final position = i * sourceRate / targetRate;
      final index = position.floor();
      final fraction = position - index;
      output[i] = index >= last
          ? filtered[last]
          : filtered[index] * (1 - fraction) + filtered[index + 1] * fraction;
    }
    return output;
  }

  static Float64List _convolveSame(Float64List input, Float64List kernel) {
    final n = input.length;
    final m = kernel.length;
    final length = math.max(n, m);
    final offset = (math.min(n, m) - 1) ~/ 2;
    final output = Float64List(length);
    for (var i = 0; i < length; i++) {
      final k = i + offset;
      final firstTap = math.max(0, k - n + 1);
      final lastTap = math.min(m - 1, k);
      var value = 0.0;
      for (var tap = firstTap; tap <= lastTap; tap++) {
        value += input[k - tap] * kernel[tap];
      }
      output[i] = value;
    }
    return output;
  }

  static Float64List _emphasize(Float64List input) {
    final output = Float64List(input.length);
    for (var i = 0; i < input.length; i++) {
      var value = 0.0;
      for (var tap = 0; tap < _emphasis.length; tap++) {
        final source = i + 2 - tap;
        if (source >= 0 && source < input.length) {
          value += input[source] * _emphasis[tap];
        }
      }
      output[i] = value;
    }
    return output;
  }

  static Int16List _toInt16(Float64List input) {
    var peak = 1e-9;
    for (final value in input) {
      peak = math.max(peak, value.abs());
    }
    final result = Int16List(input.length);
    for (var i = 0; i < input.length; i++) {
      result[i] = _roundHalfEven(input[i] / peak * 30000).clamp(-32768, 32767);
    }
    return result;
  }

  static int _roundHalfEven(double value) {
    final floor = value.floor();
    final delta = value - floor;
    if (delta < .5) return floor;
    if (delta > .5) return floor + 1;
    return floor.isEven ? floor : floor + 1;
  }

  static _SampleBlob _encodePcm(
    Float64List audio,
    int sourceRate,
    int targetRate,
  ) {
    final samples = _toInt16(
      _emphasize(_resample(audio, sourceRate, targetRate)),
    );
    if (samples.isEmpty) {
      throw const FormatException('A chunk contains no audio samples.');
    }
    var predictor = 0;
    var index = 0;
    final checkpoints = BytesBuilder(copy: false);
    final adpcm = Uint8List((samples.length + 1) ~/ 2);
    for (var i = 0; i < samples.length; i++) {
      if (i % checkpointBlock == 0) {
        final state = (predictor & 0xffff) | (index << 16);
        final bytes = ByteData(4)..setUint32(0, state, Endian.little);
        checkpoints.add(bytes.buffer.asUint8List());
      }
      final step = _stepTable[index];
      var remainder = (samples[i] - predictor).abs();
      var code = samples[i] < predictor ? 8 : 0;
      const bitMasks = [4, 2, 1];
      const shifts = [0, 1, 2];
      for (var bit = 0; bit < 3; bit++) {
        final amount = step >> shifts[bit];
        if (remainder >= amount) {
          code |= bitMasks[bit];
          remainder -= amount;
        }
      }
      adpcm[i >> 1] |= code << (4 * (i & 1));
      var difference = step >> 3;
      if ((code & 4) != 0) difference += step;
      if ((code & 2) != 0) difference += step >> 1;
      if ((code & 1) != 0) difference += step >> 2;
      predictor = (code & 8) != 0
          ? predictor - difference
          : predictor + difference;
      predictor = predictor.clamp(-32768, 32767);
      index = (index + _indexAdjust[code & 7]).clamp(0, 88);
    }
    return _SampleBlob(checkpoints.takeBytes(), adpcm, samples.length);
  }

  static _WavData _readWav(Uint8List bytes) {
    if (bytes.length < 12 ||
        String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF' ||
        String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') {
      throw const FormatException('Recording is not a valid WAV file.');
    }
    final view = ByteData.sublistView(bytes);
    int? format;
    int? channels;
    int? rate;
    int? bits;
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
        rate = view.getUint32(body + 4, Endian.little);
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
    if (format == null ||
        channels == null ||
        rate == null ||
        bits == null ||
        dataOffset == null ||
        dataLength == null ||
        channels < 1 ||
        rate < 4000) {
      throw const FormatException(
        'WAV is missing audio data or format information.',
      );
    }
    final width = bits ~/ 8;
    if (!((format == 1 && [8, 16, 24, 32].contains(bits)) ||
            (format == 3 && bits == 32)) ||
        width == 0) {
      throw FormatException('Unsupported WAV format: $bits-bit audio.');
    }
    final frameSize = width * channels;
    final frameCount =
        math.min(dataLength, bytes.length - dataOffset) ~/ frameSize;
    if (frameCount == 0) {
      throw const FormatException('WAV contains no audio frames.');
    }
    final mono = Float64List(frameCount);
    for (var frame = 0; frame < frameCount; frame++) {
      var mixed = 0.0;
      for (var channel = 0; channel < channels; channel++) {
        final sampleOffset = dataOffset + frame * frameSize + channel * width;
        double value;
        if (format == 3) {
          value = view.getFloat32(sampleOffset, Endian.little);
        } else if (bits == 8) {
          value = (bytes[sampleOffset] - 128) / 128;
        } else if (bits == 16) {
          value = view.getInt16(sampleOffset, Endian.little) / 32768;
        } else if (bits == 24) {
          var raw =
              bytes[sampleOffset] |
              (bytes[sampleOffset + 1] << 8) |
              (bytes[sampleOffset + 2] << 16);
          if ((raw & 0x800000) != 0) raw -= 0x1000000;
          value = raw / 8388608;
        } else {
          value = view.getInt32(sampleOffset, Endian.little) / 2147483648;
        }
        mixed += value;
      }
      mono[frame] = (mixed / channels).clamp(-1.0, 1.0);
    }
    return _WavData(rate, mono);
  }
}

class _WavData {
  const _WavData(this.sampleRate, this.samples);
  final int sampleRate;
  final Float64List samples;
}

class _BankEntry {
  _BankEntry.kept({
    required this.name,
    required this.length,
    required this.checkpoints,
    required this.adpcm,
    required this.loopStart,
    required this.loopEnd,
    required this.rootNote,
    required this.flags,
    required this.bars,
    required this.sampleRate,
  }) : source = null;

  _BankEntry.fromPcm(LoomPcmSource source, this.sampleRate)
    : name = source.name,
      length = 0,
      checkpoints = null,
      adpcm = null,
      loopStart = 0,
      loopEnd = 0,
      rootNote = source.rootNote,
      flags = source.flags,
      bars = source.bars,
      source = source;

  final String name;
  final int length;
  final Uint8List? checkpoints;
  final Uint8List? adpcm;
  final int loopStart;
  final int loopEnd;
  final int rootNote;
  final int flags;
  final int bars;
  final int sampleRate;
  final LoomPcmSource? source;

  _SampleBlob blob() {
    if (source != null) {
      return LoomSampleBankBuilder._encodePcm(
        source!.samples,
        source!.sampleRate,
        sampleRate,
      );
    }
    return _SampleBlob(checkpoints!, adpcm!, length);
  }
}

class _SampleBlob {
  const _SampleBlob(this.checkpoints, this.adpcm, this.length);
  final Uint8List checkpoints;
  final Uint8List adpcm;
  final int length;
}

class _Placement {
  const _Placement(this.checkpointOffset, this.adpcmOffset);
  final int checkpointOffset;
  final int adpcmOffset;
}

class _PlacementResult {
  const _PlacementResult(this.positions, this.end);
  final List<_Placement> positions;
  final int end;
}

class _TooLong implements Exception {
  const _TooLong();

  @override
  String toString() => 'Sample bank capacity exceeded.';
}

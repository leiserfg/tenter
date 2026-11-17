import 'dart:typed_data';

import 'loom_sample_bank.dart';

class LoomBackupSection {
  const LoomBackupSection({required this.tag, required this.data});
  final String tag;
  final Uint8List data;
}

class LoomBackupData {
  const LoomBackupData({
    required this.core,
    required this.flags,
    required this.sections,
  });

  final Uint8List core;
  final int flags;
  final List<LoomBackupSection> sections;

  int get objectCount => ByteData.sublistView(core).getUint16(6, Endian.little);

  LoomBackupSection? get sampleBank {
    for (final section in sections) {
      if (section.tag == 'LSMP') return section;
    }
    return null;
  }

  int get savedObjectBytes {
    var offset = 16;
    var total = 0;
    final view = ByteData.sublistView(core);
    final count = view.getUint16(6, Endian.little);
    for (var i = 0; i < count; i++) {
      final length = view.getUint16(offset + 2, Endian.little);
      total += length;
      offset += 8 + length;
    }
    return total;
  }
}

/// The LOOM-8 .loom8 container and the FM-1 USB backup framing.
class LoomBackupCodec {
  static const String extension = 'loom8';
  static const String magic = 'LM8B';
  static const int version = 1;
  static const int objectCount = 22;
  static const int headerSize = 16;
  static const int recordSize = 8;
  static const int maxObjectBytes = 3840;

  static LoomBackupData parseFile(Uint8List file) {
    if (file.length < headerSize + 4) {
      throw const FormatException(
        'This file is too short to be a LOOM-8 backup.',
      );
    }
    final view = ByteData.sublistView(file);
    if (String.fromCharCodes(file.sublist(0, 4)) != magic) {
      throw const FormatException('This is not a LOOM-8 backup (.loom8).');
    }
    final fileVersion = view.getUint16(4, Endian.little);
    final count = view.getUint16(6, Endian.little);
    final flags = view.getUint32(8, Endian.little);
    if (fileVersion != version || count != objectCount) {
      throw FormatException(
        'Unsupported LOOM-8 backup version $fileVersion ($count objects). This app supports version $version.',
      );
    }
    if (LoomSampleBankBuilder.crc32(Uint8List.sublistView(file, 0, 12)) !=
        view.getUint32(12, Endian.little)) {
      throw const FormatException('The LOOM-8 backup header is damaged.');
    }

    var offset = headerSize;
    for (var index = 0; index < count; index++) {
      if (offset + recordSize > file.length) {
        throw const FormatException('The LOOM-8 backup is cut short.');
      }
      final objectId = view.getUint16(offset, Endian.little);
      final length = view.getUint16(offset + 2, Endian.little);
      final crc = view.getUint32(offset + 4, Endian.little);
      final expectedId = index == 0 ? 1 : index + 1;
      if (objectId != expectedId || length > maxObjectBytes) {
        throw FormatException(
          'Backup object ${index + 1} has an invalid header.',
        );
      }
      offset += recordSize;
      if (offset + length + 4 > file.length) {
        throw FormatException('Backup object $objectId is cut short.');
      }
      final payload = Uint8List.sublistView(file, offset, offset + length);
      if (LoomSampleBankBuilder.crc32(payload) != crc) {
        throw FormatException('Backup object $objectId failed its CRC check.');
      }
      offset += length;
    }
    if (offset + 4 > file.length ||
        LoomSampleBankBuilder.crc32(Uint8List.sublistView(file, 0, offset)) !=
            view.getUint32(offset, Endian.little)) {
      throw const FormatException(
        'The LOOM-8 backup failed its whole-file CRC check.',
      );
    }
    final coreEnd = offset + 4;
    final core = Uint8List.sublistView(file, 0, coreEnd);
    offset = coreEnd;
    final sections = <LoomBackupSection>[];
    while (offset < file.length) {
      if (offset + 8 > file.length) {
        throw const FormatException('A backup section header is cut short.');
      }
      final tag = String.fromCharCodes(file.sublist(offset, offset + 4));
      final length = ByteData.sublistView(file)
          .getUint32(offset + 4, Endian.little);
      offset += 8;
      if (offset + length + 4 > file.length) {
        throw FormatException('The $tag backup section is cut short.');
      }
      final data = Uint8List.sublistView(file, offset, offset + length);
      final crc = ByteData.sublistView(file)
          .getUint32(offset + length, Endian.little);
      if (LoomSampleBankBuilder.crc32(data) != crc) {
        throw FormatException('The $tag backup section failed its CRC check.');
      }
      if (tag == 'LSMP') LoomSampleBankBuilder.validateBank(data);
      sections.add(LoomBackupSection(tag: tag, data: data));
      offset += length + 4;
    }
    if (sections.where((section) => section.tag == 'LSMP').length > 1) {
      throw const FormatException(
        'This backup has more than one sample-bank section.',
      );
    }
    return LoomBackupData(core: core, flags: flags, sections: sections);
  }

  static Uint8List withSampleBank(Uint8List core, Uint8List bank) {
    final parsed = parseFile(core);
    LoomSampleBankBuilder.validateBank(bank);
    final header = Uint8List(8);
    header.setRange(0, 4, 'LSMP'.codeUnits);
    ByteData.sublistView(header).setUint32(4, bank.length, Endian.little);
    final crcBytes = ByteData(4)
      ..setUint32(0, LoomSampleBankBuilder.crc32(bank), Endian.little);
    final result = Uint8List(
      parsed.core.length + header.length + bank.length + 4,
    );
    var offset = 0;
    result.setRange(offset, offset + parsed.core.length, parsed.core);
    offset += parsed.core.length;
    result.setRange(offset, offset + header.length, header);
    offset += header.length;
    result.setRange(offset, offset + bank.length, bank);
    offset += bank.length;
    result.setRange(offset, result.length, crcBytes.buffer.asUint8List());
    return result;
  }

  static Uint8List encodeFrame(int command, List<int> body) {
    var sum = 0;
    for (final value in body) {
      sum += value;
    }
    final raw = [
      0x00,
      0x59,
      command,
      body.length & 0xff,
      (body.length >> 8) & 0xff,
      0,
      ...body,
      (~sum) & 0xff,
    ];
    return Uint8List.fromList([0xf0, ..._pack7(raw), 0xf7]);
  }

  static LoomBackupFrame? parseFrame(List<int> packet) {
    if (packet.length < 2 || packet.first != 0xf0 || packet.last != 0xf7) {
      return null;
    }
    final bytes = _unpack7(packet.sublist(1, packet.length - 1));
    if (bytes.length < 7 || bytes[0] != 0 || bytes[1] != 0x59) return null;
    final length = bytes[3] | (bytes[4] << 8) | (bytes[5] << 16);
    if (length + 7 != bytes.length) return null;
    var sum = 0;
    for (var i = 6; i < 6 + length; i++) {
      sum += bytes[i];
    }
    if (((~sum) & 0xff) != bytes[6 + length]) return null;
    return LoomBackupFrame(bytes[2], bytes.sublist(6, 6 + length));
  }

  static LoomBackupReadRequest? parseReadRequest(List<int> packet) {
    final message = parseFrame(packet);
    if (message == null ||
        message.command != 0x30 ||
        message.body.length != 8) {
      return null;
    }
    final body = message.body;
    final address =
        body[1] | (body[2] << 8) | (body[3] << 16) | (body[4] << 24);
    return LoomBackupReadRequest(
      flags: body[0],
      address: address,
      length: body[5] | (body[6] << 8) | (body[7] << 16),
    );
  }

  static Uint8List encodeBackupReadRequest() =>
      encodeFrame(0x42, 'LM8B'.codeUnits);

  static Uint8List encodeRestoreRequest(Uint8List core) => encodeFrame(0x41, [
    ..._u32(core.length),
    ..._u32(LoomSampleBankBuilder.crc32(core)),
  ]);

  static Uint8List readResponse({
    required int address,
    required int flags,
    required int length,
    required Uint8List data,
  }) {
    final padded = Uint8List(length);
    padded.setRange(0, data.length, data);
    return encodeFrame(0x30, [
      flags,
      ..._u32(address),
      length & 0xff,
      (length >> 8) & 0xff,
      0,
      ...padded,
    ]);
  }

  static int uint32(List<int> bytes, int offset) =>
      (bytes[offset] & 0xff) |
      ((bytes[offset + 1] & 0xff) << 8) |
      ((bytes[offset + 2] & 0xff) << 16) |
      ((bytes[offset + 3] & 0xff) << 24);

  static List<int> _u32(int value) => [
    value & 0xff,
    (value >> 8) & 0xff,
    (value >> 16) & 0xff,
    (value >> 24) & 0xff,
  ];

  static List<int> _pack7(List<int> bytes) {
    final packed = <int>[];
    var accumulator = 0;
    var bits = 0;
    for (final byte in bytes) {
      accumulator |= (byte & 0xff) << bits;
      bits += 8;
      while (bits >= 7) {
        packed.add(accumulator & 0x7f);
        accumulator >>= 7;
        bits -= 7;
      }
    }
    if (bits > 0) packed.add(accumulator & 0x7f);
    return packed;
  }

  static List<int> _unpack7(List<int> bytes) {
    final unpacked = <int>[];
    var accumulator = 0;
    var bits = 0;
    for (final byte in bytes) {
      accumulator |= (byte & 0x7f) << bits;
      bits += 7;
      while (bits >= 8) {
        unpacked.add(accumulator & 0xff);
        accumulator >>= 8;
        bits -= 8;
      }
    }
    return unpacked;
  }
}

class LoomBackupFrame {
  const LoomBackupFrame(this.command, this.body);
  final int command;
  final List<int> body;
}

class LoomBackupReadRequest {
  const LoomBackupReadRequest({
    required this.flags,
    required this.address,
    required this.length,
  });
  final int flags;
  final int address;
  final int length;
}

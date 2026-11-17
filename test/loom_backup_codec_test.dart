import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tenter/services/loom_backup_codec.dart';
import 'package:tenter/services/loom_sample_bank.dart';

void main() {
  group('LOOM-8 backup codec', () {
    test('validates LM8B object data and the LSMP sample section', () {
      final core = _makeCoreBackup();
      final parsedCore = LoomBackupCodec.parseFile(core);
      expect(parsedCore.objectCount, 22);
      expect(parsedCore.savedObjectBytes, 22);

      final fullFile = LoomBackupCodec.withSampleBank(
        core,
        LoomSampleBankBuilder.emptyBank(),
      );
      final parsed = LoomBackupCodec.parseFile(fullFile);
      expect(parsed.sampleBank, isNotNull);
      expect(LoomSampleBankBuilder.sampleCount(parsed.sampleBank!.data), 0);
    });

    test("matches the firmware's packed SysEx framing", () {
      expect(LoomBackupCodec.encodeBackupReadRequest(), [
        0xf0,
        0x00,
        0x32,
        0x09,
        0x22,
        0x00,
        0x00,
        0x00,
        0x26,
        0x4d,
        0x70,
        0x08,
        0x62,
        0x0e,
        0xf7,
      ]);
      expect(
        LoomBackupCodec.readResponse(
          address: 0x1234,
          flags: 0,
          length: 3,
          data: Uint8List.fromList([0x41, 0x80, 0xff]),
        ),
        [
          0xf0,
          0x00,
          0x32,
          0x41,
          0x59,
          0x00,
          0x00,
          0x00,
          0x00,
          0x34,
          0x24,
          0x00,
          0x00,
          0x30,
          0x00,
          0x00,
          0x00,
          0x41,
          0x00,
          0x7e,
          0x37,
          0x0f,
          0xf7,
        ],
      );
    });

    test('round-trips SysEx file and device-read frames', () {
      final frame = LoomBackupCodec.encodeFrame(0x42, [1, 2, 3, 0x80, 0xff]);
      final parsed = LoomBackupCodec.parseFrame(frame);
      expect(parsed?.command, 0x42);
      expect(parsed?.body, [1, 2, 3, 0x80, 0xff]);

      final request = LoomBackupCodec.encodeFrame(0x30, [
        0,
        0x34,
        0x12,
        0,
        0,
        3,
        0,
        0,
      ]);
      final read = LoomBackupCodec.parseReadRequest(request);
      expect(read?.address, 0x1234);
      expect(read?.length, 3);

      final response = LoomBackupCodec.readResponse(
        address: 0x1234,
        flags: 0,
        length: 3,
        data: Uint8List.fromList([0x41, 0x80, 0xff]),
      );
      final decodedResponse = LoomBackupCodec.parseFrame(response);
      expect(decodedResponse?.command, 0x30);
      expect(decodedResponse?.body, [
        0,
        0x34,
        0x12,
        0,
        0,
        3,
        0,
        0,
        0x41,
        0x80,
        0xff,
      ]);
    });
  });
}

Uint8List _makeCoreBackup() {
  final objects = List.generate(22, (i) => [i + 1]);
  var length = 16 + 4;
  for (final payload in objects) {
    length += 8 + payload.length;
  }
  final bytes = Uint8List(length);
  bytes.setRange(0, 4, 'LM8B'.codeUnits);
  final view = ByteData.sublistView(bytes);
  view.setUint16(4, 1, Endian.little);
  view.setUint16(6, objects.length, Endian.little);
  view.setUint32(8, 0, Endian.little);
  view.setUint32(
    12,
    LoomSampleBankBuilder.crc32(Uint8List.sublistView(bytes, 0, 12)),
    Endian.little,
  );
  var offset = 16;
  for (var index = 0; index < objects.length; index++) {
    final payload = Uint8List.fromList(objects[index]);
    view.setUint16(offset, index == 0 ? 1 : index + 1, Endian.little);
    view.setUint16(offset + 2, payload.length, Endian.little);
    view.setUint32(
      offset + 4,
      LoomSampleBankBuilder.crc32(payload),
      Endian.little,
    );
    offset += 8;
    bytes.setRange(offset, offset + payload.length, payload);
    offset += payload.length;
  }
  view.setUint32(
    offset,
    LoomSampleBankBuilder.crc32(Uint8List.sublistView(bytes, 0, offset)),
    Endian.little,
  );
  return bytes;
}

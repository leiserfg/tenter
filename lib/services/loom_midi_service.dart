import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:flutter_midi_command/flutter_midi_command_messages.dart';

import '../models/sample.dart';
import 'loom_backup_codec.dart';
import 'loom_sample_bank.dart';

class LoomMidiService extends ChangeNotifier {
  LoomMidiService._() {
    _midiSubscription = _midi.onMidiDataReceived?.listen(_onMidiData);
  }

  static final LoomMidiService instance = LoomMidiService._();
  static const _sysexHeader = [0x7d, 0x46, 0x4c];
  static final _deviceName = RegExp(
    r'(loom|fm-?1|felucca|composite|sinco|usb-midi)',
    caseSensitive: false,
  );

  final MidiCommand _midi = MidiCommand();
  StreamSubscription<MidiDataReceivedEvent>? _midiSubscription;
  MidiDevice? _device;
  Completer<List<int>>? _pending;
  final Queue<List<int>> _backupPackets = Queue<List<int>>();
  Completer<void>? _backupPacketWaiter;
  int? _pendingCommand;
  bool Function(List<int>)? _pendingMatches;
  bool _connecting = false;
  bool _transferring = false;
  String _status = 'Connect the FM-1 over USB-C OTG.';
  double _progress = 0;
  int? _sampleCount;
  List<LoomBankSampleInfo> _samples = const [];
  bool _samplesLoaded = false;
  bool _loadingSamples = false;
  String? _lastError;

  bool get connected => _device?.connected ?? false;
  bool get connecting => _connecting;
  bool get transferring => _transferring || _loadingSamples;
  String get status => _status;
  String? get deviceName => _device?.name;
  int? get sampleCount => _sampleCount;
  List<LoomBankSampleInfo> get samples => List.unmodifiable(_samples);
  bool get samplesLoaded => _samplesLoaded;
  bool get loadingSamples => _loadingSamples;
  double get progress => _progress;
  String? get lastError => _lastError;

  Future<void> connect() async {
    if (connected) return;
    if (_connecting) return;
    _connecting = true;
    _lastError = null;
    _status = 'Looking for the FM-1…';
    notifyListeners();
    try {
      final devices = await _midi.devices ?? const <MidiDevice>[];
      final candidates =
          devices.where((device) => _deviceName.hasMatch(device.name)).toList()
            ..sort((a, b) {
              final al = a.name.toLowerCase().contains('loom') ? 0 : 1;
              final bl = b.name.toLowerCase().contains('loom') ? 0 : 1;
              return al.compareTo(bl);
            });
      if (candidates.isEmpty) {
        throw StateError(
          'No LOOM-8/FM-1 MIDI device found. Connect it with a USB-C OTG adapter and close other MIDI apps.',
        );
      }

      Object? connectionError;
      for (final candidate in candidates) {
        try {
          _status = 'Opening ${candidate.name}…';
          notifyListeners();
          await _midi.connectToDevice(
            candidate,
            awaitConnectionTimeout: const Duration(seconds: 10),
          );
          _device = candidate;
          final ping = await _request(
            25,
            const [],
            timeout: const Duration(seconds: 2),
          );
          if (ping.isEmpty || ping.first != 0) {
            throw StateError('The MIDI device did not answer the LOOM-8 ping.');
          }
          _samples = const [];
          _sampleCount = null;
          _samplesLoaded = false;
          _status = 'Connected · sample bank not read';
          notifyListeners();
          return;
        } catch (error) {
          connectionError = error;
          if (_device == candidate) _device = null;
          if (candidate.connected) _midi.disconnectDevice(candidate);
        }
      }
      throw StateError(
        connectionError?.toString() ?? 'Could not open the FM-1 MIDI port.',
      );
    } catch (error) {
      _lastError = error.toString().replaceFirst('Bad state: ', '');
      _status = _lastError!;
      rethrow;
    } finally {
      _connecting = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _midiSubscription?.cancel();
    final device = _device;
    if (device != null) {
      _midi.disconnectDevice(device);
    }
    super.dispose();
  }

  void sendTransportStart() => _sendRealtime(0xfa);

  void sendTransportStop() => _sendRealtime(0xfc);

  void _sendRealtime(int status) {
    final device = _device;
    if (device == null || !device.connected) {
      throw StateError('The FM-1 MIDI connection was lost.');
    }
    _midi.sendData(Uint8List.fromList([status]), deviceId: device.id);
  }

  void disconnect() {
    final device = _device;
    _device = null;
    _sampleCount = null;
    _samples = const [];
    _samplesLoaded = false;
    if (device != null) {
      _midi.disconnectDevice(device);
    }
    _status = 'Disconnected';
    _progress = 0;
    _lastError = null;
    notifyListeners();
  }

  Future<void> refreshSamples({bool force = false}) async {
    if (!connected) {
      throw StateError('Connect to LOOM-8 before reading samples.');
    }
    if (_transferring || _loadingSamples) {
      return;
    }
    if (_samplesLoaded && !force) {
      return;
    }

    _loadingSamples = true;
    _lastError = null;
    _progress = 0;
    _status = 'Reading the FM-1 sample bank…';
    notifyListeners();
    try {
      final bank = await _readBank((fraction) {
        _progress = fraction;
        notifyListeners();
      });
      _samples = bank == null
          ? const []
          : LoomSampleBankBuilder.inspectBank(bank);
      _sampleCount = _samples.length;
      _samplesLoaded = true;
      _progress = 1;
      _status = 'Read ${_samples.length} sample-bank entries.';
      notifyListeners();
    } catch (error) {
      _lastError = error.toString().replaceFirst('Bad state: ', '');
      _status = 'Could not read sample bank · $_lastError';
      rethrow;
    } finally {
      _loadingSamples = false;
      notifyListeners();
    }
  }

  Future<void> sendChunks(Sample sample, List<SampleChunk> chunks) async {
    if (!connected) {
      throw StateError('Connect to LOOM-8 before sending chunks.');
    }
    if (_transferring || _loadingSamples) {
      throw StateError('A LOOM-8 data transfer is already running.');
    }
    if (chunks.isEmpty) {
      throw StateError('Select at least one chunk to send.');
    }

    _transferring = true;
    _lastError = null;
    _progress = 0;
    _status = 'Reading the current sample bank…';
    notifyListeners();
    try {
      final existing = await _readBank((fraction) {
        _progress = fraction * .2;
        notifyListeners();
      });
      _status =
          'Preparing ${chunks.length} chunk${chunks.length == 1 ? '' : 's'}…';
      _progress = .22;
      notifyListeners();
      final clips = await LoomSampleBankBuilder.clipsFromRecording(
        sample,
        chunks,
      );
      final bank = LoomSampleBankBuilder.buildBank(
        existingImage: existing,
        newSamples: clips,
      );
      _status = 'Writing sample bank to LOOM-8…';
      notifyListeners();
      await _writeBank(bank);
      _status =
          'Sent ${chunks.length} chunk${chunks.length == 1 ? '' : 's'} to LOOM-8.';
      notifyListeners();
    } catch (error) {
      _lastError = error.toString().replaceFirst('Bad state: ', '');
      _status = 'Transfer failed · $_lastError';
      rethrow;
    } finally {
      _transferring = false;
      notifyListeners();
    }
  }

  Future<void> removeUserSample(int userSlot) async {
    if (!connected) {
      throw StateError('Connect to LOOM-8 before removing samples.');
    }
    if (_transferring || _loadingSamples) {
      throw StateError('A LOOM-8 data transfer is already running.');
    }

    _transferring = true;
    _lastError = null;
    _progress = 0;
    _status = 'Reading the sample bank before removal…';
    notifyListeners();
    try {
      final existing = await _readBank((fraction) {
        _progress = fraction * .2;
        notifyListeners();
      });
      if (existing == null) {
        throw StateError('The LOOM-8 sample bank is empty.');
      }
      final replacement = LoomSampleBankBuilder.withoutUserSample(
        existing,
        userSlot,
      );
      if (replacement == null) {
        _status = 'Erasing the last sample-bank entry…';
        notifyListeners();
        final reply = await _request(14, const [
          0,
        ], timeout: const Duration(seconds: 60));
        if (reply.length < 2 || reply[1] != 0) {
          throw StateError(
            'LOOM-8 could not erase its sample bank (code ${reply.length < 2 ? 99 : reply[1]}).',
          );
        }
        _samples = const [];
        _sampleCount = 0;
      } else {
        _status = 'Removing user sample $userSlot…';
        await _writeBank(replacement);
      }
      _progress = 1;
      _status = 'Removed user sample $userSlot from LOOM-8.';
      notifyListeners();
    } catch (error) {
      _lastError = error.toString().replaceFirst('Bad state: ', '');
      _status = 'Removal failed · $_lastError';
      rethrow;
    } finally {
      _transferring = false;
      notifyListeners();
    }
  }

  Future<Uint8List> createBackup() async {
    if (!connected) throw StateError('Connect to LOOM-8 before backing up.');
    if (_transferring || _loadingSamples) {
      throw StateError('Another LOOM-8 transfer is already running.');
    }

    _transferring = true;
    _lastError = null;
    _progress = 0;
    _status = 'Requesting projects and presets…';
    _backupPackets.clear();
    notifyListeners();
    try {
      _sendBackupPacket(LoomBackupCodec.encodeBackupReadRequest());
      final received = BytesBuilder(copy: false);
      var first = true;
      var lastResponse = DateTime.now();
      while (true) {
        final packet = await _readBackupPacket(
          const Duration(milliseconds: 500),
        );
        if (packet == null) {
          if (!connected) {
            throw StateError('The FM-1 disconnected during backup.');
          }
          final timeout = first ? 3 : 10;
          if (DateTime.now().difference(lastResponse).inSeconds > timeout) {
            throw StateError(
              first
                  ? 'LOOM-8 did not start the backup. Make sure the firmware supports backup.'
                  : 'LOOM-8 stopped sending the backup. Try again.',
            );
          }
          continue;
        }
        final message = LoomBackupCodec.parseFrame(packet);
        if (message == null) continue;
        lastResponse = DateTime.now();
        if (message.command == 0x42 && message.body.length >= 4) {
          final offset = LoomBackupCodec.uint32(message.body, 0);
          if (offset != received.length) {
            throw StateError('A piece of the backup went missing. Try again.');
          }
          received.add(message.body.sublist(4));
          first = false;
          _status = 'Receiving projects and presets · ${received.length} bytes';
          notifyListeners();
        } else if (message.command == 0x43 && message.body.length >= 10) {
          final end = message.body;
          final expectedLength = LoomBackupCodec.uint32(end, 0);
          final expectedCrc = LoomBackupCodec.uint32(end, 4);
          final status = end[8];
          if (status != 0) {
            throw StateError(
              'LOOM-8 could not read its saved data (status $status).',
            );
          }
          final core = received.takeBytes();
          if (core.length != expectedLength ||
              LoomSampleBankBuilder.crc32(core) != expectedCrc) {
            throw StateError('The backup arrived damaged. Try again.');
          }
          LoomBackupCodec.parseFile(core);
          _status = 'Reading the sample bank…';
          _progress = .5;
          notifyListeners();
          final bank =
              await _readBank((fraction) {
                _progress = .5 + fraction * .45;
                notifyListeners();
              }) ??
              LoomSampleBankBuilder.emptyBank();
          _samples = LoomSampleBankBuilder.inspectBank(bank);
          _sampleCount = _samples.length;
          _samplesLoaded = true;
          final file = LoomBackupCodec.withSampleBank(core, bank);
          final parsed = LoomBackupCodec.parseFile(file);
          _status = parsed.flags & 1 != 0
              ? 'Backup ready · instrument was playing, so unsaved changes may be missing.'
              : 'Backup ready to save.';
          _progress = 1;
          notifyListeners();
          return file;
        }
      }
    } catch (error) {
      _lastError = error.toString().replaceFirst('Bad state: ', '');
      _status = 'Backup failed · $_lastError';
      rethrow;
    } finally {
      _transferring = false;
      notifyListeners();
    }
  }

  Future<void> restoreBackup(Uint8List file) async {
    final backup = LoomBackupCodec.parseFile(file);
    if (!connected) throw StateError('Connect to LOOM-8 before restoring.');
    if (_transferring || _loadingSamples) {
      throw StateError('Another LOOM-8 transfer is already running.');
    }

    _transferring = true;
    _lastError = null;
    _progress = 0;
    _status = 'Sending projects and presets…';
    _backupPackets.clear();
    notifyListeners();
    var coreRestored = false;
    try {
      _sendBackupPacket(LoomBackupCodec.encodeRestoreRequest(backup.core));
      var lastResponse = DateTime.now();
      var idleSeconds = 3;
      var completed = false;
      while (!completed) {
        final packet = await _readBackupPacket(
          const Duration(milliseconds: 500),
        );
        if (packet == null) {
          if (!connected) {
            throw StateError('The FM-1 disconnected during restore.');
          }
          if (DateTime.now().difference(lastResponse).inSeconds > idleSeconds) {
            throw StateError(
              'LOOM-8 stopped requesting the backup. Nothing was restored.',
            );
          }
          continue;
        }
        final request = LoomBackupCodec.parseReadRequest(packet);
        if (request == null) continue;
        lastResponse = DateTime.now();
        final addressClass = request.address & 0xff000000;
        if (addressClass == 0xc0000000 ||
            addressClass == 0xc1000000 ||
            addressClass == 0xcf000000) {
          _sendBackupPacket(
            LoomBackupCodec.readResponse(
              address: request.address,
              flags: request.flags,
              length: 8,
              data: Uint8List.fromList('success'.codeUnits + [0]),
            ),
          );
          if (addressClass == 0xc1000000) {
            idleSeconds = 75;
            _progress = 1;
            _status = 'LOOM-8 is asking for confirmation on its screen. Press SEL to restore, or HOME to cancel.';
            notifyListeners();
            continue;
          }
          if (addressClass == 0xcf000000) {
            final code = request.address & 0xffff;
            throw StateError(_restoreError(code));
          }
          completed = true;
          coreRestored = true;
          break;
        }

        if (request.length > 512 || request.address >= backup.core.length) {
          throw StateError(
            'LOOM-8 requested data outside this backup. Nothing was restored.',
          );
        }
        final available = (backup.core.length - request.address)
            .clamp(0, request.length)
            .toInt();
        final data = Uint8List(available);
        data.setRange(0, available, backup.core, request.address);
        _sendBackupPacket(
          LoomBackupCodec.readResponse(
            address: request.address,
            flags: request.flags,
            length: request.length,
            data: data,
          ),
        );
        _progress = (request.address + available) / backup.core.length;
        _status =
            'Sending projects and presets · ${(_progress * 100).round()}%';
        notifyListeners();
      }

      final samples = backup.sampleBank;
      if (samples != null) {
        final count = LoomSampleBankBuilder.sampleCount(samples.data);
        if (count == 0) {
          _status = 'Erasing the sample bank…';
          notifyListeners();
          final reply = await _request(14, const [
            0,
          ], timeout: const Duration(seconds: 60));
          if (reply.length < 2 || reply[1] != 0) {
            throw StateError(
              'The projects and presets were restored, but LOOM-8 could not erase its samples.',
            );
          }
          _samples = const [];
          _sampleCount = 0;
        } else {
          _status = 'Restoring the sample bank…';
          notifyListeners();
          await _writeBank(samples.data);
        }
      }
      _progress = 1;
      _status = samples == null
          ? 'Projects and presets restored. This backup had no sample-bank section; the current samples were left alone.'
          : 'Backup restored, including the sample bank.';
      notifyListeners();
    } catch (error) {
      _lastError = error.toString().replaceFirst('Bad state: ', '');
      _status = coreRestored
          ? 'Projects and presets restored, but the sample bank did not finish: $_lastError'
          : 'Restore failed · $_lastError';
      rethrow;
    } finally {
      _transferring = false;
      notifyListeners();
    }
  }

  String _restoreError(int code) => switch (code) {
    10 => 'LOOM-8 is playing. Stop it and start the restore again. Nothing changed.',
    11 => 'Restore cancelled on the FM-1 screen. Nothing changed.',
    12 => 'LOOM-8 could not finish writing its backup headers. Follow its screen prompt before trying again.',
    3 => 'This backup is for another firmware/version. Nothing changed.',
    _ => 'LOOM-8 rejected the backup (error $code). Nothing changed.',
  };

  void _sendBackupPacket(Uint8List packet) {
    final device = _device;
    if (device == null || !device.connected) {
      throw StateError(
        'The FM-1 MIDI connection was lost. Reconnect and try again.',
      );
    }
    _midi.sendData(packet, deviceId: device.id);
  }

  Future<List<int>?> _readBackupPacket(Duration timeout) async {
    if (_backupPackets.isEmpty) {
      final waiter = Completer<void>();
      _backupPacketWaiter = waiter;
      try {
        await waiter.future.timeout(timeout);
      } on TimeoutException {
        // Poll timeouts let the caller check the MIDI connection and idle timer.
      } finally {
        if (identical(_backupPacketWaiter, waiter)) _backupPacketWaiter = null;
      }
    }
    return _backupPackets.isEmpty ? null : _backupPackets.removeFirst();
  }

  Future<void> _writeBank(Uint8List bank) async {
    final frames = LoomSampleBankBuilder.uploadFrames(bank);
    for (var i = 0; i < frames.length; i++) {
      final frame = frames[i];
      final command = frame.first;
      final args = frame.sublist(1);
      final timeout = switch (command) {
        11 => const Duration(seconds: 10),
        12 => const Duration(seconds: 5),
        13 => const Duration(seconds: 20),
        _ => const Duration(seconds: 3),
      };
      List<int> reply = const [];
      for (var attempt = 1; ; attempt++) {
        try {
          reply = await _request(
            command,
            args,
            timeout: timeout,
            matches: command == 12 ? _writeReplyMatches(args) : null,
          );
          break;
        } catch (_) {
          if (command != 12 || attempt >= 4) rethrow;
          await Future<void>.delayed(const Duration(milliseconds: 350));
        }
      }
      final resultCode = reply.isEmpty ? 99 : reply.last;
      if (resultCode != 0) {
        throw StateError(
          'LOOM-8 rejected a sample-bank write (code $resultCode). The existing bank may be unchanged; read it again before retrying.',
        );
      }
      _progress = .22 + .73 * (i + 1) / frames.length;
      _status = 'Writing sample bank · ${(_progress * 100).round()}%';
      notifyListeners();
    }
    final info = await _request(15, const [0]);
    if (info.length < 6 || info[5] != LoomSampleBankBuilder.sampleCount(bank)) {
      throw StateError(
        'LOOM-8 did not report the expected sample count after transfer.',
      );
    }
    _sampleCount = info[5];
    _samples = LoomSampleBankBuilder.inspectBank(bank);
    _progress = 1;
    notifyListeners();
  }

  Future<Uint8List?> _readBank(void Function(double) onProgress) async {
    final info = await _request(15, const [0]);
    if (info.length < 6 || info[0] != 2) {
      throw StateError('LOOM-8 returned an invalid sample-bank info response.');
    }
    if (info[5] == 0) {
      onProgress(1);
      return null;
    }

    final header = await _readBytes(
      0,
      LoomSampleBankBuilder.bankHeaderSize,
      onProgress,
    );
    final dataLength = LoomSampleBankBuilder.bankDataLength(header);
    if (dataLength > LoomSampleBankBuilder.maxDataSize) {
      throw StateError('The sample bank reports an invalid data length.');
    }
    final data = await _readBytes(
      LoomSampleBankBuilder.bankHeaderSize,
      dataLength,
      (fraction) => onProgress(fraction),
    );
    final image = Uint8List(header.length + data.length)
      ..setRange(0, header.length, header)
      ..setRange(header.length, header.length + data.length, data);
    LoomSampleBankBuilder.validateBank(image);
    onProgress(1);
    return image;
  }

  Future<Uint8List> _readBytes(
    int offset,
    int length,
    void Function(double) onProgress,
  ) async {
    final output = Uint8List(length);
    for (var read = 0; read < length;) {
      final count = (length - read).clamp(0, 224).toInt();
      final address = offset + read;
      final addressBytes = _offsetBytes(address);
      final expected = <int>[0, ...addressBytes];
      List<int> reply = const [];
      Object? lastError;
      for (var attempt = 1; attempt <= 4; attempt++) {
        try {
          reply = await _request(
            17,
            [0, ...addressBytes, count & 0x7f, count >> 7],
            matches: (data) =>
                data.length >= 5 &&
                data[0] == expected[0] &&
                data[1] == expected[1] &&
                data[2] == expected[2] &&
                data[3] == expected[3],
          );
          lastError = null;
          break;
        } catch (error) {
          lastError = error;
          if (attempt < 4) {
            await Future<void>.delayed(const Duration(milliseconds: 200));
          }
        }
      }
      if (lastError != null) throw lastError;
      if (reply.length < 5) {
        throw StateError('Short reply while reading the sample bank.');
      }
      if (reply[4] != 0) {
        throw StateError(
          reply[4] == 4
              ? 'LOOM-8 is currently writing samples; wait for it to finish and try again.'
              : 'LOOM-8 could not read the sample bank (code ${reply[4]}).',
        );
      }
      final decoded = LoomSampleBankBuilder.unpack7(reply.sublist(5));
      if (decoded.length < count) {
        throw StateError('LOOM-8 returned an incomplete sample-bank page.');
      }
      output.setRange(read, read + count, decoded);
      read += count;
      if (length > 0) onProgress(read / length);
    }
    return output;
  }

  Future<List<int>> _request(
    int command,
    List<int> args, {
    Duration timeout = const Duration(seconds: 3),
    bool Function(List<int>)? matches,
  }) async {
    final device = _device;
    if (device == null || !device.connected) {
      throw StateError(
        'The FM-1 MIDI connection was lost. Reconnect and try again.',
      );
    }
    if (_pending != null) {
      throw StateError('A MIDI request is already in progress.');
    }
    final completer = Completer<List<int>>();
    _pending = completer;
    _pendingCommand = command;
    _pendingMatches = matches;
    try {
      _midi.sendData(
        Uint8List.fromList([0xf0, ..._sysexHeader, command, ...args, 0xf7]),
        deviceId: device.id,
      );
      return await completer.future.timeout(timeout);
    } finally {
      if (identical(_pending, completer)) {
        _pending = null;
        _pendingCommand = null;
        _pendingMatches = null;
      }
    }
  }

  void _onMidiData(MidiDataReceivedEvent event) {
    final message = event.message;
    if (message is! SysExMessage) return;
    final raw = message.rawData ?? message.data;
    if (raw.length >= 2 && raw[0] == 0xf0 && raw[1] == 0x00) {
      _backupPackets.add(List<int>.from(raw));
      final waiter = _backupPacketWaiter;
      if (waiter != null && !waiter.isCompleted) waiter.complete();
      return;
    }
    if (raw.length < 6 ||
        raw[0] != 0xf0 ||
        raw[1] != _sysexHeader[0] ||
        raw[2] != _sysexHeader[1] ||
        raw[3] != _sysexHeader[2] ||
        raw.last != 0xf7 ||
        raw[4] != _pendingCommand) {
      return;
    }
    final data = raw.sublist(5, raw.length - 1);
    final completer = _pending;
    if (completer == null || completer.isCompleted) return;
    if (_pendingMatches != null && !_pendingMatches!(data)) return;
    completer.complete(data);
  }

  bool Function(List<int>) _writeReplyMatches(List<int> args) {
    final expected = args.sublist(1, 4);
    return (reply) =>
        reply.length >= 5 &&
        reply[0] == 0 &&
        reply[1] == expected[0] &&
        reply[2] == expected[1] &&
        reply[3] == expected[2];
  }

  static List<int> _offsetBytes(int offset) => [
    offset & 0x7f,
    (offset >> 7) & 0x7f,
    (offset >> 14) & 0x7f,
  ];
}

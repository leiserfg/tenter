import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/loom_midi_service.dart';
import '../services/loom_backup_codec.dart';
import '../services/loom_sample_bank.dart';
import '../ui/app_theme.dart';
import '../widgets/app_components.dart';

class LoomPage extends StatelessWidget {
  const LoomPage({super.key, required this.onOpenSamples});

  final VoidCallback onOpenSamples;

  @override
  Widget build(BuildContext context) {
    final loom = LoomMidiService.instance;
    return AnimatedBuilder(
      animation: loom,
      builder: (context, _) {
        final connected = loom.connected;
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
          children: [
            const SectionEyebrow('HARDWARE CONNECTION'),
            const SizedBox(height: 8),
            const Text(
              'Meet your\nLOOM-8.',
              style: TextStyle(
                fontSize: 35,
                height: 1.05,
                fontWeight: FontWeight.w700,
                letterSpacing: -1.2,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.panel,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color:
                              (connected
                                      ? AppColors.accent
                                      : AppColors.trackOne)
                                  .withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: Icon(
                          connected ? Icons.cable_rounded : Icons.usb_rounded,
                          color: connected
                              ? AppColors.accent
                              : AppColors.trackOne,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              connected
                                  ? 'Connected to ${loom.deviceName ?? 'LOOM-8'}'
                                  : (loom.connecting
                                        ? 'Connecting…'
                                        : 'No device connected'),
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              connected && !loom.connecting
                                  ? '${loom.sampleCount ?? 0} sample-bank entries on the instrument'
                                  : loom.status,
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.circle,
                        color: connected ? AppColors.accent : AppColors.line,
                        size: 10,
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    connected
                        ? 'USB-MIDI SysEx is ready. Chunk transfers preserve the sample bank already on the FM-1 and append the selected ranges.'
                        : 'Connect the FM-1 running LOOM-8 with a USB-C OTG adapter. Keep the instrument in its normal USB/computer mode.',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: loom.connecting || loom.transferring
                          ? null
                          : () async {
                              if (connected) {
                                loom.disconnect();
                              } else {
                                try {
                                  await loom.connect();
                                } catch (_) {
                                  // The service exposes the connection error in this screen.
                                }
                              }
                            },
                      style: FilledButton.styleFrom(
                        backgroundColor: connected
                            ? AppColors.panelRaised
                            : AppColors.accent,
                        foregroundColor: connected
                            ? AppColors.paper
                            : AppColors.ink,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: Icon(
                        loom.connecting
                            ? Icons.sync_rounded
                            : (connected
                                  ? Icons.link_off_rounded
                                  : Icons.link_rounded),
                      ),
                      label: Text(
                        loom.connecting
                            ? 'CONNECTING…'
                            : (connected ? 'DISCONNECT' : 'CONNECT LOOM-8'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          letterSpacing: .8,
                        ),
                      ),
                    ),
                  ),
                  if (connected) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: onOpenSamples,
                        icon: const Icon(Icons.graphic_eq_rounded, size: 18),
                        label: const Text('CHOOSE CHUNKS TO SEND'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.accent,
                          side: const BorderSide(color: AppColors.line),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                      ),
                    ),
                  ],
                  if (loom.connecting || loom.transferring) ...[
                    const SizedBox(height: 18),
                    LinearProgressIndicator(
                      value: loom.progress == 0 ? null : loom.progress,
                      color: AppColors.accent,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      loom.status,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 11,
                      ),
                    ),
                  ] else if (loom.lastError != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      loom.lastError!,
                      style: const TextStyle(
                        color: AppColors.record,
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (connected) ...[
              const SizedBox(height: 22),
              const SectionEyebrow('SAMPLES ON FM-1'),
              const SizedBox(height: 10),
              if (loom.samples.isEmpty)
                const InfoStrip(
                  icon: Icons.info_outline_rounded,
                  text: 'The FM-1 sample bank is empty.',
                )
              else
                for (final sample in loom.samples)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _DeviceSampleTile(
                      sample: sample,
                      onDelete: sample.userSlot == null
                          ? null
                          : () => _confirmRemoveSample(context, loom, sample),
                    ),
                  ),
            ],
            const SizedBox(height: 18),
            const InfoStrip(
              icon: Icons.warning_amber_rounded,
              text: 'LOOM-8 briefly silences audio while writing sample flash. Keep the USB cable connected until the transfer is verified.',
            ),
          ],
        );
      },
    );
  }
}

class _DeviceSampleTile extends StatelessWidget {
  const _DeviceSampleTile({required this.sample, required this.onDelete});

  final LoomBankSampleInfo sample;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
    decoration: BoxDecoration(
      color: AppColors.panel,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.line),
    ),
    child: Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: sample.isFactory
                ? AppColors.trackOne.withValues(alpha: .12)
                : AppColors.accent.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(
            sample.isFactory
                ? Icons.inventory_2_outlined
                : Icons.graphic_eq_rounded,
            size: 18,
            color: sample.isFactory ? AppColors.trackOne : AppColors.accent,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                sample.name,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                sample.isFactory
                    ? 'LOOM-8 FACTORY  ·  ${sample.durationSeconds.toStringAsFixed(1)} s'
                    : 'USER ${sample.userSlot}  ·  ${sample.sampleRate} Hz  ·  ${sample.durationSeconds.toStringAsFixed(1)} s',
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 9,
                  letterSpacing: .3,
                ),
              ),
            ],
          ),
        ),
        if (onDelete != null)
          IconButton(
            tooltip: 'Remove user sample ${sample.userSlot}',
            onPressed: onDelete,
            visualDensity: VisualDensity.compact,
            icon: const Icon(
              Icons.delete_outline_rounded,
              color: AppColors.record,
              size: 19,
            ),
          ),
      ],
    ),
  );
}

Future<void> _confirmRemoveSample(
  BuildContext context,
  LoomMidiService loom,
  LoomBankSampleInfo sample,
) async {
  final slot = sample.userSlot;
  if (slot == null) return;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppColors.panel,
      title: Text('Remove USER $slot?'),
      content: Text(
        'This removes “${sample.name}” from the FM-1 and shifts later user sample slots up. Projects that refer to those slots may play different sounds. Back up your work before continuing.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('CANCEL'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.record,
            foregroundColor: AppColors.ink,
          ),
          child: const Text('REMOVE'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  try {
    await loom.removeUserSample(slot);
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not remove sample: $error')),
      );
    }
  }
}

class BackupPage extends StatefulWidget {
  const BackupPage({super.key});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  bool _fileAction = false;

  Future<void> _saveBackup() async {
    final loom = LoomMidiService.instance;
    if (!loom.connected) {
      _showMessage('Connect to LOOM-8 from the device tab first.');
      return;
    }
    if (_fileAction || loom.transferring) {
      return;
    }
    setState(() => _fileAction = true);
    try {
      late final Uint8List backupBytes;
      final operation = loom.createBackup().then<void>((bytes) {
        backupBytes = bytes;
      });
      await _showProgress(operation, 'Backing up LOOM-8');
      if (!mounted) return;
      final now = DateTime.now();
      final date =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final uri = await FilePicker.saveFile(
        dialogTitle: 'Save LOOM-8 backup',
        fileName: 'loom-8-backup-$date.${LoomBackupCodec.extension}',
        mimeType: 'application/octet-stream',
        bytes: backupBytes,
      );
      if (!mounted) return;
      if (uri == null) {
        _showMessage('Backup was read but not saved to a file.');
      } else {
        _showMessage(
          'Saved LOOM-8 backup: ${uri.pathSegments.isEmpty ? uri : uri.pathSegments.last}',
        );
      }
    } catch (error) {
      if (mounted) _showMessage('Backup failed: $error');
    } finally {
      if (mounted) setState(() => _fileAction = false);
    }
  }

  Future<void> _restoreBackup() async {
    final loom = LoomMidiService.instance;
    if (!loom.connected) {
      _showMessage('Connect to LOOM-8 from the device tab first.');
      return;
    }
    if (_fileAction || loom.transferring) {
      return;
    }
    try {
      final file = await FilePicker.pickFile(
        dialogTitle: 'Choose a LOOM-8 backup',
        type: FileType.custom,
        allowedExtensions: const [LoomBackupCodec.extension],
      );
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      final backup = LoomBackupCodec.parseFile(bytes);
      final bank = backup.sampleBank;
      final bankSummary = bank == null
          ? 'This backup has no sample-bank section; the samples currently on the FM-1 will be left as they are.'
          : '${LoomSampleBankBuilder.sampleCount(bank.data)} sample-bank entries will also be restored.';
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.panel,
          title: const Text('Replace LOOM-8 data?'),
          content: Text(
            'This replaces all three projects and presets on the instrument. $bankSummary Stop the sequencer first. The FM-1 will ask for confirmation on its screen; press SEL to continue or HOME to cancel. ${backup.flags & 1 != 0 ? 'This backup was captured while the instrument was playing, so it may omit unsaved changes.' : ''}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('CANCEL'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.record,
                foregroundColor: AppColors.ink,
              ),
              child: const Text('RESTORE'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      setState(() => _fileAction = true);
      await _showProgress(loom.restoreBackup(bytes), 'Restoring LOOM-8');
      if (mounted) _showMessage('LOOM-8 backup restored.');
    } catch (error) {
      if (mounted) _showMessage('Restore failed: $error');
    } finally {
      if (mounted) setState(() => _fileAction = false);
    }
  }

  Future<void> _showProgress(Future<void> operation, String title) async {
    Object? failure;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => FutureBuilder<void>(
        future: operation,
        builder: (context, snapshot) {
          final complete = snapshot.connectionState == ConnectionState.done;
          if (complete && snapshot.hasError) failure = snapshot.error;
          return PopScope(
            canPop: complete,
            child: AlertDialog(
              backgroundColor: AppColors.panel,
              title: Text(
                complete
                    ? (failure == null ? 'Done' : 'Transfer stopped')
                    : title,
              ),
              content: AnimatedBuilder(
                animation: LoomMidiService.instance,
                builder: (context, _) {
                  final loom = LoomMidiService.instance;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LinearProgressIndicator(
                        value: complete
                            ? (failure == null ? 1 : null)
                            : (loom.progress == 0 ? null : loom.progress),
                        color: AppColors.accent,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        failure?.toString() ?? loom.status,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
                  );
                },
              ),
              actions: complete
                  ? [
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: const Text('CLOSE'),
                      ),
                    ]
                  : null,
            ),
          );
        },
      ),
    );
    if (failure != null) {
      Error.throwWithStackTrace(failure!, StackTrace.current);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String _connectionSubtitle(LoomMidiService loom) {
    if (!loom.connected) return 'Connect from the LOOM-8 tab first.';
    if (loom.transferring) return loom.status;
    return 'Connected to ${loom.deviceName ?? 'LOOM-8'}';
  }

  @override
  Widget build(BuildContext context) {
    final loom = LoomMidiService.instance;
    return AnimatedBuilder(
      animation: loom,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
        children: [
          const SectionEyebrow('KEEP YOUR WORK SAFE'),
          const SizedBox(height: 8),
          const Text(
            'Backups,\nwhen you need them.',
            style: TextStyle(
              fontSize: 34,
              height: 1.05,
              fontWeight: FontWeight.w700,
              letterSpacing: -1.1,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Save or restore the three projects, presets, and sample bank as one .loom8 file.',
            style: TextStyle(color: AppColors.muted, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.panel,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.usb_rounded,
                      color: AppColors.accent,
                      size: 20,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        _connectionSubtitle(loom),
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed:
                        !loom.connected || loom.transferring || _fileAction
                        ? null
                        : _saveBackup,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: AppColors.ink,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.save_alt_rounded),
                    label: const Text(
                      'BACK UP TO .LOOM8',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        letterSpacing: .7,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 9),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed:
                        !loom.connected || loom.transferring || _fileAction
                        ? null
                        : _restoreBackup,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.accent,
                      side: const BorderSide(color: AppColors.line),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    icon: const Icon(Icons.restore_rounded),
                    label: const Text(
                      'RESTORE FROM .LOOM8',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        letterSpacing: .5,
                      ),
                    ),
                  ),
                ),
                if (loom.transferring) ...[
                  const SizedBox(height: 15),
                  LinearProgressIndicator(
                    value: loom.progress == 0 ? null : loom.progress,
                    color: AppColors.accent,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    loom.status,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 11,
                    ),
                  ),
                ] else if (loom.lastError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    loom.lastError!,
                    style: const TextStyle(
                      color: AppColors.record,
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          const InfoStrip(
            icon: Icons.warning_amber_rounded,
            text: 'Restoring replaces all projects and presets. Stop LOOM-8 first, keep the cable connected, and confirm the restore on the FM-1 screen. Sample-bank flash writes briefly silence audio.',
          ),
          const SizedBox(height: 12),
          const InfoStrip(
            icon: Icons.info_outline_rounded,
            text: 'A backup made while the sequencer is playing can omit unsaved changes. Older .loom8 files without an LSMP section leave the current sample bank untouched.',
          ),
        ],
      ),
    );
  }
}

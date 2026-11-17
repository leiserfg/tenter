import 'dart:io';

import 'package:flutter/material.dart';

import '../data/sample_store.dart';
import '../models/sample.dart';
import '../services/loom_midi_service.dart';
import '../ui/app_theme.dart';
import '../utils/formatters.dart';
import '../widgets/app_components.dart';
import '../widgets/waveform.dart';
import 'device_pages.dart';
import 'recording_sheet.dart';
import 'sample_editor.dart';

class CompanionHome extends StatefulWidget {
  const CompanionHome({super.key});

  @override
  State<CompanionHome> createState() => _CompanionHomeState();
}

class _CompanionHomeState extends State<CompanionHome> {
  int _tab = 0;
  List<Sample> _samples = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSamples();
  }

  Future<void> _loadSamples() async {
    final samples = await SampleStore.load();
    if (!mounted) return;
    setState(() {
      _samples = samples;
      _loading = false;
    });
  }

  Future<void> _record() async {
    final result = await showModalBottomSheet<RecordedAudio>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.panel,
      builder: (_) => const RecordingSheet(),
    );
    if (result == null || !mounted) return;
    final sample = Sample(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: 'New recording ${_samples.length + 1}',
      path: result.path,
      createdAt: DateTime.now(),
      durationMs: result.durationMs,
    );
    setState(() => _samples.insert(0, sample));
    await SampleStore.save(_samples);
    if (mounted) _openEditor(sample);
  }

  Future<void> _openEditor(Sample sample) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.panel,
      builder: (_) => SampleEditor(
        sample: sample,
        onChanged: () async {
          await SampleStore.save(_samples);
          if (mounted) setState(() {});
        },
        onDelete: () async {
          setState(() => _samples.removeWhere((item) => item.id == sample.id));
          await File(sample.path).delete().catchError((_) => File(sample.path));
          await SampleStore.save(_samples);
          if (mounted) Navigator.of(context).pop();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _samplesPage(),
      LoomPage(onOpenSamples: () => setState(() => _tab = 0)),
      const BackupPage(),
    ];
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(tab: _tab),
            Expanded(child: pages[_tab]),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: AppColors.ink,
        indicatorColor: AppColors.accent.withValues(alpha: .13),
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.graphic_eq_rounded),
            label: 'Samples',
          ),
          NavigationDestination(icon: Icon(Icons.usb_rounded), label: 'LOOM-8'),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            label: 'Backups',
          ),
        ],
      ),
      floatingActionButton: _tab == 0
          ? FloatingActionButton.extended(
              onPressed: _record,
              backgroundColor: AppColors.accent,
              foregroundColor: AppColors.ink,
              icon: const Icon(Icons.fiber_manual_record_rounded, size: 18),
              label: const Text(
                'RECORD',
                style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1),
              ),
            )
          : null,
    );
  }

  Widget _samplesPage() {
    return _loading
        ? const Center(
            child: CircularProgressIndicator(color: AppColors.accent),
          )
        : ListView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 110),
            children: [
              const SectionEyebrow('YOUR FIELD RECORDER'),
              const SizedBox(height: 8),
              Text(
                _samples.isEmpty
                    ? 'Catch a sound.'
                    : 'A bank of\nsmall moments.',
                style: const TextStyle(
                  fontSize: 35,
                  height: 1.05,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1.2,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _samples.isEmpty
                    ? 'Record a sound, then mark the parts you want to keep.'
                    : '${_samples.length.toString().padLeft(2, '0')} LOCAL ${_samples.length == 1 ? 'SAMPLE' : 'SAMPLES'}  ·  STORED ON THIS DEVICE',
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 12,
                  letterSpacing: .8,
                ),
              ),
              const SizedBox(height: 24),
              if (_samples.isEmpty)
                const _EmptyLibrary()
              else ...[
                const SectionEyebrow('RECENT CAPTURES'),
                const SizedBox(height: 10),
                for (final sample in _samples)
                  Padding(
                    key: ValueKey('sample-${sample.id}'),
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _SampleCard(
                      sample: sample,
                      onTap: () => _openEditor(sample),
                    ),
                  ),
              ],
              const SizedBox(height: 22),
              const InfoStrip(
                icon: Icons.lightbulb_outline_rounded,
                text: 'Chunk ranges are saved with each recording. They stay local until you export or transfer them.',
              ),
            ],
          );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.tab});
  final int tab;

  @override
  Widget build(BuildContext context) {
    final titles = ['TENTER', 'DEVICE LINK', 'BACKUP & RESTORE'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.trackOne,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Center(
              child: Text(
                'T8',
                style: TextStyle(
                  color: AppColors.ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -.5,
                ),
              ),
            ),
          ),
          const SizedBox(width: 11),
          Text(
            titles[tab],
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
          const Spacer(),
          AnimatedBuilder(
            animation: LoomMidiService.instance,
            builder: (context, _) {
              final connected = LoomMidiService.instance.connected;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.line),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.circle,
                      size: 7,
                      color: connected ? AppColors.accent : AppColors.trackOne,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      connected ? 'LOOM ONLINE' : 'OFFLINE',
                      style: TextStyle(
                        fontSize: 9,
                        letterSpacing: 1.1,
                        color: connected ? AppColors.accent : AppColors.muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
    decoration: BoxDecoration(
      color: AppColors.panel,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppColors.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Waveform(height: 76),
        const SizedBox(height: 18),
        const Text(
          'The first sound is yours.',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 7),
        const Text(
          'Capture a room tone, a phrase, or a happy accident. Your audio and marked ranges are kept on this phone.',
          style: TextStyle(color: AppColors.muted, height: 1.45, fontSize: 13),
        ),
        const SizedBox(height: 16),
        const Row(
          children: [
            Icon(Icons.lock_outline_rounded, size: 14, color: AppColors.accent),
            SizedBox(width: 6),
            Text(
              'PRIVATE BY DEFAULT',
              style: TextStyle(
                color: AppColors.accent,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _SampleCard extends StatelessWidget {
  const _SampleCard({required this.sample, required this.onTap});
  final Sample sample;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.panel,
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(
                    Icons.graphic_eq_rounded,
                    color: AppColors.accent,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sample.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${formatDuration(sample.durationMs)}  ·  ${formatDate(sample.createdAt)}',
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${sample.chunks.length} CHUNK${sample.chunks.length == 1 ? '' : 'S'}',
                  style: const TextStyle(
                    color: AppColors.accent,
                    fontWeight: FontWeight.w800,
                    fontSize: 9,
                    letterSpacing: .7,
                  ),
                ),
                const SizedBox(width: 5),
                const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
              ],
            ),
            const SizedBox(height: 10),
            Waveform(filePath: sample.path, height: 36, chunks: sample.chunks),
          ],
        ),
      ),
    ),
  );
}

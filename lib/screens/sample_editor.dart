import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../models/sample.dart';
import '../services/loom_midi_service.dart';
import '../ui/app_theme.dart';
import '../utils/formatters.dart';
import '../services/wav_exporter.dart';
import '../widgets/app_components.dart';
import '../widgets/waveform.dart';

class SampleEditor extends StatefulWidget {
  const SampleEditor({
    super.key,
    required this.sample,
    required this.onChanged,
    required this.onDelete,
  });
  final Sample sample;
  final Future<void> Function() onChanged;
  final Future<void> Function() onDelete;

  @override
  State<SampleEditor> createState() => _SampleEditorState();
}

class _SampleEditorState extends State<SampleEditor> {
  late final TextEditingController _nameController = TextEditingController(
    text: widget.sample.name,
  );
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration?>? _durationSubscription;
  StreamSubscription<PlayerState>? _playerStateSubscription;
  Timer? _rangeTimer;
  Timer? _saveDebounce;
  double _playhead = 0;
  String? _activeChunkId;
  final Set<String> _selectedChunkIds = {};
  int? _rangeEndMs;
  bool _loaded = false;
  bool _playing = false;
  String? _playbackError;
  bool _normalizeExport = true;
  bool _exporting = false;

  int get _timelineDurationMs =>
      _player.duration?.inMilliseconds ?? widget.sample.durationMs;

  SampleChunk? get _activeChunk {
    for (final chunk in widget.sample.chunks) {
      if (chunk.id == _activeChunkId) return chunk;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    if (widget.sample.chunks.isNotEmpty) {
      _activeChunkId = widget.sample.chunks.first.id;
    }
    _positionSubscription = _player.positionStream.listen((position) {
      if (!mounted) return;
      final duration = _timelineDurationMs;
      if (duration <= 0) return;
      setState(
        () => _playhead = (position.inMilliseconds / duration).clamp(0.0, 1.0),
      );
    });
    _durationSubscription = _player.durationStream.listen((_) {
      if (mounted) setState(() {});
    });
    _playerStateSubscription = _player.playerStateStream.listen((state) {
      if (mounted) setState(() => _playing = state.playing);
    });
    unawaited(_loadAudioDuration());
  }

  @override
  void dispose() {
    _rangeTimer?.cancel();
    _saveDebounce?.cancel();
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _playerStateSubscription?.cancel();
    _player.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _ensurePlayerReady() async {
    if (_loaded) return;
    await _player.setFilePath(widget.sample.path);
    _loaded = true;
  }

  Future<void> _loadAudioDuration() async {
    try {
      await _ensurePlayerReady();
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) {
        setState(() => _playbackError = 'Could not load recording: $error');
      }
    }
  }

  void _startPlayback() {
    unawaited(
      _player.play().catchError((Object error) {
        if (mounted) {
          setState(() => _playbackError = 'Could not play audio: $error');
        }
      }),
    );
  }

  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 350), () {
      unawaited(widget.onChanged());
    });
  }

  Future<void> _saveName() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    _saveDebounce?.cancel();
    widget.sample.name = name;
    _nameController.value = _nameController.value.copyWith(
      text: name,
      selection: TextSelection.collapsed(offset: name.length),
    );
    await widget.onChanged();
  }

  Future<void> _saveWav({SampleChunk? chunk}) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final wav = await WavExporter.cropToWav(
        path: widget.sample.path,
        start: chunk?.start ?? 0,
        end: chunk?.end ?? 1,
        normalize: _normalizeExport,
      );
      final baseName = (chunk?.name ?? widget.sample.name)
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9._-]+'), '-')
          .replaceAll(RegExp(r'^-+|-+$'), '');
      final uri = await FilePicker.saveFile(
        dialogTitle: 'Save WAV recording',
        fileName: '${baseName.isEmpty ? 'loom-recording' : baseName}.wav',
        mimeType: 'audio/wav',
        bytes: wav,
      );
      if (!mounted) return;
      if (uri == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('WAV export cancelled.')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Saved WAV: ${uri.pathSegments.isEmpty ? uri : uri.pathSegments.last}',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not export WAV: $error')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _saveChunkName(SampleChunk chunk, String value) async {
    _saveDebounce?.cancel();
    final name = value.trim();
    if (name.isNotEmpty) chunk.name = name;
    await widget.onChanged();
    if (mounted) setState(() {});
  }

  Future<void> _playAll() async {
    try {
      final requestedFraction = _playhead;
      await _ensurePlayerReady();
      _rangeTimer?.cancel();
      _rangeEndMs = null;
      final startMs = requestedFraction >= .999
          ? 0
          : (_timelineDurationMs * requestedFraction).round();
      await _player.seek(Duration(milliseconds: startMs));
      _startPlayback();
    } catch (error) {
      if (mounted) {
        setState(() => _playbackError = 'Could not play audio: $error');
      }
    }
  }

  Future<void> _playChunk(SampleChunk chunk) async {
    try {
      await _ensurePlayerReady();
      final duration = _timelineDurationMs;
      final startMs = (duration * chunk.start).round();
      final endMs = (duration * chunk.end).round();
      setState(() {
        _activeChunkId = chunk.id;
        _playhead = chunk.start;
        _playbackError = null;
      });
      await _player.seek(Duration(milliseconds: startMs));
      _rangeEndMs = endMs;
      _rangeTimer?.cancel();
      _rangeTimer = Timer.periodic(const Duration(milliseconds: 30), (_) {
        final limit = _rangeEndMs;
        if (limit != null && _player.position.inMilliseconds >= limit) {
          _rangeTimer?.cancel();
          _rangeEndMs = null;
          unawaited(_player.pause());
          unawaited(_player.seek(Duration(milliseconds: limit)));
        }
      });
      _startPlayback();
    } catch (error) {
      if (mounted) {
        setState(() => _playbackError = 'Could not play chunk: $error');
      }
    }
  }

  Future<void> _pause() async {
    _rangeTimer?.cancel();
    _rangeEndMs = null;
    await _player.pause();
  }

  Future<void> _seek(double value) async {
    if (!_loaded) return;
    _rangeTimer?.cancel();
    _rangeEndMs = null;
    await _player.seek(
      Duration(milliseconds: (_timelineDurationMs * value).round()),
    );
  }

  Future<void> _addChunk() async {
    final start = _playhead >= .98 ? .88 : _playhead;
    final end = (start + .12).clamp(start + .005, 1.0).toDouble();
    final number = widget.sample.chunks.length + 1;
    final chunk = SampleChunk(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: 'Chunk ${number.toString().padLeft(2, '0')}',
      start: start,
      end: end,
    );
    setState(() {
      widget.sample.chunks = [...widget.sample.chunks, chunk];
      _activeChunkId = chunk.id;
    });
    await widget.onChanged();
  }

  Future<void> _setBoundary({required bool start}) async {
    final chunk = _activeChunk;
    if (chunk == null) return;
    if ((start && _playhead >= chunk.end) ||
        (!start && _playhead <= chunk.start)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            start
                ? 'In point must be before the out point.'
                : 'Out point must be after the in point.',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    setState(() {
      if (start) {
        chunk.start = _playhead;
      } else {
        chunk.end = _playhead;
      }
    });
    await widget.onChanged();
  }

  Future<void> _removeChunk(SampleChunk chunk) async {
    setState(() {
      widget.sample.chunks.removeWhere((item) => item.id == chunk.id);
      _selectedChunkIds.remove(chunk.id);
      _activeChunkId = widget.sample.chunks.isEmpty
          ? null
          : widget.sample.chunks.first.id;
    });
    await widget.onChanged();
  }

  Future<void> _saveChunkRange() => widget.onChanged();

  Future<void> _sendSelectedChunks() async {
    final service = LoomMidiService.instance;
    if (!service.connected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Connect to LOOM-8 from the device tab first.'),
        ),
      );
      return;
    }
    final selected = widget.sample.chunks
        .where((chunk) => _selectedChunkIds.contains(chunk.id))
        .toList();
    if (selected.isEmpty) return;

    final transfer = service.sendChunks(widget.sample, selected);
    final error = await showDialog<Object?>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => FutureBuilder<void>(
        future: transfer,
        builder: (context, snapshot) {
          final complete = snapshot.connectionState == ConnectionState.done;
          return AlertDialog(
            backgroundColor: AppColors.panel,
            title: Text(
              complete
                  ? (snapshot.hasError ? 'Transfer stopped' : 'Chunks sent')
                  : 'Sending to LOOM-8',
            ),
            content: AnimatedBuilder(
              animation: service,
              builder: (context, _) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(
                    value: complete
                        ? (snapshot.hasError ? null : 1)
                        : service.progress,
                    color: AppColors.accent,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    snapshot.hasError
                        ? snapshot.error.toString()
                        : service.status,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            actions: complete
                ? [
                    TextButton(
                      onPressed: () =>
                          Navigator.of(dialogContext).pop(snapshot.error),
                      child: const Text('CLOSE'),
                    ),
                  ]
                : null,
          );
        },
      ),
    );
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('LOOM-8 transfer failed: $error')));
    } else {
      setState(() => _selectedChunkIds.clear());
    }
  }

  @override
  Widget build(BuildContext context) {
    final chunk = _activeChunk;
    final duration = _timelineDurationMs;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        15,
        20,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.line,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 22),
            const SectionEyebrow('SAMPLE NAME'),
            const SizedBox(height: 5),
            TextField(
              controller: _nameController,
              onChanged: (value) {
                widget.sample.name = value;
                _scheduleSave();
              },
              textCapitalization: TextCapitalization.sentences,
              onSubmitted: (_) => _saveName(),
              onEditingComplete: _saveName,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: 'Sample name',
                suffixIcon: IconButton(
                  onPressed: _saveName,
                  icon: const Icon(
                    Icons.check_rounded,
                    color: AppColors.accent,
                  ),
                ),
              ),
            ),
            Text(
              '${formatDuration(widget.sample.durationMs)}  ·  ${formatDate(widget.sample.createdAt)}',
              style: const TextStyle(color: AppColors.muted, fontSize: 11),
            ),
            const SizedBox(height: 18),
            Waveform(
              filePath: widget.sample.path,
              height: 92,
              chunks: widget.sample.chunks,
              selectedChunkId: _activeChunkId,
              playhead: _playhead,
            ),
            Slider(
              value: _playhead.clamp(0.0, 1.0),
              onChanged: (value) => setState(() => _playhead = value),
              onChangeEnd: (value) => _seek(value),
              activeColor: AppColors.accent,
              inactiveColor: AppColors.line,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  formatPreciseDuration((duration * _playhead).round()),
                  style: const TextStyle(color: AppColors.muted, fontSize: 10),
                ),
                Text(
                  formatDuration(duration),
                  style: const TextStyle(color: AppColors.muted, fontSize: 10),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _playing ? _pause : _playAll,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: AppColors.ink,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    icon: Icon(
                      _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    ),
                    label: Text(_playing ? 'PAUSE' : 'PLAY RECORDING'),
                  ),
                ),
                const SizedBox(width: 9),
                OutlinedButton.icon(
                  onPressed: _addChunk,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.accent,
                    side: const BorderSide(color: AppColors.line),
                    padding: const EdgeInsets.symmetric(
                      vertical: 13,
                      horizontal: 12,
                    ),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('ADD CHUNK'),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _exporting ? null : () => _saveWav(),
                icon: const Icon(Icons.save_alt_rounded, size: 17),
                label: Text(_exporting ? 'PREPARING WAV…' : 'SAVE FULL WAV'),
                style: TextButton.styleFrom(foregroundColor: AppColors.accent),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _normalizeExport,
              onChanged: _exporting
                  ? null
                  : (value) => setState(() => _normalizeExport = value),
              activeThumbColor: AppColors.accent,
              title: const Text('Normalize exported WAV'),
              subtitle: const Text(
                'Boosts a quiet file to a healthy peak; the recording stays unchanged.',
                style: TextStyle(color: AppColors.muted, fontSize: 10),
              ),
            ),
            if (_playbackError != null) ...[
              const SizedBox(height: 8),
              Text(
                _playbackError!,
                style: const TextStyle(color: AppColors.record, fontSize: 11),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                const SectionEyebrow('SAVED CHUNKS'),
                const Spacer(),
                if (widget.sample.chunks.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(() {
                      if (_selectedChunkIds.length ==
                          widget.sample.chunks.length) {
                        _selectedChunkIds.clear();
                      } else {
                        _selectedChunkIds
                          ..clear()
                          ..addAll(
                            widget.sample.chunks.map((chunk) => chunk.id),
                          );
                      }
                    }),
                    child: Text(
                      _selectedChunkIds.length == widget.sample.chunks.length
                          ? 'SELECT NONE'
                          : 'SELECT ALL',
                      style: const TextStyle(fontSize: 9, letterSpacing: .6),
                    ),
                  ),
                Text(
                  '${widget.sample.chunks.length}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 11),
                ),
              ],
            ),
            if (widget.sample.chunks.isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Text(
                  'Tick each range you want to add to the LOOM-8 bank.',
                  style: TextStyle(color: AppColors.muted, fontSize: 10),
                ),
              ),
            const SizedBox(height: 8),
            if (widget.sample.chunks.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 9),
                child: Text(
                  'Move the playhead to a sound, then add a chunk. Adjust its in and out points below.',
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              )
            else
              for (final item in widget.sample.chunks)
                Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Material(
                    color: item.id == _activeChunkId
                        ? AppColors.panelRaised
                        : AppColors.panel,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => setState(() => _activeChunkId = item.id),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.name,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '${formatPreciseDuration((duration * item.start).round())} — ${formatPreciseDuration((duration * item.end).round())}',
                                    style: const TextStyle(
                                      color: AppColors.muted,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Checkbox(
                              value: _selectedChunkIds.contains(item.id),
                              activeColor: AppColors.accent,
                              onChanged: (selected) => setState(() {
                                if (selected == true) {
                                  _selectedChunkIds.add(item.id);
                                } else {
                                  _selectedChunkIds.remove(item.id);
                                }
                              }),
                            ),
                            IconButton(
                              tooltip: 'Play ${item.name}',
                              onPressed: () => _playChunk(item),
                              icon: const Icon(
                                Icons.play_circle_outline_rounded,
                                color: AppColors.accent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            if (widget.sample.chunks.isNotEmpty) ...[
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed:
                      _selectedChunkIds.isEmpty ||
                          LoomMidiService.instance.transferring
                      ? null
                      : _sendSelectedChunks,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.ink,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  icon: const Icon(Icons.file_upload_outlined, size: 18),
                  label: Text(
                    _selectedChunkIds.isEmpty
                        ? 'TICK CHUNKS ABOVE TO SEND'
                        : 'SEND ${_selectedChunkIds.length} CHUNK${_selectedChunkIds.length == 1 ? '' : 'S'} TO LOOM-8',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      letterSpacing: .5,
                    ),
                  ),
                ),
              ),
            ],
            if (chunk != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.fromLTRB(13, 12, 13, 10),
                decoration: BoxDecoration(
                  color: AppColors.panel,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            key: ValueKey('chunk-name-${chunk.id}'),
                            initialValue: chunk.name,
                            textCapitalization: TextCapitalization.sentences,
                            textInputAction: TextInputAction.done,
                            maxLength: 32,
                            onChanged: (value) {
                              chunk.name = value;
                              _scheduleSave();
                              setState(() {});
                            },
                            onFieldSubmitted: (value) =>
                                _saveChunkName(chunk, value),
                            decoration: InputDecoration(
                              labelText: 'CHUNK NAME',
                              hintText: 'e.g. Kick hit',
                              counterText: '',
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(9),
                              ),
                            ),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Delete chunk',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _removeChunk(chunk),
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 18,
                            color: AppColors.record,
                          ),
                        ),
                      ],
                    ),
                    RangeSlider(
                      values: RangeValues(
                        chunk.start.clamp(0.0, 1.0),
                        chunk.end.clamp(0.0, 1.0),
                      ),
                      min: 0,
                      max: 1,
                      divisions: 200,
                      activeColor: AppColors.accent,
                      inactiveColor: AppColors.line,
                      onChanged: (range) {
                        if (range.end - range.start < .005) return;
                        setState(() {
                          chunk.start = range.start;
                          chunk.end = range.end;
                        });
                      },
                      onChangeEnd: (_) => _saveChunkRange(),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'IN  ${formatPreciseDuration((duration * chunk.start).round())}',
                          style: const TextStyle(
                            color: AppColors.accent,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'OUT  ${formatPreciseDuration((duration * chunk.end).round())}',
                          style: const TextStyle(
                            color: AppColors.accent,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _exporting
                            ? null
                            : () => _saveWav(chunk: chunk),
                        icon: const Icon(Icons.content_cut_rounded, size: 17),
                        label: Text(
                          'CROP & SAVE ${chunk.name.toUpperCase()} WAV',
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.accent,
                          side: const BorderSide(color: AppColors.line),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton.icon(
                            onPressed: () => _setBoundary(start: true),
                            icon: const Icon(
                              Icons.first_page_rounded,
                              size: 17,
                            ),
                            label: const Text('SET IN AT PLAYHEAD'),
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.muted,
                              textStyle: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: TextButton.icon(
                            onPressed: () => _setBoundary(start: false),
                            icon: const Icon(Icons.last_page_rounded, size: 17),
                            label: const Text('SET OUT AT PLAYHEAD'),
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.muted,
                              textStyle: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            const InfoStrip(
              icon: Icons.info_outline_rounded,
              text: 'Chunk in/out ranges are saved. Export a full WAV or crop the selected range to a new WAV file; the source recording stays untouched.',
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: widget.onDelete,
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: const Text('Delete recording'),
                style: TextButton.styleFrom(foregroundColor: AppColors.record),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

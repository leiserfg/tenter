class SampleChunk {
  SampleChunk({
    required this.id,
    required this.name,
    required this.start,
    required this.end,
  });

  final String id;
  String name;
  double start;
  double end;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'start': start,
    'end': end,
  };

  factory SampleChunk.fromJson(Map<String, dynamic> json) => SampleChunk(
    id: json['id'] as String,
    name: json['name'] as String,
    start: (json['start'] as num).toDouble(),
    end: (json['end'] as num).toDouble(),
  );
}

class Sample {
  Sample({
    required this.id,
    required this.name,
    required this.path,
    required this.createdAt,
    required this.durationMs,
    this.chunks = const [],
  });

  final String id;
  String name;
  final String path;
  final DateTime createdAt;
  final int durationMs;
  List<SampleChunk> chunks;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'path': path,
    'createdAt': createdAt.toIso8601String(),
    'durationMs': durationMs,
    'chunks': chunks.map((chunk) => chunk.toJson()).toList(),
  };

  factory Sample.fromJson(Map<String, dynamic> json) {
    final chunks = (json['chunks'] as List?)
        ?.map((item) => SampleChunk.fromJson(item as Map<String, dynamic>))
        .toList();
    final legacyMarkers =
        (json['markers'] as List? ?? const [])
            .map(
              (value) => (value as num).toDouble().clamp(0.0, 1.0).toDouble(),
            )
            .toList()
          ..sort();
    final migratedChunks = <SampleChunk>[];
    if (chunks == null) {
      for (var i = 0; i < legacyMarkers.length; i++) {
        final start = legacyMarkers[i];
        final end = i + 1 < legacyMarkers.length ? legacyMarkers[i + 1] : 1.0;
        if (end - start >= .005) {
          migratedChunks.add(
            SampleChunk(
              id: 'legacy-$i',
              name: 'Chunk ${i + 1}',
              start: start,
              end: end,
            ),
          );
        }
      }
    }
    return Sample(
      id: json['id'] as String,
      name: json['name'] as String,
      path: json['path'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      durationMs: json['durationMs'] as int,
      chunks: chunks ?? migratedChunks,
    );
  }
}

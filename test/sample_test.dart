import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tenter/models/sample.dart';

void main() {
  group('Sample chunk ranges', () {
    test('round-trips named in/out ranges', () {
      final sample = Sample(
        id: 'sample-1',
        name: 'Glass tap',
        path: '/not-read-by-this-test.wav',
        createdAt: DateTime.utc(2025, 1, 2),
        durationMs: 4000,
        chunks: [
          SampleChunk(id: 'chunk-a', name: 'Attack', start: .15, end: .42),
          SampleChunk(id: 'chunk-b', name: 'Tail', start: .63, end: .95),
        ],
      );

      final restored = Sample.fromJson(
        jsonDecode(jsonEncode(sample.toJson())) as Map<String, dynamic>,
      );

      expect(restored.chunks, hasLength(2));
      expect(restored.chunks[0].name, 'Attack');
      expect(restored.chunks[0].start, .15);
      expect(restored.chunks[0].end, .42);
      expect(restored.chunks[1].start, .63);
      expect(restored.chunks[1].end, .95);
    });

    test('migrates old point markers to ranges', () {
      final restored = Sample.fromJson({
        'id': 'old-sample',
        'name': 'Old capture',
        'path': '/old.wav',
        'createdAt': DateTime.utc(2025, 1, 2).toIso8601String(),
        'durationMs': 5000,
        'markers': [.2, .6],
      });

      expect(restored.chunks, hasLength(2));
      expect(restored.chunks[0].start, .2);
      expect(restored.chunks[0].end, .6);
      expect(restored.chunks[1].start, .6);
      expect(restored.chunks[1].end, 1.0);
    });
  });
}

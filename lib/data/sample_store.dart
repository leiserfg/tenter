import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/sample.dart';

class SampleStore {
  static const _key = 'tenter.samples.v1';

  static Future<List<Sample>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_key);
    if (data == null) return [];
    try {
      final decoded = jsonDecode(data) as List;
      return decoded
          .map((item) => Sample.fromJson(item as Map<String, dynamic>))
          .where((sample) => File(sample.path).existsSync())
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<Sample> samples) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(samples.map((sample) => sample.toJson()).toList()),
    );
  }
}

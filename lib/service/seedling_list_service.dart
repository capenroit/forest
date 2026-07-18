import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'lookup_service.dart';

class SeedlingListService {
  final supabase = Supabase.instance.client;

  static const String _cacheFileName = 'seedling_list_cache.json';
  static List<String> _cachedNames = [];
  static bool _cacheLoaded = false;

  static Future<File> _cacheFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_cacheFileName');
  }

  static Future<void> _loadCache() async {
    if (_cacheLoaded) return;
    try {
      final file = await _cacheFile();
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is List) {
          _cachedNames = decoded.cast<String>();
        }
      }
    } catch (_) {
      // Ignore — fall back to empty or network.
    } finally {
      _cacheLoaded = true;
    }
  }

  static Future<void> _persistCache() async {
    try {
      final file = await _cacheFile();
      await file.writeAsString(jsonEncode(_cachedNames));
    } catch (_) {
      // Best effort.
    }
  }

  /// Returns seedling names, serving from disk cache when offline.
  Future<List<String>> getSeedlingNames() async {
    await _loadCache();

    try {
      final response = await supabase
          .from('seedling_list')
          .select('seedling_name');

      final data = response as List<dynamic>;
      final seen = <String>{};
      final parsedNames = <String>[];

      for (final row in data) {
        if (row is! Map<String, dynamic>) {
          continue;
        }

        final rawName = row['seedling_name'];
        final name = (rawName ?? '').toString().trim();
        if (name.isEmpty) {
          continue;
        }

        final key = name.toLowerCase();
        if (seen.add(key)) {
          parsedNames.add(name);
        }
      }

      parsedNames.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      _cachedNames = parsedNames;
      await _persistCache();
      return _cachedNames;
    } catch (_) {
      // Offline — return whatever is cached.
      return _cachedNames;
    }
  }

  /// Returns the last known seedling names without a network request.
  static List<String> getCachedNames() => List.unmodifiable(_cachedNames);

  /// Returns seedling lookup options with ids for saving foreign keys.
  Future<List<LookupOption>> getSeedlingOptions() async {
    try {
      final response = await supabase
          .from('seedling_list')
          .select('seq_id, seedling_name')
          .order('seedling_name', ascending: true);

      final options = (response as List<dynamic>)
          .map(
            (row) => LookupOption(
              id: (row['seq_id'] as num).toInt(),
              name: (row['seedling_name'] as String).trim(),
            ),
          )
          .where((option) => option.name.isNotEmpty)
          .toList();

      options.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return options;
    } catch (_) {
      return const <LookupOption>[];
    }
  }

  /// Adds a new seedling to the shared lookup table and local cache.
  Future<Map<String, dynamic>> addSeedlingName({
    required String seedlingName,
    String? details,
  }) async {
    final name = seedlingName.trim();
    final description = (details ?? '').trim();
    if (name.isEmpty) {
      throw Exception('Seedling name cannot be empty.');
    }

    final inserted = await supabase
        .from('seedling_list')
        .insert({
          'seedling_name': name,
          'details': description.isEmpty ? name : description,
        })
        .select('seq_id, seedling_name')
        .single();

    await _loadCache();
    final alreadyExists =
        _cachedNames.any((existing) => existing.toLowerCase() == name.toLowerCase());

    if (!alreadyExists) {
      _cachedNames = [..._cachedNames, name]
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      await _persistCache();
    }

    return Map<String, dynamic>.from(inserted);
  }
}


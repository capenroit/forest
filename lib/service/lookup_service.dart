import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LookupOption {
  final int id;
  final String name;

  const LookupOption({required this.id, required this.name});

  factory LookupOption.fromJson(Map<String, dynamic> json) {
    return LookupOption(
      id: json['id'] as int,
      name: json['name'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
    };
  }
}

class LookupService {
  static final SupabaseClient _supabase = Supabase.instance.client;
  static const String _cacheFileName = 'lookup_cache.json';

  static List<LookupOption> _cachedMunicipalityOptions = [];
  static bool _municipalityOptionsLoaded = false;
  static final Map<int, List<LookupOption>> _cachedBarangayOptionsByMunicipality = {};
  static List<LookupOption> _cachedFloraClassificationOptions = [];
  static List<LookupOption> _cachedFaunaClassificationOptions = [];
  static List<LookupOption> _cachedProjectTypeOptions = [];
  static List<Map<String, dynamic>> _cachedNurseryRows = [];
  static bool _diskCacheLoaded = false;

  static void _sortMunicipalityOptionsWithIdOneFirst() {
    _cachedMunicipalityOptions.sort(
      (a, b) {
        if (a.id == 1 && b.id != 1) return -1;
        if (b.id == 1 && a.id != 1) return 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      },
    );
  }

  static Future<File> _cacheFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_cacheFileName');
  }

  static Future<void> _loadDiskCache() async {
    if (_diskCacheLoaded) {
      return;
    }

    try {
      final file = await _cacheFile();
      if (!await file.exists()) {
        _diskCacheLoaded = true;
        return;
      }

      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, dynamic>) {
        final municipalities = decoded['municipalities'];
        if (municipalities is List) {
          _cachedMunicipalityOptions = municipalities
              .whereType<Map>()
              .map((item) => LookupOption.fromJson(
                    Map<String, dynamic>.from(item),
                  ))
              .toList();
          _sortMunicipalityOptionsWithIdOneFirst();
        }

        final barangays = decoded['barangays'];
        if (barangays is Map) {
          _cachedBarangayOptionsByMunicipality.clear();
          barangays.forEach((key, value) {
            final municipalityId = int.tryParse(key.toString());
            if (municipalityId == null || value is! List) {
              return;
            }

            _cachedBarangayOptionsByMunicipality[municipalityId] = value
                .whereType<Map>()
                .map((item) => LookupOption.fromJson(
                      Map<String, dynamic>.from(item),
                    ))
                .toList();
          });
        }

        final floraClassifications = decoded['flora_classifications'];
        if (floraClassifications is List) {
          _cachedFloraClassificationOptions = floraClassifications
              .whereType<Map>()
              .map((item) => LookupOption.fromJson(
                    Map<String, dynamic>.from(item),
                  ))
              .toList();
        }

        final faunaClassifications = decoded['fauna_classifications'];
        if (faunaClassifications is List) {
          _cachedFaunaClassificationOptions = faunaClassifications
              .whereType<Map>()
              .map((item) => LookupOption.fromJson(
                    Map<String, dynamic>.from(item),
                  ))
              .toList();
        }

        final projectTypes = decoded['project_types'];
        if (projectTypes is List) {
          _cachedProjectTypeOptions = projectTypes
              .whereType<Map>()
              .map((item) => LookupOption.fromJson(
                    Map<String, dynamic>.from(item),
                  ))
              .toList();
        }

        final nurseryRows = decoded['nursery_rows'];
        if (nurseryRows is List) {
          _cachedNurseryRows = nurseryRows
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList();
        }
      }
    } catch (_) {
      // Ignore disk cache parsing errors and fall back to network or empty state.
    } finally {
      _municipalityOptionsLoaded = _cachedMunicipalityOptions.isNotEmpty;
      _diskCacheLoaded = true;
    }
  }

  static Future<void> _persistDiskCache() async {
    try {
      final file = await _cacheFile();
      final payload = <String, dynamic>{
        'municipalities': _cachedMunicipalityOptions
            .map((option) => option.toJson())
            .toList(),
        'barangays': _cachedBarangayOptionsByMunicipality.map(
          (municipalityId, options) => MapEntry(
            municipalityId.toString(),
            options.map((option) => option.toJson()).toList(),
          ),
        ),
        'flora_classifications': _cachedFloraClassificationOptions
            .map((option) => option.toJson())
            .toList(),
        'fauna_classifications': _cachedFaunaClassificationOptions
            .map((option) => option.toJson())
            .toList(),
        'project_types': _cachedProjectTypeOptions
            .map((option) => option.toJson())
            .toList(),
        'nursery_rows': _cachedNurseryRows,
      };
      await file.writeAsString(jsonEncode(payload));
    } catch (_) {
      // Persistence is best-effort; ignore failures so lookups still work online.
    }
  }

  static Future<List<LookupOption>> _fetchMunicipalityOptionsFromNetwork() async {
    final response = await _supabase
        .from('municipalities')
        .select('id, name')
      .order('name', ascending: true);

    return (response as List)
        .map((row) => LookupOption(
              id: row['id'] as int,
              name: row['name'] as String,
            ))
        .toList()
      ..sort((a, b) {
        if (a.id == 1 && b.id != 1) return -1;
        if (b.id == 1 && a.id != 1) return 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
  }

  static Future<void> _loadAllBarangaysFromNetwork() async {
    final response = await _supabase
        .from('barangay')
        .select('id, barangay_name, municipality_id')
        .order('barangay_name');

    final grouped = <int, List<LookupOption>>{};
    for (final row in response as List) {
      final municipalityId = row['municipality_id'] as int?;
      if (municipalityId == null) {
        continue;
      }

      grouped.putIfAbsent(municipalityId, () => []);
      grouped[municipalityId]!.add(
        LookupOption(
          id: row['id'] as int,
          name: row['barangay_name'] as String,
        ),
      );
    }

    _cachedBarangayOptionsByMunicipality
      ..clear()
      ..addAll(grouped);
  }

  static Future<List<String>> getMunicipalities({bool refresh = false}) async {
    final options = await getMunicipalityOptions(refresh: refresh);
    return options.map((option) => option.name).toList();
  }

  static Future<List<LookupOption>> getMunicipalityOptions({
    bool refresh = false,
  }) async {
    await _loadDiskCache();

    if (!refresh &&
        _municipalityOptionsLoaded &&
        _cachedMunicipalityOptions.isNotEmpty) {
      _sortMunicipalityOptionsWithIdOneFirst();
      return _cachedMunicipalityOptions;
    }

    try {
      _cachedMunicipalityOptions = await _fetchMunicipalityOptionsFromNetwork();
      _sortMunicipalityOptionsWithIdOneFirst();
      _municipalityOptionsLoaded = true;

      if (_cachedBarangayOptionsByMunicipality.isEmpty || refresh) {
        await _loadAllBarangaysFromNetwork();
      }

      await _persistDiskCache();
      return _cachedMunicipalityOptions;
    } catch (_) {
      _sortMunicipalityOptionsWithIdOneFirst();
      return _cachedMunicipalityOptions;
    }
  }

  static Future<List<String>> getBarangays({bool refresh = false}) async {
    await _loadDiskCache();

    if (refresh || _cachedBarangayOptionsByMunicipality.isEmpty) {
      try {
        await _loadAllBarangaysFromNetwork();
        await _persistDiskCache();
      } catch (_) {
        // Fall back to whatever is already cached.
      }
    }

    return _cachedBarangayOptionsByMunicipality.values
        .expand((options) => options)
        .map((option) => option.name)
        .toList();
  }

  static Future<List<LookupOption>> getSpeciesTypeOptions() async {
    try {
      final response = await _supabase
          .from('species_type')
          .select('seq_id, name')
          .order('name', ascending: true);

      return (response as List<dynamic>)
          .map(
            (row) => LookupOption(
              id: (row['seq_id'] as num).toInt(),
              name: (row['name'] as String).trim(),
            ),
          )
          .where((option) => option.name.isNotEmpty)
          .toList();
    } catch (_) {
      return const <LookupOption>[];
    }
  }

  static Future<List<LookupOption>> getFloraClassificationOptions() async {
    await _loadDiskCache();

    try {
      final response = await _supabase
          .from('flora_classification')
          .select('id, name')
          .order('name', ascending: true);

      _cachedFloraClassificationOptions = (response as List<dynamic>)
          .map(
            (row) => LookupOption(
              id: (row['id'] as num).toInt(),
              name: (row['name'] as String).trim(),
            ),
          )
          .where((option) => option.name.isNotEmpty)
          .toList();

      await _persistDiskCache();
      return _cachedFloraClassificationOptions;
    } catch (_) {
      // Offline or Supabase unavailable: fall back to whatever was cached
      // from the last successful fetch.
      return _cachedFloraClassificationOptions;
    }
  }

  static Future<List<LookupOption>> getFaunaClassificationOptions() async {
    await _loadDiskCache();

    try {
      final response = await _supabase
          .from('fauna_classification')
          .select('id, name')
          .order('name', ascending: true);

      _cachedFaunaClassificationOptions = (response as List<dynamic>)
          .map(
            (row) => LookupOption(
              id: (row['id'] as num).toInt(),
              name: (row['name'] as String).trim(),
            ),
          )
          .where((option) => option.name.isNotEmpty)
          .toList();

      await _persistDiskCache();
      return _cachedFaunaClassificationOptions;
    } catch (_) {
      // Offline or Supabase unavailable: fall back to whatever was cached
      // from the last successful fetch.
      return _cachedFaunaClassificationOptions;
    }
  }

  static Future<List<LookupOption>> getProjectTypeOptions({
    bool refresh = false,
  }) async {
    await _loadDiskCache();

    if (!refresh && _cachedProjectTypeOptions.isNotEmpty) {
      return _cachedProjectTypeOptions;
    }

    try {
      final response = await _supabase
          .from('project_type')
          .select('id, projectname')
          .order('id', ascending: true);

      _cachedProjectTypeOptions = (response as List<dynamic>)
          .map(
            (row) => LookupOption(
              id: (row['id'] as num).toInt(),
              name: (row['projectname'] as String).trim(),
            ),
          )
          .where((option) => option.name.isNotEmpty)
          .toList();

      await _persistDiskCache();
      return _cachedProjectTypeOptions;
    } catch (_) {
      // Offline or Supabase unavailable: fall back to whatever was cached
      // from the last successful fetch.
      return _cachedProjectTypeOptions;
    }
  }

  /// Raw seedling_nursery rows (seq_id, name, description, div_type) —
  /// kept as maps rather than [LookupOption] since callers need the extra
  /// fields, not just id/name.
  static Future<List<Map<String, dynamic>>> getNurseryRows({
    bool refresh = false,
  }) async {
    await _loadDiskCache();

    if (!refresh && _cachedNurseryRows.isNotEmpty) {
      return _cachedNurseryRows;
    }

    try {
      final response = await _supabase
          .from('seedling_nursery')
          .select('seq_id, name, description, div_type')
          .order('name', ascending: true);

      _cachedNurseryRows = (response as List<dynamic>)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();

      await _persistDiskCache();
      return _cachedNurseryRows;
    } catch (_) {
      // Offline or Supabase unavailable: fall back to whatever was cached
      // from the last successful fetch.
      return _cachedNurseryRows;
    }
  }

  static Future<List<LookupOption>> getBarangayOptionsByMunicipalityId(
    int municipalityId, {
    bool refresh = false,
  }) async {
    await _loadDiskCache();

    final cached = _cachedBarangayOptionsByMunicipality[municipalityId];
    if (!refresh && cached != null && cached.isNotEmpty) {
      return cached;
    }

    try {
      if (refresh || _cachedBarangayOptionsByMunicipality.isEmpty) {
        await _loadAllBarangaysFromNetwork();
        await _persistDiskCache();
      }
    } catch (_) {
      // Offline or Supabase unavailable: use cached data below.
    }

    return _cachedBarangayOptionsByMunicipality[municipalityId] ?? [];
  }

  static List<String> getCachedMunicipalities() =>
      _cachedMunicipalityOptions.map((option) => option.name).toList();

  static List<String> getCachedBarangays() => _cachedBarangayOptionsByMunicipality.values
      .expand((options) => options)
      .map((option) => option.name)
      .toList();

  static void clearCache() {
    _cachedMunicipalityOptions = [];
    _municipalityOptionsLoaded = false;
    _cachedBarangayOptionsByMunicipality.clear();
    _cachedFloraClassificationOptions = [];
    _cachedFaunaClassificationOptions = [];
    _cachedProjectTypeOptions = [];
    _cachedNurseryRows = [];
    _diskCacheLoaded = false;

    _cacheFile().then((file) {
      if (file.existsSync()) {
        file.deleteSync();
      }
    });
  }
}


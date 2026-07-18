import 'package:supabase_flutter/supabase_flutter.dart';

class MunicipalityService {
  final supabase = Supabase.instance.client;

  Future<List<String>> getMunicipalities() async {
    final response = await supabase
        .from('municipalities')   // your table name
        .select('id, name')
        .order('name', ascending: true);          // fetch ascending by name

    final rows = (response as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList()
      ..sort((a, b) {
        final aId = (a['id'] as num?)?.toInt() ?? -1;
        final bId = (b['id'] as num?)?.toInt() ?? -1;
        if (aId == 1 && bId != 1) return -1;
        if (bId == 1 && aId != 1) return 1;

        final aName = (a['name'] ?? '').toString().toLowerCase();
        final bName = (b['name'] ?? '').toString().toLowerCase();
        return aName.compareTo(bName);
      });

    return rows.map((row) => (row['name'] ?? '').toString()).toList();
  }
}


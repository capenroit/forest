import 'package:supabase_flutter/supabase_flutter.dart';

class BarangayService {
  final supabase = Supabase.instance.client;

  Future<List<String>> getBarangays() async {
    final response = await supabase
        .from('barangay')   // your table name
        .select('barangay_name');          // only fetch the "name" column

    return (response as List)
        .map((row) => row['barangay_name'] as String)
       .toList();
  }
}


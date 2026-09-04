import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_session.dart';

/// Reads and writes public.nursery_attendant, plus the per-attendant totals
/// from the nursery_attendant_accomplishment view.
///
/// Writes are additionally restricted by RLS (access_level 1/2 only, see
/// add_nursery_attendant.sql) — the UI gating in the settings page is a
/// convenience, not the enforcement.
class NurseryAttendantService {
  const NurseryAttendantService._();

  static SupabaseClient get _client => Supabase.instance.client;

  static const String _table = 'nursery_attendant';
  static const String _accomplishmentView = 'nursery_attendant_accomplishment';

  /// SWM — belongs to a separate app, so its nurseries are never listed here.
  static const int _swmDivisionTypeId = 3;

  /// The nursery divisions the signed-in user may see.
  ///
  /// access_level 1 administers every division; everyone else is scoped to
  /// their own, matching how the propagation form already picks its species
  /// list and nursery options by division.
  static int? scopedDivisionTypeId() {
    final user = AuthSession.currentUser;
    if (user?.accessLevel == 1) return null;
    final divisionTypeId = user?.divisionTypeId;
    if (divisionTypeId == null || divisionTypeId == _swmDivisionTypeId) {
      return _swmDivisionTypeId; // matches no listed nursery
    }
    return divisionTypeId;
  }

  /// Every attendant, newest nurseries first by name.
  ///
  /// [nurseryIds] limits the result to those nurseries — pass the ids the
  /// caller is allowed to see so out-of-division rows never reach the device.
  static Future<List<Map<String, dynamic>>> getAttendants({
    List<int>? nurseryIds,
  }) async {
    if (nurseryIds != null && nurseryIds.isEmpty) return [];

    try {
      var query = _client.from(_table).select(
            'seq_id, name, nursery_id, status, created_at',
          );
      if (nurseryIds != null) {
        query = query.inFilter('nursery_id', nurseryIds);
      }
      final response = await query.order('name', ascending: true);
      return List<Map<String, dynamic>>.from(response as List<dynamic>);
    } catch (e) {
      throw Exception('Error fetching nursery attendants: $e');
    }
  }

  static Future<void> addAttendant({
    required String name,
    required int nurseryId,
    String status = 'Active',
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw Exception('Attendant name cannot be empty.');
    }

    try {
      await _client.from(_table).insert({
        'name': trimmed,
        'nursery_id': nurseryId,
        'status': status,
      });
    } catch (e) {
      throw Exception('Error adding attendant: $e');
    }
  }

  static Future<void> updateAttendant({
    required int seqId,
    required String name,
    required int nurseryId,
    required String status,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw Exception('Attendant name cannot be empty.');
    }

    try {
      // .select() + emptiness check: Postgrest does not throw when an UPDATE
      // matches zero rows because RLS filtered it out, so without this a
      // blocked edit would report success. Same guard the members page uses.
      final response = await _client
          .from(_table)
          .update({
            'name': trimmed,
            'nursery_id': nurseryId,
            'status': status,
          })
          .eq('seq_id', seqId)
          .select('seq_id');

      if (response.isEmpty) {
        throw Exception(
          'No row was updated. You may not have permission to edit this attendant.',
        );
      }
    } catch (e) {
      throw Exception('Error updating attendant: $e');
    }
  }

  static Future<void> deleteAttendant(int seqId) async {
    try {
      final response = await _client
          .from(_table)
          .delete()
          .eq('seq_id', seqId)
          .select('seq_id');

      if (response.isEmpty) {
        throw Exception(
          'No row was removed. You may not have permission to remove this attendant.',
        );
      }
    } catch (e) {
      throw Exception('Error removing attendant: $e');
    }
  }

  /// Per-attendant propagation totals from the database view, which already
  /// does the aggregation and keeps attendants with nothing recorded at zero
  /// rather than dropping them.
  static Future<List<Map<String, dynamic>>> getAccomplishments({
    List<int>? nurseryIds,
  }) async {
    if (nurseryIds != null && nurseryIds.isEmpty) return [];

    try {
      var query = _client.from(_accomplishmentView).select(
            'nursery_attendant_id, attendant_name, status, nursery_id, '
            'nursery_name, propagation_count, total_seeds, last_propagated_date',
          );
      if (nurseryIds != null) {
        query = query.inFilter('nursery_id', nurseryIds);
      }
      final response = await query.order('total_seeds', ascending: false);
      return List<Map<String, dynamic>>.from(response as List<dynamic>);
    } catch (e) {
      throw Exception('Error fetching attendant accomplishments: $e');
    }
  }
}

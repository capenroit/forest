class SeedDetail {
  final int seedId;
  final String speciesType;
  final String speciesName;
  final int speciesCount;

  const SeedDetail({
    required this.seedId,
    required this.speciesType,
    required this.speciesName,
    required this.speciesCount,
  });
}

class SeedForForestEntry {
  final int? id;
  final String? userId;
  final String donorName;
  final List<SeedDetail> seedDetails;
  final DateTime date;
  final int totalCount;
  final String remarks;
  final String status;
  final bool isConverted;
  final int? survive;

  /// Set only by the propagation flow (Seedling Inventory -> plus icon).
  final int? nurseryId;

  /// Which nursery attendant propagated it. Null on records saved before
  /// the attendant roster existed, which is why [isFromNurseryAttendant]
  /// falls back to [nurseryId].
  final int? nurseryAttendantId;

  const SeedForForestEntry({
    this.id,
    this.userId,
    required this.donorName,
    required this.seedDetails,
    required this.date,
    required this.totalCount,
    required this.remarks,
    this.status = 'DONATED',
    this.isConverted = false,
    this.survive,
    this.nurseryId,
    this.nurseryAttendantId,
  });

  /// Whether this came from nursery staff rather than a member of the public.
  ///
  /// Keyed on nursery_id rather than status: status is user-editable from the
  /// activity list (DONATED / PROPAGATED), so it can be flipped on a genuine
  /// public donation, whereas nursery_id is only ever written by the
  /// propagation form.
  bool get isFromNurseryAttendant =>
      nurseryAttendantId != null || nurseryId != null;
}

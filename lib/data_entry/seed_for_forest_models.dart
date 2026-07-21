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
  final String donorName;
  final List<SeedDetail> seedDetails;
  final DateTime date;
  final int totalCount;
  final String remarks;
  final String status;
  final bool isConverted;

  const SeedForForestEntry({
    this.id,
    required this.donorName,
    required this.seedDetails,
    required this.date,
    required this.totalCount,
    required this.remarks,
    this.status = 'DONATED',
    this.isConverted = false,
  });
}

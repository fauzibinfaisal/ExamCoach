class SyncRunSummary {
  const SyncRunSummary({
    this.skippedOffline = false,
    this.authenticationRequired = false,
    this.batches = 0,
    this.attempted = 0,
    this.acknowledged = 0,
    this.duplicates = 0,
    this.superseded = 0,
    this.retryScheduled = 0,
    this.deadLettered = 0,
    this.pruned = 0,
  });

  final bool skippedOffline;
  final bool authenticationRequired;
  final int batches;
  final int attempted;
  final int acknowledged;
  final int duplicates;
  final int superseded;
  final int retryScheduled;
  final int deadLettered;
  final int pruned;
}

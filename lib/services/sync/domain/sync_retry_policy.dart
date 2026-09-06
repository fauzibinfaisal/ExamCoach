class SyncRetryPolicy {
  const SyncRetryPolicy({
    this.maxAttempts = 5,
    this.initialDelay = const Duration(seconds: 5),
    this.maxDelay = const Duration(minutes: 15),
  }) : assert(maxAttempts > 0);

  final int maxAttempts;
  final Duration initialDelay;
  final Duration maxDelay;

  bool shouldDeadLetter(int attemptsAfterFailure) =>
      attemptsAfterFailure >= maxAttempts;

  Duration delayForAttempt(int attemptsAfterFailure) {
    if (attemptsAfterFailure < 1) {
      throw ArgumentError.value(
        attemptsAfterFailure,
        'attemptsAfterFailure',
        'must be at least 1',
      );
    }
    if (initialDelay.isNegative || maxDelay.isNegative) {
      throw StateError('Retry delays cannot be negative.');
    }
    var delay = initialDelay;
    for (var attempt = 1; attempt < attemptsAfterFailure; attempt++) {
      if (delay.compareTo(maxDelay) >= 0) {
        return maxDelay;
      }
      final doubled = delay * 2;
      delay = doubled.compareTo(maxDelay) > 0 ? maxDelay : doubled;
    }
    return delay;
  }
}

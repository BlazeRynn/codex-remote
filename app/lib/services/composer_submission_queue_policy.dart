bool shouldQueueComposerSubmission({
  required bool hasActiveTurnInFlight,
  required bool hasQueuedSubmissions,
}) {
  return hasActiveTurnInFlight || hasQueuedSubmissions;
}

bool canDispatchQueuedComposerSubmissions({
  required bool hasQueuedSubmissions,
  required bool queuedSubmissionDrainInFlight,
  required bool submitting,
  required bool awaitingTurnCompletion,
  required bool hasActiveTurnInFlight,
  required bool previousHadActiveTurnInFlight,
}) {
  if (hasQueuedSubmissions == false ||
      queuedSubmissionDrainInFlight ||
      submitting) {
    return false;
  }
  if (awaitingTurnCompletion) {
    return previousHadActiveTurnInFlight && !hasActiveTurnInFlight;
  }
  return !hasActiveTurnInFlight;
}

bool shouldAwaitQueuedTurnCompletion({
  required bool hasQueuedSubmissions,
  required bool hasActiveTurnInFlight,
}) {
  return hasQueuedSubmissions && hasActiveTurnInFlight;
}

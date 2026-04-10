import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/services/composer_submission_queue_policy.dart';

void main() {
  group('shouldQueueComposerSubmission', () {
    test('queues when a turn is still active', () {
      expect(
        shouldQueueComposerSubmission(
          hasActiveTurnInFlight: true,
          hasQueuedSubmissions: false,
        ),
        isTrue,
      );
    });

    test('queues when older prompts are already waiting', () {
      expect(
        shouldQueueComposerSubmission(
          hasActiveTurnInFlight: false,
          hasQueuedSubmissions: true,
        ),
        isTrue,
      );
    });

    test('sends immediately when idle and queue is empty', () {
      expect(
        shouldQueueComposerSubmission(
          hasActiveTurnInFlight: false,
          hasQueuedSubmissions: false,
        ),
        isFalse,
      );
    });
  });

  group('canDispatchQueuedComposerSubmissions', () {
    test('does not dispatch while still waiting for the current turn to finish', () {
      expect(
        canDispatchQueuedComposerSubmissions(
          hasQueuedSubmissions: true,
          queuedSubmissionDrainInFlight: false,
          submitting: false,
          awaitingTurnCompletion: true,
          hasActiveTurnInFlight: true,
          previousHadActiveTurnInFlight: true,
        ),
        isFalse,
      );
    });

    test('dispatches once the previous active turn has completed', () {
      expect(
        canDispatchQueuedComposerSubmissions(
          hasQueuedSubmissions: true,
          queuedSubmissionDrainInFlight: false,
          submitting: false,
          awaitingTurnCompletion: true,
          hasActiveTurnInFlight: false,
          previousHadActiveTurnInFlight: true,
        ),
        isTrue,
      );
    });

    test('dispatches after completion even when the prior turn id was unavailable', () {
      expect(
        canDispatchQueuedComposerSubmissions(
          hasQueuedSubmissions: true,
          queuedSubmissionDrainInFlight: false,
          submitting: false,
          awaitingTurnCompletion: true,
          hasActiveTurnInFlight: false,
          previousHadActiveTurnInFlight: true,
        ),
        isTrue,
      );
    });

    test('does not dispatch when a drain is already running', () {
      expect(
        canDispatchQueuedComposerSubmissions(
          hasQueuedSubmissions: true,
          queuedSubmissionDrainInFlight: true,
          submitting: false,
          awaitingTurnCompletion: false,
          hasActiveTurnInFlight: false,
          previousHadActiveTurnInFlight: false,
        ),
        isFalse,
      );
    });
  });

  group('shouldAwaitQueuedTurnCompletion', () {
    test('waits for completion when queued prompts remain after a new turn starts', () {
      expect(
        shouldAwaitQueuedTurnCompletion(
          hasQueuedSubmissions: true,
          hasActiveTurnInFlight: true,
        ),
        isTrue,
      );
    });

    test('does not wait when the queue is empty', () {
      expect(
        shouldAwaitQueuedTurnCompletion(
          hasQueuedSubmissions: false,
          hasActiveTurnInFlight: true,
        ),
        isFalse,
      );
    });
  });
}

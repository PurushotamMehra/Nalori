import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/reader_position_session.dart';

void main() {
  group('ReaderPositionSession', () {
    test('normal navigation updates committed and active positions', () {
      final session = ReaderPositionSession(initialDisplayIndex: 196);

      session.commit(200);

      expect(session.committedReadingPosition, 200);
      expect(session.activeVisiblePosition, 200);
      expect(session.hasActivePreviewPosition, isFalse);
      expect(session.canCommitActiveVisiblePosition, isTrue);
    });

    test('scrub preview preserves committed reading position', () {
      final session = ReaderPositionSession(initialDisplayIndex: 200);

      session.startPreview(200, scrubbing: true);
      session.updatePreview(500);
      session.finishScrub();

      expect(session.committedReadingPosition, 200);
      expect(session.activeVisiblePosition, 500);
      expect(session.previewPosition, 500);
      expect(session.canCommitActiveVisiblePosition, isFalse);
    });

    test('preview promotion makes preview the committed position', () {
      final session = ReaderPositionSession(initialDisplayIndex: 200);

      session.startPreview(200);
      session.updatePreview(500);
      final promoted = session.promotePreview();

      expect(promoted, 500);
      expect(session.committedReadingPosition, 500);
      expect(session.activeVisiblePosition, 500);
      expect(session.hasActivePreviewPosition, isFalse);
      expect(session.canCommitActiveVisiblePosition, isTrue);
    });

    test(
      'clearing preview returns to committed without committing preview',
      () {
        final session = ReaderPositionSession(initialDisplayIndex: 200);

        session.startPreview(200);
        session.updatePreview(500);
        session.clearPreview(visibleDisplayIndex: 200);

        expect(session.committedReadingPosition, 200);
        expect(session.activeVisiblePosition, 200);
        expect(session.hasActivePreviewPosition, isFalse);
        expect(session.canCommitActiveVisiblePosition, isTrue);
      },
    );

    test('navigation generation changes when visible position changes', () {
      final session = ReaderPositionSession(initialDisplayIndex: 196);
      final initialGeneration = session.navigationGeneration;

      session.markVisible(200);

      expect(session.activeVisiblePosition, 200);
      expect(session.navigationGeneration, greaterThan(initialGeneration));
    });

    test('modal state freezes active position and prevents commits', () {
      final session = ReaderPositionSession(initialDisplayIndex: 200);

      session.beginModalState(200);
      session.markVisible(204);
      session.commit(204);
      session.startPreview(204);
      session.updatePreview(205);

      expect(session.isNavigationSuspended, isTrue);
      expect(session.activeVisiblePosition, 200);
      expect(session.committedReadingPosition, 200);
      expect(session.hasActivePreviewPosition, isFalse);
      expect(session.canCommitActiveVisiblePosition, isFalse);

      final restored = session.endModalState();

      expect(restored, 200);
      expect(session.isNavigationSuspended, isFalse);
      expect(session.activeVisiblePosition, 200);
      expect(session.committedReadingPosition, 200);
      expect(session.canCommitActiveVisiblePosition, isTrue);
    });
  });
}

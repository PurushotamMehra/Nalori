import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/book_metadata.dart';
import 'package:nalori/models/stable_book_location.dart';
import 'package:nalori/services/reader_structural_progress_service.dart';

void main() {
  group('ReaderStructuralProgressService', () {
    test('within-chunk cards retain distinct exact structural positions', () {
      const base = StableBookLocation(
        bookId: 'book.epub',
        spineIndex: 2,
        href: 'chapter.xhtml',
        sourceChecksum: 'checksum',
        localChunkIndex: 0,
      );

      final first = ReaderStructuralProgressService.refineSourceOffset(
        base: base,
        sourceChunkCount: 1,
        sourceTextLength: 1000,
        textOffset: 100,
        publicationSectionStart: 0.2,
        publicationSectionEnd: 0.4,
      );
      final second = ReaderStructuralProgressService.refineSourceOffset(
        base: base,
        sourceChunkCount: 1,
        sourceTextLength: 1000,
        textOffset: 600,
        publicationSectionStart: 0.2,
        publicationSectionEnd: 0.4,
      );

      expect(first.textOffset, 100);
      expect(second.textOffset, 600);
      expect(first.sectionProgression, closeTo(0.1, 0.0001));
      expect(second.sectionProgression, closeTo(0.6, 0.0001));
      expect(
        second.publicationProgression,
        greaterThan(first.publicationProgression!),
      );
    });

    test('position revisions remain ordered when the clock repeats', () {
      final clock = ReaderPositionRevisionClock(clock: () => 42);

      expect(clock.next(), 42);
      expect(clock.next(), 43);
      expect(clock.next(), 44);
    });

    test('exit flush takes the latest visible card snapshot', () {
      const first = StableBookLocation(
        bookId: 'book.epub',
        spineIndex: 1,
        href: 'chapter.xhtml',
        sourceChecksum: 'checksum',
        localChunkIndex: 0,
        textOffset: 120,
      );
      const latest = StableBookLocation(
        bookId: 'book.epub',
        spineIndex: 1,
        href: 'chapter.xhtml',
        sourceChecksum: 'checksum',
        localChunkIndex: 0,
        textOffset: 640,
      );
      final queue = ReaderPositionPersistenceQueue()
        ..stage(
          const ReaderCommittedPosition(
            revision: 10,
            displayIndex: 2,
            originalIndex: 4,
            location: first,
          ),
        )
        ..stage(
          const ReaderCommittedPosition(
            revision: 11,
            displayIndex: 5,
            originalIndex: 4,
            location: latest,
          ),
        );

      final flushed = queue.takeLatest();

      expect(flushed?.displayIndex, 5);
      expect(flushed?.location?.textOffset, 640);
      expect(queue.pending, isNull);
    });

    test('lazy global progress uses weighted stable source progression', () {
      const location = StableBookLocation(
        bookId: 'book.epub',
        spineIndex: 8,
        href: 'chapter-8.xhtml',
        sourceChecksum: 'checksum',
        sectionProgression: 0.42,
        publicationProgression: 0.73,
      );

      final progress = ReaderStructuralProgressService.global(
        location: location,
        isLazyWindow: true,
        displayIndex: 1,
        displayChunkCount: 2,
        displayWindowComplete: true,
      );

      expect(progress.label, '73%');
      expect(progress.progress, 0.73);
      expect(progress.isExact, isFalse);
    });

    test('loaded lazy window never reports false 100 percent', () {
      final progress = ReaderStructuralProgressService.global(
        location: const StableBookLocation(
          bookId: 'book.epub',
          spineIndex: 1,
          href: 'chapter-1.xhtml',
          sourceChecksum: 'checksum',
          publicationProgression: 0.18,
        ),
        isLazyWindow: true,
        displayIndex: 4,
        displayChunkCount: 5,
        displayWindowComplete: true,
      );

      expect(progress.label, '18%');
      expect(progress.progress, 0.18);
    });

    test('missing structural progression is safely unknown', () {
      final progress = ReaderStructuralProgressService.global(
        location: null,
        isLazyWindow: true,
        displayIndex: 2,
        displayChunkCount: 3,
        displayWindowComplete: true,
      );

      expect(progress.label, 'Progress unknown');
      expect(progress.progress, isNull);
      expect(progress.isExact, isFalse);
    });

    test('legacy complete publication can retain exact display progress', () {
      final progress = ReaderStructuralProgressService.global(
        location: null,
        isLazyWindow: false,
        displayIndex: 2,
        displayChunkCount: 4,
        displayWindowComplete: true,
      );

      expect(progress.label, '75%');
      expect(progress.progress, 0.75);
      expect(progress.isExact, isTrue);
    });

    test('committed stable location becomes canonical persisted progress', () {
      final metadata =
          ReaderStructuralProgressService.metadataForCommittedLocation(
            metadata: BookMetadata(
              id: 'book.epub',
              title: 'Book',
              author: 'Author',
              lastReadIndex: 10,
              totalChunks: 101,
            ),
            currentStableLocation: const StableBookLocation(
              bookId: 'book.epub',
              spineIndex: 8,
              href: 'chapter-8.xhtml',
              sourceChecksum: 'checksum',
              publicationProgression: 0.8,
            ),
            meaningfulReadAt: 123,
            revision: 1,
          );

      expect(metadata.readingProgress, 0.8);
      expect(metadata.lastReadIndex, 10);
      expect(metadata.totalChunks, 101);
      expect(metadata.lastMeaningfulReadAt, 123);
    });

    test(
      'persistence uses published current location, not requested target',
      () {
        const requestedTarget = StableBookLocation(
          bookId: 'book.epub',
          spineIndex: 8,
          href: 'chapter-8.xhtml',
          sourceChecksum: 'checksum-8',
          publicationProgression: 0.8,
        );
        const publishedCurrent = StableBookLocation(
          bookId: 'book.epub',
          spineIndex: 4,
          href: 'chapter-4.xhtml',
          sourceChecksum: 'checksum-4',
          publicationProgression: 0.42,
        );
        final metadata =
            ReaderStructuralProgressService.metadataForCommittedLocation(
              metadata: BookMetadata(
                id: 'book.epub',
                title: 'Book',
                author: 'Author',
              ),
              currentStableLocation: publishedCurrent,
              meaningfulReadAt: 456,
              revision: 2,
            );

        expect(requestedTarget.publicationProgression, 0.8);
        expect(metadata.readingProgress, 0.42);
        expect(metadata.lastReadLocation, publishedCurrent);
      },
    );

    test(
      'final published source end persists exact publication completion',
      () {
        const start = StableBookLocation(
          bookId: 'book.epub',
          spineIndex: 8,
          href: 'final.xhtml',
          sourceChecksum: 'final-checksum',
          localChunkIndex: 12,
          textOffset: 0,
          sectionProgression: 0.96,
          publicationProgression: 0.99,
        );
        final evidence = ReaderPublishedCardBoundaryEvidence(
          startLocation: start,
          endLocation: start.copyWith(textOffset: 840),
          reachesEndOfSourceChunk: true,
          reachesEndOfResolvedSection: true,
          resolvedSectionComplete: true,
          nextReadableSpineIndex: null,
        );

        final committed = evidence.locationForCommittedProgress();
        final metadata =
            ReaderStructuralProgressService.metadataForCommittedLocation(
              metadata: BookMetadata(
                id: 'book.epub',
                title: 'Book',
                author: 'Author',
              ),
              currentStableLocation: committed,
              meaningfulReadAt: 789,
              revision: 3,
            );

        expect(evidence.provesPublicationEnd, isTrue);
        expect(committed.textOffset, 840);
        expect(committed.sectionProgression, 1);
        expect(metadata.readingProgress, 1);
      },
    );

    test('loaded-window end and penultimate cards remain below completion', () {
      const start = StableBookLocation(
        bookId: 'book.epub',
        spineIndex: 7,
        href: 'chapter-7.xhtml',
        sourceChecksum: 'checksum-7',
        localChunkIndex: 4,
        publicationProgression: 0.91,
      );
      final evidence = ReaderPublishedCardBoundaryEvidence(
        startLocation: start,
        endLocation: start.copyWith(textOffset: 400),
        reachesEndOfSourceChunk: true,
        reachesEndOfResolvedSection: true,
        resolvedSectionComplete: true,
        nextReadableSpineIndex: 8,
      );

      expect(evidence.provesPublicationEnd, isFalse);
      expect(
        evidence.locationForCommittedProgress().publicationProgression,
        0.91,
      );
    });

    test('chapter boundary proof uses source end inside one XHTML file', () {
      const start = StableBookLocation(
        bookId: 'book.epub',
        spineIndex: 3,
        href: 'chapters.xhtml',
        sourceChecksum: 'checksum',
        localChunkIndex: 4,
        publicationProgression: 0.4,
      );
      final evidence = ReaderPublishedCardBoundaryEvidence(
        startLocation: start,
        endLocation: start.copyWith(textOffset: 620),
        reachesEndOfSourceChunk: true,
        reachesEndOfResolvedSection: false,
        resolvedSectionComplete: true,
        nextReadableSpineIndex: 4,
      );

      expect(
        evidence.reachesChapterBoundary(
          start.copyWith(localChunkIndex: 5, textOffset: 0),
        ),
        isTrue,
      );
      expect(
        evidence.reachesChapterBoundary(
          start.copyWith(localChunkIndex: 6, textOffset: 0),
        ),
        isFalse,
      );
    });

    test('chapter boundary proof crosses only the next readable section', () {
      const start = StableBookLocation(
        bookId: 'book.epub',
        spineIndex: 3,
        href: 'chapter.xhtml',
        sourceChecksum: 'checksum',
        localChunkIndex: 9,
      );
      final evidence = ReaderPublishedCardBoundaryEvidence(
        startLocation: start,
        endLocation: start.copyWith(textOffset: 500),
        reachesEndOfSourceChunk: true,
        reachesEndOfResolvedSection: true,
        resolvedSectionComplete: true,
        nextReadableSpineIndex: 5,
      );

      expect(
        evidence.reachesChapterBoundary(
          start.copyWith(spineIndex: 5, localChunkIndex: 0, textOffset: 0),
        ),
        isTrue,
      );
      expect(
        evidence.reachesChapterBoundary(
          start.copyWith(spineIndex: 6, localChunkIndex: 0, textOffset: 0),
        ),
        isFalse,
      );
    });
  });

  test('structural scrub changes preview and commit one final navigation', () {
    final policy = ReaderStructuralScrubCommitPolicy();
    policy.begin(0.1);
    policy.update(0.35);
    policy.update(0.62);
    policy.update(0.8);

    expect(policy.preview, 0.8);
    expect(policy.commit(0.81), 0.81);
    expect(policy.commit(0.4), isNull);
  });
}

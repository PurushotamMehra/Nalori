import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/book_chunk.dart';

void main() {
  group('BookChunk source range mapping', () {
    test('falls back to identity mapping for original chunks', () {
      const chunk = BookChunk(
        index: 7,
        type: BookChunkType.text,
        text: 'Hello world',
      );

      final mapped = chunk.mapDisplayRangeToOriginal(6, 11);

      expect(mapped, hasLength(1));
      expect(mapped.first.originalChunkIndex, 7);
      expect(mapped.first.originalStartOffset, 6);
      expect(mapped.first.originalEndOffset, 11);
      expect(mapped.first.displayStartOffset, 6);
      expect(mapped.first.displayEndOffset, 11);
    });

    test('splits display selections across mapped source ranges', () {
      const chunk = BookChunk(
        index: 99,
        type: BookChunkType.text,
        text: 'Alpha\n\nBeta',
        sourceRanges: [
          ChunkSourceRange(
            originalChunkIndex: 1,
            originalStartOffset: 0,
            originalEndOffset: 5,
            displayStartOffset: 0,
            displayEndOffset: 5,
          ),
          ChunkSourceRange(
            originalChunkIndex: 2,
            originalStartOffset: 10,
            originalEndOffset: 14,
            displayStartOffset: 7,
            displayEndOffset: 11,
          ),
        ],
      );

      final mapped = chunk.mapDisplayRangeToOriginal(3, 9);

      expect(mapped, hasLength(2));
      expect(mapped[0].originalChunkIndex, 1);
      expect(mapped[0].originalStartOffset, 3);
      expect(mapped[0].originalEndOffset, 5);
      expect(mapped[0].displayStartOffset, 3);
      expect(mapped[0].displayEndOffset, 5);

      expect(mapped[1].originalChunkIndex, 2);
      expect(mapped[1].originalStartOffset, 10);
      expect(mapped[1].originalEndOffset, 12);
      expect(mapped[1].displayStartOffset, 7);
      expect(mapped[1].displayEndOffset, 9);
    });

    test('maps stored original ranges back into display offsets', () {
      const chunk = BookChunk(
        index: 99,
        type: BookChunkType.text,
        text: 'Intro\n\nOutro',
        sourceRanges: [
          ChunkSourceRange(
            originalChunkIndex: 4,
            originalStartOffset: 20,
            originalEndOffset: 25,
            displayStartOffset: 0,
            displayEndOffset: 5,
          ),
          ChunkSourceRange(
            originalChunkIndex: 4,
            originalStartOffset: 25,
            originalEndOffset: 30,
            displayStartOffset: 7,
            displayEndOffset: 12,
          ),
        ],
      );

      final mapped = chunk.mapOriginalRangeToDisplay(4, 26, 29);

      expect(mapped, hasLength(1));
      expect(mapped.first.displayStartOffset, 8);
      expect(mapped.first.displayEndOffset, 11);
      expect(mapped.first.originalStartOffset, 26);
      expect(mapped.first.originalEndOffset, 29);
    });
  });

  group('BookChunk publisher layout metadata', () {
    test('round-trips special block presentation through compact JSON', () {
      const chunk = BookChunk(
        index: 3,
        type: BookChunkType.text,
        text: 'A quoted passage',
        blockRole: BookBlockRole.quote,
        publisherTextAlign: BookTextAlign.center,
        publisherLeftIndent: 20,
        publisherRightIndent: 12,
        preserveLineBreaks: true,
      );

      final decoded = BookChunk.fromJson(chunk.toJson());

      expect(decoded.blockRole, BookBlockRole.quote);
      expect(decoded.publisherTextAlign, BookTextAlign.center);
      expect(decoded.publisherLeftIndent, 20);
      expect(decoded.publisherRightIndent, 12);
      expect(decoded.preserveLineBreaks, isTrue);
      expect(decoded.usesPublisherLayout, isTrue);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/book_chunk.dart';
import 'package:nalori/models/book_list_semantics.dart';
import 'package:nalori/screens/reader_screen.dart';

void main() {
  const semantics = BookListSemantics(
    listId: 'chapter.xhtml#list-0',
    itemId: 'chapter.xhtml#list-0#item-0',
    ordered: true,
    depth: 0,
    markerType: BookListMarkerType.decimal,
    resolvedOrdinal: 4,
    orderedStart: 4,
    blockIndex: 0,
    beginsItem: true,
    endsItem: true,
  );
  const text = 'A long list item that remains authoritative across fragments.';
  const chunk = BookChunk(
    index: 3,
    type: BookChunkType.text,
    text: text,
    logicalParagraphId: 'chapter.xhtml#list-0#item-0#block-0',
    logicalParagraphEndOffset: text.length,
    listSemantics: semantics,
  );

  test('list metadata and display fragments round trip through JSON', () {
    final restored = BookChunk.fromJson(chunk.toJson());

    expect(restored.listSemantics?.itemId, semantics.itemId);
    expect(restored.listSemantics?.resolvedOrdinal, 4);
    expect(
      restored.effectiveListDisplaySegments.single.fragmentState,
      BookListFragmentState.complete,
    );
  });

  test('long item slice states expose marker only on opening fragment', () {
    final opening = readerListDisplaySegmentsForSlice(
      chunk: chunk,
      startOffset: 0,
      endOffset: 12,
    ).single;
    final continuation = readerListDisplaySegmentsForSlice(
      chunk: chunk,
      startOffset: 12,
      endOffset: 28,
    ).single;
    final finalFragment = readerListDisplaySegmentsForSlice(
      chunk: chunk,
      startOffset: 28,
      endOffset: text.length,
    ).single;

    expect(opening.fragmentState, BookListFragmentState.opening);
    expect(opening.showsMarker, isTrue);
    expect(continuation.fragmentState, BookListFragmentState.continuation);
    expect(continuation.showsMarker, isFalse);
    expect(finalFragment.fragmentState, BookListFragmentState.finalFragment);
    expect(finalFragment.showsMarker, isFalse);
  });

  test('list body ranges remain authoritative UTF-16 source ranges', () {
    final fragment = chunk.copyWith(
      text: text.substring(12, 28),
      sourceRanges: const [
        ChunkSourceRange(
          originalChunkIndex: 3,
          originalStartOffset: 12,
          originalEndOffset: 28,
          displayStartOffset: 0,
          displayEndOffset: 16,
        ),
      ],
      listDisplaySegments: readerListDisplaySegmentsForSlice(
        chunk: chunk,
        startOffset: 12,
        endOffset: 28,
      ),
    );

    expect(fragment.text, text.substring(12, 28));
    expect(fragment.text, isNot(contains('4.')));
    expect(fragment.effectiveSourceRanges.single.originalStartOffset, 12);
    expect(fragment.effectiveSourceRanges.single.originalEndOffset, 28);
    expect(
      readerDisplayChunkContainsSourceOffset(
        chunk: fragment,
        sourceIndex: 3,
        textOffset: 20,
      ),
      isTrue,
    );
  });

  test('list blocks merge only within the same list relationship', () {
    const sibling = BookChunk(
      index: 4,
      type: BookChunkType.text,
      text: 'Sibling',
      listSemantics: BookListSemantics(
        listId: 'chapter.xhtml#list-0',
        itemId: 'chapter.xhtml#list-0#item-1',
        ordered: true,
        depth: 0,
        markerType: BookListMarkerType.decimal,
        resolvedOrdinal: 5,
        orderedStart: 4,
        blockIndex: 0,
        beginsItem: true,
        endsItem: true,
      ),
    );
    const otherList = BookChunk(
      index: 5,
      type: BookChunkType.text,
      text: 'Other',
      listSemantics: BookListSemantics(
        listId: 'chapter.xhtml#list-1',
        itemId: 'chapter.xhtml#list-1#item-0',
        ordered: false,
        depth: 0,
        markerType: BookListMarkerType.unordered,
        blockIndex: 0,
        beginsItem: true,
        endsItem: true,
      ),
    );
    const prose = BookChunk(index: 6, type: BookChunkType.text, text: 'Prose');

    expect(readerChunksShareHardMergeBoundary(chunk, sibling), isTrue);
    expect(readerChunksShareHardMergeBoundary(chunk, otherList), isFalse);
    expect(readerChunksShareHardMergeBoundary(chunk, prose), isFalse);
  });
}

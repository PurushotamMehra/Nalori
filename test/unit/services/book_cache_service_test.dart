import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/services/book_cache_service.dart';

void main() {
  group('BookCacheService.displayChunkKey', () {
    test('differs when only paragraphSpacing differs', () {
      final base = BookCacheService.displayChunkKey(
        bookId: 'book.epub',
        fontSize: 18,
        fontFamily: 'serif',
        fontWeight: 'regular',
        density: 1,
        lineHeight: 1.4,
        paragraphSpacing: 1,
        screenW: 412,
        screenH: 915,
        enableCardDepth: false,
        textScaleFactor: 1,
        safeAreaTop: 44,
        safeAreaBottom: 34,
        safeAreaLeft: 0,
        safeAreaRight: 0,
      );
      final changed = BookCacheService.displayChunkKey(
        bookId: 'book.epub',
        fontSize: 18,
        fontFamily: 'serif',
        fontWeight: 'regular',
        density: 1,
        lineHeight: 1.4,
        paragraphSpacing: 2,
        screenW: 412,
        screenH: 915,
        enableCardDepth: false,
        textScaleFactor: 1,
        safeAreaTop: 44,
        safeAreaBottom: 34,
        safeAreaLeft: 0,
        safeAreaRight: 0,
      );

      expect(changed, isNot(base));
    });
  });
}

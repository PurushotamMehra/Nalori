import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/screens/reader_screen.dart';
import 'package:nalori/services/lazy_section_repository.dart';

void main() {
  group('card-depth lazy chapter completion', () {
    test('active chapter boundary request uses explicit lazy priority', () {
      expect(
        lazySectionPriorityForReaderReason(
          'card_depth_current_chapter_boundary',
        ),
        LazySectionWorkPriority.explicitNavigation,
      );
    });

    test('ordinary boundary prefetch priority is unchanged', () {
      expect(
        lazySectionPriorityForReaderReason('lazy_forward_boundary'),
        LazySectionWorkPriority.boundaryPrefetch,
      );
    });
  });
}

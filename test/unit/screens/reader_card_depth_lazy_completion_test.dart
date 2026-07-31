import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/screens/reader_screen.dart';
import 'package:nalori/services/lazy_section_repository.dart';

void main() {
  group('card-depth bounded readiness', () {
    test(
      'chapter denominators do not receive explicit navigation priority',
      () {
        expect(
          lazySectionPriorityForReaderReason(
            'card_depth_current_chapter_boundary',
          ),
          LazySectionWorkPriority.boundaryPrefetch,
        );
      },
    );

    test('ordinary boundary prefetch priority is unchanged', () {
      expect(
        lazySectionPriorityForReaderReason('lazy_forward_boundary'),
        LazySectionWorkPriority.boundaryPrefetch,
      );
    });
  });
}

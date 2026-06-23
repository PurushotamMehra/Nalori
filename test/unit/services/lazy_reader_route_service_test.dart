import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/services/lazy_reader_route_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'per-book lazy reader disable marker is independent and reversible',
    () async {
      final service = LazyReaderRouteService();

      expect(await service.isDisabledForBook('a.epub'), isFalse);
      expect(await service.isDisabledForBook('b.epub'), isFalse);

      await service.disableForBook('a.epub');

      expect(await service.isDisabledForBook('a.epub'), isTrue);
      expect(await service.isDisabledForBook('b.epub'), isFalse);

      await service.enableForBook('a.epub');

      expect(await service.isDisabledForBook('a.epub'), isFalse);
    },
  );
}

import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/services/user_education_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late UserEducationService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    service = UserEducationService();
  });

  test('defaults intro and reader hint to unseen', () async {
    expect(await service.hasSeenHowToUse(), false);
    expect(await service.hasSeenReaderGestureHint(), false);
  });

  test('marking intro and reader hint makes them seen', () async {
    await service.markHowToUseSeen();
    await service.markReaderGestureHintSeen();

    expect(await service.hasSeenHowToUse(), true);
    expect(await service.hasSeenReaderGestureHint(), true);
  });
}

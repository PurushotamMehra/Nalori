import 'package:shared_preferences/shared_preferences.dart';

class UserEducationService {
  static const String _howToUseSeenKey = 'education_howToUseSeen_v1';
  static const String _readerGestureHintSeenKey =
      'education_readerGestureHintSeen_v1';

  Future<bool> hasSeenHowToUse() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_howToUseSeenKey) ?? false;
  }

  Future<void> markHowToUseSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_howToUseSeenKey, true);
  }

  Future<bool> hasSeenReaderGestureHint() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_readerGestureHintSeenKey) ?? false;
  }

  Future<void> markReaderGestureHintSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_readerGestureHintSeenKey, true);
  }
}

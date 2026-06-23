import 'package:shared_preferences/shared_preferences.dart';

class LazyReaderRouteService {
  static const String _disabledBooksKey = 'lazy_reader_disabled_books_v1';

  Future<bool> isDisabledForBook(String bookId) async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_disabledBooksKey) ?? const <String>[])
        .contains(bookId);
  }

  Future<void> disableForBook(String bookId) async {
    final prefs = await SharedPreferences.getInstance();
    final disabled = {
      ...prefs.getStringList(_disabledBooksKey) ?? const <String>[],
      bookId,
    }.toList()..sort();
    await prefs.setStringList(_disabledBooksKey, disabled);
  }

  Future<void> enableForBook(String bookId) async {
    final prefs = await SharedPreferences.getInstance();
    final disabled = prefs.getStringList(_disabledBooksKey) ?? const <String>[];
    await prefs.setStringList(
      _disabledBooksKey,
      disabled.where((entry) => entry != bookId).toList(),
    );
  }
}

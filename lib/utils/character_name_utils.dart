String normalizeCharacterNameForKey(String text) {
  return text.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
}

String normalizeCharacterNameForDisplay(String text) {
  return text.trim().replaceAll(RegExp(r'\s+'), ' ');
}

List<String> characterNameAliases(String name) {
  final displayName = normalizeCharacterNameForDisplay(name);
  if (displayName.isEmpty) return const [];

  final aliases = <String>{displayName};
  for (final word in displayName.split(RegExp(r'\s+'))) {
    final clean = word.trim();
    if (_isUsefulNamePart(clean)) aliases.add(clean);
  }
  final sorted = aliases.toList()
    ..sort((a, b) {
      final length = b.length.compareTo(a.length);
      if (length != 0) return length;
      return a.toLowerCase().compareTo(b.toLowerCase());
    });
  return sorted;
}

bool _isUsefulNamePart(String word) {
  final lettersOnly = word.replaceAll(RegExp(r'[^A-Za-z]'), '');
  if (lettersOnly.length < 2) return false;
  const ignoredParts = {
    'mr',
    'mrs',
    'ms',
    'miss',
    'dr',
    'prof',
    'sir',
    'lady',
    'lord',
  };
  return !ignoredParts.contains(lettersOnly.toLowerCase());
}

String normalizePersonNameForDisplay(String value) {
  final compact = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (compact.isEmpty) return '';

  final parts = compact
      .split(',')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.length < 2) return compact;

  final lastName = parts.first;
  final remaining = parts.skip(1).join(' ').trim();
  if (remaining.isEmpty) return compact;
  return '$remaining $lastName';
}

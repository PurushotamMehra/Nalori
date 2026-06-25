import '../utils/person_name_utils.dart';

String normalizeCatalogText(String value) {
  return value
      .toLowerCase()
      .replaceAll('&', ' and ')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String normalizeCatalogPersonName(String value) {
  return normalizeCatalogText(normalizePersonNameForDisplay(value));
}

List<String> catalogSearchTokens(String value) {
  final normalized = normalizeCatalogText(value);
  if (normalized.isEmpty) return const [];
  return normalized.split(' ').where((token) => token.isNotEmpty).toList();
}

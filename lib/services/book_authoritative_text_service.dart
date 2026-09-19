import '../models/book_chunk.dart';

/// Returns normalized publisher-authored text for source consumers.
///
/// Phase A list markers are display-only, so list chunks require no special
/// filtering here. Existing table payload behavior intentionally remains
/// unchanged until the table phase.
String? authoritativeBookChunkText(BookChunk chunk) => chunk.text;

String authoritativeBookChunkTextOrEmpty(BookChunk chunk) =>
    authoritativeBookChunkText(chunk) ?? '';

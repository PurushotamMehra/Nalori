import 'dart:convert';

import '../services/lazy_epub_index_service.dart';
import '../services/lazy_parsed_book.dart';
import '../services/lazy_stable_card_service.dart';
import 'book_chunk.dart';
import 'canonical_pagination.dart';
import 'lazy_stable_card.dart';
import 'reader_checkpoint.dart';

/// Immutable reading-order metadata. Residency and known-empty maps are not
/// publication-end evidence. No content is parsed to capture this authority.
final class PublicationSpineAuthority {
  PublicationSpineAuthority.capture(LazyEpubIndex index)
    : _index = LazyEpubIndex(
        filePath: index.filePath,
        bookId: index.bookId,
        title: index.title,
        author: index.author,
        authorList: List.unmodifiable(index.authorList),
        contentDirectoryPath: index.contentDirectoryPath,
        manifest: Map.unmodifiable(index.manifest),
        spine: List.unmodifiable(index.spine),
        chapters: const [],
        coverHref: index.coverHref,
        schemaVersion: index.schemaVersion,
        publicationFingerprint: index.publicationFingerprint,
        fileSizeBytes: index.fileSizeBytes,
        fileModifiedMs: index.fileModifiedMs,
        normalizedHrefToManifestHref: Map.unmodifiable(
          index.normalizedHrefToManifestHref,
        ),
        normalizedHrefToSpineIndex: Map.unmodifiable(
          index.normalizedHrefToSpineIndex,
        ),
        totalReadableWeight: index.totalReadableWeight,
        warnings: const [],
      );

  final LazyEpubIndex _index;
  String get bookId => _index.bookId;
  String get publicationFingerprint => _index.publicationFingerprint;
  String get dependencyIdentity => lazySectionDependencySignature(_index);

  LazyStableSectionAuthority sectionAuthority(ParsedSection section) =>
      LazyStableSectionAuthority.capture(_index, section);

  LazySectionIdentity? successorOf(ParsedSection section) {
    sectionAuthority(section);
    final position = section.identity.spineIndex;
    if (!_index.spine[position].isLinear) {
      throw StateError('Nonlinear target has no linear book-end authority');
    }
    for (var i = position + 1; i < _index.spine.length; i++) {
      final item = _index.spine[i];
      if (item.isLinear) {
        return LazySectionIdentity.fromIndexItem(
          bookId: bookId,
          publicationFingerprint: publicationFingerprint,
          item: item,
          sourceChecksum: item.sourceChecksum,
          dependencySignature: dependencyIdentity,
        );
      }
    }
    return null;
  }
}

/// Complete, bounded source evidence for one section, or a single A -> A+B
/// extension. Records are copied before any async pagination can begin.
final class LazySectionInput {
  LazySectionInput._(
    this.publication,
    this._sections,
    this.snapshot,
    this.sectionAuthorities,
    this.nextCandidate,
  );

  factory LazySectionInput.capture({
    required PublicationSpineAuthority publication,
    required List<ParsedSection> sections,
  }) {
    if (sections.fold<int>(
          0,
          (count, section) => count + section.chunks.length,
        ) >
        CanonicalPaginationBounds.activeSourceCeiling) {
      throw StateError('Aggregate source count exceeds the bound');
    }
    if (sections.isEmpty || sections.length > 2) {
      throw StateError('Only one adjacent transfer is supported');
    }
    final encoded = sections
        .map((s) => canonicalJsonEncode(s.toJson()))
        .toList();
    if (encoded.fold<int>(0, (sum, s) => sum + utf8.encode(s).length) >
        LazyStableCardBody.maxEncodedBytes) {
      throw StateError('Aggregate source evidence exceeds the byte bound');
    }
    final copies = [
      for (final s in encoded)
        ParsedSection.fromJson(jsonDecode(s) as Map<String, dynamic>),
    ];
    final authorities = [
      for (final section in copies) publication.sectionAuthority(section),
    ];
    for (var i = 0; i < copies.length; i++) {
      if (copies[i].chunks.isEmpty) {
        throw StateError(
          'Empty-section certificates require a separate transfer',
        );
      }
      if (i > 0 &&
          publication.successorOf(copies[i - 1])?.stableKey !=
              copies[i].identity.stableKey) {
        throw StateError(
          'Section is not the immediate pinned linear successor',
        );
      }
    }
    final chunks = <BookChunk>[];
    final keys = <CanonicalPaginationSourceKey>[];
    for (var i = 0; i < copies.length; i++) {
      final section = copies[i];
      final authority = authorities[i];
      for (var local = 0; local < section.chunks.length; local++) {
        final ordinal = chunks.length;
        // Only unpublished source projections receive dense runtime ordinals.
        final json = Map<String, dynamic>.from(section.chunks[local].toJson());
        json['i'] = ordinal;
        if (json['sr'] case final List ranges) {
          final start = ordinal - local;
          json['sr'] = [
            for (final range in ranges)
              {
                ...Map<String, dynamic>.from(range as Map),
                'ci': (range['ci'] as int) + start,
              },
          ];
        }
        chunks.add(BookChunk.fromJson(json));
        keys.add(
          CanonicalPaginationSourceKey(
            sourceIdentity: authority.sourceIdentity(local),
            sectionIdentity: authority.sectionKey,
            spineIdentity: authority.sectionKey,
            sourceOrdinalHint: ordinal,
          ),
        );
      }
    }
    if (chunks.length > CanonicalPaginationBounds.activeSourceCeiling) {
      throw StateError('Aggregate snapshot exceeds the source bound');
    }
    final snapshot = CanonicalPaginationSourceSnapshot.pin(
      bookId: publication.bookId,
      publicationFingerprint: publication.publicationFingerprint,
      parserSourceIdentity: lazyParsedSectionParserVersion,
      sourceRevision: readerSha256(['LazySectionInputV1', encoded]),
      sourceChunks: chunks,
      sourceKeys: keys,
    );
    return LazySectionInput._(
      publication,
      List.unmodifiable(encoded),
      snapshot,
      List.unmodifiable(authorities),
      publication.successorOf(copies.last),
    );
  }

  final PublicationSpineAuthority publication;
  final List<String> _sections;
  final CanonicalPaginationSourceSnapshot snapshot;
  final List<LazyStableSectionAuthority> sectionAuthorities;
  final LazySectionIdentity? nextCandidate;
  bool get verifiedBookEnd => nextCandidate == null;
  int get sectionCount => _sections.length;
  int get lastSectionStart =>
      snapshot.sourceCount - sectionAuthorities.last.owners.length;
  List<ParsedSection> get sections => [
    for (final s in _sections)
      ParsedSection.fromJson(jsonDecode(s) as Map<String, dynamic>),
  ];

  LazySectionInput append(ParsedSection successor) => LazySectionInput.capture(
    publication: publication,
    sections: [...sections, successor],
  );

  void validateSnapshot(CanonicalPaginationSourceSnapshot candidate) {
    if (candidate.snapshotDigest != snapshot.snapshotDigest ||
        candidate.sourceRevision != snapshot.sourceRevision) {
      throw StateError('Section evidence does not authorize this snapshot');
    }
  }

  String prefixDigest(int count) => readerSha256([
    'LazyExactPrefixV1',
    for (var i = 0; i < count; i++)
      [
        snapshot.ownerAt(i).toDigestJson(),
        snapshot.resolveOrdinalSource(i).toJson(),
      ],
  ]);

  void validateExtensionOf(LazySectionInput old) {
    if (old.sectionCount != 1 ||
        sectionCount != 2 ||
        sectionAuthorities.first.publication !=
            old.sectionAuthorities.first.publication ||
        _sections.first != old._sections.single ||
        old.nextCandidate?.stableKey != sections.last.identity.stableKey ||
        prefixDigest(old.snapshot.sourceCount) !=
            old.prefixDigest(old.snapshot.sourceCount)) {
      throw StateError(
        'Exact prefix, complete section or adjacency proof failed',
      );
    }
  }
}

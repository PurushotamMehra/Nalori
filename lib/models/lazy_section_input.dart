import 'dart:convert';

import '../services/lazy_epub_index_service.dart';
import '../services/lazy_parsed_book.dart';
import '../services/lazy_stable_card_service.dart';
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
  int get accountedMetadataBytes =>
      2 *
      canonicalJsonEncode([
        _index.filePath,
        _index.bookId,
        _index.title,
        _index.author,
        _index.authorList,
        _index.contentDirectoryPath,
        _index.coverHref,
        _index.schemaVersion,
        _index.publicationFingerprint,
        _index.fileSizeBytes,
        _index.fileModifiedMs,
        _index.normalizedHrefToManifestHref,
        _index.normalizedHrefToSpineIndex,
        for (final item in _index.spine)
          [
            item.index,
            item.idRef,
            item.href,
            item.mediaType,
            item.fullPath,
            item.isLinear,
            item.sizeBytes,
            item.sourceChecksum,
            item.normalizedHref,
            item.structuralWeight,
            item.prefixWeight,
          ],
        for (final item in _index.manifest.values)
          [
            item.id,
            item.href,
            item.mediaType,
            item.fullPath,
            item.sizeBytes,
            item.normalizedHref,
            item.properties,
          ],
      ]).length;

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
    final records = <CanonicalLazySourceRecord>[];
    for (var i = 0; i < copies.length; i++) {
      final authority = authorities[i];
      for (var local = 0; local < copies[i].chunks.length; local++) {
        records.add(
          CanonicalLazySourceRecord.pin(
            source: copies[i].chunks[local],
            sourceIdentity: authority.sourceIdentity(local),
            sectionIdentity: authority.sectionKey,
            spineIdentity: authority.sectionKey,
          ),
        );
      }
    }
    final snapshot = _snapshot(publication, encoded, records);
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

  static CanonicalPaginationSourceSnapshot _snapshot(
    PublicationSpineAuthority publication,
    List<String> encoded,
    List<CanonicalLazySourceRecord> records,
  ) => CanonicalPaginationSourceSnapshot.pinLazy(
    bookId: publication.bookId,
    publicationFingerprint: publication.publicationFingerprint,
    parserSourceIdentity: lazyParsedSectionParserVersion,
    sourceRevision: readerSha256(['LazySectionInputV1', encoded]),
    records: records,
  );

  List<String> get encodedSections => _sections;
  List<CanonicalLazySourceRecord> get sourceRecords => snapshot.lazyRecords!;

  LazySectionInput append(ParsedSection successor) {
    if (sectionCount != 1) {
      throw StateError('Retire obsolete prefix before another handoff');
    }
    final added = LazySectionInput.capture(
      publication: publication,
      sections: [successor],
    );
    if (nextCandidate?.stableKey != successor.identity.stableKey) {
      throw StateError('Section is not the immediate pinned successor');
    }
    final encoded = List<String>.unmodifiable([
      ..._sections,
      ...added._sections,
    ]);
    final records = [...sourceRecords, ...added.sourceRecords];
    if (records.length > CanonicalPaginationBounds.activeSourceCeiling ||
        encoded.fold<int>(0, (n, s) => n + utf8.encode(s).length) >
            LazyStableCardBody.maxEncodedBytes) {
      throw StateError('Expanded source evidence exceeds bounds');
    }
    return LazySectionInput._(
      publication,
      encoded,
      _snapshot(publication, encoded, records),
      List.unmodifiable([...sectionAuthorities, ...added.sectionAuthorities]),
      added.nextCandidate,
    );
  }

  /// Exact immutable suffix; retained records are shared, not reencoded.
  LazySectionInput retainLastSection() {
    final encoded = List<String>.unmodifiable([_sections.last]);
    final records = sourceRecords.sublist(lastSectionStart);
    final result = LazySectionInput._(
      publication,
      encoded,
      _snapshot(publication, encoded, records),
      List.unmodifiable([sectionAuthorities.last]),
      nextCandidate,
    );
    result.validateSuffixOf(this);
    return result;
  }

  void validateSuffixOf(LazySectionInput old) {
    if (sectionCount != 1 ||
        _sections.single != old._sections.last ||
        sourceRecords.length !=
            old.sourceRecords.length - old.lastSectionStart) {
      throw StateError('Invalid retained suffix');
    }
    for (var i = 0; i < sourceRecords.length; i++) {
      if (!identical(
        sourceRecords[i],
        old.sourceRecords[old.lastSectionStart + i],
      )) {
        throw StateError('Suffix backing/source ownership changed');
      }
    }
  }

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

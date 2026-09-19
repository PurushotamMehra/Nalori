import 'package:nalori/models/reading_settings.dart';
import 'package:nalori/services/book_cache_service.dart';
import 'package:nalori/services/display_generation_coordinator.dart';
import 'package:nalori/services/display_section_memory_cache.dart';
import 'package:nalori/services/progressive_display_state.dart';
import 'package:nalori/services/segmented_display_cache_service.dart';

import '../support/reader_contract_sandbox.dart';
import 'reader_core_pagination_harness.dart';

enum ReaderCacheOrderState {
  coldFull('cold-full'),
  coldSegmented('cold-segmented'),
  warmMemory('warm-memory'),
  warmDisk('warm-disk'),
  memoryEviction('memory-eviction'),
  reopenReload('close-reopen-reload');

  const ReaderCacheOrderState(this.label);

  final String label;
}

final class ReaderCacheRangePlan {
  const ReaderCacheRangePlan({
    required this.label,
    required this.ranges,
    required this.expectedToMatchFull,
    this.failureIds = const <ReaderCacheOrderState, String>{},
  });

  final String label;
  final List<SourceChunkRange> ranges;
  final bool expectedToMatchFull;
  final Map<ReaderCacheOrderState, String> failureIds;

  String? failureIdFor(ReaderCacheOrderState state) => failureIds[state];
}

final class ReaderCacheOrderOutcome {
  const ReaderCacheOrderOutcome({
    required this.construction,
    required this.diagnostics,
  });

  final ReaderPaginationConstruction construction;
  final String diagnostics;
}

/// Connects the P03 paginator harness to the same production memory, disk,
/// record-conversion and progressive-publication APIs used by ReaderScreen.
/// It contains no cache policy, serialization or pagination implementation.
final class ReaderCoreCacheOrderHarness {
  ReaderCoreCacheOrderHarness._({
    required this.sandbox,
    required this.pagination,
    required this.cacheKey,
    required this.signature,
    required this.segmentedKey,
  });

  factory ReaderCoreCacheOrderHarness.create({
    required ReaderContractSandbox sandbox,
    required ReaderCorePaginationHarness pagination,
  }) {
    const settings = ReadingSettings();
    final inputs = pagination.environment.inputs;
    final cacheKey = BookCacheService.displayChunkKey(
      bookId: sandbox.identity.bookId,
      fontSize: settings.fontSizeValue,
      fontFamily: settings.fontFamily.name,
      fontWeight: settings.fontWeight.name,
      fontMetricIdentity: settings.fontMetricIdentity,
      locale: inputs.locale.toLanguageTag(),
      density: settings.densityMultiplier,
      lineHeight: settings.lineHeight,
      paragraphSpacing: settings.paragraphSpacing,
      sideMargin: settings.sideMargin,
      screenW: inputs.viewportSize.width,
      screenH: inputs.viewportSize.height,
      enableCardDepth: settings.enableCardDepth,
      textScaleFactor: inputs.textScaleFactor,
      safeAreaTop: inputs.safeArea.top,
      safeAreaBottom: inputs.safeArea.bottom,
      safeAreaLeft: inputs.safeArea.left,
      safeAreaRight: inputs.safeArea.right,
    );
    final settingsSignature =
        '${settings.fontSizeValue}|${settings.fontFamily.name}|'
        '${settings.fontWeight.name}|${settings.densityMultiplier}|'
        '${settings.fontMetricIdentity}|${inputs.locale.toLanguageTag()}|'
        '${settings.lineHeight}|${settings.paragraphSpacing}|'
        '${settings.sideMargin}|${settings.enableCardDepth}|'
        '${inputs.textScaleFactor}';
    final viewportSignature =
        '${inputs.viewportSize.width}x${inputs.viewportSize.height}|'
        '${inputs.safeArea.top},${inputs.safeArea.bottom},'
        '${inputs.safeArea.left},${inputs.safeArea.right}';
    final signature = DisplayGenerationSignature(
      bookId: sandbox.identity.bookId,
      parsedContentVersion: BookCacheService.parsedBookCacheFormatVersion,
      layoutSignature: BookCacheService.displayLayoutVersion,
      settingsSignature: settingsSignature,
      viewportSignature: viewportSignature,
      cacheKey: cacheKey,
    );
    return ReaderCoreCacheOrderHarness._(
      sandbox: sandbox,
      pagination: pagination,
      cacheKey: cacheKey,
      signature: signature,
      segmentedKey: SegmentedDisplayCacheKey(
        bookId: sandbox.identity.bookId,
        cacheKey: cacheKey,
        signature: signature,
        sourceChunkCount: pagination.sourceChunks.length,
      ),
    );
  }

  final ReaderContractSandbox sandbox;
  final ReaderCorePaginationHarness pagination;
  final String cacheKey;
  final DisplayGenerationSignature signature;
  final SegmentedDisplayCacheKey segmentedKey;

  Future<ReaderCacheOrderOutcome> exercise({
    required ReaderCacheRangePlan plan,
    required ReaderCacheOrderState state,
  }) async {
    final initialMemoryEntries = sandbox.memoryDisplayCache.entryCount;
    final initialManifest = await sandbox.segmentedDisplayCache.loadManifest(
      segmentedKey,
    );
    if (initialMemoryEntries != 0 || initialManifest != null) {
      throw StateError(
        'Cache scenario did not start cold: memory=$initialMemoryEntries; '
        'manifest=${initialManifest?.segments.length}.\n${sandbox.diagnostics}',
      );
    }

    if (state == ReaderCacheOrderState.coldFull) {
      final construction = await pagination.fullRange();
      return ReaderCacheOrderOutcome(
        construction: construction,
        diagnostics: _diagnostics(
          plan: plan,
          state: state,
          observations: const <String>[
            'memory-miss: entryCount=0',
            'disk-miss: manifest=null',
            'actual: independent full-range production pagination',
          ],
        ),
      );
    }

    final generated = await pagination.legacyForwardFirst(plan.ranges);
    final manifest = await _storeGenerated(generated.results);
    await sandbox.wholeCache.cacheDisplayChunks(
      key: cacheKey,
      displayChunks: generated.state.displayChunks,
      displayToOriginal: generated.state.displayToOriginal,
      originalToDisplay: generated.state.originalToDisplay,
      shouldWrite: () => true,
    );
    final wholeRecord = await sandbox.wholeCache.loadDisplayChunks(cacheKey);
    if (wholeRecord == null) {
      throw StateError('Expected production whole-display cache hit.');
    }
    final observations = <String>[
      'initial-memory-miss: entryCount=$initialMemoryEntries',
      'initial-disk-miss: manifest=null',
      'stored-records: ${_manifestEvidence(manifest)}',
      'whole-cache-hit: cards=${wholeRecord.displayChunks.length}',
      'whole-cache-direct-publication-rejected: '
          '${CanonicalDisplayPublicationOutcomeKind.canonicalRegenerationRequired.name}',
    ];

    final replay = switch (state) {
      ReaderCacheOrderState.coldSegmented => await _loadColdSegmented(
        plan,
        generated.results,
        observations,
      ),
      ReaderCacheOrderState.warmMemory => _loadFromMemory(
        plan,
        generated.results,
        observations,
      ),
      ReaderCacheOrderState.warmDisk => await _loadFromFreshDiskService(
        plan,
        generated.results,
        observations,
        label: 'warm-disk',
      ),
      ReaderCacheOrderState.memoryEviction => await _loadAfterMemoryEviction(
        plan,
        generated.results,
        observations,
      ),
      ReaderCacheOrderState.reopenReload => await _loadAfterReopen(
        plan,
        generated.results,
        observations,
      ),
      ReaderCacheOrderState.coldFull => throw StateError('handled above'),
    };
    observations.add(
      'direct-publication-rejected: '
      '${CanonicalDisplayPublicationOutcomeKind.canonicalRegenerationRequired.name}; '
      'records=${replay.results.length}',
    );
    final construction = await pagination.regenerateCanonicalAfterCacheRecords(
      label: 'cache-${state.label}-canonical-regenerated',
      cachedResults: replay.results,
      requestedRanges: plan.ranges.map((range) => range.toString()).toList(),
    );
    observations.add(
      'bounded-canonical-regeneration: operations=${construction.results.length}; '
      'cards=${construction.state.canonicalCards.length}; '
      'cacheWriteAuthority=${construction.state.hasCanonicalCacheWriteAuthority}',
    );

    return ReaderCacheOrderOutcome(
      construction: construction,
      diagnostics: _diagnostics(
        plan: plan,
        state: state,
        observations: observations,
      ),
    );
  }

  Future<SegmentedDisplayCacheManifest> _storeGenerated(
    List<DisplayRangeResult> results,
  ) async {
    for (final result in results) {
      sandbox.memoryDisplayCache.put(cacheKey: cacheKey, result: result);
      await sandbox.segmentedDisplayCache.writeSegment(
        key: segmentedKey,
        result: result,
        generationId: result.request.generationId,
        shouldWrite: () => true,
      );
    }
    final manifest = await sandbox.segmentedDisplayCache.loadManifest(
      segmentedKey,
    );
    if (manifest == null || manifest.segments.length != results.length) {
      throw StateError(
        'Production segment writes did not yield the expected records: '
        '${manifest?.segments.length}/${results.length}.\n'
        '${sandbox.diagnostics}',
      );
    }
    return manifest;
  }

  Future<ReaderPaginationConstruction> _loadColdSegmented(
    ReaderCacheRangePlan plan,
    List<DisplayRangeResult> generated,
    List<String> observations,
  ) async {
    final hits = await _loadDiskResults(
      service: sandbox.segmentedDisplayCache,
      plan: plan,
      generated: generated,
      observations: observations,
      reason: 'cold-segmented',
    );
    return pagination.publishForwardResults(
      label: 'cache-cold-segmented',
      results: hits,
      requestedRanges: plan.ranges.map((range) => range.toString()).toList(),
    );
  }

  ReaderPaginationConstruction _loadFromMemory(
    ReaderCacheRangePlan plan,
    List<DisplayRangeResult> generated,
    List<String> observations,
  ) {
    final hits = <DisplayRangeResult>[];
    for (var index = 0; index < plan.ranges.length; index++) {
      final range = plan.ranges[index];
      final entry = sandbox.memoryDisplayCache.get(
        DisplaySectionMemoryCacheKey(cacheKey: cacheKey, sourceRange: range),
      );
      if (entry == null) {
        throw StateError('Expected production memory hit for $range.');
      }
      observations.add(
        'memory-hit: range=$range bytes=${entry.estimatedBytes}',
      );
      hits.add(
        entry.toResult(
          direction: index == 0
              ? DisplayRangeDirection.initial
              : DisplayRangeDirection.forward,
          generationId: 7000 + index,
          reason: 'display_memory_p03_cache_order',
        ),
      );
    }
    observations.add(
      'memory-hit-count=${hits.length}; retainedBytes='
      '${sandbox.memoryDisplayCache.estimatedBytes}',
    );
    return pagination.publishForwardResults(
      label: 'cache-warm-memory',
      results: hits,
      requestedRanges: plan.ranges.map((range) => range.toString()).toList(),
    );
  }

  Future<ReaderPaginationConstruction> _loadFromFreshDiskService(
    ReaderCacheRangePlan plan,
    List<DisplayRangeResult> generated,
    List<String> observations, {
    required String label,
  }) async {
    sandbox.memoryDisplayCache.clear();
    for (final range in plan.ranges) {
      final miss = sandbox.memoryDisplayCache.get(
        DisplaySectionMemoryCacheKey(cacheKey: cacheKey, sourceRange: range),
      );
      if (miss != null) throw StateError('Memory was not empty for $range.');
    }
    observations.add('memory-cleared-and-miss-proven');

    final reopened = SegmentedDisplayCacheService(
      rootDirectory: sandbox.segmentedDisplayCacheDirectory,
    );
    final hits = await _loadDiskResults(
      service: reopened,
      plan: plan,
      generated: generated,
      observations: observations,
      reason: label,
    );
    return pagination.publishForwardResults(
      label: 'cache-$label',
      results: hits,
      requestedRanges: plan.ranges.map((range) => range.toString()).toList(),
    );
  }

  Future<ReaderPaginationConstruction> _loadAfterMemoryEviction(
    ReaderCacheRangePlan plan,
    List<DisplayRangeResult> generated,
    List<String> observations,
  ) async {
    final sizingCache = DisplaySectionMemoryCache();
    for (final result in generated) {
      sizingCache.put(cacheKey: cacheKey, result: result);
    }
    final sizes = <SourceChunkRange, int>{};
    for (final range in plan.ranges) {
      final entry = sizingCache.get(
        DisplaySectionMemoryCacheKey(cacheKey: cacheKey, sourceRange: range),
      );
      if (entry == null) throw StateError('Sizing entry missing for $range.');
      sizes[range] = entry.estimatedBytes;
    }
    sizingCache.clear();

    final victim = plan.ranges.first;
    final retained = plan.ranges.skip(1).toList(growable: false);
    final retainedBudget = retained.fold<int>(
      0,
      (sum, range) => sum + sizes[range]!,
    );
    final bounded = DisplaySectionMemoryCache(byteBudget: retainedBudget);
    bounded.pinPreparedRanges(cacheKey, retained);
    for (final result in generated) {
      bounded.put(cacheKey: cacheKey, result: result);
    }
    final victimKey = DisplaySectionMemoryCacheKey(
      cacheKey: cacheKey,
      sourceRange: victim,
    );
    if (bounded.get(victimKey) != null) {
      throw StateError('Production memory policy did not evict $victim.');
    }
    for (final range in retained) {
      final entry = bounded.get(
        DisplaySectionMemoryCacheKey(cacheKey: cacheKey, sourceRange: range),
      );
      if (entry == null) {
        throw StateError('Production memory policy did not retain $range.');
      }
    }
    observations.add(
      'policy-eviction: budget=$retainedBudget victim=$victim '
      'retained=${retained.join(',')} keys=${bounded.keys.map((key) => key.sourceRange).join(',')}',
    );

    final disk = SegmentedDisplayCacheService(
      rootDirectory: sandbox.segmentedDisplayCacheDirectory,
    );
    final replay = <DisplayRangeResult>[];
    for (var index = 0; index < plan.ranges.length; index++) {
      final range = plan.ranges[index];
      final memory = bounded.get(
        DisplaySectionMemoryCacheKey(cacheKey: cacheKey, sourceRange: range),
      );
      if (memory != null) {
        observations.add('fallback-memory-hit: range=$range');
        replay.add(
          memory.toResult(
            direction: index == 0
                ? DisplayRangeDirection.initial
                : DisplayRangeDirection.forward,
            generationId: 7200 + index,
            reason: 'display_memory_p03_eviction',
          ),
        );
        continue;
      }
      final segment = await disk.loadRange(
        key: segmentedKey,
        sourceRange: range,
      );
      if (segment == null) {
        throw StateError('Disk fallback missed evicted range $range.');
      }
      observations.add(
        'fallback-disk-hit: range=$range record=${_recordEvidence(segment.record)}',
      );
      replay.add(
        segment.toResult(
          direction: index == 0
              ? DisplayRangeDirection.initial
              : DisplayRangeDirection.forward,
          generationId: 7200 + index,
          reason: 'segmented_cache_p03_eviction',
        ),
      );
    }
    bounded.clear();
    return pagination.publishForwardResults(
      label: 'cache-memory-eviction-disk-fallback',
      results: replay,
      requestedRanges: plan.ranges.map((range) => range.toString()).toList(),
    );
  }

  Future<ReaderPaginationConstruction> _loadAfterReopen(
    ReaderCacheRangePlan plan,
    List<DisplayRangeResult> generated,
    List<String> observations,
  ) async {
    sandbox.memoryDisplayCache.clear();
    final firstFreshService = SegmentedDisplayCacheService(
      rootDirectory: sandbox.segmentedDisplayCacheDirectory,
    );
    final firstLoad = await _loadDiskResults(
      service: firstFreshService,
      plan: plan,
      generated: generated,
      observations: observations,
      reason: 'pre-reopen-proof',
    );
    if (firstLoad.length != plan.ranges.length) {
      throw StateError('Pre-reopen persisted-byte load was incomplete.');
    }
    final reopened = SegmentedDisplayCacheService(
      rootDirectory: sandbox.segmentedDisplayCacheDirectory,
    );
    final reloaded = await _loadDiskResults(
      service: reopened,
      plan: plan,
      generated: generated,
      observations: observations,
      reason: 'fresh-service-reload',
    );
    observations.add(
      'service-lifecycle: writes awaited; no production close API; '
      'two fresh service instances loaded persisted bytes',
    );
    return pagination.publishForwardResults(
      label: 'cache-close-reopen-reload',
      results: reloaded,
      requestedRanges: plan.ranges.map((range) => range.toString()).toList(),
    );
  }

  Future<List<DisplayRangeResult>> _loadDiskResults({
    required SegmentedDisplayCacheService service,
    required ReaderCacheRangePlan plan,
    required List<DisplayRangeResult> generated,
    required List<String> observations,
    required String reason,
  }) async {
    final manifest = await service.loadManifest(segmentedKey);
    if (manifest == null || manifest.segments.length != plan.ranges.length) {
      throw StateError('Fresh disk service did not load the manifest.');
    }
    observations.add('$reason-manifest: ${_manifestEvidence(manifest)}');
    final hits = <DisplayRangeResult>[];
    for (var index = 0; index < plan.ranges.length; index++) {
      final range = plan.ranges[index];
      final segment = await service.loadRange(
        key: segmentedKey,
        sourceRange: range,
      );
      if (segment == null) throw StateError('Disk hit missing for $range.');
      if (segment.displayChunks.isNotEmpty &&
          generated[index].displayChunks.isNotEmpty &&
          identical(
            segment.displayChunks.first,
            generated[index].displayChunks.first,
          )) {
        throw StateError('Disk hit reused the generated in-memory card.');
      }
      observations.add(
        '$reason-disk-hit: range=$range record=${_recordEvidence(segment.record)}',
      );
      hits.add(
        segment.toResult(
          direction: index == 0
              ? DisplayRangeDirection.initial
              : DisplayRangeDirection.forward,
          generationId: 7100 + index,
          reason: 'segmented_cache_p03_$reason',
        ),
      );
    }
    return hits;
  }

  String _diagnostics({
    required ReaderCacheRangePlan plan,
    required ReaderCacheOrderState state,
    required List<String> observations,
  }) =>
      'cacheState=${state.label}; plan=${plan.label}; '
      'sandboxRoot=${sandbox.root.path}; book=${sandbox.identity.bookId}; '
      'session=${sandbox.identity.sessionId}; '
      'publication=${sandbox.identity.publicationFingerprint}; '
      'layout=${pagination.layoutIdentity}; cacheKey=$cacheKey; '
      'generationSignature=$signature; '
      'requests=${plan.ranges.map((range) => range.toString()).join(' -> ')}; '
      'observations=${observations.join(' | ')}';
}

String _manifestEvidence(SegmentedDisplayCacheManifest manifest) =>
    'version=${manifest.version}; book=${manifest.bookId}; '
    'cacheKey=${manifest.cacheKey}; parsed=${manifest.parsedContentVersion}; '
    'parser=${manifest.parserVersion}; layout=${manifest.displayLayoutVersion}; '
    'settings=${manifest.settingsSignature}; '
    'viewport=${manifest.viewportSignature}; '
    'sourceChunkCount=${manifest.sourceChunkCount}; complete=${manifest.complete}; '
    'records=${manifest.segments.map(_recordEvidence).join(' / ')}';

String _recordEvidence(DisplaySegmentRecord record) =>
    'range=${record.sourceRange}; actual='
    '[${record.actualSourceStart},${record.actualSourceEndExclusive}); '
    'file=${record.fileName}; cards=${record.displayChunkCount}; '
    'dto=${record.displayToOriginalCount}; otd=${record.originalToDisplayCount}; '
    'checksum=${record.checksum}; generation=${record.generationId}; '
    'status=${record.status}; bytes=${record.fileSizeBytes}';

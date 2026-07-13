import 'lazy_parsed_book.dart';

enum ParsedCacheStoragePressure { normal, low, critical }

typedef ParsedCacheClock = DateTime Function();
typedef ParsedCacheStoragePressureProvider =
    ParsedCacheStoragePressure Function();

enum ParsedSectionProtection {
  cold,
  recentBook,
  recentNearby,
  activeBook,
  activeNearby,
}

final class ParsedSectionRetentionSnapshot {
  const ParsedSectionRetentionSnapshot({
    required this.activePublications,
    required this.activeNearbyKeys,
    required this.recentBookIds,
    required this.recentNearbyKeys,
  });

  final Set<String> activePublications;
  final Set<String> activeNearbyKeys;
  final List<String> recentBookIds;
  final Set<String> recentNearbyKeys;

  ParsedSectionProtection protectionFor(LazySectionIdentity identity) {
    if (activeNearbyKeys.contains(identity.stableKey)) {
      return ParsedSectionProtection.activeNearby;
    }
    if (activePublications.contains(
      '${identity.bookId}|${identity.publicationFingerprint}',
    )) {
      return ParsedSectionProtection.activeBook;
    }
    if (recentNearbyKeys.contains(identity.stableKey)) {
      return ParsedSectionProtection.recentNearby;
    }
    if (recentBookIds.contains(identity.bookId)) {
      return ParsedSectionProtection.recentBook;
    }
    return ParsedSectionProtection.cold;
  }
}

final class ParsedSectionRetentionRegistry {
  ParsedSectionRetentionRegistry();

  static final ParsedSectionRetentionRegistry instance =
      ParsedSectionRetentionRegistry();

  final Map<Object, _ActivePublication> _active = {};
  final Map<String, _RecentPublication> _recent = {};

  void setActive({
    required Object owner,
    required String bookId,
    required String publicationFingerprint,
    required Iterable<LazySectionIdentity> nearbySections,
  }) {
    _active[owner] = _ActivePublication(
      bookId: bookId,
      publicationFingerprint: publicationFingerprint,
      nearbyKeys: nearbySections.map((identity) => identity.stableKey).toSet(),
    );
  }

  void clearActive(Object owner) => _active.remove(owner);

  void removeBook(String bookId) {
    _recent.remove(bookId);
    _active.removeWhere((_, publication) => publication.bookId == bookId);
  }

  void recordMeaningfulRead({
    required String bookId,
    required int readAtMs,
    LazySectionIdentity? lastVisible,
    Iterable<LazySectionIdentity> adjacent = const [],
  }) {
    _recent[bookId] = _RecentPublication(
      readAtMs: readAtMs,
      nearbyKeys: {
        if (lastVisible != null) lastVisible.stableKey,
        ...adjacent.map((identity) => identity.stableKey),
      },
    );
  }

  ParsedSectionRetentionSnapshot snapshot({
    ParsedCacheStoragePressure pressure = ParsedCacheStoragePressure.normal,
  }) {
    final activePublications = _active.values
        .map((entry) => '${entry.bookId}|${entry.publicationFingerprint}')
        .toSet();
    final activeNearby = _active.values
        .expand((entry) => entry.nearbyKeys)
        .toSet();
    final recentLimit = switch (pressure) {
      ParsedCacheStoragePressure.normal => 2,
      ParsedCacheStoragePressure.low => 1,
      ParsedCacheStoragePressure.critical => 0,
    };
    final recent = _recent.entries.toList()
      ..sort((a, b) => b.value.readAtMs.compareTo(a.value.readAtMs));
    final protectedRecent = recent.take(recentLimit).toList(growable: false);
    return ParsedSectionRetentionSnapshot(
      activePublications: activePublications,
      activeNearbyKeys: activeNearby,
      recentBookIds: protectedRecent.map((entry) => entry.key).toList(),
      recentNearbyKeys: protectedRecent
          .expand((entry) => entry.value.nearbyKeys)
          .toSet(),
    );
  }
}

final class ParsedSectionCachePolicy {
  const ParsedSectionCachePolicy({
    this.configuredBudgetBytes = defaultBudgetBytes,
    this.lowStorageBudgetFraction = 0.5,
    this.criticalStorageBudgetFraction = 0.25,
    this.minimumBudgetBytes = 24 * 1024 * 1024,
  });

  static const int defaultBudgetBytes = 192 * 1024 * 1024;

  final int configuredBudgetBytes;
  final double lowStorageBudgetFraction;
  final double criticalStorageBudgetFraction;
  final int minimumBudgetBytes;

  int effectiveBudget(ParsedCacheStoragePressure pressure) {
    final fraction = switch (pressure) {
      ParsedCacheStoragePressure.normal => 1.0,
      ParsedCacheStoragePressure.low => lowStorageBudgetFraction,
      ParsedCacheStoragePressure.critical => criticalStorageBudgetFraction,
    };
    return (configuredBudgetBytes * fraction).round().clamp(
      minimumBudgetBytes,
      configuredBudgetBytes,
    );
  }

  bool allowsSpeculativeWork(
    int priorityRank,
    ParsedCacheStoragePressure pressure,
  ) {
    if (priorityRank <= 2) return true;
    return switch (pressure) {
      ParsedCacheStoragePressure.normal => true,
      ParsedCacheStoragePressure.low => priorityRank <= 3,
      ParsedCacheStoragePressure.critical => false,
    };
  }
}

final class _ActivePublication {
  const _ActivePublication({
    required this.bookId,
    required this.publicationFingerprint,
    required this.nearbyKeys,
  });

  final String bookId;
  final String publicationFingerprint;
  final Set<String> nearbyKeys;
}

final class _RecentPublication {
  const _RecentPublication({required this.readAtMs, required this.nearbyKeys});

  final int readAtMs;
  final Set<String> nearbyKeys;
}

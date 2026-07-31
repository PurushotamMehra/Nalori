import 'dart:async';

import '../models/stable_book_location.dart';

class ChapterCardLayoutKey {
  const ChapterCardLayoutKey({
    required this.bookId,
    required this.publicationFingerprint,
    required this.chapterIdentity,
    required this.parserSchema,
    required this.displaySchema,
    required this.settingsSignature,
    required this.viewportSignature,
    required this.cardMode,
  });

  final String bookId;
  final String publicationFingerprint;
  final String chapterIdentity;
  final int parserSchema;
  final String displaySchema;
  final String settingsSignature;
  final String viewportSignature;
  final bool cardMode;

  String get cacheKey => [
    bookId,
    publicationFingerprint,
    chapterIdentity,
    parserSchema,
    displaySchema,
    settingsSignature,
    viewportSignature,
    cardMode,
  ].join('|');

  Map<String, dynamic> toJson() => {
    'bookId': bookId,
    'publicationFingerprint': publicationFingerprint,
    'chapterIdentity': chapterIdentity,
    'parserSchema': parserSchema,
    'displaySchema': displaySchema,
    'settingsSignature': settingsSignature,
    'viewportSignature': viewportSignature,
    'cardMode': cardMode,
  };

  factory ChapterCardLayoutKey.fromJson(Map<String, dynamic> json) {
    return ChapterCardLayoutKey(
      bookId: json['bookId'] as String,
      publicationFingerprint: json['publicationFingerprint'] as String,
      chapterIdentity: json['chapterIdentity'] as String,
      parserSchema: (json['parserSchema'] as num).toInt(),
      displaySchema: json['displaySchema'] as String,
      settingsSignature: json['settingsSignature'] as String,
      viewportSignature: json['viewportSignature'] as String,
      cardMode: json['cardMode'] as bool,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ChapterCardLayoutKey && other.cacheKey == cacheKey;

  @override
  int get hashCode => cacheKey.hashCode;
}

class ChapterCardSourceRange {
  const ChapterCardSourceRange({required this.start, required this.end});

  final StableBookLocation start;
  final StableBookLocation end;

  bool contains(StableBookLocation location) {
    return compareStableSourceLocations(start, location) <= 0 &&
        compareStableSourceLocations(location, end) < 0;
  }

  Map<String, dynamic> toJson() => {
    'start': start.toJson(),
    'end': end.toJson(),
  };

  factory ChapterCardSourceRange.fromJson(Map<String, dynamic> json) {
    return ChapterCardSourceRange(
      start: StableBookLocation.fromJson(
        Map<String, dynamic>.from(json['start'] as Map),
      ),
      end: StableBookLocation.fromJson(
        Map<String, dynamic>.from(json['end'] as Map),
      ),
    );
  }
}

class ChapterCardLayout {
  const ChapterCardLayout({
    required this.key,
    required this.pages,
    required this.completedAtMs,
  });

  final ChapterCardLayoutKey key;
  final List<ChapterCardSourceRange> pages;
  final int completedAtMs;

  int get totalCards => pages.length;

  int? pageNumberFor(StableBookLocation location) {
    for (var i = 0; i < pages.length; i++) {
      if (pages[i].contains(location)) return i + 1;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'v': 1,
    'key': key.toJson(),
    'pages': pages.map((page) => page.toJson()).toList(),
    'completedAtMs': completedAtMs,
  };

  factory ChapterCardLayout.fromJson(Map<String, dynamic> json) {
    return ChapterCardLayout(
      key: ChapterCardLayoutKey.fromJson(
        Map<String, dynamic>.from(json['key'] as Map),
      ),
      pages: (json['pages'] as List<dynamic>)
          .map(
            (page) => ChapterCardSourceRange.fromJson(
              Map<String, dynamic>.from(page as Map),
            ),
          )
          .toList(growable: false),
      completedAtMs: (json['completedAtMs'] as num).toInt(),
    );
  }
}

int compareStableSourceLocations(
  StableBookLocation left,
  StableBookLocation right,
) {
  final spine = left.spineIndex.compareTo(right.spineIndex);
  if (spine != 0) return spine;
  final leftLocal = left.localChunkIndex;
  final rightLocal = right.localChunkIndex;
  if (leftLocal != null && rightLocal != null) {
    final local = leftLocal.compareTo(rightLocal);
    if (local != 0) return local;
  }
  return left.textOffset.compareTo(right.textOffset);
}

typedef ChapterCardLayoutLoader = Future<ChapterCardLayout?> Function();
typedef ChapterCardLayoutGenerator =
    Future<ChapterCardLayout?> Function(bool Function() isCurrent);

class ChapterCardLayoutCoordinator {
  int _generation = 0;
  ChapterCardLayoutKey? _activeKey;
  Future<ChapterCardLayout?>? _active;
  ChapterCardLayout? _published;

  ChapterCardLayout? get published => _published;
  bool get isCounting => _active != null;
  bool isActiveFor(ChapterCardLayoutKey key) =>
      _active != null && _activeKey == key;

  Future<ChapterCardLayout?> ensure({
    required ChapterCardLayoutKey key,
    required ChapterCardLayoutLoader load,
    required ChapterCardLayoutGenerator generate,
  }) {
    final published = _published;
    if (published != null && published.key == key) {
      return Future<ChapterCardLayout?>.value(published);
    }
    final active = _active;
    if (active != null && _activeKey == key) return active;

    final generation = ++_generation;
    _activeKey = key;
    bool isCurrent() => generation == _generation && _activeKey == key;

    final task = () async {
      final cached = await load();
      if (!isCurrent()) return null;
      final result = cached ?? await generate(isCurrent);
      if (!isCurrent() || result == null || result.key != key) return null;
      _published = result;
      return result;
    }();
    _active = task;
    void clearActive() {
      if (identical(_active, task)) {
        _active = null;
        _activeKey = null;
      }
    }

    unawaited(
      task.then<void>(
        (_) => clearActive(),
        onError: (Object _, StackTrace __) => clearActive(),
      ),
    );
    return task;
  }

  void cancel() {
    _generation++;
    _active = null;
    _activeKey = null;
  }

  void clearPublished() {
    cancel();
    _published = null;
  }
}

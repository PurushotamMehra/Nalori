import '../utils/person_name_utils.dart';

String labelForLanguageCode(String code) {
  switch (code.toLowerCase()) {
    case 'en':
      return 'English';
    case 'fr':
      return 'French';
    case 'de':
      return 'German';
    case 'es':
      return 'Spanish';
    case 'it':
      return 'Italian';
    case 'pt':
      return 'Portuguese';
    case 'nl':
      return 'Dutch';
    case 'fi':
      return 'Finnish';
    case 'la':
      return 'Latin';
    case 'el':
      return 'Greek';
    default:
      return code.toUpperCase();
  }
}

class PublicDomainPerson {
  final String name;
  final int? birthYear;
  final int? deathYear;

  const PublicDomainPerson({
    required this.name,
    this.birthYear,
    this.deathYear,
  });

  String get lifespanLabel {
    if (birthYear == null && deathYear == null) return '';
    final start = birthYear?.toString() ?? '?';
    final end = deathYear?.toString() ?? '?';
    return '$start-$end';
  }

  String get displayLabel {
    final lifespan = lifespanLabel;
    if (lifespan.isEmpty) return name;
    return '$name ($lifespan)';
  }

  factory PublicDomainPerson.fromJson(Map<String, dynamic> json) {
    final name = (json['name'] as String?)?.trim() ?? '';
    if (name.isEmpty) {
      throw const FormatException('Missing person name');
    }

    return PublicDomainPerson(
      name: normalizePersonNameForDisplay(name),
      birthYear: (json['birth_year'] as num?)?.toInt(),
      deathYear: (json['death_year'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'birth_year': birthYear,
    'death_year': deathYear,
  };
}

enum PublicDomainSearchMode { titleAuthor, topic }

enum PublicDomainSort { popular, ascending, descending }

class PublicDomainBookQuery {
  final String text;
  final String? languageCode;
  final PublicDomainSearchMode searchMode;
  final PublicDomainSort sort;
  final String? exactAuthor;

  const PublicDomainBookQuery({
    this.text = '',
    this.languageCode = 'en',
    this.searchMode = PublicDomainSearchMode.titleAuthor,
    this.sort = PublicDomainSort.popular,
    this.exactAuthor,
  });

  String get trimmedText => text.trim();

  bool get hasText => trimmedText.isNotEmpty;

  String get cacheKey {
    return [
      trimmedText.toLowerCase(),
      languageCode ?? '',
      searchMode.name,
      sort.name,
      (exactAuthor ?? '').trim().toLowerCase(),
    ].join('|');
  }

  PublicDomainBookQuery copyWith({
    String? text,
    String? languageCode,
    bool clearLanguageCode = false,
    PublicDomainSearchMode? searchMode,
    PublicDomainSort? sort,
    String? exactAuthor,
    bool clearExactAuthor = false,
  }) {
    return PublicDomainBookQuery(
      text: text ?? this.text,
      languageCode: clearLanguageCode
          ? null
          : (languageCode ?? this.languageCode),
      searchMode: searchMode ?? this.searchMode,
      sort: sort ?? this.sort,
      exactAuthor: clearExactAuthor ? null : (exactAuthor ?? this.exactAuthor),
    );
  }
}

class PublicDomainBook {
  final int id;
  final String title;
  final List<String> authors;
  final List<PublicDomainPerson> authorDetails;
  final String? summary;
  final List<String> subjects;
  final List<String> bookshelves;
  final List<String> languages;
  final List<PublicDomainPerson> translators;
  final List<PublicDomainPerson> editors;
  final String? coverUrl;
  final String epubUrl;
  final int downloadCount;
  final String? mediaType;

  const PublicDomainBook({
    required this.id,
    required this.title,
    required this.authors,
    required this.epubUrl,
    required this.downloadCount,
    this.authorDetails = const [],
    this.summary,
    this.subjects = const [],
    this.bookshelves = const [],
    this.languages = const [],
    this.translators = const [],
    this.editors = const [],
    this.coverUrl,
    this.mediaType,
  });

  String get authorLabel {
    if (authors.isEmpty) return 'Unknown Author';
    return authors.join(', ');
  }

  List<String> get topicLabels {
    final seen = <String>{};
    final labels = <String>[];
    for (final value in [...bookshelves, ...subjects]) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) continue;
      final key = trimmed.toLowerCase();
      if (!seen.add(key)) continue;
      labels.add(trimmed);
    }
    return labels;
  }

  PublicDomainBook copyWith({
    String? title,
    List<String>? authors,
    List<PublicDomainPerson>? authorDetails,
    String? summary,
    bool clearSummary = false,
    List<String>? subjects,
    List<String>? bookshelves,
    List<String>? languages,
    List<PublicDomainPerson>? translators,
    List<PublicDomainPerson>? editors,
    String? coverUrl,
    bool clearCoverUrl = false,
    String? epubUrl,
    int? downloadCount,
    String? mediaType,
    bool clearMediaType = false,
  }) {
    return PublicDomainBook(
      id: id,
      title: title ?? this.title,
      authors: authors ?? this.authors,
      authorDetails: authorDetails ?? this.authorDetails,
      summary: clearSummary ? null : (summary ?? this.summary),
      subjects: subjects ?? this.subjects,
      bookshelves: bookshelves ?? this.bookshelves,
      languages: languages ?? this.languages,
      translators: translators ?? this.translators,
      editors: editors ?? this.editors,
      coverUrl: clearCoverUrl ? null : (coverUrl ?? this.coverUrl),
      epubUrl: epubUrl ?? this.epubUrl,
      downloadCount: downloadCount ?? this.downloadCount,
      mediaType: clearMediaType ? null : (mediaType ?? this.mediaType),
    );
  }

  factory PublicDomainBook.fromGutendex(Map<String, dynamic> json) {
    final formats = json['formats'];
    if (formats is! Map<String, dynamic>) {
      throw const FormatException('Missing book formats');
    }

    final epubUrl = _findFormatUrl(formats, 'application/epub+zip');
    if (epubUrl == null) {
      throw const FormatException('Missing EPUB download URL');
    }

    final authorDetails = _parsePeople(json['authors']);
    final authors = authorDetails
        .map((author) => author.name)
        .toList(growable: false);
    final summaries = (json['summaries'] as List?)
        ?.whereType<String>()
        .map((summary) => summary.trim())
        .where((summary) => summary.isNotEmpty)
        .toList(growable: false);

    return PublicDomainBook(
      id: (json['id'] as num).toInt(),
      title: (json['title'] as String?)?.trim() ?? 'Untitled',
      authors: authors,
      authorDetails: authorDetails,
      summary: summaries?.isNotEmpty == true ? summaries!.first : null,
      subjects:
          (json['subjects'] as List?)?.whereType<String>().toList() ?? const [],
      bookshelves:
          (json['bookshelves'] as List?)?.whereType<String>().toList() ??
          const [],
      languages:
          (json['languages'] as List?)?.whereType<String>().toList() ??
          const [],
      translators: _parsePeople(json['translators']),
      editors: _parsePeople(json['editors']),
      coverUrl: _findFormatUrl(formats, 'image/jpeg'),
      epubUrl: epubUrl,
      downloadCount: (json['download_count'] as num?)?.toInt() ?? 0,
      mediaType: (json['media_type'] as String?)?.trim(),
    );
  }

  factory PublicDomainBook.fromCache(Map<String, dynamic> json) {
    return PublicDomainBook(
      id: (json['id'] as num).toInt(),
      title: (json['title'] as String?)?.trim() ?? 'Untitled',
      authors:
          (json['authors'] as List?)?.whereType<String>().toList() ?? const [],
      authorDetails:
          (json['authorDetails'] as List?)
              ?.whereType<Map>()
              .map(
                (value) => PublicDomainPerson.fromJson(
                  Map<String, dynamic>.from(value),
                ),
              )
              .toList(growable: false) ??
          const [],
      summary: (json['summary'] as String?)?.trim(),
      subjects:
          (json['subjects'] as List?)?.whereType<String>().toList() ?? const [],
      bookshelves:
          (json['bookshelves'] as List?)?.whereType<String>().toList() ??
          const [],
      languages:
          (json['languages'] as List?)?.whereType<String>().toList() ??
          const [],
      translators:
          (json['translators'] as List?)
              ?.whereType<Map>()
              .map(
                (value) => PublicDomainPerson.fromJson(
                  Map<String, dynamic>.from(value),
                ),
              )
              .toList(growable: false) ??
          const [],
      editors:
          (json['editors'] as List?)
              ?.whereType<Map>()
              .map(
                (value) => PublicDomainPerson.fromJson(
                  Map<String, dynamic>.from(value),
                ),
              )
              .toList(growable: false) ??
          const [],
      coverUrl: (json['coverUrl'] as String?)?.trim(),
      epubUrl: (json['epubUrl'] as String?)?.trim() ?? '',
      downloadCount: (json['downloadCount'] as num?)?.toInt() ?? 0,
      mediaType: (json['mediaType'] as String?)?.trim(),
    );
  }

  Map<String, dynamic> toCacheJson() => {
    'id': id,
    'title': title,
    'authors': authors,
    'authorDetails': authorDetails.map((author) => author.toJson()).toList(),
    'summary': summary,
    'subjects': subjects,
    'bookshelves': bookshelves,
    'languages': languages,
    'translators': translators.map((person) => person.toJson()).toList(),
    'editors': editors.map((person) => person.toJson()).toList(),
    'coverUrl': coverUrl,
    'epubUrl': epubUrl,
    'downloadCount': downloadCount,
    'mediaType': mediaType,
  };

  static List<PublicDomainPerson> _parsePeople(Object? raw) {
    return (raw as List?)
            ?.whereType<Map<String, dynamic>>()
            .map(PublicDomainPerson.fromJson)
            .toList(growable: false) ??
        const [];
  }

  static String? _findFormatUrl(
    Map<String, dynamic> formats,
    String mimeTypePrefix,
  ) {
    for (final entry in formats.entries) {
      if (!entry.key.toLowerCase().startsWith(mimeTypePrefix)) continue;
      final value = entry.value;
      if (value is String && value.trim().isNotEmpty) return value;
    }
    return null;
  }
}

class PublicDomainBookPage {
  final List<PublicDomainBook> books;
  final int count;
  final bool hasNextPage;
  final int page;
  final String? nextUrl;
  final String? previousUrl;
  final String? catalogStatusMessage;
  final bool isFallbackOnly;

  const PublicDomainBookPage({
    required this.books,
    required this.count,
    required this.hasNextPage,
    required this.page,
    this.nextUrl,
    this.previousUrl,
    this.catalogStatusMessage,
    this.isFallbackOnly = false,
  });

  factory PublicDomainBookPage.fromCache(Map<String, dynamic> json) {
    final rawBooks = json['books'];
    return PublicDomainBookPage(
      books:
          (rawBooks as List?)
              ?.whereType<Map>()
              .map(
                (value) => PublicDomainBook.fromCache(
                  Map<String, dynamic>.from(value),
                ),
              )
              .where((book) => book.epubUrl.isNotEmpty)
              .toList(growable: false) ??
          const [],
      count: (json['count'] as num?)?.toInt() ?? 0,
      hasNextPage: json['hasNextPage'] == true,
      page: (json['page'] as num?)?.toInt() ?? 1,
      nextUrl: (json['nextUrl'] as String?)?.trim(),
      previousUrl: (json['previousUrl'] as String?)?.trim(),
      catalogStatusMessage: (json['catalogStatusMessage'] as String?)?.trim(),
      isFallbackOnly: json['isFallbackOnly'] == true,
    );
  }

  Map<String, dynamic> toCacheJson() => {
    'books': books.map((book) => book.toCacheJson()).toList(),
    'count': count,
    'hasNextPage': hasNextPage,
    'page': page,
    'nextUrl': nextUrl,
    'previousUrl': previousUrl,
    'catalogStatusMessage': catalogStatusMessage,
    'isFallbackOnly': isFallbackOnly,
  };
}

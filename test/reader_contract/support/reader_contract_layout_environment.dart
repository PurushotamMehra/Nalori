import 'dart:convert';
import 'dart:ui' show ViewPadding;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';

/// Immutable, declared host inputs for reader-contract tests.
///
/// This records inputs only. It does not claim that production pagination
/// measurement and `ReadingCard` rendering are equivalent; TASK-P05-001 owns
/// that comparison and the final layout fingerprint.
@immutable
final class ReaderContractLayoutInputs {
  const ReaderContractLayoutInputs({
    required this.logicalSurfaceSize,
    required this.devicePixelRatio,
    required this.viewportSize,
    required this.safeArea,
    required this.cardBodySize,
    required this.textScaleFactor,
    required this.locale,
    required this.textDirection,
    required this.font,
    required this.lineHeight,
    required this.strutHeight,
    required this.forceStrutHeight,
    required this.textHeightBehaviorId,
    required this.controlsVisible,
    required this.platformBrightness,
    required this.boldText,
    required this.highContrast,
    required this.accessibleNavigation,
  }) : assert(devicePixelRatio > 0),
       assert(textScaleFactor > 0),
       assert(lineHeight > 0),
       assert(strutHeight > 0);

  factory ReaderContractLayoutInputs.standard({
    ReaderContractBundledFont? font,
  }) {
    return ReaderContractLayoutInputs(
      logicalSurfaceSize: const Size(390, 844),
      devicePixelRatio: 1,
      viewportSize: const Size(390, 844),
      safeArea: const EdgeInsets.only(top: 24, bottom: 16),
      cardBodySize: const Size(342, 680),
      textScaleFactor: 1,
      locale: const Locale('en', 'US'),
      textDirection: TextDirection.ltr,
      font: font ?? ReaderContractBundledFont.standardLexend(),
      lineHeight: 1.45,
      strutHeight: 1.45,
      forceStrutHeight: false,
      textHeightBehaviorId: 'readerTextHeightBehavior-default',
      controlsVisible: false,
      platformBrightness: Brightness.light,
      boldText: false,
      highContrast: false,
      accessibleNavigation: false,
    );
  }

  /// A P03-only reduced-height declaration that exercises the current
  /// production paragraph splitter with the same bundled Lexend assets.
  ///
  /// This is characterization input, not the final P05 layout contract. The
  /// only changes from [standard] are the logical surface, viewport, and
  /// recorded card-body heights.
  factory ReaderContractLayoutInputs.splitStress({
    ReaderContractBundledFont? font,
  }) {
    return ReaderContractLayoutInputs.standard(font: font).copyWith(
      logicalSurfaceSize: const Size(390, 300),
      viewportSize: const Size(390, 300),
      cardBodySize: const Size(342, 58),
    );
  }

  final Size logicalSurfaceSize;
  final double devicePixelRatio;
  final Size viewportSize;
  final EdgeInsets safeArea;
  final Size cardBodySize;
  final double textScaleFactor;
  final Locale locale;
  final TextDirection textDirection;
  final ReaderContractBundledFont font;
  final double lineHeight;
  final double strutHeight;
  final bool forceStrutHeight;

  /// A declared input because the production `TextHeightBehavior` boundary is
  /// not test-callable without mounting the reader. P05 maps it to the real
  /// renderer/measurement contract.
  final String textHeightBehaviorId;
  final bool controlsVisible;
  final Brightness platformBrightness;
  final bool boldText;
  final bool highContrast;
  final bool accessibleNavigation;

  ReaderContractLayoutInputs copyWith({
    Size? logicalSurfaceSize,
    double? devicePixelRatio,
    Size? viewportSize,
    EdgeInsets? safeArea,
    Size? cardBodySize,
    double? textScaleFactor,
    Locale? locale,
    TextDirection? textDirection,
    ReaderContractBundledFont? font,
    double? lineHeight,
    double? strutHeight,
    bool? forceStrutHeight,
    String? textHeightBehaviorId,
    bool? controlsVisible,
    Brightness? platformBrightness,
    bool? boldText,
    bool? highContrast,
    bool? accessibleNavigation,
  }) {
    return ReaderContractLayoutInputs(
      logicalSurfaceSize: logicalSurfaceSize ?? this.logicalSurfaceSize,
      devicePixelRatio: devicePixelRatio ?? this.devicePixelRatio,
      viewportSize: viewportSize ?? this.viewportSize,
      safeArea: safeArea ?? this.safeArea,
      cardBodySize: cardBodySize ?? this.cardBodySize,
      textScaleFactor: textScaleFactor ?? this.textScaleFactor,
      locale: locale ?? this.locale,
      textDirection: textDirection ?? this.textDirection,
      font: font ?? this.font,
      lineHeight: lineHeight ?? this.lineHeight,
      strutHeight: strutHeight ?? this.strutHeight,
      forceStrutHeight: forceStrutHeight ?? this.forceStrutHeight,
      textHeightBehaviorId: textHeightBehaviorId ?? this.textHeightBehaviorId,
      controlsVisible: controlsVisible ?? this.controlsVisible,
      platformBrightness: platformBrightness ?? this.platformBrightness,
      boldText: boldText ?? this.boldText,
      highContrast: highContrast ?? this.highContrast,
      accessibleNavigation: accessibleNavigation ?? this.accessibleNavigation,
    );
  }

  /// Stable diagnostic JSON for comparisons between repeated host runs.
  String get diagnosticJson => jsonEncode(toDiagnosticMap());

  Map<String, Object?> toDiagnosticMap() => <String, Object?>{
    'logicalSurface': _sizeMap(logicalSurfaceSize),
    'devicePixelRatio': devicePixelRatio,
    'viewport': _sizeMap(viewportSize),
    'safeArea': _edgeMap(safeArea),
    'cardBody': _sizeMap(cardBodySize),
    'textScaleFactor': textScaleFactor,
    'locale': locale.toLanguageTag(),
    'textDirection': textDirection.name,
    'font': font.toDiagnosticMap(),
    'lineHeight': lineHeight,
    'strutHeight': strutHeight,
    'forceStrutHeight': forceStrutHeight,
    'textHeightBehavior': textHeightBehaviorId,
    'controlsVisible': controlsVisible,
    'platformBrightness': platformBrightness.name,
    'boldText': boldText,
    'highContrast': highContrast,
    'accessibleNavigation': accessibleNavigation,
  };

  @override
  bool operator ==(Object other) =>
      other is ReaderContractLayoutInputs &&
      logicalSurfaceSize == other.logicalSurfaceSize &&
      devicePixelRatio == other.devicePixelRatio &&
      viewportSize == other.viewportSize &&
      safeArea == other.safeArea &&
      cardBodySize == other.cardBodySize &&
      textScaleFactor == other.textScaleFactor &&
      locale == other.locale &&
      textDirection == other.textDirection &&
      font == other.font &&
      lineHeight == other.lineHeight &&
      strutHeight == other.strutHeight &&
      forceStrutHeight == other.forceStrutHeight &&
      textHeightBehaviorId == other.textHeightBehaviorId &&
      controlsVisible == other.controlsVisible &&
      platformBrightness == other.platformBrightness &&
      boldText == other.boldText &&
      highContrast == other.highContrast &&
      accessibleNavigation == other.accessibleNavigation;

  @override
  int get hashCode => Object.hash(
    logicalSurfaceSize,
    devicePixelRatio,
    viewportSize,
    safeArea,
    cardBodySize,
    textScaleFactor,
    locale,
    textDirection,
    font,
    lineHeight,
    strutHeight,
    forceStrutHeight,
    textHeightBehaviorId,
    controlsVisible,
    platformBrightness,
    boldText,
    highContrast,
    accessibleNavigation,
  );
}

/// A local reader-font declaration. No production font metrics are copied or
/// calculated here.
@immutable
final class ReaderContractBundledFont {
  ReaderContractBundledFont({
    required this.readerFontFamily,
    required this.fontFamily,
    required List<FontWeight> availableWeights,
    required Map<FontWeight, String> assetPathsByWeight,
    required Map<FontWeight, String> assetSha256ByWeight,
    required this.productionDeclaredMetricIdentity,
    required this.resolvedMetricIdentity,
  }) : availableWeights = List<FontWeight>.unmodifiable(availableWeights),
       assetPathsByWeight = Map<FontWeight, String>.unmodifiable(
         assetPathsByWeight,
       ),
       assetSha256ByWeight = Map<FontWeight, String>.unmodifiable(
         assetSha256ByWeight,
       );

  /// The reader setting under test (for example, `lexend`).
  final String readerFontFamily;

  /// The family registered with [FontLoader]. The standard declaration uses a
  /// host-only alias so it cannot change production's `GoogleFonts.lexend`
  /// runtime selection.
  final String fontFamily;
  final List<FontWeight> availableWeights;
  final Map<FontWeight, String> assetPathsByWeight;

  /// Stable SHA-256 asset identity for each declared root-bundle input.
  ///
  /// These are byte identities only. They are not resolved glyph metrics and
  /// must not be used as a P05 measurement/render fingerprint.
  final Map<FontWeight, String> assetSha256ByWeight;

  /// Current production's declared typography-profile identity, if known.
  /// It is not a runtime-resolved glyph/metric identity.
  final String? productionDeclaredMetricIdentity;

  /// The resolved runtime glyph/metric identity, if production exposes one.
  /// Current production does not, so the standard declaration keeps this null
  /// for P05 rather than inventing an identity from the bundled bytes.
  final String? resolvedMetricIdentity;

  /// The one controlled Nalori reader-core font declaration.
  ///
  /// Production defaults to Lexend regular. The reader card additionally uses
  /// semi-bold list/structural text, bold inline text, and black headings, so
  /// those four normal static weights are the smallest complete core set.
  factory ReaderContractBundledFont.standardLexend() {
    return ReaderContractBundledFont(
      readerFontFamily: 'lexend',
      fontFamily: 'NaloriReaderContractLexend',
      availableWeights: const <FontWeight>[
        FontWeight.w400,
        FontWeight.w600,
        FontWeight.w700,
        FontWeight.w900,
      ],
      assetPathsByWeight: <FontWeight, String>{
        FontWeight.w400: 'assets/fonts/reader_contract/Lexend-Regular.ttf',
        FontWeight.w600: 'assets/fonts/reader_contract/Lexend-SemiBold.ttf',
        FontWeight.w700: 'assets/fonts/reader_contract/Lexend-Bold.ttf',
        FontWeight.w900: 'assets/fonts/reader_contract/Lexend-Black.ttf',
      },
      assetSha256ByWeight: <FontWeight, String>{
        FontWeight.w400:
            'e92ff07c5686aee1cf71ba2aaf8b3afcab70db722680d082dd2fc496e65fe383',
        FontWeight.w600:
            'bcac18cdf67555e75f7d747fa6055c11fc58a61ea8cc68af0ade707717018908',
        FontWeight.w700:
            'fe323c8e142d5f92b974a48973bac235966aa3a76cf0e6d76ea89d03f7a2aa3d',
        FontWeight.w900:
            '6c3c72060a805613a735fdb9523152f880e1cca7577bacfe751cfa7d5ece2053',
      },
      productionDeclaredMetricIdentity:
          'reader_typography_v1:lexend:regular:0.525:0.7:1.165',
      resolvedMetricIdentity: null,
    );
  }

  /// Loads every declared font byte only from Flutter's root bundle.
  ///
  /// This deliberately cannot use Google Fonts, a device-file lookup, Ahem,
  /// or any fallback. It returns only after all byte checks and [FontLoader]
  /// registration have completed.
  Future<ReaderContractLoadedFont> load() => _loadFrom(rootBundle);

  /// Narrow corruption-path hook for this support file's self-test.
  ///
  /// [ReaderContractLayoutEnvironment.install] never calls this method; all
  /// real reader-contract environments load exclusively from [rootBundle].
  @visibleForTesting
  Future<ReaderContractLoadedFont> loadForTesting(AssetBundle assetBundle) =>
      _loadFrom(assetBundle);

  Future<ReaderContractLoadedFont> _loadFrom(AssetBundle assetBundle) async {
    if (assetPathsByWeight.isEmpty) {
      throw StateError(
        'Reader-contract font "$readerFontFamily" is not bundled in this '
        'repository. Runtime Google Fonts fetching is prohibited. Add an '
        'approved local asset and declare it before a measurement-dependent '
        'reader-contract test can report a ready layout environment.',
      );
    }
    final required = availableWeights.toSet();
    final missingPaths = required.difference(assetPathsByWeight.keys.toSet());
    final missingChecksums = required.difference(
      assetSha256ByWeight.keys.toSet(),
    );
    if (missingPaths.isNotEmpty || missingChecksums.isNotEmpty) {
      final missingPathValues = missingPaths
          .map((weight) => weight.value)
          .join(', ');
      final missingChecksumValues = missingChecksums
          .map((weight) => weight.value)
          .join(', ');
      throw StateError(
        'Reader-contract font "$readerFontFamily" has incomplete bundled '
        'declarations. Missing asset paths: '
        '${missingPathValues.isEmpty ? 'none' : missingPathValues}; '
        'missing SHA-256 identities: '
        '${missingChecksumValues.isEmpty ? 'none' : missingChecksumValues}.',
      );
    }

    final loader = FontLoader(fontFamily);
    final loadedAssetSha256ByWeight = <FontWeight, String>{};
    for (final entry in _sortedWeightAssets(assetPathsByWeight)) {
      final ByteData bytes;
      try {
        bytes = await assetBundle.load(entry.value);
      } catch (error) {
        throw StateError(
          'Reader-contract font "$readerFontFamily" could not load required '
          'root-bundle asset for weight ${entry.key.value} at "${entry.value}". '
          'The asset is missing or not declared in pubspec.yaml: $error',
        );
      }
      final actualChecksum = _sha256(bytes);
      final expectedChecksum = assetSha256ByWeight[entry.key]!;
      if (actualChecksum != expectedChecksum) {
        throw StateError(
          'Reader-contract font "$readerFontFamily" has a corrupt asset for '
          'weight ${entry.key.value} at "${entry.value}". Expected SHA-256 '
          '$expectedChecksum, got $actualChecksum.',
        );
      }
      loadedAssetSha256ByWeight[entry.key] = actualChecksum;
      loader.addFont(Future<ByteData>.value(bytes));
    }

    try {
      await loader.load();
    } catch (error) {
      throw StateError(
        'Reader-contract font "$readerFontFamily" could not register its '
        'verified root-bundle assets with FontLoader: $error',
      );
    }

    return ReaderContractLoadedFont._(
      font: this,
      assetPathsByWeight: Map<FontWeight, String>.unmodifiable(
        assetPathsByWeight,
      ),
      assetSha256ByWeight: Map<FontWeight, String>.unmodifiable(
        loadedAssetSha256ByWeight,
      ),
    );
  }

  Map<String, Object?> toDiagnosticMap() => <String, Object?>{
    'readerFontFamily': readerFontFamily,
    'fontFamily': fontFamily,
    'availableWeights': availableWeights.map((weight) => weight.value).toList(),
    'assetPathsByWeight': <String, String>{
      for (final entry in _sortedWeightAssets(assetPathsByWeight))
        '${entry.key.value}': entry.value,
    },
    'assetSha256ByWeight': <String, String>{
      for (final entry in _sortedWeightAssets(assetSha256ByWeight))
        '${entry.key.value}': entry.value,
    },
    'productionDeclaredMetricIdentity': productionDeclaredMetricIdentity,
    'resolvedMetricIdentity': resolvedMetricIdentity,
  };

  @override
  bool operator ==(Object other) =>
      other is ReaderContractBundledFont &&
      readerFontFamily == other.readerFontFamily &&
      fontFamily == other.fontFamily &&
      _sameList(availableWeights, other.availableWeights) &&
      _sameWeightAssets(assetPathsByWeight, other.assetPathsByWeight) &&
      _sameWeightAssets(assetSha256ByWeight, other.assetSha256ByWeight) &&
      productionDeclaredMetricIdentity ==
          other.productionDeclaredMetricIdentity &&
      resolvedMetricIdentity == other.resolvedMetricIdentity;

  @override
  int get hashCode => Object.hash(
    readerFontFamily,
    fontFamily,
    Object.hashAll(availableWeights),
    Object.hashAll(
      _sortedWeightAssets(
        assetPathsByWeight,
      ).map((entry) => Object.hash(entry.key, entry.value)),
    ),
    Object.hashAll(
      _sortedWeightAssets(
        assetSha256ByWeight,
      ).map((entry) => Object.hash(entry.key, entry.value)),
    ),
    productionDeclaredMetricIdentity,
    resolvedMetricIdentity,
  );
}

/// Evidence that every declared font byte was loaded before an environment
/// reported ready. It contains asset identity, not resolved glyph metrics.
@immutable
final class ReaderContractLoadedFont {
  const ReaderContractLoadedFont._({
    required this.font,
    required this.assetPathsByWeight,
    required this.assetSha256ByWeight,
  });

  final ReaderContractBundledFont font;
  final Map<FontWeight, String> assetPathsByWeight;
  final Map<FontWeight, String> assetSha256ByWeight;
}

/// Applies and restores only Flutter host-test globals. The production reader
/// is not mounted or modified by this utility.
final class ReaderContractLayoutEnvironment {
  ReaderContractLayoutEnvironment._({
    required this.inputs,
    required _ReaderContractTestState previousState,
  }) : _previousState = previousState;

  final ReaderContractLayoutInputs inputs;
  final _ReaderContractTestState _previousState;
  ReaderContractLoadedFont? _loadedFont;
  bool _ready = false;
  bool _closed = false;

  bool get isReady => _ready && !_closed;
  String get diagnosticOutput => inputs.diagnosticJson;

  /// Throws until all declared local font bytes have been verified and loaded.
  ReaderContractLoadedFont get loadedFont {
    if (!isReady || _loadedFont == null) {
      throw StateError('Reader-contract layout environment is not ready.');
    }
    return _loadedFont!;
  }

  static Future<ReaderContractLayoutEnvironment> install(
    WidgetTester tester, {
    ReaderContractLayoutInputs? inputs,
  }) async {
    final declared = inputs ?? ReaderContractLayoutInputs.standard();
    final environment = ReaderContractLayoutEnvironment._(
      inputs: declared,
      previousState: _ReaderContractTestState.capture(tester),
    );
    try {
      // This must happen before any requested GoogleFont style can schedule a
      // fetch. [ReaderContractBundledFont.load] only reads root-bundle assets.
      GoogleFonts.config.allowRuntimeFetching = false;
      environment._loadedFont = await declared.font.load();
      environment._apply(tester);
      environment._ready = true;
      return environment;
    } catch (_) {
      await environment.close(tester);
      rethrow;
    }
  }

  void _apply(WidgetTester tester) {
    final view = tester.view;
    final physicalSize = Size(
      inputs.logicalSurfaceSize.width * inputs.devicePixelRatio,
      inputs.logicalSurfaceSize.height * inputs.devicePixelRatio,
    );
    final physicalSafeArea = _asPhysicalPadding(
      inputs.safeArea,
      inputs.devicePixelRatio,
    );
    view.devicePixelRatio = inputs.devicePixelRatio;
    view.physicalSize = physicalSize;
    view.padding = physicalSafeArea;
    view.viewPadding = physicalSafeArea;
    tester.platformDispatcher.localeTestValue = inputs.locale;
    tester.platformDispatcher.localesTestValue = <Locale>[inputs.locale];
    tester.platformDispatcher.textScaleFactorTestValue = inputs.textScaleFactor;
  }

  /// Wrap the production widget under explicit locale, media-query,
  /// directionality and theme inputs. This wrapper records inputs; it is not a
  /// substitute for P05's shared renderer/measurement contract.
  Widget wrap(Widget child) {
    if (!isReady) {
      throw StateError('Reader-contract layout environment is not ready.');
    }
    final media = MediaQueryData(
      size: inputs.viewportSize,
      devicePixelRatio: inputs.devicePixelRatio,
      padding: inputs.safeArea,
      viewPadding: inputs.safeArea,
      textScaler: TextScaler.linear(inputs.textScaleFactor),
      platformBrightness: inputs.platformBrightness,
      boldText: inputs.boldText,
      highContrast: inputs.highContrast,
      accessibleNavigation: inputs.accessibleNavigation,
    );
    return Localizations(
      locale: inputs.locale,
      delegates: GlobalMaterialLocalizations.delegates,
      child: Directionality(
        textDirection: inputs.textDirection,
        child: MediaQuery(
          data: media,
          child: Theme(
            data: ThemeData(
              brightness: inputs.platformBrightness,
              fontFamily: inputs.font.fontFamily,
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  Future<void> close(WidgetTester tester) async {
    if (_closed) return;
    _closed = true;
    _ready = false;
    _loadedFont = null;
    _previousState.restore(tester);
  }
}

final class _ReaderContractTestState {
  const _ReaderContractTestState({
    required this.physicalSize,
    required this.devicePixelRatio,
    required this.padding,
    required this.viewPadding,
    required this.locale,
    required this.locales,
    required this.textScaleFactor,
    required this.allowRuntimeFontFetching,
  });

  factory _ReaderContractTestState.capture(WidgetTester tester) {
    return _ReaderContractTestState(
      physicalSize: tester.view.physicalSize,
      devicePixelRatio: tester.view.devicePixelRatio,
      padding: _copyPadding(tester.view.padding),
      viewPadding: _copyPadding(tester.view.viewPadding),
      locale: tester.platformDispatcher.locale,
      locales: List<Locale>.of(tester.platformDispatcher.locales),
      textScaleFactor: tester.platformDispatcher.textScaleFactor,
      allowRuntimeFontFetching: GoogleFonts.config.allowRuntimeFetching,
    );
  }

  final Size physicalSize;
  final double devicePixelRatio;
  final FakeViewPadding padding;
  final FakeViewPadding viewPadding;
  final Locale locale;
  final List<Locale> locales;
  final double textScaleFactor;
  final bool allowRuntimeFontFetching;

  void restore(WidgetTester tester) {
    tester.view.devicePixelRatio = devicePixelRatio;
    tester.view.physicalSize = physicalSize;
    tester.view.padding = padding;
    tester.view.viewPadding = viewPadding;
    tester.platformDispatcher.localeTestValue = locale;
    tester.platformDispatcher.localesTestValue = locales;
    tester.platformDispatcher.textScaleFactorTestValue = textScaleFactor;
    GoogleFonts.config.allowRuntimeFetching = allowRuntimeFontFetching;
  }
}

FakeViewPadding _asPhysicalPadding(
  EdgeInsets logical,
  double devicePixelRatio,
) {
  return FakeViewPadding(
    left: logical.left * devicePixelRatio,
    top: logical.top * devicePixelRatio,
    right: logical.right * devicePixelRatio,
    bottom: logical.bottom * devicePixelRatio,
  );
}

FakeViewPadding _copyPadding(ViewPadding value) => FakeViewPadding(
  left: value.left,
  top: value.top,
  right: value.right,
  bottom: value.bottom,
);

Map<String, double> _sizeMap(Size value) => <String, double>{
  'width': value.width,
  'height': value.height,
};

Map<String, double> _edgeMap(EdgeInsets value) => <String, double>{
  'left': value.left,
  'top': value.top,
  'right': value.right,
  'bottom': value.bottom,
};

bool _sameList<T>(List<T> first, List<T> second) {
  if (first.length != second.length) return false;
  for (var index = 0; index < first.length; index++) {
    if (first[index] != second[index]) return false;
  }
  return true;
}

bool _sameWeightAssets(
  Map<FontWeight, String> first,
  Map<FontWeight, String> second,
) {
  if (first.length != second.length) return false;
  return first.entries.every((entry) => second[entry.key] == entry.value);
}

List<MapEntry<FontWeight, String>> _sortedWeightAssets(
  Map<FontWeight, String> assets,
) {
  final entries = assets.entries.toList()
    ..sort((first, second) => first.key.value.compareTo(second.key.value));
  return entries;
}

String _sha256(ByteData data) {
  final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  return sha256.convert(bytes).toString();
}

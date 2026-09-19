import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'reader_contract_layout_environment.dart';

void main() {
  group('[REQ-032, REQ-035, REQ-051] reader-contract layout inputs', () {
    test(
      'repeated standard declarations are byte-for-byte diagnostic equals',
      () {
        final first = ReaderContractLayoutInputs.standard();
        final second = ReaderContractLayoutInputs.standard();

        expect(first, second);
        expect(first.diagnosticJson, second.diagnosticJson);
        expect(first.diagnosticJson, contains('"controlsVisible":false'));
        expect(first.diagnosticJson, contains('"cardBody"'));
        expect(first.diagnosticJson, contains('NaloriReaderContractLexend'));
        expect(
          first.diagnosticJson,
          contains('"availableWeights":[400,600,700,900]'),
        );
        expect(first.diagnosticJson, contains('"assetSha256ByWeight"'));
        expect(first.font.resolvedMetricIdentity, isNull);
        expect(
          () => first.font.availableWeights.add(FontWeight.w100),
          throwsUnsupportedError,
        );
        expect(
          () => first.font.assetPathsByWeight[FontWeight.w100] = 'mutated.ttf',
          throwsUnsupportedError,
        );
      },
    );

    test('explicit viewport, scale, locale and direction remain distinct', () {
      final baseline = ReaderContractLayoutInputs.standard();
      final changed = baseline.copyWith(
        viewportSize: const Size(480, 720),
        textScaleFactor: 1.25,
        locale: const Locale('ar', 'EG'),
        textDirection: TextDirection.rtl,
      );

      expect(changed, isNot(baseline));
      expect(changed.diagnosticJson, isNot(baseline.diagnosticJson));
      expect(changed.diagnosticJson, contains('"ar-EG"'));
      expect(changed.diagnosticJson, contains('"rtl"'));
    });

    test('safe area and controls visibility are immutable per declaration', () {
      final baseline = ReaderContractLayoutInputs.standard();
      final changed = baseline.copyWith(
        safeArea: const EdgeInsets.fromLTRB(10, 20, 30, 40),
        controlsVisible: true,
      );

      expect(baseline.safeArea, const EdgeInsets.only(top: 24, bottom: 16));
      expect(baseline.controlsVisible, isFalse);
      expect(changed.safeArea, const EdgeInsets.fromLTRB(10, 20, 30, 40));
      expect(changed.controlsVisible, isTrue);
    });

    testWidgets(
      'standard environment loads every verified root-bundle asset before readiness',
      (tester) async {
        final previousFontFetching = GoogleFonts.config.allowRuntimeFetching;
        GoogleFonts.config.allowRuntimeFetching = true;
        addTearDown(() {
          GoogleFonts.config.allowRuntimeFetching = previousFontFetching;
        });

        final declared = ReaderContractLayoutInputs.standard();
        final environment = await ReaderContractLayoutEnvironment.install(
          tester,
          inputs: declared,
        );
        addTearDown(() => environment.close(tester));

        expect(environment.isReady, isTrue);
        expect(GoogleFonts.config.allowRuntimeFetching, isFalse);
        expect(environment.loadedFont.font, declared.font);
        expect(
          environment.loadedFont.assetPathsByWeight,
          declared.font.assetPathsByWeight,
        );
        expect(
          environment.loadedFont.assetSha256ByWeight,
          declared.font.assetSha256ByWeight,
        );
        expect(environment.diagnosticOutput, contains('Lexend-Black.ttf'));
        expect(
          environment.diagnosticOutput,
          contains(
            '6c3c72060a805613a735fdb9523152f880e1cca7577bacfe751cfa7d5ece2053',
          ),
        );

        await environment.close(tester);
        expect(environment.isReady, isFalse);
        expect(GoogleFonts.config.allowRuntimeFetching, isTrue);
      },
    );

    testWidgets(
      'repeated installations retain equal declarations without safe-area or controls leakage',
      (tester) async {
        final custom = ReaderContractLayoutInputs.standard().copyWith(
          safeArea: const EdgeInsets.fromLTRB(10, 20, 30, 40),
          controlsVisible: true,
        );
        final first = await ReaderContractLayoutEnvironment.install(
          tester,
          inputs: custom,
        );
        addTearDown(() => first.close(tester));

        late MediaQueryData customMedia;
        late String? themedFontFamily;
        await tester.pumpWidget(
          first.wrap(
            Builder(
              builder: (context) {
                customMedia = MediaQuery.of(context);
                themedFontFamily = Theme.of(
                  context,
                ).textTheme.bodyMedium?.fontFamily;
                return const SizedBox();
              },
            ),
          ),
        );
        expect(customMedia.padding, custom.safeArea);
        expect(themedFontFamily, custom.font.fontFamily);
        expect(first.inputs.controlsVisible, isTrue);
        await first.close(tester);

        final second = await ReaderContractLayoutEnvironment.install(tester);
        addTearDown(() => second.close(tester));
        expect(second.inputs, ReaderContractLayoutInputs.standard());
        expect(
          second.inputs.safeArea,
          const EdgeInsets.only(top: 24, bottom: 16),
        );
        expect(second.inputs.controlsVisible, isFalse);
        expect(second.diagnosticOutput, isNot(first.diagnosticOutput));
        await second.close(tester);
      },
    );

    testWidgets(
      'close restores previous Flutter test bindings and font setting',
      (tester) async {
        tester.view.devicePixelRatio = 2;
        tester.view.physicalSize = const Size(800, 1200);
        tester.view.padding = const FakeViewPadding(
          left: 2,
          top: 4,
          right: 6,
          bottom: 8,
        );
        tester.view.viewPadding = const FakeViewPadding(
          left: 1,
          top: 3,
          right: 5,
          bottom: 7,
        );
        tester.platformDispatcher.localeTestValue = const Locale('fr', 'FR');
        tester.platformDispatcher.localesTestValue = const <Locale>[
          Locale('fr', 'FR'),
        ];
        tester.platformDispatcher.textScaleFactorTestValue = 1.1;
        final previousFontFetching = GoogleFonts.config.allowRuntimeFetching;
        GoogleFonts.config.allowRuntimeFetching = true;
        addTearDown(() {
          GoogleFonts.config.allowRuntimeFetching = previousFontFetching;
        });

        final environment = await ReaderContractLayoutEnvironment.install(
          tester,
        );
        addTearDown(() => environment.close(tester));
        expect(tester.view.devicePixelRatio, 1);
        expect(tester.view.physicalSize, const Size(390, 844));
        expect(tester.view.padding.top, 24);
        expect(tester.view.viewPadding.bottom, 16);

        await environment.close(tester);
        expect(tester.view.devicePixelRatio, 2);
        expect(tester.view.physicalSize, const Size(800, 1200));
        expect(tester.view.padding.top, 4);
        expect(tester.view.viewPadding.bottom, 7);
        expect(tester.platformDispatcher.locale, const Locale('fr', 'FR'));
        expect(tester.platformDispatcher.locales, const <Locale>[
          Locale('fr', 'FR'),
        ]);
        expect(tester.platformDispatcher.textScaleFactor, 1.1);
        expect(GoogleFonts.config.allowRuntimeFetching, isTrue);
      },
    );

    testWidgets(
      'missing or undeclared root-bundle assets fail before readiness without fallback',
      (tester) async {
        final standard = ReaderContractBundledFont.standardLexend();
        final undeclaredPaths =
            Map<FontWeight, String>.of(standard.assetPathsByWeight)
              ..[FontWeight.w400] =
                  'assets/fonts/reader_contract/Lexend-NotDeclared.ttf';
        final undeclared = ReaderContractBundledFont(
          readerFontFamily: standard.readerFontFamily,
          fontFamily: 'NaloriReaderContractUndeclaredLexend',
          availableWeights: standard.availableWeights,
          assetPathsByWeight: undeclaredPaths,
          assetSha256ByWeight: standard.assetSha256ByWeight,
          productionDeclaredMetricIdentity:
              standard.productionDeclaredMetricIdentity,
          resolvedMetricIdentity: standard.resolvedMetricIdentity,
        );
        final previousFontFetching = GoogleFonts.config.allowRuntimeFetching;
        GoogleFonts.config.allowRuntimeFetching = true;
        addTearDown(() {
          GoogleFonts.config.allowRuntimeFetching = previousFontFetching;
        });

        await expectLater(
          ReaderContractLayoutEnvironment.install(
            tester,
            inputs: ReaderContractLayoutInputs.standard(font: undeclared),
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              allOf(
                contains('could not load required root-bundle asset'),
                contains('not declared'),
              ),
            ),
          ),
        );

        expect(GoogleFonts.config.allowRuntimeFetching, isTrue);
      },
    );

    test(
      'a corrupt font byte stream fails its declared SHA-256 check clearly',
      () async {
        final standard = ReaderContractBundledFont.standardLexend();
        final corrupt = ReaderContractBundledFont(
          readerFontFamily: standard.readerFontFamily,
          fontFamily: 'NaloriReaderContractCorruptLexend',
          availableWeights: const <FontWeight>[FontWeight.w400],
          assetPathsByWeight: <FontWeight, String>{
            FontWeight.w400: 'test-only-corrupt.ttf',
          },
          assetSha256ByWeight: <FontWeight, String>{
            FontWeight.w400: standard.assetSha256ByWeight[FontWeight.w400]!,
          },
          productionDeclaredMetricIdentity:
              standard.productionDeclaredMetricIdentity,
          resolvedMetricIdentity: null,
        );

        await expectLater(
          corrupt.loadForTesting(_CorruptAssetBundle()),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              allOf(contains('corrupt asset'), contains('Expected SHA-256')),
            ),
          ),
        );
      },
    );

    test(
      'an incomplete font declaration fails before attempting any asset load',
      () async {
        final incomplete = ReaderContractBundledFont(
          readerFontFamily: 'lexend',
          fontFamily: 'NaloriReaderContractIncompleteLexend',
          availableWeights: const <FontWeight>[
            FontWeight.w400,
            FontWeight.w700,
          ],
          assetPathsByWeight: <FontWeight, String>{
            FontWeight.w400: 'test-only-regular.ttf',
          },
          assetSha256ByWeight: <FontWeight, String>{
            FontWeight.w400: 'not-used',
          },
          productionDeclaredMetricIdentity: null,
          resolvedMetricIdentity: null,
        );

        await expectLater(
          incomplete.loadForTesting(_FailIfReadAssetBundle()),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('incomplete bundled declarations'),
            ),
          ),
        );
      },
    );
  });
}

final class _CorruptAssetBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(Uint8List.fromList(<int>[0, 1, 2, 3]));
}

final class _FailIfReadAssetBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) {
    throw StateError('Incomplete declarations must fail before reading $key.');
  }
}

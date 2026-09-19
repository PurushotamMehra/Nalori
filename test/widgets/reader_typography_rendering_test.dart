import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nalori/models/reading_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('painter and rendered body use identical resolved typography', (
    tester,
  ) async {
    const settings = ReadingSettings(
      fontFamily: ReaderFontFamily.lora,
      fontSize: ReaderFontSize.l,
      fontWeight: ReaderFontWeight.bold,
      lineHeight: 1.15,
    );
    const locale = Locale('en');
    const scaler = TextScaler.linear(1.25);
    const width = 240.0;
    const text = 'Áccented capitals and gyp descenders wrap safely. 世界。';
    final style = settings.getTextStyle().copyWith(locale: locale);
    final strut = settings.getBodyStrutStyle();
    final span = TextSpan(text: text, style: style);
    final painter = TextPainter(
      text: span,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.left,
      textScaler: scaler,
      strutStyle: strut,
      textHeightBehavior: readerTextHeightBehavior,
      locale: locale,
    )..layout(maxWidth: width);

    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        home: MediaQuery(
          data: const MediaQueryData(textScaler: scaler),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: RichText(
                key: const ValueKey('resolved-reader-text'),
                text: span,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.left,
                textScaler: scaler,
                strutStyle: strut,
                textHeightBehavior: readerTextHeightBehavior,
                locale: locale,
              ),
            ),
          ),
        ),
      ),
    );

    final rendered = tester.getSize(
      find.byKey(const ValueKey('resolved-reader-text')),
    );
    expect(rendered.width, width);
    expect(rendered.height, closeTo(painter.height, 0.01));
    expect(strut.fontSize, style.fontSize);
    expect(strut.height, style.height);
    expect(strut.fontWeight, style.fontWeight);
    painter.dispose();
  });
}

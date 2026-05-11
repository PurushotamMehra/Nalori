import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nalori/models/reading_settings.dart';
import 'package:nalori/screens/how_to_use_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('renders Nalori help sections and first-run action', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: HowToUseScreen(settings: ReadingSettings(), firstRun: true),
      ),
    );

    expect(find.text('How to use Nalori'), findsOneWidget);
    expect(find.text('Build your library'), findsOneWidget);
    expect(find.text('Read with gestures'), findsOneWidget);
    expect(find.text('Use reader tools'), findsOneWidget);
    expect(find.text('Work with text'), findsOneWidget);
    expect(find.text('Make it yours'), findsOneWidget);
    expect(find.text('Privacy'), findsOneWidget);
    expect(find.text('Start reading'), findsOneWidget);
  });
}

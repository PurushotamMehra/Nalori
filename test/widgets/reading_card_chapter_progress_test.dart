import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nalori/models/book_chunk.dart';
import 'package:nalori/models/reading_settings.dart';
import 'package:nalori/widgets/reading_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('card depth footer renders chapter progress and percent', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 720,
            child: ReadingCard(
              chunk: BookChunk(
                index: 0,
                type: BookChunkType.text,
                text: 'Chapter page text.',
              ),
              settings: ReadingSettings(enableCardDepth: true),
              chapterTitle: 'Chapter 3',
              chapterPageLabel: '2 / 3',
              chapterProgress: 0.5,
            ),
          ),
        ),
      ),
    );

    final progress = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(progress.value, 0.5);
    expect(find.text('50%'), findsOneWidget);
    expect(find.text('Chapter 3'), findsOneWidget);
    expect(find.text('2 / 3'), findsOneWidget);
  });
}

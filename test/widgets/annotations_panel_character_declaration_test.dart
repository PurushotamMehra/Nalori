import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/highlight.dart';
import 'package:nalori/services/dictionary_service.dart';
import 'package:nalori/widgets/navigation_panel.dart';

void main() {
  testWidgets('Reader Menu lists declarations but never generated name terms', (
    tester,
  ) async {
    final declaration = Highlight(
      id: 'elizabeth-bennet',
      originalChunkIndex: 0,
      startOffset: 0,
      endOffset: 16,
      text: 'Elizabeth Bennet',
      type: HighlightType.character,
      createdAt: DateTime(2026, 8, 6),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnnotationsPanel(
            currentPage: 0,
            originalToDisplay: const <int, int>{0: 0},
            totalDisplayPages: 1,
            onNavigate:
                (
                  _, {
                  int? originalStartOffset,
                  String? sourceText,
                  stableLocation,
                }) {},
            highlights: <Highlight>[declaration],
            dictionaryService: DictionaryService(bookId: 'reader-menu-test'),
          ),
        ),
      ),
    );

    expect(find.text('Elizabeth Bennet'), findsOneWidget);
    expect(find.text('Elizabeth'), findsNothing);
    expect(find.text('Bennet'), findsNothing);
    expect(
      find.byKey(const ValueKey('highlight-elizabeth-bennet')),
      findsOneWidget,
    );
  });
}

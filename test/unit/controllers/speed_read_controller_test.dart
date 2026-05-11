import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:nalori/controllers/speed_read_controller.dart';

void main() {
  group('calculateSpeedReadWordDelayMs', () {
    test('short words are slightly faster than base delay', () {
      final delay = calculateSpeedReadWordDelayMs('to', 300);

      expect(delay, lessThan(200));
      expect(delay, greaterThanOrEqualTo(150));
    });

    test('normal words use the base delay', () {
      expect(calculateSpeedReadWordDelayMs('middle', 300), 200);
    });

    test('long words are slower than base delay', () {
      expect(
        calculateSpeedReadWordDelayMs('misunderstanding', 300),
        greaterThan(200),
      );
    });

    test('punctuation adds predictable pauses', () {
      final base = calculateSpeedReadWordDelayMs('hello', 300);
      final comma = calculateSpeedReadWordDelayMs('hello,', 300);
      final fullStop = calculateSpeedReadWordDelayMs('hello.', 300);

      expect(comma, greaterThan(base));
      expect(fullStop, greaterThan(comma));
    });

    test('adaptive delay is clamped to the maximum multiplier', () {
      expect(
        calculateSpeedReadWordDelayMs(
          'supercalifragilisticexpialidocious.',
          300,
        ),
        360,
      );
    });

    test('fixed pacing returns the base delay', () {
      expect(
        calculateSpeedReadWordDelayMs(
          'supercalifragilisticexpialidocious.',
          300,
          adaptivePacing: false,
        ),
        200,
      );
    });
  });

  group('SpeedReadController', () {
    test('setWPM clamps to the supported speed read range', () {
      final controller = SpeedReadController();

      controller.setWPM(50);
      expect(controller.wordsPerMinute, 100);

      controller.setWPM(999);
      expect(controller.wordsPerMinute, 700);

      controller.dispose();
    });

    test('WPM and adaptive pacing changes recalculate current word delay', () {
      final controller = SpeedReadController()
        ..setWPM(300)
        ..start('misunderstanding', 0);

      final adaptiveDelay = controller.currentWordDelay;
      expect(adaptiveDelay.inMilliseconds, greaterThan(200));

      controller.setWPM(600);
      expect(controller.currentWordDelay, lessThan(adaptiveDelay));

      controller.setAdaptivePacing(false);
      expect(controller.currentWordDelay.inMilliseconds, 100);

      controller.dispose();
    });

    test('page changes can restart active speed read in a paused state', () {
      final controller = SpeedReadController()..start('Alpha beta', 0);

      controller.onPageChanged('Gamma delta', 1, startPaused: true);

      expect(controller.isActive, isTrue);
      expect(controller.isPaused, isTrue);
      expect(controller.currentPageIndex, 1);
      expect(controller.currentWordIndex, 0);
      expect(controller.tokens.map((token) => token.word), ['Gamma', 'delta']);

      controller.dispose();
    });

    test('page changes keep auto-continue behavior when not startPaused', () {
      final controller = SpeedReadController()..start('Alpha beta', 0);

      controller.onPageChanged('Gamma delta', 1);

      expect(controller.isActive, isTrue);
      expect(controller.isPaused, isFalse);
      expect(controller.currentPageIndex, 1);
      expect(controller.currentWordIndex, 0);

      controller.dispose();
    });

    test(
      'completed pages restart automatically after a manual page change',
      () {
        fakeAsync((async) {
          final controller = SpeedReadController()..start('Alpha', 0);

          async.elapse(const Duration(seconds: 1));
          expect(controller.isActive, isTrue);
          expect(controller.isPaused, isTrue);
          expect(controller.isPageComplete, isTrue);

          controller.onPageChanged('Beta gamma', 1);

          expect(controller.isActive, isTrue);
          expect(controller.isPaused, isFalse);
          expect(controller.isPageComplete, isFalse);
          expect(controller.currentPageIndex, 1);
          expect(controller.currentWordIndex, 0);
          expect(controller.tokens.map((token) => token.word), [
            'Beta',
            'gamma',
          ]);

          controller.dispose();
        });
      },
    );

    test(
      'jumping back after page completion resumes if it completed playing',
      () {
        fakeAsync((async) {
          final controller = SpeedReadController()..start('Alpha beta', 0);

          async.elapse(const Duration(seconds: 2));
          expect(controller.isPageComplete, isTrue);
          expect(controller.isPaused, isTrue);

          controller.jumpToWord(0);

          expect(controller.currentWordIndex, 0);
          expect(controller.isPageComplete, isFalse);
          expect(controller.isPaused, isFalse);

          controller.dispose();
        });
      },
    );
  });
}

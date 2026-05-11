import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/word_token.dart';

int calculateSpeedReadWordDelayMs(
  String token,
  int wpm, {
  bool adaptivePacing = true,
}) {
  final clampedWpm = wpm.clamp(100, 700).toInt();
  final baseMs = 60000 / clampedWpm;
  if (!adaptivePacing) return baseMs.round();

  final readableLength = _readableCharacterCount(token);
  final lengthMultiplier = readableLength <= 0
      ? 1.0
      : readableLength <= 3
      ? 0.85
      : readableLength <= 6
      ? 1.0
      : readableLength <= 9
      ? 1.15
      : readableLength <= 12
      ? 1.3
      : 1.45;

  final punctuationMultiplier = switch (_terminalPunctuation(token)) {
    ',' => 1.2,
    ';' || ':' || '\u2014' => 1.35,
    '.' || '?' || '!' => 1.6,
    _ => 1.0,
  };

  final rawDelay = baseMs * lengthMultiplier * punctuationMultiplier;
  final minDelay = baseMs * 0.75;
  final maxDelay = baseMs * 1.8;
  return rawDelay.clamp(minDelay, maxDelay).round();
}

int _readableCharacterCount(String token) {
  var count = 0;
  for (var i = 0; i < token.length; i++) {
    if (_isReadableCodeUnit(token.codeUnitAt(i))) count++;
  }
  return count;
}

String? _terminalPunctuation(String token) {
  var index = token.length - 1;
  while (index >= 0) {
    final unit = token.codeUnitAt(index);
    if (_isTrailingWrapper(unit) || unit == 32 || unit == 9 || unit == 10) {
      index--;
      continue;
    }
    return token[index];
  }
  return null;
}

bool _isTrailingWrapper(int codeUnit) {
  return codeUnit == 34 || // "
      codeUnit == 39 || // '
      codeUnit == 41 || // )
      codeUnit == 93 || // ]
      codeUnit == 125 || // }
      codeUnit == 0x2019 ||
      codeUnit == 0x201D;
}

bool _isReadableCodeUnit(int codeUnit) {
  final isDigit = codeUnit >= 48 && codeUnit <= 57;
  final isUpper = codeUnit >= 65 && codeUnit <= 90;
  final isLower = codeUnit >= 97 && codeUnit <= 122;
  final isLatin1Letter = codeUnit >= 192 && codeUnit <= 255;
  return isDigit || isUpper || isLower || isLatin1Letter;
}

class SpeedReadController extends ChangeNotifier {
  int _wordsPerMinute = 200;
  bool _adaptivePacing = true;
  bool _isActive = false;
  bool _isPaused = false;
  bool _isPageComplete = false;
  bool _resumeAfterPageComplete = false;
  int _currentWordIndex = 0;
  int _currentPageIndex = 0;
  List<WordToken> _tokens = [];
  List<Duration> _wordDelays = [];
  Timer? _timer;

  // Getters
  int get wordsPerMinute => _wordsPerMinute;
  bool get adaptivePacing => _adaptivePacing;
  bool get isActive => _isActive;
  bool get isPaused => _isPaused;
  bool get isPageComplete => _isPageComplete;
  int get currentWordIndex => _currentWordIndex;
  int get currentPageIndex => _currentPageIndex;
  List<WordToken> get tokens => _tokens;
  Duration get currentWordDelay => _durationForCurrentToken();

  WordToken? get activeToken {
    if (_currentWordIndex >= 0 && _currentWordIndex < _tokens.length) {
      return _tokens[_currentWordIndex];
    }
    return null;
  }

  double get progressInPage => _tokens.isEmpty
      ? 0.0
      : (_currentWordIndex / _tokens.length).clamp(0.0, 1.0);

  Duration get _baseInterval => Duration(
    milliseconds: calculateSpeedReadWordDelayMs(
      '',
      _wordsPerMinute,
      adaptivePacing: false,
    ),
  );

  void setWPM(int wpm) {
    if (wpm < 100) wpm = 100;
    if (wpm > 700) wpm = 700;
    if (_wordsPerMinute == wpm) return;

    _wordsPerMinute = wpm;
    _recomputeWordDelays();
    notifyListeners();

    if (_isActive && !_isPaused) {
      _scheduleNextTick();
    }
  }

  void setAdaptivePacing(bool enabled) {
    if (_adaptivePacing == enabled) return;

    _adaptivePacing = enabled;
    _recomputeWordDelays();
    notifyListeners();

    if (_isActive && !_isPaused) {
      _scheduleNextTick();
    }
  }

  void start(String pageText, int pageIndex) {
    _currentPageIndex = pageIndex;
    _tokenize(pageText);
    _currentWordIndex = 0;
    _isActive = true;
    _isPaused = false;
    _isPageComplete = _tokens.isEmpty;
    _resumeAfterPageComplete = false;
    notifyListeners();
    _scheduleNextTick();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _isActive = false;
    _isPaused = false;
    _isPageComplete = false;
    _resumeAfterPageComplete = false;
    _currentWordIndex = 0;
    notifyListeners();
  }

  void pause() {
    if (!_isActive || _isPaused) return;
    _timer?.cancel();
    _isPaused = true;
    _resumeAfterPageComplete = false;
    notifyListeners();
  }

  void resume() {
    if (!_isActive || !_isPaused) return;
    // Don't resume if we've finished the page
    if (_isPageComplete || _currentWordIndex >= _tokens.length) return;

    _isPaused = false;
    notifyListeners();
    _scheduleNextTick();
  }

  void jumpToWord(int wordIndex) {
    if (!_isActive) return;
    if (wordIndex >= 0 && wordIndex < _tokens.length) {
      final shouldResume = _isPageComplete && _resumeAfterPageComplete;
      _currentWordIndex = wordIndex;
      _isPageComplete = false;
      if (shouldResume) {
        _isPaused = false;
      }
      _resumeAfterPageComplete = false;
      notifyListeners();
      if (!_isPaused) {
        _scheduleNextTick();
      }
    }
  }

  void onPageChanged(
    String newPageText,
    int newPageIndex, {
    bool startPaused = false,
  }) {
    final bool wasActive = _isActive;
    stop();
    _currentPageIndex = newPageIndex;
    _tokenize(newPageText);

    if (wasActive) {
      _currentWordIndex = 0;
      _isActive = true;
      _isPaused = startPaused || _tokens.isEmpty;
      _isPageComplete = _tokens.isEmpty;
      _resumeAfterPageComplete = false;
      notifyListeners();
      if (!_isPaused) {
        _scheduleNextTick();
      }
    } else {
      _isPageComplete = false;
      notifyListeners();
    }
  }

  void _tokenize(String text) {
    _tokens = [];
    final regex = RegExp(r'\S+');
    final matches = regex.allMatches(text);
    for (final match in matches) {
      final raw = match.group(0)!;
      final core = _readableCore(raw);
      if (core == null) continue;
      _tokens.add(
        WordToken(
          startOffset: match.start,
          endOffset: match.end,
          coreStartOffset: match.start + core.start,
          coreEndOffset: match.start + core.end,
          word: raw,
          coreWord: raw.substring(core.start, core.end),
        ),
      );
    }
    _recomputeWordDelays();
  }

  ({int start, int end})? _readableCore(String token) {
    int start = 0;
    int end = token.length;

    bool isReadable(int codeUnit) {
      return _isReadableCodeUnit(codeUnit);
    }

    while (start < end && !isReadable(token.codeUnitAt(start))) {
      start++;
    }
    while (end > start && !isReadable(token.codeUnitAt(end - 1))) {
      end--;
    }
    if (start >= end) return null;
    return (start: start, end: end);
  }

  void _scheduleNextTick() {
    _timer?.cancel();
    if (_tokens.isEmpty || !_isActive || _isPaused || _isPageComplete) return;

    _timer = Timer(_durationForCurrentToken(), () {
      if (_currentWordIndex < _tokens.length - 1) {
        _currentWordIndex++;
        notifyListeners();
        _scheduleNextTick();
      } else {
        _completePage();
      }
    });
  }

  Duration _durationForCurrentToken() {
    if (_currentWordIndex >= 0 && _currentWordIndex < _wordDelays.length) {
      return _wordDelays[_currentWordIndex];
    }
    return _baseInterval;
  }

  void _recomputeWordDelays() {
    _wordDelays = [
      for (final token in _tokens)
        Duration(
          milliseconds: calculateSpeedReadWordDelayMs(
            token.word,
            _wordsPerMinute,
            adaptivePacing: _adaptivePacing,
          ),
        ),
    ];
  }

  void _completePage() {
    _timer?.cancel();
    _timer = null;
    _resumeAfterPageComplete = !_isPaused;
    _currentWordIndex = _tokens.length;
    _isPaused = true;
    _isPageComplete = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

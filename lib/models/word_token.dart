class WordToken {
  final int startOffset; // visual char offset in chunk text
  final int endOffset; // visual char offset end (exclusive)
  final int
  coreStartOffset; // readable word start, excluding wrapping punctuation
  final int coreEndOffset; // readable word end, excluding wrapping punctuation
  final String word; // the displayed token text
  final String coreWord; // token text used for pacing decisions

  const WordToken({
    required this.startOffset,
    required this.endOffset,
    int? coreStartOffset,
    int? coreEndOffset,
    required this.word,
    String? coreWord,
  }) : coreStartOffset = coreStartOffset ?? startOffset,
       coreEndOffset = coreEndOffset ?? endOffset,
       coreWord = coreWord ?? word;

  bool get hasReadableCore => coreStartOffset < coreEndOffset;
}

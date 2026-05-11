class PositionHistory {
  final int chunkIndex;
  final int displayIndex;
  final String label;

  PositionHistory({
    required this.chunkIndex,
    required this.displayIndex,
    required this.label,
  });

  Map<String, dynamic> toMap() {
    return {
      'chunkIndex': chunkIndex,
      'displayIndex': displayIndex,
      'label': label,
    };
  }

  factory PositionHistory.fromMap(Map<String, dynamic> map) {
    return PositionHistory(
      chunkIndex: map['chunkIndex'] as int,
      displayIndex: map['displayIndex'] as int,
      label: map['label'] as String,
    );
  }
}

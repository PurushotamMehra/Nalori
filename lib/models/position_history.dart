import 'stable_book_location.dart';

class PositionHistory {
  final int chunkIndex;
  final int displayIndex;
  final String label;
  final StableBookLocation? stableLocation;

  PositionHistory({
    required this.chunkIndex,
    required this.displayIndex,
    required this.label,
    this.stableLocation,
  });

  Map<String, dynamic> toMap() {
    return {
      'chunkIndex': chunkIndex,
      'displayIndex': displayIndex,
      'label': label,
      if (stableLocation != null) 'stableLocation': stableLocation!.toJson(),
    };
  }

  factory PositionHistory.fromMap(Map<String, dynamic> map) {
    return PositionHistory(
      chunkIndex: map['chunkIndex'] as int,
      displayIndex: map['displayIndex'] as int,
      label: map['label'] as String,
      stableLocation: StableBookLocation.maybeFromJson(map['stableLocation']),
    );
  }
}

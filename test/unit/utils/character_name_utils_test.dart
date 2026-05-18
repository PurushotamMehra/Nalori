import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/utils/character_name_utils.dart';

void main() {
  test('builds aliases from full character names for reader coloring', () {
    expect(characterNameAliases(' Elizabeth   Bennet '), [
      'Elizabeth Bennet',
      'Elizabeth',
      'Bennet',
    ]);
  });

  test('does not create aliases from initials or common titles', () {
    expect(characterNameAliases('G. A. Raymond'), ['G. A. Raymond', 'Raymond']);
    expect(characterNameAliases('Mr. Darcy'), ['Mr. Darcy', 'Darcy']);
  });
}

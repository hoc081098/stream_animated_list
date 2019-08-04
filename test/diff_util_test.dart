import 'package:flutter_test/flutter_test.dart';
import 'package:stream_animated_list/src/diff_util.dart';

List<T> applyEditScript<T>(List<T> oldList, List<T> newList, List<Diff> diffs) {
  final copy = List.of(oldList);

  for (final diff in diffs) {
    diff.fold(
      onInsert: (InsertDiff insertDiff) {
        final add = newList.getRange(
          insertDiff.globalIndex,
          insertDiff.globalIndex + insertDiff.size,
        );
        copy.insertAll(insertDiff.index, add);
      },
      onRemove: (RemoveDiff removeDiff) {
        copy.removeRange(
          removeDiff.index,
          removeDiff.index + removeDiff.size,
        );
      },
    );
    print('Apply $diff => $copy');
  }
  return copy;
}

class Wrap {
  final int n;
  Wrap(this.n);
  @override
  bool operator ==(other) =>
      identical(this, other) || other is Wrap && other.n == n;
}

main() {
  group('Test $DiffUtil', () {
    test('Diff matcher should produce a correct edit script. 1', () {
      final a = ['a', 'b', 'c', 'a', 'b', 'b', 'a'];
      final b = ['c', 'b', 'a', 'b', 'a', 'c'];
      final diffs = DiffUtil.calculateDiff(a, b);
      expect(
        applyEditScript(a, b, diffs),
        b,
      );
    });

    test('Diff matcher should produce a correct edit script. 2', () {
      final a = ['a', 'b', 'c'];
      final b = ['a', 'b', 'd'];
      final diffs = DiffUtil.calculateDiff(a, b);
      expect(
        applyEditScript(a, b, diffs),
        b,
      );
    });

    test('Diff matcher should produce a correct edit script. 3', () {
      final a = [Wrap(1), Wrap(2), Wrap(3)];
      final b = [Wrap(1), Wrap(2), Wrap(2)];
      final diffs = DiffUtil.calculateDiff<Wrap>(a, b);
      expect(
        applyEditScript(a, b, diffs),
        b,
      );
    });
  });
}

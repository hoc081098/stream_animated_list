import 'package:flutter/material.dart';

typedef Eq<E> = bool Function(E oldItem, E newItem);

/// Snakes represent a match between two lists. It is optionally prefixed or postfixed with an
/// add or remove operation. See the Myers' paper for details.
class _Snake {
  /// Position in the old list
  int x;

  /// Position in the new list
  int y;

  /// Number of matches. Might be 0.
  int size;

  /// If true, this is a removal from the original list followed by {@code size} matches.
  /// If false, this is an addition from the new list followed by {@code size} matches.
  bool removal;

  /// If true, the addition or removal is at the end of the snake.
  /// If false, the addition or removal is at the beginning of the snake.
  bool reverse;

  _Snake({
    this.x: 0,
    this.y: 0,
    this.size: 0,
    this.removal: false,
    this.reverse: false,
  });
}

/// Represents a range in two lists that needs to be solved.
///
/// This internal class is used when running Myers' algorithm without recursion.
class _Range {
  int oldListStart;
  int oldListEnd;

  int newListStart;
  int newListEnd;

  _Range(
    this.oldListStart,
    this.oldListEnd,
    this.newListStart,
    this.newListEnd,
  );
}

abstract class Diff {
  final int index;
  final int size;

  const Diff(this.index, this.size);

  void fold({
    @required onRemove(RemoveDiff removeDiff),
    @required onInsert(InsertDiff insertDiff),
  }) {
    if (this is RemoveDiff) {
      return onRemove(this);
    }
    if (this is InsertDiff) {
      return onInsert(this);
    }
  }
}

class InsertDiff extends Diff {
  final int globalIndex;

  const InsertDiff(int index, int size, this.globalIndex) : super(index, size);

  @override
  String toString() => 'InsertDiff(index=$index, size=$size, globalIndex=$globalIndex)';
}

class RemoveDiff extends Diff {
  const RemoveDiff(int index, int size) : super(index, size);

  @override
  String toString() => 'RemoveDiff(index=$index, size=$size)';
}

class DiffUtil {
  ///
  /// Calculates the list of update operations that can covert one list into the other one.
  /// <p>
  /// If your old and new lists are sorted by the same constraint and items never move (swap
  /// positions), you can disable move detection which takes <code>O(N^2)</code> time where
  /// N is the number of added, moved, removed items.
  ///
  /// @param cb The callback that acts as a gateway to the backing list data
  /// @param detectMoves True if DiffUtil should try to detect moved items, false otherwise.
  ///
  /// @return A DiffResult that contains the information about the edit sequence to convert the
  /// old list into the new list.
  ///
  static List<Diff> calculateDiff<E>(List<E> oldList, List<E> newList,
      {Eq<E> eq}) {
    eq ??= (E a, E b) => a == b;
    final oldSize = oldList.length;
    final newSize = newList.length;

    final List<_Snake> snakes = [];

    // instead of a recursive implementation, we keep our own stack to avoid potential stack
    // overflow exceptions
    final List<_Range> stack = [];

    stack.add(_Range(0, oldSize, 0, newSize));

    final max = oldSize + newSize + (oldSize - newSize).abs();
    // allocate forward and backward k-lines. K lines are diagonal lines in the matrix. (see the
    // paper for details)
    // These arrays lines keep the max reachable position for each k-line.
    final forward = List<int>(max * 2);
    final backward = List<int>(max * 2);

    // We pool the ranges to avoid allocations for each recursive call.
    final List<_Range> rangePool = [];
    while (stack.isNotEmpty) {
      final _Range range = stack.removeAt(stack.length - 1);
      final _Snake snake = _diffPartial(
        (oldIndex, newIndex) => eq(oldList[oldIndex], newList[newIndex]),
        range.oldListStart,
        range.oldListEnd,
        range.newListStart,
        range.newListEnd,
        forward,
        backward,
        max,
      );
      if (snake != null) {
        if (snake.size > 0) {
          snakes.add(snake);
        }
        // offset the snake to convert its coordinates from the Range's area to global
        snake.x += range.oldListStart;
        snake.y += range.newListStart;

        // add new ranges for left and right
        final _Range left = rangePool.isEmpty
            ? _Range(0, 0, 0, 0)
            : rangePool.removeAt(rangePool.length - 1);
        left.oldListStart = range.oldListStart;
        left.newListStart = range.newListStart;
        if (snake.reverse) {
          left.oldListEnd = snake.x;
          left.newListEnd = snake.y;
        } else {
          if (snake.removal) {
            left.oldListEnd = snake.x - 1;
            left.newListEnd = snake.y;
          } else {
            left.oldListEnd = snake.x;
            left.newListEnd = snake.y - 1;
          }
        }
        stack.add(left);

        // re-use range for right
        final _Range right = range;
        if (snake.reverse) {
          if (snake.removal) {
            right.oldListStart = snake.x + snake.size + 1;
            right.newListStart = snake.y + snake.size;
          } else {
            right.oldListStart = snake.x + snake.size;
            right.newListStart = snake.y + snake.size + 1;
          }
        } else {
          right.oldListStart = snake.x + snake.size;
          right.newListStart = snake.y + snake.size;
        }
        stack.add(right);
      } else {
        rangePool.add(range);
      }
    }
    // sort snakes
    snakes.sort((o1, o2) {
      int cmpX = o1.x - o2.x;
      return cmpX == 0 ? o1.y - o2.y : cmpX;
    });

    _addRootSnake(snakes);
    return _dispatch(oldSize, newSize, snakes);
  }

  static List<Diff> _dispatch(
    int oldListSize,
    int newListSize,
    List<_Snake> snakes,
  ) {
    // These are add/remove ops that are converted to moves. We track their positions until
    // their respective update operations are processed.
    final List<Diff> diffs = [];
    int posOld = oldListSize;
    int posNew = newListSize;
    for (int snakeIndex = snakes.length - 1; snakeIndex >= 0; snakeIndex--) {
      final _Snake snake = snakes[snakeIndex];
      final int snakeSize = snake.size;
      final int endX = snake.x + snakeSize;
      final int endY = snake.y + snakeSize;

      if (endX < posOld) {
        diffs.add(RemoveDiff(endX, posOld - endX));
      }
      if (endY < posNew) {
        diffs.add(InsertDiff(endX, posNew - endY, endY));
      }
      posOld = snake.x;
      posNew = snake.y;
    }
    return diffs;
  }

  /// We always add a Snake to 0/0 so that we can run loops from end to beginning and be done
  /// when we run out of snakes.
  static void _addRootSnake(List<_Snake> snakes) {
    _Snake firstSnake = snakes.isEmpty ? null : snakes.first;
    if (firstSnake == null || firstSnake.x != 0 || firstSnake.y != 0) {
      _Snake root = _Snake()
        ..x = 0
        ..y = 0
        ..removal = false
        ..size = 0
        ..reverse = false;
      snakes.insert(0, root);
    }
  }

  static _Snake _diffPartial<E>(
    bool areItemsTheSame(int oldIndex, int newIndex),
    int startOld,
    int endOld,
    int startNew,
    int endNew,
    List<int> forward,
    List<int> backward,
    int kOffset,
  ) {
    final int oldSize = endOld - startOld;
    final int newSize = endNew - startNew;

    if (endOld - startOld < 1 || endNew - startNew < 1) {
      return null;
    }

    final int delta = oldSize - newSize;
    final int dLimit = (oldSize + newSize + 1) ~/ 2;
    forward.fillRange(kOffset - dLimit - 1, kOffset + dLimit + 1, 0);
    backward.fillRange(
      kOffset - dLimit - 1 + delta,
      kOffset + dLimit + 1 + delta,
      oldSize,
    );
    final bool checkInFwd = delta % 2 != 0;
    for (int d = 0; d <= dLimit; d++) {
      for (int k = -d; k <= d; k += 2) {
        // find forward path
        // we can reach k from k - 1 or k + 1. Check which one is further in the graph
        int x;
        bool removal;
        if (k == -d ||
            (k != d && forward[kOffset + k - 1] < forward[kOffset + k + 1])) {
          x = forward[kOffset + k + 1];
          removal = false;
        } else {
          x = forward[kOffset + k - 1] + 1;
          removal = true;
        }
        // set y based on x
        int y = x - k;
        // move diagonal as long as items match
        while (x < oldSize &&
            y < newSize &&
            areItemsTheSame(startOld + x, startNew + y)) {
          x++;
          y++;
        }
        forward[kOffset + k] = x;
        if (checkInFwd && k >= delta - d + 1 && k <= delta + d - 1) {
          if (forward[kOffset + k] >= backward[kOffset + k]) {
            _Snake outSnake = _Snake()..x = backward[kOffset + k];
            outSnake
              ..y = outSnake.x - k
              ..size = forward[kOffset + k] - backward[kOffset + k]
              ..removal = removal
              ..reverse = false;
            return outSnake;
          }
        }
      }
      for (int k = -d; k <= d; k += 2) {
        // find reverse path at k + delta, in reverse
        final int backwardK = k + delta;
        int x;
        bool removal;
        if (backwardK == d + delta ||
            (backwardK != -d + delta &&
                backward[kOffset + backwardK - 1] <
                    backward[kOffset + backwardK + 1])) {
          x = backward[kOffset + backwardK - 1];
          removal = false;
        } else {
          x = backward[kOffset + backwardK + 1] - 1;
          removal = true;
        }

        // set y based on x
        int y = x - backwardK;
        // move diagonal as long as items match
        while (x > 0 &&
            y > 0 &&
            areItemsTheSame(startOld + x - 1, startNew + y - 1)) {
          x--;
          y--;
        }
        backward[kOffset + backwardK] = x;
        if (!checkInFwd && k + delta >= -d && k + delta <= d) {
          if (forward[kOffset + backwardK] >= backward[kOffset + backwardK]) {
            _Snake outSnake = _Snake()..x = backward[kOffset + backwardK];
            outSnake
              ..y = outSnake.x - backwardK
              ..size =
                  forward[kOffset + backwardK] - backward[kOffset + backwardK]
              ..removal = removal
              ..reverse = true;
            return outSnake;
          }
        }
      }
    }
    throw StateError('DiffUtil hit an unexpected case while trying to calculate' +
        ' the optimal path. Please make sure your data is not changing during the' +
        ' diff calculation.');
  }
}

/// The conversation list's "when".
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/chat/relative_time.dart';

void main() {
  final now = DateTime(2026, 10, 13, 12);

  test('recent times count up', () {
    expect(relativeTime(now.subtract(const Duration(seconds: 30)), now), 'just now');
    expect(relativeTime(now.subtract(const Duration(minutes: 5)), now), '5m ago');
    expect(relativeTime(now.subtract(const Duration(hours: 3)), now), '3h ago');
    expect(relativeTime(now.subtract(const Duration(days: 2)), now), '2d ago');
  });

  test('older times are dates', () {
    expect(relativeTime(DateTime(2026, 9), now), '1 Sep');
    expect(relativeTime(DateTime(2025, 12, 25), now), '25 Dec 2025');
  });

  test('a time in the future reads as now', () {
    expect(relativeTime(now.add(const Duration(minutes: 3)), now), 'just now');
  });
}

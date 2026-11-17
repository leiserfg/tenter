import 'package:flutter_test/flutter_test.dart';
import 'package:tenter/utils/formatters.dart';

void main() {
  test('precise timestamps preserve millisecond chunk boundaries', () {
    expect(formatPreciseDuration(1234), '00:01.234');
    expect(formatPreciseDuration(60507), '01:00.507');
    expect(formatPreciseDuration(-1), '00:00.000');
  });
}

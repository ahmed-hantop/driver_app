import 'dart:async';

import 'package:driver_app/services/refresh_coalescer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('coalesces bursts into a single refresh and keeps heavy flag', () async {
    final calls = <bool>[];
    final gate = Completer<void>();

    final coalescer = RefreshCoalescer(
      runRefresh: (includeHeavy) async {
        calls.add(includeHeavy);
        await gate.future;
      },
    );

    coalescer.schedule(includeHeavy: false);
    coalescer.schedule(includeHeavy: true);
    coalescer.schedule(includeHeavy: false);

    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(calls.length, 1);
    expect(calls.first, true);

    gate.complete();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(calls.length, 1);
  });

  test('runs another cycle when new work arrives during active refresh', () async {
    final calls = <bool>[];
    late RefreshCoalescer coalescer;

    coalescer = RefreshCoalescer(
      runRefresh: (includeHeavy) async {
        calls.add(includeHeavy);
        if (calls.length == 1) {
          coalescer.schedule(includeHeavy: true);
        }
      },
    );

    coalescer.schedule(includeHeavy: false);
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(calls.length, 2);
    expect(calls[0], false);
    expect(calls[1], true);
  });
}

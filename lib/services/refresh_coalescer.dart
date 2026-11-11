import 'dart:async';

class RefreshCoalescer {
  RefreshCoalescer({
    required Future<void> Function(bool includeHeavy) runRefresh,
  }) : _runRefresh = runRefresh;

  final Future<void> Function(bool includeHeavy) _runRefresh;

  bool _scheduled = false;
  bool _queued = false;
  bool _includeHeavy = false;

  void schedule({bool includeHeavy = true}) {
    _queued = true;
    _includeHeavy = _includeHeavy || includeHeavy;

    if (_scheduled) return;
    _scheduled = true;
    Future.microtask(_drain);
  }

  Future<void> _drain() async {
    while (_queued) {
      final includeHeavy = _includeHeavy;
      _queued = false;
      _includeHeavy = false;
      await _runRefresh(includeHeavy);
    }

    _scheduled = false;
    if (_queued) {
      _scheduled = true;
      Future.microtask(_drain);
    }
  }
}

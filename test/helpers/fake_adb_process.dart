import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A dart:io [Process] the test drives, standing in for adb behind the
/// bridge. [arguments] starts with the executable.
class FakeAdbProcess implements Process {
  FakeAdbProcess(this.arguments);

  final List<String> arguments;
  final StreamController<List<int>> _stdout = StreamController<List<int>>();
  final StreamController<List<int>> _stderr = StreamController<List<int>>();
  final Completer<int> _exit = Completer<int>();
  bool killed = false;

  void out(String text) => _stdout.add(utf8.encode(text));

  void err(String text) => _stderr.add(utf8.encode(text));

  void finish([int code = 0]) {
    if (!_exit.isCompleted) {
      unawaited(_stdout.close());
      unawaited(_stderr.close());
      _exit.complete(code);
    }
  }

  @override
  Stream<List<int>> get stdout => _stdout.stream;

  @override
  Stream<List<int>> get stderr => _stderr.stream;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  int get pid => 4242;

  @override
  IOSink get stdin =>
      throw UnimplementedError('The bridge never writes to adb.');

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    finish(-15);
    return true;
  }
}

/// Starts [FakeAdbProcess]es and keeps them. [onStart] scripts each one.
class FakeAdb {
  final List<FakeAdbProcess> started = [];
  void Function(FakeAdbProcess process)? onStart;
  Object? startError;

  Future<Process> start(String executable, List<String> arguments) async {
    final error = startError;
    if (error != null) {
      throw error;
    }
    final process = FakeAdbProcess([executable, ...arguments]);
    started.add(process);
    onStart?.call(process);
    return process;
  }
}

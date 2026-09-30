import 'dart:async';
import 'dart:convert';

import 'package:fcm_studio/features/devices/data/process_runner.dart';

ProcessOutput ok(String stdout) => ProcessOutput(exitCode: 0, stdout: stdout);

/// Answers commands from a script. A command is the executable and its
/// arguments joined by spaces. Unscripted commands fail like a missing program.
class FakeProcessRunner implements ProcessRunner {
  final List<List<String>> calls = [];
  final Map<String, Object> _answers = {};
  final Map<String, FakeRunningProcess Function()> _starts = {};

  List<String> get commands => [for (final call in calls) call.join(' ')];

  /// [answer] is a [ProcessOutput], a `List<ProcessOutput>` (one per call;
  /// the last one repeats) or an [Exception] to throw.
  void on(String command, Object answer) => _answers[command] = answer;

  void onStart(String command, FakeRunningProcess Function() create) =>
      _starts[command] = create;

  @override
  Future<ProcessOutput> run(
    String executable,
    List<String> arguments, {
    Duration timeout = ProcessRunner.defaultTimeout,
  }) async {
    calls.add([executable, ...arguments]);
    final command = describeCommand(executable, arguments);
    switch (_answers[command]) {
      case final ProcessOutput output:
        return output;
      case final List<ProcessOutput> outputs:
        return outputs.length > 1 ? outputs.removeAt(0) : outputs.single;
      case final Exception error:
        throw error;
      default:
        throw ProcessRunException(command, 'could not start: not scripted');
    }
  }

  @override
  Future<RunningProcess> start(
    String executable,
    List<String> arguments,
  ) async {
    calls.add([executable, ...arguments]);
    final command = describeCommand(executable, arguments);
    final create = _starts[command];
    if (create == null) {
      throw ProcessRunException(command, 'could not start: not scripted');
    }
    return create();
  }
}

/// A long-running process whose output the test writes.
class FakeRunningProcess implements RunningProcess {
  final StreamController<List<int>> _stdout = StreamController<List<int>>();
  final Completer<int> _exit = Completer<int>();
  bool killed = false;

  void emit(String text) => _stdout.add(utf8.encode(text));

  void exit([int code = 0]) {
    if (!_exit.isCompleted) {
      _exit.complete(code);
      unawaited(_stdout.close());
    }
  }

  @override
  Stream<List<int>> get stdout => _stdout.stream;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  void kill() {
    killed = true;
    exit(-9);
  }
}

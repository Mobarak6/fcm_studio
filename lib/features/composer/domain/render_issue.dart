import 'package:equatable/equatable.dart';

/// A note, warning or error about one part of the message.
class RenderIssue extends Equatable {
  const RenderIssue(this.path, this.message);

  /// Where the issue is, e.g. `data.order_id`, `target`, `android.priority`.
  final String path;
  final String message;

  @override
  List<Object?> get props => [path, message];
}

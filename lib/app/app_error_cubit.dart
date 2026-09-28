import 'package:fcm_studio/core/utils/redact.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The app-wide, dismissible error (spec §11). The state is the message, or
/// null when there is nothing to show.
class AppErrorCubit extends Cubit<String?> {
  AppErrorCubit() : super(null);

  /// Shows [error], redacted, after what the app was doing ([context]).
  void report(Object error, {String? context}) {
    final text = redact('$error');
    emit(context == null ? text : '$context: $text');
  }

  void dismiss() => emit(null);
}

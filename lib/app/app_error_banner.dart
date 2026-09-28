import 'package:fcm_studio/app/app_error_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class AppErrorBanner extends StatelessWidget {
  const AppErrorBanner({super.key});

  static const dismissKey = Key('app-error-dismiss');

  @override
  Widget build(BuildContext context) {
    final message = context.watch<AppErrorCubit>().state;
    if (message == null) {
      return const SizedBox.shrink();
    }
    return MaterialBanner(
      leading: const Icon(Icons.error_outline),
      content: Text(message),
      actions: [
        TextButton(
          key: dismissKey,
          onPressed: () => context.read<AppErrorCubit>().dismiss(),
          child: const Text('Dismiss'),
        ),
      ],
    );
  }
}

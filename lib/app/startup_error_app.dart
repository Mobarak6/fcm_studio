import 'package:fcm_studio/app/theme.dart';
import 'package:fcm_studio/core/utils/redact.dart';
import 'package:flutter/material.dart';

/// Shown instead of the app when startup fails, so it never ends as a blank
/// screen (spec §11).
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({required this.error, super.key});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FCM Studio',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'FCM Studio could not start',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  SelectableText(redact('$error')),
                  const SizedBox(height: 12),
                  const Text(
                    'Quit and reopen FCM Studio. If it keeps happening, the '
                    'local database may be damaged.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

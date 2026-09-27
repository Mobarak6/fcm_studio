import 'package:fcm_studio/features/projects/view/project_switcher.dart';
import 'package:flutter/material.dart';

class ComposerScreen extends StatelessWidget {
  const ComposerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('FCM Studio')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [ProjectSwitcher()],
      ),
    );
  }
}

import 'package:fcm_studio/app/theme.dart';
import 'package:flutter/material.dart';

class FcmStudioApp extends StatelessWidget {
  const FcmStudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FCM Studio',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: const Scaffold(body: Center(child: Text('FCM Studio'))),
    );
  }
}

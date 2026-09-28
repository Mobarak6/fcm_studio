import 'package:fcm_studio/features/projects/cubit/projects_cubit.dart';
import 'package:fcm_studio/features/projects/domain/project.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The red banner above the composer for production projects (spec §4.3).
class ProdBanner extends StatelessWidget {
  const ProdBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final project = context.select((ProjectsCubit c) => c.state.selected);
    if (project == null || project.environment != ProjectEnvironment.prod) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const Key('prod-banner'),
      width: double.infinity,
      color: scheme.error,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        'PRODUCTION · ${project.id} · every send asks for confirmation',
        style: TextStyle(color: scheme.onError, fontWeight: FontWeight.w600),
      ),
    );
  }
}

import 'package:fcm_studio/app/app_error_cubit.dart';
import 'package:fcm_studio/app/navigation_cubit.dart';
import 'package:fcm_studio/features/composer/cubit/composer_cubit.dart';
import 'package:fcm_studio/features/composer/domain/target.dart';
import 'package:fcm_studio/features/devices/bloc/devices_bloc.dart';
import 'package:fcm_studio/features/devices/cubit/token_reader_cubit.dart';
import 'package:fcm_studio/features/devices/domain/device_token.dart';
import 'package:fcm_studio/features/projects/cubit/projects_cubit.dart';
import 'package:fcm_studio/features/targets/cubit/targets_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Uses a token read from the phone (spec §9.3 "Result"): it becomes the
/// composer's target and is saved as a device target, and the composer is
/// shown again.
Future<void> useDeviceToken(
  BuildContext context, {
  required String package,
  required FoundToken found,
  required TokenReadMethod method,
}) async {
  final devices = context.read<DevicesBloc>().state;
  final reader = context.read<TokenReaderCubit>();
  final composer = context.read<ComposerCubit>();
  final targets = context.read<TargetsCubit>();
  final projectId = context.read<ProjectsCubit>().state.selectedId;
  final navigation = context.read<NavigationCubit>();
  final errors = context.read<AppErrorCubit>();
  final messenger = ScaffoldMessenger.of(context);
  final serial = reader.state.serial;
  if (serial == null) {
    return;
  }
  final device = devices.devices.where((d) => d.serial == serial).firstOrNull;
  final token = DeviceToken(
    token: found.token,
    senderId: found.senderId,
    method: method,
    readAt: DateTime.now().toUtc(),
    serial: serial,
    package: package,
    deviceName: device == null ? serial : devices.nameOf(device),
  );
  composer.setTarget(TargetKind.token, token.token);
  reader.dismiss();
  navigation.show(AppSection.composer);
  messenger.showSnackBar(
    SnackBar(content: Text('Using the token of ${token.label}.')),
  );
  try {
    await targets.saveDeviceToken(token, projectId: projectId);
  } catch (e) {
    errors.report(e, context: 'Could not save the device target');
  }
}

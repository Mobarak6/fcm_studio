import 'package:flutter_bloc/flutter_bloc.dart';

/// The app's screens. The rail shows them in [AppShell.sectionsFor] order.
enum AppSection { composer, presets, targets, history, devices, settings }

class NavigationCubit extends Cubit<AppSection> {
  NavigationCubit() : super(AppSection.composer);

  void show(AppSection section) => emit(section);
}

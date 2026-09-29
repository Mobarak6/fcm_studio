import 'package:flutter_bloc/flutter_bloc.dart';

/// The screens in the navigation rail, in rail order.
enum AppSection { composer, presets, targets, history }

class NavigationCubit extends Cubit<AppSection> {
  NavigationCubit() : super(AppSection.composer);

  void show(AppSection section) => emit(section);
}

import 'package:flutter/widgets.dart';
import 'package:matrix/matrix.dart';

import '../matrix/matrix_ids.dart';

class MatrixExperience extends InheritedWidget {
  final bool on;

  const MatrixExperience({required this.on, required super.child, super.key});

  static bool isOn(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MatrixExperience>()?.on ??
      false;

  @override
  bool updateShouldNotify(MatrixExperience oldWidget) => on != oldWidget.on;
}

extension MatrixExperienceLabels on BuildContext {
  String matrixIdLabel(String id) =>
      MatrixExperience.isOn(this) ? id : withoutServer(id);

  String? matrixRoomAddress(Room room) {
    final alias = room.canonicalAlias;
    return MatrixExperience.isOn(this) && alias.isNotEmpty ? alias : null;
  }
}

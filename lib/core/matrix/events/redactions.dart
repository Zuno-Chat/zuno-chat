import 'package:matrix/matrix.dart';

String? redactionTarget(MatrixEvent redaction) =>
    redaction.redacts ?? redaction.content.tryGet<String>('redacts');

import 'dart:io';

import 'native_strings.dart';

void main(List<String> args) {
  final root = Directory.current;
  final outputs = buildOutputs(root);
  if (args.contains('--check')) {
    final stale = staleFiles(root, outputs);
    if (stale.isEmpty) return;
    stderr.writeln(
      'Stale native strings: ${stale.join(', ')}\nRun: dart run tool/l10n/generate_native.dart',
    );
    exitCode = 1;
    return;
  }
  writeOutputs(root, outputs);
  deleteOrphans(root, outputs);
}

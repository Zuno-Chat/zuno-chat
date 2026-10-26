import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';
import 'package:zuno_lints/src/direct_background_work.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(DirectBackgroundWorkTest);
  });
}

@reflectiveTest
class DirectBackgroundWorkTest extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = DirectBackgroundWork();
    final flutter = newPackage('flutter');
    super.setUp();
    flutter.addFile('lib/foundation.dart', r'''
Future<R> compute<M, R>(R Function(M) callback, M message) async => throw 0;
''');
  }

  Future<void> test_isolateSpawn() async {
    const code = r'''
import 'dart:isolate';
final started = Isolate.spawnUri(Uri(), [], null);
''';
    await assertDiagnostics(code, [lint(code.indexOf('spawnUri'), 8)]);
  }

  Future<void> test_compute() async {
    const code = r'''
import 'package:flutter/foundation.dart';
int twice(int n) => n * 2;
final result = compute(twice, 2);
''';
    await assertDiagnostics(code, [lint(code.indexOf('compute(twice'), 7)]);
  }

  Future<void> test_computeTearOff() async {
    const code = r'''
import 'package:flutter/foundation.dart';
final run = compute<int, int>;
''';
    await assertDiagnostics(code, [lint(code.indexOf('compute<'), 7)]);
  }

  Future<void> test_importCombinatorIsNotReported() async {
    const code = r'''
import 'package:flutter/foundation.dart' show compute;
int twice(int n) => n * 2;
final result = compute(twice, 2);
''';
    await assertDiagnostics(code, [lint(code.indexOf('compute(twice'), 7)]);
  }

  Future<void> test_ownerIsExempt() async {
    final path = '$testPackageRootPath/lib/core/async/background_work.dart';
    newFile(path, r'''
import 'dart:isolate';
final started = Isolate.spawnUri(Uri(), [], null);
''');
    await assertNoDiagnosticsInFile(path);
  }

  Future<void> test_testFilesAreOutOfScope() async {
    final path = '$testPackageRootPath/test/isolate_test.dart';
    newFile(path, r'''
import 'dart:isolate';
final started = Isolate.spawnUri(Uri(), [], null);
''');
    await assertNoDiagnosticsInFile(path);
  }
}

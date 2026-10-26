import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';
import 'package:zuno_lints/src/direct_clock_read.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(DirectClockReadTest);
  });
}

@reflectiveTest
class DirectClockReadTest extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = DirectClockRead();
    final clock = newPackage('clock');
    super.setUp();
    clock.addFile('lib/clock.dart', r'''
class Clock {
  DateTime now() => throw 0;
  Stopwatch stopwatch() => throw 0;
}
Clock get clock => throw 0;
''');
  }

  Future<void> test_dateTimeNow() async {
    const code = r'''
final at = DateTime.now();
''';
    await assertDiagnostics(code, [lint(code.indexOf('DateTime.now()'), 14)]);
  }

  Future<void> test_dateTimeNowTearOff() async {
    const code = r'''
DateTime Function() read = DateTime.now;
''';
    await assertDiagnostics(code, [lint(code.indexOf('DateTime.now'), 12)]);
  }

  Future<void> test_stopwatch() async {
    const code = r'''
final watch = Stopwatch();
''';
    await assertDiagnostics(code, [lint(code.indexOf('Stopwatch()'), 11)]);
  }

  Future<void> test_clockStopwatch() async {
    const code = r'''
import 'package:clock/clock.dart';
final watch = clock.stopwatch();
''';
    await assertDiagnostics(code, [
      lint(code.indexOf('clock.stopwatch()'), 17),
    ]);
  }

  Future<void> test_spanOwnerIsExempt() async {
    final path = '$testPackageRootPath/lib/core/async/elapsed.dart';
    newFile(path, r'''
import 'package:clock/clock.dart';
final real = Stopwatch();
final fake = clock.stopwatch();
''');
    await assertNoDiagnosticsInFile(path);
  }

  Future<void> test_clockIsAllowed() async {
    await assertNoDiagnostics(r'''
import 'package:clock/clock.dart';
final at = clock.now();
''');
  }

  Future<void> test_otherDateTimeUseIsAllowed() async {
    await assertNoDiagnostics(r'''
bool early(DateTime a, DateTime b) => a.isBefore(b);
''');
  }

  Future<void> test_testFiles() async {
    final path = '$testPackageRootPath/test/clock_test.dart';
    const code = r'''
final at = DateTime.now();
''';
    newFile(path, code);
    await assertDiagnosticsInFile(path, [
      lint(code.indexOf('DateTime.now()'), 14),
    ]);
  }

  Future<void> test_realTimeCeilingHelperIsExempt() async {
    final path = '$testPackageRootPath/test/helpers/pump_until.dart';
    newFile(path, r'''
final watch = Stopwatch();
''');
    await assertNoDiagnosticsInFile(path);
  }

  Future<void> test_toolFilesAreOutOfScope() async {
    final path = '$testPackageRootPath/tool/release.dart';
    newFile(path, r'''
final at = DateTime.now();
''');
    await assertNoDiagnosticsInFile(path);
  }
}

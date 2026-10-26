import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';
import 'package:zuno_lints/src/real_time_wait.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(RealTimeWaitTest);
  });
}

@reflectiveTest
class RealTimeWaitTest extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = RealTimeWait();
    final flutterTest = newPackage('flutter_test');
    final fakeAsync = newPackage('fake_async');
    super.setUp();
    flutterTest.addFile('lib/flutter_test.dart', r'''
class WidgetTester {
  Future<T?> runAsync<T>(Future<T> Function() callback) async => null;
  Future<void> pump([Duration? duration]) async {}
}
void testWidgets(String description, Future<void> Function(WidgetTester) callback) {}
void test(String description, dynamic Function() body) {}
void setUp(dynamic Function() body) {}
void group(String description, void Function() body) {}
''');
    fakeAsync.addFile('lib/fake_async.dart', r'''
class FakeAsync {
  T run<T>(T Function(FakeAsync self) callback) => throw 0;
}
T fakeAsync<T>(T Function(FakeAsync async) callback) => throw 0;
''');
  }

  String get _testPath => '$testPackageRootPath/test/wait_test.dart';

  Future<void> _expectLints(String code, List<String> snippets) async {
    newFile(_testPath, code);
    await assertDiagnosticsInFile(_testPath, [
      for (final snippet in snippets)
        lint(code.indexOf(snippet), snippet.length),
    ]);
  }

  Future<void> _expectNone(String code) async {
    newFile(_testPath, code);
    await assertNoDiagnosticsInFile(_testPath);
  }

  Future<void> test_realTurnInRunAsync() async {
    await _expectLints(
      r'''
import 'package:flutter_test/flutter_test.dart';
void main() {
  testWidgets('x', (tester) async {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  });
}
''',
      ['Future<void>.delayed(Duration.zero)'],
    );
  }

  Future<void> test_realDelayInRunAsync() async {
    await _expectLints(
      r'''
import 'package:flutter_test/flutter_test.dart';
void main() {
  testWidgets('x', (tester) async {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
  });
}
''',
      ['Future<void>.delayed(const Duration(milliseconds: 20))'],
    );
  }

  Future<void> test_realDelayInPlainTest() async {
    await _expectLints(
      r'''
import 'package:flutter_test/flutter_test.dart';
void main() {
  group('g', () {
    test('x', () async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
  });
}
''',
      ['Future<void>.delayed(const Duration(milliseconds: 50))'],
    );
  }

  Future<void> test_realDelayInSetUp() async {
    await _expectLints(
      r'''
import 'package:flutter_test/flutter_test.dart';
void main() {
  setUp(() => Future<void>.delayed(const Duration(milliseconds: 10)));
}
''',
      ['Future<void>.delayed(const Duration(milliseconds: 10))'],
    );
  }

  Future<void> test_zeroDelayInPlainTestIsAllowed() async {
    await _expectNone(r'''
import 'package:flutter_test/flutter_test.dart';
void main() {
  test('x', () async {
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(const Duration());
    await Future<void>.delayed(const Duration(milliseconds: 0));
  });
}
''');
  }

  Future<void> test_fakeTimeInWidgetTestIsAllowed() async {
    await _expectNone(r'''
import 'package:flutter_test/flutter_test.dart';
void main() {
  testWidgets('x', (tester) async {
    final slow = Future.delayed(const Duration(milliseconds: 200), () => true);
    await tester.pump(const Duration(milliseconds: 200));
    await slow;
  });
}
''');
  }

  Future<void> test_fakeTimeInFakeAsyncIsAllowed() async {
    await _expectNone(r'''
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
void main() {
  test('x', () {
    fakeAsync((async) {
      Future<void>.delayed(const Duration(seconds: 1));
    });
    FakeAsync().run((async) {
      Future<void>.delayed(const Duration(seconds: 1));
    });
  });
}
''');
  }

  Future<void> test_helperOutsideATestIsNotJudged() async {
    await _expectNone(r'''
Future<bool> slowly() => Future.delayed(const Duration(seconds: 1), () => true);
''');
  }

  Future<void> test_realTimeCeilingHelperIsExempt() async {
    final path = '$testPackageRootPath/test/helpers/pump_until.dart';
    newFile(path, r'''
import 'package:flutter_test/flutter_test.dart';
Future<void> pumpUntil(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
}
''');
    await assertNoDiagnosticsInFile(path);
  }

  Future<void> test_libFilesAreOutOfScope() async {
    await assertNoDiagnostics(r'''
import 'package:flutter_test/flutter_test.dart';
void main() {
  test('x', () => Future<void>.delayed(const Duration(seconds: 1)));
}
''');
  }
}

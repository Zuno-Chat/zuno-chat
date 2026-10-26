import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';
import 'package:zuno_lints/src/direct_disk_access.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(DirectDiskAccessTest);
  });
}

@reflectiveTest
class DirectDiskAccessTest extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = DirectDiskAccess();
    final pathProvider = newPackage('path_provider');
    super.setUp();
    pathProvider.addFile('lib/path_provider.dart', r'''
import 'dart:io';
Future<Directory> getTemporaryDirectory() async => throw 0;
''');
  }

  Future<void> test_fileConstructor() async {
    const code = r'''
import 'dart:io';
final file = File('a.txt');
''';
    await assertDiagnostics(code, [lint(code.indexOf("File('a.txt')"), 13)]);
  }

  Future<void> test_directoryConstructor() async {
    const code = r'''
import 'dart:io';
final dir = Directory('cache');
''';
    await assertDiagnostics(code, [
      lint(code.indexOf("Directory('cache')"), 18),
    ]);
  }

  Future<void> test_staticEntityQuery() async {
    const code = r'''
import 'dart:io';
Future<bool> isDir() => FileSystemEntity.isDirectory('cache');
''';
    await assertDiagnostics(code, [lint(code.indexOf('isDirectory'), 11)]);
  }

  Future<void> test_pathProviderLookup() async {
    const code = r'''
import 'package:path_provider/path_provider.dart';
final dir = getTemporaryDirectory();
''';
    await assertDiagnostics(code, [
      lint(code.lastIndexOf('getTemporaryDirectory'), 21),
    ]);
  }

  Future<void> test_fileTypesAreAllowed() async {
    await assertNoDiagnostics(r'''
import 'dart:io';
Future<DateTime> modified(File file) => file.lastModified();
''');
  }

  Future<void> test_ownerIsExempt() async {
    final path = '$testPackageRootPath/lib/core/files/file_system.dart';
    newFile(path, r'''
import 'dart:io';
import 'package:path_provider/path_provider.dart';
final file = File('a.txt');
final dir = getTemporaryDirectory();
''');
    await assertNoDiagnosticsInFile(path);
  }

  Future<void> test_testFilesAreOutOfScope() async {
    final path = '$testPackageRootPath/test/disk_test.dart';
    newFile(path, r'''
import 'dart:io';
final file = File('a.txt');
''');
    await assertNoDiagnosticsInFile(path);
  }
}

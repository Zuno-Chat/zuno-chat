import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';
import 'package:zuno_lints/src/hardcoded_user_text.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(HardcodedUserTextTest);
  });
}

@reflectiveTest
class HardcodedUserTextTest extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = HardcodedUserText();
    final flutter = newPackage('flutter');
    final notifications = newPackage('flutter_local_notifications');
    final share = newPackage('share_plus_platform_interface');
    final filePicker = newPackage('file_picker');
    super.setUp();
    flutter.addFile('lib/widgets.dart', r'''
abstract class Widget { const Widget(); }
class Text extends Widget { const Text(String data, {String? semanticsLabel}); }
class Image extends Widget { const Image.asset(String name); }
class Tooltip extends Widget { const Tooltip({required String message, String? restorationId}); }
class Semantics extends Widget { const Semantics({String? label, String? value}); }
class DropdownMenuItem<T> extends Widget { const DropdownMenuItem({T? value, required Widget child}); }
class InputDecoration { const InputDecoration({String? hintText}); }
''');
    notifications.addFile('lib/flutter_local_notifications.dart', r'''
class DarwinNotificationAction {
  factory DarwinNotificationAction.plain(String identifier, String title) =>
      DarwinNotificationAction._(identifier, title);
  factory DarwinNotificationAction.text(String identifier, String title,
          {required String buttonTitle, String? placeholder}) =>
      DarwinNotificationAction._(identifier, title);
  const DarwinNotificationAction._(this.identifier, this.title);
  final String identifier;
  final String title;
}
class AndroidNotificationActionInput {
  const AndroidNotificationActionInput({String? label});
}
''');
    share.addFile('lib/share_plus_platform_interface.dart', r'''
class ShareParams {
  const ShareParams({String? text, String? subject, String? title});
}
''');
    filePicker.addFile('lib/file_picker.dart', r'''
class FilePicker {
  static Future<String?> saveFile({String? dialogTitle, String? fileName}) async => null;
}
''');
  }

  Future<void> test_literalInWidget() async {
    await assertDiagnostics(
      r'''
import 'package:flutter/widgets.dart';
final w = Text('Hello there');
''',
      [lint(54, 13)],
    );
  }

  Future<void> test_interpolationInWidget() async {
    await assertDiagnostics(
      r'''
import 'package:flutter/widgets.dart';
String name = 'x';
final w = Text('Hi $name');
''',
      [lint(73, 10)],
    );
  }

  Future<void> test_ternaryInWidget() async {
    await assertDiagnostics(
      r'''
import 'package:flutter/widgets.dart';
bool on = true;
final w = Text(on ? 'On' : 'Off');
''',
      [lint(75, 4), lint(82, 5)],
    );
  }

  Future<void> test_nonWidgetSink() async {
    await assertDiagnostics(
      r'''
import 'package:flutter/widgets.dart';
final d = InputDecoration(hintText: 'Search');
''',
      [lint(75, 8)],
    );
  }

  Future<void> test_displayTextParameter() async {
    await assertDiagnostics(
      r'''
const displayText = Object();
void show(@displayText String message) {}
void f() => show('Saved');
''',
      [lint(89, 7)],
    );
  }

  Future<void> test_tooltipMessage() async {
    await assertDiagnostics(
      r'''
import 'package:flutter/widgets.dart';
final w = Tooltip(message: 'Hello');
''',
      [lint(66, 7)],
    );
  }

  Future<void> test_userDefinedWidget() async {
    await assertDiagnostics(
      r'''
import 'package:flutter/widgets.dart';
class Banner extends Widget { const Banner({required String title}); }
final b = Banner(title: 'Welcome');
''',
      [lint(134, 9)],
    );
  }

  Future<void> test_technicalParameter() async {
    await assertNoDiagnostics(r'''
import 'package:flutter/widgets.dart';
final w = Image.asset('assets/logo.png');
final t = Tooltip(message: '', restorationId: 'tip');
''');
  }

  Future<void> test_userAgentPackageName() async {
    await assertNoDiagnostics(r'''
import 'package:flutter/widgets.dart';
class TileLayer extends Widget { const TileLayer({String? userAgentPackageName}); }
final t = TileLayer(userAgentPackageName: 'im.zuno.chat');
''');
  }

  Future<void> test_noLetters() async {
    await assertNoDiagnostics(r'''
import 'package:flutter/widgets.dart';
final w = Text(' · ');
''');
  }

  Future<void> test_darwinNotificationAction() async {
    await assertDiagnostics(
      r'''
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
final a = DarwinNotificationAction.plain('read', 'Mark as read');
final b = DarwinNotificationAction.text('reply', 'Reply',
    buttonTitle: 'Send', placeholder: 'Message');
''',
      [lint(128, 14), lint(194, 7), lint(220, 6), lint(241, 9)],
    );
  }

  Future<void> test_notificationActionInputLabel() async {
    await assertDiagnostics(
      r'''
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
final i = AndroidNotificationActionInput(label: 'Message');
''',
      [lint(127, 9)],
    );
  }

  Future<void> test_shareParams() async {
    await assertDiagnostics(
      r'''
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';
final p = ShareParams(text: 'report body', subject: 'Report', title: 'Share');
''',
      [lint(135, 8), lint(152, 7)],
    );
  }

  Future<void> test_filePickerDialogTitle() async {
    await assertDiagnostics(
      r'''
import 'package:file_picker/file_picker.dart';
final f = FilePicker.saveFile(dialogTitle: 'Save file', fileName: 'code.txt');
''',
      [lint(90, 11)],
    );
  }

  Future<void> test_semanticsValue() async {
    await assertDiagnostics(
      r'''
import 'package:flutter/widgets.dart';
final w = Semantics(value: 'Selected');
''',
      [lint(66, 10)],
    );
  }

  Future<void> test_customWidgetName() async {
    await assertDiagnostics(
      r'''
import 'package:flutter/widgets.dart';
class Badge extends Widget { const Badge({required String name}); }
final b = Badge(name: 'Admin');
''',
      [lint(129, 7)],
    );
  }

  Future<void> test_technicalNameAndValueOnFlutterClasses() async {
    await assertNoDiagnostics(r'''
import 'package:flutter/widgets.dart';
final i = Image.asset('assets/logo.png');
final d = DropdownMenuItem<String>(value: 'en', child: Text(''));
''');
  }

  Future<void> test_outsideLibIsSkipped() async {
    final path = '$testPackageRootPath/test/widget_test.dart';
    newFile(path, r'''
import 'package:flutter/widgets.dart';
final w = Text('Hello there');
''');
    await assertNoDiagnosticsInFile(path);
  }

  Future<void> test_nonSinkFunction() async {
    await assertNoDiagnostics(r'''
void log(String message) {}
void f() => log('Sync started');
''');
  }
}

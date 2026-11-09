import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';
import 'package:zuno_lints/src/direct_network_client.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(DirectNetworkClientTest);
  });
}

@reflectiveTest
class DirectNetworkClientTest extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = DirectNetworkClient();
    final http = newPackage('http');
    final zunoHttp = newPackage('zuno_http');
    super.setUp();
    zunoHttp.addFile('lib/zuno_http.dart', r'''
class ZunoHttpClient {
  ZunoHttpClient({String userAgent = ''});
}
class ZunoWebSocket {
  static Future<ZunoWebSocket> connect(Uri url) async => throw 0;
}
''');
    http.addFile('lib/http.dart', r'''
abstract interface class Client {
  factory Client() => throw 0;
}
Future<Object> get(Uri url) async => throw 0;
Future<Object> post(Uri url) async => throw 0;
Future<String> read(Uri url) async => throw 0;
''');
    http.addFile('lib/io_client.dart', r'''
import 'http.dart';
class IOClient implements Client {
  IOClient([Object? inner]);
}
''');
  }

  Future<void> test_clientConstructor() async {
    const code = r'''
import 'package:http/http.dart' as http;
final client = http.Client();
''';
    await assertDiagnostics(code, [lint(code.indexOf('http.Client()'), 13)]);
  }

  Future<void> test_clientTearOff() async {
    const code = r'''
import 'package:http/http.dart' as http;
final make = http.Client.new;
''';
    await assertDiagnostics(code, [lint(code.indexOf('http.Client.new'), 15)]);
  }

  Future<void> test_ioClient() async {
    const code = r'''
import 'package:http/io_client.dart';
final client = IOClient();
''';
    await assertDiagnostics(code, [lint(code.indexOf('IOClient()'), 10)]);
  }

  Future<void> test_topLevelGet() async {
    const code = r'''
import 'package:http/http.dart' as http;
final answer = http.get(Uri());
''';
    await assertDiagnostics(code, [lint(code.indexOf('get('), 3)]);
  }

  Future<void> test_topLevelRead() async {
    const code = r'''
import 'package:http/http.dart' as http;
final answer = http.read(Uri());
''';
    await assertDiagnostics(code, [lint(code.indexOf('read('), 4)]);
  }

  Future<void> test_ioClientTearOff() async {
    const code = r'''
import 'package:http/io_client.dart';
final make = IOClient.new;
''';
    await assertDiagnostics(code, [lint(code.indexOf('IOClient.new'), 12)]);
  }

  Future<void> test_topLevelPost() async {
    const code = r'''
import 'package:http/http.dart' as http;
final answer = http.post(Uri());
''';
    await assertDiagnostics(code, [lint(code.indexOf('post('), 4)]);
  }

  Future<void> test_shownClient() async {
    const code = r'''
import 'package:http/http.dart' show Client;
final client = Client();
''';
    await assertDiagnostics(code, [lint(code.indexOf('Client()'), 8)]);
  }

  Future<void> test_hiddenShortcutIsNotFlagged() async {
    await assertNoDiagnostics(r'''
import 'package:http/http.dart' hide get;
Future<void> use(Client client) async {}
''');
  }

  Future<void> test_nativeClientOutsideTheFactory() async {
    const code = r'''
import 'package:zuno_http/zuno_http.dart';
final client = ZunoHttpClient();
''';
    await assertDiagnostics(code, [lint(code.indexOf('ZunoHttpClient()'), 16)]);
  }

  Future<void> test_nativeSocketOutsideTheFactory() async {
    const code = r'''
import 'package:zuno_http/zuno_http.dart';
final socket = ZunoWebSocket.connect(Uri());
''';
    await assertDiagnostics(code, [lint(code.indexOf('connect('), 7)]);
  }

  Future<void> test_clientTypeIsAllowed() async {
    await assertNoDiagnostics(r'''
import 'package:http/http.dart' as http;
Future<void> use(http.Client client) async {}
''');
  }

  Future<void> test_ownerIsExempt() async {
    final path = '$testPackageRootPath/lib/core/network/app_http_client.dart';
    newFile(path, r'''
import 'package:http/http.dart' as http;
import 'package:zuno_http/zuno_http.dart';
final client = http.Client();
final native = ZunoHttpClient();
final socket = ZunoWebSocket.connect(Uri());
''');
    await assertNoDiagnosticsInFile(path);
  }

  Future<void> test_testFilesAreOutOfScope() async {
    final path = '$testPackageRootPath/test/client_test.dart';
    newFile(path, r'''
import 'package:http/http.dart' as http;
final client = http.Client();
''');
    await assertNoDiagnosticsInFile(path);
  }
}

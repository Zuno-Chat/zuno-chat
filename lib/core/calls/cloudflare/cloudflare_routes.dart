import 'package:matrix/matrix.dart';

import '../module/calls_module.dart';

Uri cloudflareCallsBaseUri(Client client) =>
    callsModuleUri(client, const ['cloudflare']);

Uri turnCredentialsUri(Client client) =>
    callsModuleUri(client, const ['cloudflare', 'turn', 'credentials']);

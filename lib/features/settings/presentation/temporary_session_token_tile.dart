import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../core/matrix/auth_error_message.dart';
import '../../../core/matrix/matrix_client_provider.dart';

const temporarySessionTokenDeviceName = 'Zuno token (temporary)';

Future<LoginResponse> requestUnrefreshableSessionToken(
  Client client,
  String password,
) {
  return MatrixApi(
    homeserver: client.homeserver,
    httpClient: client.httpClient,
  ).login(
    LoginType.mLoginPassword,
    identifier: AuthenticationUserIdentifier(user: client.userID!),
    password: password,
    initialDeviceDisplayName: temporarySessionTokenDeviceName,
    refreshToken: false,
  );
}

class TemporarySessionTokenTile extends ConsumerWidget {
  const TemporarySessionTokenTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: const Icon(Icons.vpn_key_outlined),
      title: const Text('Get a session token'),
      subtitle: const Text(
        'Temporary · Signs in a second session without a refresh token and '
        'shows its access token',
      ),
      trailing: const Icon(Icons.chevron_right_outlined),
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) =>
            _SessionTokenDialog(client: ref.read(matrixClientProvider)),
      ),
    );
  }
}

class _SessionTokenDialog extends StatefulWidget {
  final Client client;
  const _SessionTokenDialog({required this.client});

  @override
  State<_SessionTokenDialog> createState() => _SessionTokenDialogState();
}

class _SessionTokenDialogState extends State<_SessionTokenDialog> {
  final _password = TextEditingController();
  bool _loading = false;
  String? _error;
  LoginResponse? _session;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _request() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final session = await requestUnrefreshableSessionToken(
        widget.client,
        _password.text,
      );
      if (mounted) setState(() => _session = session);
    } catch (e) {
      if (mounted) setState(() => _error = loginErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _copy(String token) {
    Clipboard.setData(ClipboardData(text: token));
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Session token copied')));
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    if (session != null) {
      return AlertDialog(
        title: const Text('Session token'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Session ID: ${session.deviceId}'),
            const SizedBox(height: 12),
            SelectableText(session.accessToken),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () => _copy(session.accessToken),
            child: const Text('Copy'),
          ),
        ],
      );
    }

    return AlertDialog(
      title: const Text('Get a session token'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Signs in as ${widget.client.userID} in a second session.'),
          const SizedBox(height: 12),
          AutofillGroup(
            onDisposeAction: AutofillContextAction.cancel,
            child: TextField(
              autofillHints: const [AutofillHints.password],
              controller: _password,
              obscureText: true,
              autofocus: true,
              enabled: !_loading,
              decoration: InputDecoration(
                labelText: 'Password',
                errorText: _error,
              ),
              onSubmitted: (_) => _request(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _loading ? null : _request,
          child: const Text('Get token'),
        ),
      ],
    );
  }
}

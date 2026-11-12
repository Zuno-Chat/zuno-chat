import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../navigation/zuno_links.dart';
import '../auth/auth_browser.dart';
import '../auth/oauth_sign_in.dart';
import '../client/matrix_client_provider.dart';

const _longerThanAnyToken = Duration(days: 36500);

Future<void> openAccountPage(BuildContext context, Uri page) {
  final container = ProviderScope.containerOf(context, listen: false);
  final browser = container.read(authBrowserProvider);
  return openLink(
    context,
    page,
    openUrl: (page) async {
      final shown = await showUntilClosed(
        browser,
        page,
        callbackScheme: zunoOAuthCallbackScheme,
      );
      final client = container.read(matrixClientProvider);
      if (shown && client.isLogged()) {
        await client.ensureNotSoftLoggedOut(_longerThanAnyToken);
      }
      return shown;
    },
  );
}

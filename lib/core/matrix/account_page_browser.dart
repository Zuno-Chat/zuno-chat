import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../navigation/zuno_links.dart';
import 'auth_browser.dart';
import 'oauth_sign_in.dart';

Future<void> openAccountPage(BuildContext context, Uri page) {
  final browser = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(authBrowserProvider);
  return openLink(
    context,
    page,
    openUrl: (page) =>
        showUntilClosed(browser, page, callbackScheme: zunoOAuthCallbackScheme),
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/navigation/zuno_links.dart';
import '../../../core/settings/app_preferences_provider.dart';
import '../../../core/ui/card_group.dart';
import '../../../core/ui/card_list_view.dart';

const _matrixSdkVersion = '12.0.1';
const _vodozemacVersion = '0.8.0';
const _licenseNotice =
    'Copyright 2026 The Zuno Chat Authors.\n\n'
    'Free software under the GNU Affero General Public License, version 3 '
    'or later, with no warranty. The full text is listed under zuno below.';

class AboutPage extends ConsumerWidget {
  final UrlOpener openUrl;

  const AboutPage({this.openUrl = openExternally, super.key});

  Future<void> _open(BuildContext context, Uri uri) =>
      openLink(context, uri, openUrl: openUrl);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final crashReporting = ref.watch(crashReportingProvider);
    final showHiddenMessages = ref.watch(showHiddenMessagesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: FutureBuilder<PackageInfo>(
        future: PackageInfo.fromPlatform(),
        builder: (context, snapshot) {
          final info = snapshot.data;
          final version = info == null
              ? null
              : '${info.version} (build ${info.buildNumber})';
          return CardListView(
            children: [
              const SizedBox(height: 12),
              Center(
                child: SvgPicture.asset(
                  'assets/logo/zuno-mark-amber.svg',
                  width: 64,
                  height: 64,
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'Zuno',
                  style: Theme.of(context).textTheme.titleMedium!
                      .copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 18),
              CardGroup(
                children: [
                  ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: const Text('App version'),
                    subtitle: Text(version ?? 'Loading…'),
                  ),
                  const ListTile(
                    leading: Icon(Icons.hub_outlined),
                    title: Text('Chat library version'),
                    subtitle: Text(_matrixSdkVersion),
                  ),
                  const ListTile(
                    leading: Icon(Icons.enhanced_encryption_outlined),
                    title: Text('Encryption library version'),
                    subtitle: Text(_vodozemacVersion),
                  ),
                ],
              ),
              CardGroup(
                children: [
                  ListTile(
                    leading: const Icon(Icons.volunteer_activism_outlined),
                    title: const Text('Donate'),
                    subtitle: const Text(
                      'Donations help pay for running Zuno.',
                    ),
                    trailing: const Icon(Icons.open_in_new),
                    onTap: () => _open(context, donateUri),
                  ),
                  ListTile(
                    leading: const Icon(Icons.privacy_tip_outlined),
                    title: const Text('Privacy policy'),
                    trailing: const Icon(Icons.open_in_new),
                    onTap: () => _open(context, privacyPolicyUri),
                  ),
                  ListTile(
                    leading: const Icon(Icons.description_outlined),
                    title: const Text('Terms'),
                    trailing: const Icon(Icons.open_in_new),
                    onTap: () => _open(context, termsUri),
                  ),
                ],
              ),
              CardGroup(
                children: [
                  ListTile(
                    leading: const Icon(Icons.code),
                    title: const Text('Source code'),
                    trailing: const Icon(Icons.open_in_new),
                    onTap: () => _open(context, sourceCodeUri),
                  ),
                  ListTile(
                    leading: const Icon(Icons.article_outlined),
                    title: const Text('Open source licenses'),
                    trailing: const Icon(Icons.chevron_right_outlined),
                    onTap: () => showLicensePage(
                      context: context,
                      applicationName: 'Zuno',
                      applicationVersion: version,
                      applicationLegalese: _licenseNotice,
                    ),
                  ),
                ],
              ),
              CardGroup(
                title: 'Diagnostics',
                children: [
                  SwitchListTile(
                    secondary: const Icon(Icons.bug_report_outlined),
                    title: const Text('Send crash reports'),
                    subtitle: const Text(
                      'Sends the technical details of a crash to a reporting '
                      'service, with message content, names and addresses '
                      'removed. No crash report is sent while this is off',
                    ),
                    value: crashReporting,
                    onChanged: (value) =>
                        ref.read(crashReportingProvider.notifier).set(value),
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.visibility_off_outlined),
                    title: const Text('Show hidden messages'),
                    subtitle: const Text(
                      'Shows the call-signaling events Zuno normally hides, '
                      'marked apart from real messages',
                    ),
                    value: showHiddenMessages,
                    onChanged: (value) => ref
                        .read(showHiddenMessagesProvider.notifier)
                        .set(value),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/brand.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/navigation/zuno_links.dart';
import '../../../core/platform/platform_capabilities.dart';
import '../../../core/settings/app_preferences_provider.dart';
import '../../../core/settings/library_versions.dart';
import '../../../core/ui/card_group.dart';
import '../../../core/ui/card_list_view.dart';

class AboutPage extends ConsumerWidget {
  final UrlOpener openUrl;

  const AboutPage({this.openUrl = openExternally, super.key});

  Future<void> _open(BuildContext context, Uri uri) =>
      openLink(context, uri, openUrl: openUrl);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final crashReporting = ref.watch(crashReportingProvider);
    final showHiddenMessages = ref.watch(showHiddenMessagesProvider);
    final paymentLinks = ref
        .watch(platformCapabilitiesProvider)
        .externalPaymentLinks;
    final libraries = ref.watch(libraryVersionsProvider);
    String libraryVersion(String Function(LibraryVersions) pick) =>
        switch (libraries) {
          AsyncData(:final value) => pick(value),
          AsyncError() => l10n.settingsAboutUnknown,
          _ => l10n.commonLoading,
        };

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsAboutTitle)),
      body: FutureBuilder<PackageInfo>(
        future: PackageInfo.fromPlatform(),
        builder: (context, snapshot) {
          final info = snapshot.data;
          final version = info == null
              ? null
              : l10n.settingsAboutAppVersionBuild(
                  info.version,
                  info.buildNumber,
                );
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
                  zunoName,
                  style: Theme.of(context).textTheme.titleMedium!
                      .copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 18),
              CardGroup(
                children: [
                  ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: Text(l10n.settingsAboutAppVersion),
                    subtitle: Text(version ?? l10n.commonLoading),
                  ),
                  ListTile(
                    leading: const Icon(Icons.hub_outlined),
                    title: Text(l10n.settingsAboutChatLibraryVersion),
                    subtitle: Text(libraryVersion((v) => v.matrix)),
                  ),
                  ListTile(
                    leading: const Icon(Icons.enhanced_encryption_outlined),
                    title: Text(l10n.settingsAboutEncryptionLibraryVersion),
                    subtitle: Text(libraryVersion((v) => v.vodozemac)),
                  ),
                ],
              ),
              CardGroup(
                children: [
                  if (paymentLinks)
                    ListTile(
                      leading: const Icon(Icons.volunteer_activism_outlined),
                      title: Text(l10n.settingsAboutDonate),
                      subtitle: Text(l10n.settingsAboutDonateSubtitle),
                      trailing: const Icon(Icons.open_in_new),
                      onTap: () => _open(context, donateUri),
                    ),
                  ListTile(
                    leading: const Icon(Icons.privacy_tip_outlined),
                    title: Text(l10n.commonPrivacyPolicy),
                    trailing: const Icon(Icons.open_in_new),
                    onTap: () => _open(context, privacyPolicyUri),
                  ),
                  ListTile(
                    leading: const Icon(Icons.description_outlined),
                    title: Text(l10n.commonTerms),
                    trailing: const Icon(Icons.open_in_new),
                    onTap: () => _open(context, termsUri),
                  ),
                ],
              ),
              CardGroup(
                children: [
                  ListTile(
                    leading: const Icon(Icons.code),
                    title: Text(l10n.settingsAboutSourceCode),
                    trailing: const Icon(Icons.open_in_new),
                    onTap: () => _open(context, sourceCodeUri),
                  ),
                  ListTile(
                    leading: const Icon(Icons.article_outlined),
                    title: Text(l10n.settingsAboutLicenses),
                    trailing: const Icon(Icons.chevron_right_outlined),
                    onTap: () => showLicensePage(
                      context: context,
                      applicationName: zunoName,
                      applicationVersion: version,
                      applicationLegalese: l10n.settingsAboutLicenseNotice,
                    ),
                  ),
                ],
              ),
              CardGroup(
                title: l10n.settingsAboutDiagnostics,
                children: [
                  SwitchListTile(
                    secondary: const Icon(Icons.bug_report_outlined),
                    title: Text(l10n.settingsAboutCrashReports),
                    subtitle: Text(l10n.settingsAboutCrashReportsSubtitle),
                    value: crashReporting,
                    onChanged: (value) =>
                        ref.read(crashReportingProvider.notifier).set(value),
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.visibility_off_outlined),
                    title: Text(l10n.settingsAboutHiddenMessages),
                    subtitle: Text(l10n.settingsAboutHiddenMessagesSubtitle),
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

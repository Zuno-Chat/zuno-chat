import 'package:flutter/material.dart';

import '../../../core/ui/section_label.dart';

class SettingsSectionHeader extends StatelessWidget {
  final String title;
  const SettingsSectionHeader(this.title, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: SectionLabel(title),
  );
}

class ComingSoonTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;

  const ComingSoonTile({
    required this.icon,
    required this.title,
    this.subtitle,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      enabled: false,
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: const Chip(
        label: Text('Coming soon'),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

class ComingSoonSwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;

  const ComingSoonSwitchTile({
    required this.icon,
    required this.title,
    this.subtitle,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle ?? 'Coming soon'),
      value: false,
      onChanged: null,
    );
  }
}

import 'package:flutter/material.dart';

import 'zuno_theme.dart';

class ViewerScaffold extends StatelessWidget {
  final Widget? title;
  final List<Widget> actions;
  final Widget body;

  const ViewerScaffold({
    this.title,
    required this.actions,
    required this.body,
    super.key,
  });

  @override
  Widget build(BuildContext context) => Theme(
    data: zunoViewerTheme,
    child: Scaffold(
      appBar: AppBar(title: title, actions: actions),
      body: body,
    ),
  );
}

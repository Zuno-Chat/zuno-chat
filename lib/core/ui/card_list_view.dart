import 'package:flutter/material.dart';

class CardListView extends StatelessWidget {
  final List<Widget> children;
  final ScrollPhysics? physics;

  const CardListView({super.key, required this.children, this.physics});

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.paddingOf(context).bottom;
    return MediaQuery.removePadding(
      context: context,
      removeBottom: true,
      child: ListView(
        physics: physics,
        padding: EdgeInsets.only(top: 4, bottom: 16 + inset),
        children: children,
      ),
    );
  }
}

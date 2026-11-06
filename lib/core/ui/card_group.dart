import 'package:flutter/material.dart';

import 'sheet.dart';
import 'zuno_theme.dart';

const _cardMargin = EdgeInsets.fromLTRB(12, 6, 12, 6);

TextStyle cardGroupTitleStyle(BuildContext context) {
  final titleSmall = Theme.of(context).textTheme.titleSmall!;
  return titleSmall.copyWith(fontWeight: FontWeight.w500);
}

TextStyle _cardHeadingStyle(BuildContext context) {
  final titleMedium = Theme.of(context).textTheme.titleMedium!;
  return titleMedium.copyWith(fontWeight: FontWeight.w700);
}

Color _cardColor(BuildContext context, {bool highlighted = false}) {
  final scheme = Theme.of(context).colorScheme;
  if (highlighted) return scheme.secondaryContainer;
  return SheetSurface.holds(context)
      ? scheme.surfaceContainer
      : scheme.surfaceContainerLow;
}

BorderRadius _segmentCorners(int index, int count) {
  const corner = Radius.circular(ZunoRadius.large);
  return BorderRadius.vertical(
    top: index == 0 ? corner : Radius.zero,
    bottom: index == count - 1 ? corner : Radius.zero,
  );
}

class CardGroup extends StatelessWidget {
  final String? title;
  final List<Widget> children;

  const CardGroup({super.key, this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final title = this.title;
    return Padding(
      padding: _cardMargin,
      child: Material(
        color: _cardColor(context),
        borderRadius: BorderRadius.circular(ZunoRadius.large),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (title != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 6),
                child: Text(title, style: cardGroupTitleStyle(context)),
              ),
            ...children,
          ],
        ),
      ),
    );
  }
}

class SliverCardGroup extends StatelessWidget {
  final String? title;
  final Widget? leading;
  final VoidCallback? onTitleTap;
  final VoidCallback? onTitleLongPress;
  final bool highlighted;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final ChildIndexGetter? findChildIndexCallback;

  const SliverCardGroup({
    required this.itemCount,
    required this.itemBuilder,
    this.title,
    this.leading,
    this.onTitleTap,
    this.onTitleLongPress,
    this.highlighted = false,
    this.findChildIndexCallback,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final color = _cardColor(context, highlighted: highlighted);
    final title = this.title;
    final headings = title == null ? 0 : 1;
    final segments = headings + itemCount;
    Widget segment(int index, Widget child) {
      final corners = _segmentCorners(index, segments);
      return Material(
        key: child.key,
        color: color,
        borderRadius: corners,
        clipBehavior: corners == BorderRadius.zero ? Clip.none : Clip.antiAlias,
        child: child,
      );
    }

    return SliverPadding(
      padding: _cardMargin,
      sliver: SliverMainAxisGroup(
        slivers: [
          if (title != null)
            SliverToBoxAdapter(
              child: segment(
                0,
                _CardHeading(
                  title: title,
                  leading: leading,
                  onTap: onTitleTap,
                  onLongPress: onTitleLongPress,
                ),
              ),
            ),
          SliverList.builder(
            itemCount: itemCount,
            findChildIndexCallback: findChildIndexCallback,
            itemBuilder: (context, index) =>
                segment(headings + index, itemBuilder(context, index)),
          ),
        ],
      ),
    );
  }
}

class _CardHeading extends StatelessWidget {
  final String title;
  final Widget? leading;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const _CardHeading({
    required this.title,
    required this.leading,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final leading = this.leading;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 12, 4),
        child: Row(
          children: [
            if (leading != null) ...[leading, const SizedBox(width: 12)],
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _cardHeadingStyle(context),
              ),
            ),
            if (onTap != null)
              Icon(
                Icons.chevron_right,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
          ],
        ),
      ),
    );
  }
}

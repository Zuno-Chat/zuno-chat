import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/ui/keep_clear.dart';
import '../../../core/ui/zuno_motion.dart';

enum HomeTab {
  chats(Icons.chat_bubble_outline, Icons.chat_bubble),
  communities(Icons.workspaces_outlined, Icons.workspaces);

  const HomeTab(this.icon, this.selectedIcon);

  final IconData icon;
  final IconData selectedIcon;

  String label(AppLocalizations l10n) => switch (this) {
    HomeTab.chats => l10n.roomsChats,
    HomeTab.communities => l10n.roomsCommunities,
  };
}

class HomeBottomBar extends StatelessWidget {
  final HomeTab selected;
  final bool chatsUnread;
  final bool communitiesUnread;
  final ValueChanged<HomeTab> onSelect;
  final VoidCallback onNew;

  const HomeBottomBar({
    required this.selected,
    required this.chatsUnread,
    required this.communitiesUnread,
    required this.onSelect,
    required this.onNew,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    return KeepClearArea(
      child: ColoredBox(
        color: colors.surface,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(end: selected.index.toDouble()),
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : ZunoDurations.standard,
                        curve: Curves.fastOutSlowIn,
                        builder: (context, position, _) => LayoutBuilder(
                          builder: (context, constraints) {
                            final spare = math.max(
                              0.0,
                              constraints.maxWidth -
                                  HomeTab.values.length * _collapsedTabWidth,
                            );
                            return Row(
                              children: [
                                for (final tab in HomeTab.values)
                                  _tab(
                                    tab,
                                    l10n,
                                    spare,
                                    (1 - (position - tab.index).abs()).clamp(
                                      0.0,
                                      1.0,
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _NewButton(
                  tooltip: selected == HomeTab.chats
                      ? l10n.roomsNewChat
                      : l10n.roomsNewCommunity,
                  onTap: onNew,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tab(
    HomeTab tab,
    AppLocalizations l10n,
    double spare,
    double expansion,
  ) {
    final isSelected = tab == selected;
    return _Tab(
      label: tab.label(l10n),
      icon: isSelected ? tab.selectedIcon : tab.icon,
      selected: isSelected,
      unread: switch (tab) {
        HomeTab.chats => chatsUnread,
        HomeTab.communities => communitiesUnread,
      },
      width: _collapsedTabWidth + expansion * spare,
      expansion: expansion,
      onTap: () => onSelect(tab),
    );
  }
}

const _collapsedTabWidth = 56.0;

class _Tab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final bool unread;
  final double width;
  final double expansion;
  final VoidCallback onTap;

  const _Tab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.unread,
    required this.width,
    required this.expansion,
    required this.onTap,
  });

  static const _labelReveal = Interval(0.5, 1);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        value: unread ? context.l10n.roomsUnread : null,
        child: Container(
          width: width,
          constraints: const BoxConstraints(minHeight: 44),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLowest.withValues(alpha: expansion),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              customBorder: const StadiumBorder(),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Badge(
                      isLabelVisible: unread,
                      smallSize: 8,
                      child: Icon(
                        icon,
                        size: 22,
                        color: selected
                            ? colors.onSurface
                            : colors.onSurfaceVariant,
                      ),
                    ),
                    if (expansion > 0)
                      Flexible(
                        child: Opacity(
                          opacity: _labelReveal.transform(expansion),
                          child: Padding(
                            padding: const EdgeInsetsDirectional.only(start: 8),
                            child: ExcludeSemantics(
                              child: Text(
                                label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: colors.onSurface,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NewButton extends StatelessWidget {
  final String tooltip;
  final VoidCallback onTap;

  const _NewButton({required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: SizedBox.square(
        dimension: 56,
        child: Material(
          color: colors.primaryContainer,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Icon(Icons.add_outlined, color: colors.onPrimaryContainer),
          ),
        ),
      ),
    );
  }
}

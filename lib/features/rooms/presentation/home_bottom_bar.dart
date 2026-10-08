import 'package:flutter/material.dart';

import '../../../core/ui/keep_clear.dart';
import '../../../core/ui/zuno_motion.dart';

enum HomeTab { chats, communities }

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
                      child: Row(
                        children: [
                          _Tab(
                            label: 'Chats',
                            icon: Icons.chat_bubble_outline,
                            selectedIcon: Icons.chat_bubble,
                            selected: selected == HomeTab.chats,
                            unread: chatsUnread,
                            onTap: () => onSelect(HomeTab.chats),
                          ),
                          _Tab(
                            label: 'Communities',
                            icon: Icons.workspaces_outlined,
                            selectedIcon: Icons.workspaces,
                            selected: selected == HomeTab.communities,
                            unread: communitiesUnread,
                            onTap: () => onSelect(HomeTab.communities),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _NewButton(
                  tooltip: selected == HomeTab.chats
                      ? 'New chat'
                      : 'New community',
                  onTap: onNew,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final bool selected;
  final bool unread;
  final VoidCallback onTap;

  const _Tab({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.selected,
    required this.unread,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final color = selected ? colors.onSurface : colors.onSurfaceVariant;
    return Expanded(
      child: MergeSemantics(
        child: Semantics(
          button: true,
          selected: selected,
          value: unread ? 'Unread' : null,
          child: AnimatedContainer(
            duration: ZunoDurations.fast,
            constraints: const BoxConstraints(minHeight: 44),
            decoration: BoxDecoration(
              color: selected ? colors.surfaceContainerLowest : null,
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
                          selected ? selectedIcon : icon,
                          size: 22,
                          color: color,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: color,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
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

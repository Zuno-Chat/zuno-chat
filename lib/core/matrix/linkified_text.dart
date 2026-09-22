import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ui/zuno_colors.dart';
import 'matrix_ids.dart';
import 'urls.dart';

typedef _Hit = ({int start, int end, String shown, bool isMention});

class LinkifiedText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final int? maxLines;
  final Set<String>? mentionable;
  final InlineSpan? trailing;

  const LinkifiedText(
    this.text, {
    this.style,
    this.maxLines,
    this.mentionable,
    this.trailing,
    super.key,
  });

  static final _roomMentionPattern = RegExp(
    r'(?<![\w@])@room(?![\w])',
    caseSensitive: false,
  );

  static const _serverName = r'[a-z0-9-]+(?:\.[a-z0-9-]+)+(?::\d+)?';

  static final _userMentionPattern = RegExp(
    '(?<![\\w@])(@(?:\\[[^\\]]+\\]|[$matrixLocalpartChars]+))'
    '(?::$_serverName)?',
    caseSensitive: false,
  );

  TextOverflow get _overflow =>
      maxLines == null ? TextOverflow.clip : TextOverflow.ellipsis;

  @override
  Widget build(BuildContext context) {
    final mentionable = this.mentionable;
    final hits = <_Hit>[
      for (final m in urlPattern.allMatches(text))
        (start: m.start, end: m.end, shown: m.group(0)!, isMention: false),
      for (final m in _roomMentionPattern.allMatches(text))
        (start: m.start, end: m.end, shown: m.group(0)!, isMention: true),
      if (mentionable != null)
        for (final m in _userMentionPattern.allMatches(text))
          if (mentionable.contains(m.group(1)!.toLowerCase()))
            (start: m.start, end: m.end, shown: m.group(1)!, isMention: true),
    ]..sort((a, b) => a.start.compareTo(b.start));
    final trailing = this.trailing;
    if (hits.isEmpty && trailing == null) {
      return Text(text, style: style, maxLines: maxLines, overflow: _overflow);
    }

    final baseStyle = DefaultTextStyle.of(context).style.merge(style);
    final linkStyle = baseStyle.copyWith(color: ZunoColors.of(context).link);
    final mentionStyle = baseStyle.copyWith(
      color: Theme.of(context).colorScheme.primary,
      fontWeight: FontWeight.bold,
    );

    final spans = <InlineSpan>[];
    var last = 0;
    for (final hit in hits) {
      if (hit.start < last) continue;
      if (hit.start > last) {
        spans.add(TextSpan(text: text.substring(last, hit.start)));
      }
      if (hit.isMention) {
        spans.add(TextSpan(text: hit.shown, style: mentionStyle));
      } else {
        final uri = Uri.tryParse(hit.shown);
        spans.add(
          TextSpan(
            text: hit.shown,
            style: linkStyle,
            recognizer: uri == null || !isSafeExternalUri(uri)
                ? null
                : (TapGestureRecognizer()
                    ..onTap = () =>
                        launchUrl(uri, mode: LaunchMode.externalApplication)),
          ),
        );
      }
      last = hit.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    if (trailing != null) spans.add(trailing);

    return Text.rich(
      TextSpan(style: baseStyle, children: spans),
      maxLines: maxLines,
      overflow: _overflow,
    );
  }
}

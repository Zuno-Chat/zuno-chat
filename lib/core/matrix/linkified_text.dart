import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../navigation/zuno_links.dart';
import '../ui/zuno_colors.dart';
import 'mention_fragments.dart';
import 'urls.dart';

typedef _Hit = ({int start, int end, String shown, Uri? link});

class LinkifiedText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextAlign? textAlign;
  final Set<String> mentionable;
  final InlineSpan? trailing;

  const LinkifiedText(
    this.text, {
    this.style,
    this.maxLines,
    this.textAlign,
    this.mentionable = const {},
    this.trailing,
    super.key,
  });

  @override
  State<LinkifiedText> createState() => _LinkifiedTextState();
}

class _LinkifiedTextState extends State<LinkifiedText> {
  List<_Hit>? _hits;
  final _recognizers = <Uri, TapGestureRecognizer>{};

  TextOverflow get _overflow =>
      widget.maxLines == null ? TextOverflow.clip : TextOverflow.ellipsis;

  @override
  void didUpdateWidget(LinkifiedText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        !setEquals(oldWidget.mentionable, widget.mentionable)) {
      _hits = null;
      _disposeRecognizers();
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers.values) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  List<_Hit> _findHits() {
    final text = widget.text;
    final mentionable = widget.mentionable;
    return <_Hit>[
      for (final link in linksIn(text))
        (
          start: link.start,
          end: link.end,
          shown: text.substring(link.start, link.end),
          link: link.uri,
        ),
      for (final m in roomMentionPattern.allMatches(text))
        (start: m.start, end: m.end, shown: m.group(0)!, link: null),
      if (mentionable.isNotEmpty)
        for (final m in userMentionPattern.allMatches(text))
          if (mentionable.contains(m.group(1)!.toLowerCase()))
            (start: m.start, end: m.end, shown: m.group(1)!, link: null),
    ]..sort((a, b) => a.start.compareTo(b.start));
  }

  TapGestureRecognizer _recognizerFor(Uri link) =>
      _recognizers[link] ??= TapGestureRecognizer()
        ..onTap = () {
          if (mounted) openLink(context, link, openUrl: openExternally);
        };

  @override
  Widget build(BuildContext context) {
    final text = widget.text;
    final style = widget.style;
    final hits = _hits ??= _findHits();
    final trailing = widget.trailing;
    if (hits.isEmpty && trailing == null) {
      return Text(
        text,
        style: style,
        maxLines: widget.maxLines,
        overflow: _overflow,
        textAlign: widget.textAlign,
      );
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
      final link = hit.link;
      if (link == null) {
        spans.add(TextSpan(text: hit.shown, style: mentionStyle));
      } else {
        spans.add(
          TextSpan(
            text: hit.shown,
            style: linkStyle,
            recognizer: _recognizerFor(link),
          ),
        );
      }
      last = hit.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    if (trailing != null) spans.add(trailing);

    return Text.rich(
      TextSpan(style: baseStyle, children: spans),
      maxLines: widget.maxLines,
      overflow: _overflow,
      textAlign: widget.textAlign,
    );
  }
}

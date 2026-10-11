import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:matrix/matrix.dart' hide CallSession;

import '../../../../core/matrix/linkified_text.dart';
import '../../../../core/matrix/mention_fragments.dart';
import '../../../../core/matrix/mention_only_html.dart';
import '../../../../core/matrix/sanitize_message_html.dart';
import '../../../../core/matrix/urls.dart';
import '../../../../core/navigation/zuno_links.dart';
import '../../../../core/ui/row_memo.dart';
import '../../../../core/ui/zuno_colors.dart';
import '../expandable_message.dart';
import '../message_html_style.dart';
import '../message_meta.dart';
import '../text_width_estimate.dart';

final _htmlMessages = RowMemo<String>(capacity: 200);

class _HtmlMessage extends StatelessWidget {
  final String html;

  final bool collapsed;

  const _HtmlMessage({required this.html, this.collapsed = false});

  @override
  Widget build(BuildContext context) {
    final bodyStyle = DefaultTextStyle.of(context).style;
    final html = _buildHtml(context, bodyStyle);
    if (!collapsed) return html;
    return ClipRect(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: collapsedMessageMaxHeight),
        child: Align(
          alignment: Alignment.topLeft,
          heightFactor: 1,
          child: html,
        ),
      ),
    );
  }

  Widget _buildHtml(BuildContext context, TextStyle bodyStyle) {
    final colors = Theme.of(context).colorScheme;
    return Html(
      data: sanitizeMessageHtml(html, mentionColor: colors.primary),
      doNotRenderTheseTags: const {'img'},
      shrinkWrap: true,
      style: messageHtmlStyle(
        bodyStyle: bodyStyle,
        colors: colors,
        link: ZunoColors.of(context).link,
      ),
      onLinkTap: (url, attributes, element) {
        final uri = url == null ? null : Uri.tryParse(url);
        if (uri == null || !isSafeExternalUri(uri)) return;
        openLink(context, uri, openUrl: openExternally);
      },
    );
  }
}

class TextMessage extends StatelessWidget {
  final Event displayEvent;
  final String body;
  final Widget? meta;

  const TextMessage({
    super.key,
    required this.displayEvent,
    required this.body,
    required this.meta,
  });

  @override
  Widget build(BuildContext context) {
    final meta = this.meta;
    final html = displayEvent.formattedText;
    final asHtml =
        displayEvent.isRichMessage &&
        !isMentionOnlyHtml(html: html, body: body);
    if (asHtml) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: math.max(
              estimateTextWidth(context, body, padding: 0),
              MediaQuery.sizeOf(context).width / 3 - 24,
            ),
            child: ExpandableMessage(
              text: body,
              builder: (context, maxLines) => _htmlMessages.obtain(
                '${displayEvent.eventId}|${maxLines != null}',
                html,
                () => _HtmlMessage(html: html, collapsed: maxLines != null),
              ),
            ),
          ),
          if (meta != null)
            Padding(padding: const EdgeInsets.only(top: 3), child: meta),
        ],
      );
    }

    final mentionable = mentionFragmentsOf(displayEvent);
    return ExpandableMessage(
      text: body,
      collapsedTrailing: meta,
      builder: (context, maxLines) {
        if (maxLines != null || meta == null) {
          return LinkifiedText(
            body,
            maxLines: maxLines,
            mentionable: mentionable,
          );
        }
        return TuckedMeta(
          meta: meta,
          textBuilder: (spacer) =>
              LinkifiedText(body, mentionable: mentionable, trailing: spacer),
        );
      },
    );
  }
}

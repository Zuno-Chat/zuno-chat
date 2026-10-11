import 'package:html/dom.dart';
import 'package:html/parser.dart' show parseFragment;

import 'sanitize_message_html.dart';

bool isMentionOnlyHtml({required String html, required String body}) {
  final nodes = [
    for (final node in parseFragment(html).nodes)
      if (!(node is Element && node.localName == 'mx-reply')) node,
  ];
  final content = [
    for (final node in nodes)
      if (node is! Text || node.data.trim().isNotEmpty) node,
  ];
  final inline = switch (content) {
    [Element(localName: 'p') && final paragraph] => paragraph.nodes,
    _ => nodes,
  };
  final text = StringBuffer();
  for (final node in inline) {
    switch (node) {
      case Text():
        text.write(node.data);
      case Element(localName: 'br'):
        text.write('\n');
      case Element(localName: 'a')
          when isUserPillHref(node.attributes['href']) &&
              node.nodes.every((child) => child is Text):
        text.write(node.text);
      default:
        return false;
    }
  }
  return text.toString().trim() == body.trim();
}

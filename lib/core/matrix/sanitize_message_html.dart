import 'dart:ui' show Color;

import 'package:html/dom.dart';
import 'package:html/parser.dart' show parse;

import 'matrix_ids.dart';
import 'mention_fragments.dart';
import 'urls.dart';

const _allowedTags = {
  'a',
  'b',
  'blockquote',
  'br',
  'caption',
  'code',
  'del',
  'div',
  'em',
  'font',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'hr',
  'i',
  'li',
  'ol',
  'p',
  'pre',
  's',
  'span',
  'strike',
  'strong',
  'sub',
  'sup',
  'table',
  'tbody',
  'td',
  'tfoot',
  'th',
  'thead',
  'tr',
  'u',
  'ul',
};

const _droppedSubtrees = {
  'audio',
  'button',
  'canvas',
  'embed',
  'form',
  'frame',
  'frameset',
  'iframe',
  'img',
  'input',
  'link',
  'math',
  'meta',
  'mx-reply',
  'noscript',
  'object',
  'script',
  'select',
  'style',
  'svg',
  'template',
  'textarea',
  'title',
  'video',
};

const _allowedAttributes = <String, Set<String>>{
  'a': {'href', 'title'},
  'code': {'class'},
  'font': {'color', 'data-mx-color', 'data-mx-bg-color'},
  'ol': {'start'},
  'span': {'data-mx-color', 'data-mx-bg-color', 'data-mx-spoiler'},
};

final _languageClass = RegExp(r'^language-[A-Za-z0-9_+-]{1,32}$');

final _colorValue = RegExp(r'^(#[0-9A-Fa-f]{3,8}|[A-Za-z]{1,20})$');

Element sanitizedMessageDocument(
  DocumentFragment html, {
  required Color mentionColor,
}) {
  final hex = mentionColor.toARGB32().toRadixString(16).padLeft(8, '0');
  final mentionStyle = 'color: #${hex.substring(2)}; font-weight: bold;';
  final document = parse('');
  final body = document.body!;
  for (final node in html.nodes) {
    body.nodes.addAll(_sanitizeNode(node, mentionStyle));
  }
  return document.documentElement!;
}

List<Node> _sanitizeNode(Node node, String mentionStyle) {
  if (node is Text) return _markRoomMentions(node.data, mentionStyle);

  if (node is! Element) return const [];

  final tag = node.localName?.toLowerCase();
  if (tag == null) return const [];
  if (_droppedSubtrees.contains(tag)) return const [];
  if (tag == 'a' && isUserPillHref(node.attributes['href'])) {
    return [_mention(withoutServer(node.text.trim()), mentionStyle)];
  }

  final children = <Node>[];
  for (final child in List<Node>.from(node.nodes)) {
    children.addAll(_sanitizeNode(child, mentionStyle));
  }
  if (!_allowedTags.contains(tag)) return children;

  final element = Element.tag(tag);
  final allowed = _allowedAttributes[tag] ?? const <String>{};
  node.attributes.forEach((key, value) {
    final name = key.toString().toLowerCase();
    if (!allowed.contains(name)) return;
    if (_isAcceptableValue(tag: tag, attribute: name, value: value)) {
      element.attributes[name] = value;
    }
  });
  element.nodes.addAll(children);
  return [element];
}

bool isUserPillHref(String? href) {
  final uri = href == null ? null : Uri.tryParse(href.trim());
  if (uri == null || uri.host != 'matrix.to') return false;
  final target = uri.fragment.toLowerCase();
  return target.startsWith('/@') || target.startsWith('/%40');
}

List<Node> _markRoomMentions(String text, String mentionStyle) {
  final nodes = <Node>[];
  var last = 0;
  for (final match in roomMentionPattern.allMatches(text)) {
    if (match.start > last) nodes.add(Text(text.substring(last, match.start)));
    nodes.add(_mention(match.group(0)!, mentionStyle));
    last = match.end;
  }
  if (last < text.length || nodes.isEmpty) {
    nodes.add(Text(text.substring(last)));
  }
  return nodes;
}

Element _mention(String name, String mentionStyle) => Element.tag('span')
  ..attributes['style'] = mentionStyle
  ..nodes.add(Text(name));

bool _isAcceptableValue({
  required String tag,
  required String attribute,
  required String value,
}) {
  switch (attribute) {
    case 'href':
      final uri = Uri.tryParse(value.trim());
      return uri != null && isSafeExternalUri(uri);
    case 'class':
      return tag == 'code' && _languageClass.hasMatch(value);
    case 'color':
    case 'data-mx-color':
    case 'data-mx-bg-color':
      return _colorValue.hasMatch(value.trim());
    case 'start':
      return int.tryParse(value) != null;
    default:
      return true;
  }
}

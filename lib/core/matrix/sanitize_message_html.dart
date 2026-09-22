import 'package:html/dom.dart';
import 'package:html/parser.dart' show parseFragment;

import 'urls.dart';

const _allowedTags = {
  'a', 'b', 'blockquote', 'br', 'caption', 'code', 'del', 'div', 'em',
  'font', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'hr', 'i', 'li', 'ol', 'p',
  'pre', 's', 'span', 'strike', 'strong', 'sub', 'sup', 'table', 'tbody',
  'td', 'tfoot', 'th', 'thead', 'tr', 'u', 'ul',
};

const _droppedSubtrees = {
  'audio', 'button', 'canvas', 'embed', 'form', 'frame', 'frameset',
  'iframe', 'img', 'input', 'link', 'math', 'meta', 'noscript', 'object',
  'script', 'select', 'style', 'svg', 'template', 'textarea', 'title',
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

String sanitizeMessageHtml(String html) {
  final source = parseFragment(html);
  final out = DocumentFragment();
  for (final node in List<Node>.from(source.nodes)) {
    out.nodes.addAll(_sanitizeNode(node));
  }
  return out.outerHtml;
}

List<Node> _sanitizeNode(Node node) {
  if (node is Text) return [Text(node.data)];

  if (node is! Element) return const [];

  final tag = node.localName?.toLowerCase();
  if (tag == null) return const [];
  if (_droppedSubtrees.contains(tag)) return const [];

  final children = <Node>[];
  for (final child in List<Node>.from(node.nodes)) {
    children.addAll(_sanitizeNode(child));
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

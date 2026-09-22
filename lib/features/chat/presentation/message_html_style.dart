import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';

Map<String, Style> messageHtmlStyle({
  required TextStyle bodyStyle,
  required ColorScheme colors,
  required Color link,
}) => {
  'body': Style(
    margin: Margins.zero,
    padding: HtmlPaddings.zero,
    fontSize: FontSize(bodyStyle.fontSize ?? 14),
    color: bodyStyle.color,
  ),
  'p': Style(margin: Margins.zero),
  'a': Style(color: link, textDecoration: TextDecoration.none),
  'blockquote': Style(
    margin: Margins.only(left: 8),
    padding: HtmlPaddings.only(left: 8),
    border: Border(left: BorderSide(color: colors.outline, width: 2)),
  ),
};

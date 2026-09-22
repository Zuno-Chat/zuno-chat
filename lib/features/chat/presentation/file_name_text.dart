import 'package:flutter/material.dart';

const _maxExtensionLength = 10;

({String base, String extension}) splitFileExtension(String name) {
  final dot = name.lastIndexOf('.');
  final extensionLength = name.length - dot - 1;
  if (dot <= 0 ||
      extensionLength < 1 ||
      extensionLength > _maxExtensionLength) {
    return (base: name, extension: '');
  }
  return (base: name.substring(0, dot), extension: name.substring(dot));
}

class FileNameText extends StatelessWidget {
  final String name;
  final TextStyle? style;

  const FileNameText(this.name, {this.style, super.key});

  @override
  Widget build(BuildContext context) {
    final parts = splitFileExtension(name);
    final base = Text(
      parts.base,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
    if (parts.extension.isEmpty) return base;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: base),
        Text(parts.extension, maxLines: 1, style: style),
      ],
    );
  }
}

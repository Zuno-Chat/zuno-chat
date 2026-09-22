import 'package:flutter/material.dart';

const zunoAmber = Color(0xFFE8A33D);
const zunoInk = Color(0xFF2A1E05);

const callEndColor = Color(0xFFD32F2F);
const callAcceptColor = Color(0xFF188038);
const onCallActionColor = Color(0xFFFFFFFF);

const avatarTones = <Color>[
  Color(0xFFC98F8F),
  Color(0xFF93AD8C),
  Color(0xFF86A0C4),
  Color(0xFFCFA950),
  Color(0xFFA897C8),
  Color(0xFFD39B73),
  Color(0xFF7DB0A6),
  Color(0xFFB3A894),
];

Color avatarToneFor(String seed) {
  var hash = 0x811C9DC5;
  for (final unit in seed.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xFFFFFFFF;
  }
  hash ^= hash >> 16;
  return avatarTones[hash % avatarTones.length];
}

@immutable
class ZunoColors extends ThemeExtension<ZunoColors> {
  final Color bubbleOutgoing;
  final Color onBubbleOutgoing;
  final Color onBubbleOutgoingVariant;
  final Color success;
  final Color link;

  const ZunoColors({
    required this.bubbleOutgoing,
    required this.onBubbleOutgoing,
    required this.onBubbleOutgoingVariant,
    required this.success,
    required this.link,
  });

  static const light = ZunoColors(
    bubbleOutgoing: Color(0xFFF8E3BB),
    onBubbleOutgoing: Color(0xFF1F1A12),
    onBubbleOutgoingVariant: Color(0xFF696151),
    success: Color(0xFF2F6B3C),
    link: Color(0xFF1D5C9E),
  );

  static const dark = ZunoColors(
    bubbleOutgoing: Color(0xFF65491C),
    onBubbleOutgoing: Color(0xFFF5EFE6),
    onBubbleOutgoingVariant: Color(0xFFD2C8B5),
    success: Color(0xFF8FCB9A),
    link: Color(0xFF81D4FA),
  );

  static ZunoColors of(BuildContext context) => ofTheme(Theme.of(context));

  static ZunoColors ofTheme(ThemeData theme) =>
      theme.extension<ZunoColors>() ??
      (theme.brightness == Brightness.dark ? dark : light);

  @override
  ZunoColors copyWith({
    Color? bubbleOutgoing,
    Color? onBubbleOutgoing,
    Color? onBubbleOutgoingVariant,
    Color? success,
    Color? link,
  }) => ZunoColors(
    bubbleOutgoing: bubbleOutgoing ?? this.bubbleOutgoing,
    onBubbleOutgoing: onBubbleOutgoing ?? this.onBubbleOutgoing,
    onBubbleOutgoingVariant:
        onBubbleOutgoingVariant ?? this.onBubbleOutgoingVariant,
    success: success ?? this.success,
    link: link ?? this.link,
  );

  @override
  ZunoColors lerp(ZunoColors? other, double t) {
    if (other == null) return this;
    return ZunoColors(
      bubbleOutgoing: Color.lerp(bubbleOutgoing, other.bubbleOutgoing, t)!,
      onBubbleOutgoing: Color.lerp(
        onBubbleOutgoing,
        other.onBubbleOutgoing,
        t,
      )!,
      onBubbleOutgoingVariant: Color.lerp(
        onBubbleOutgoingVariant,
        other.onBubbleOutgoingVariant,
        t,
      )!,
      success: Color.lerp(success, other.success, t)!,
      link: Color.lerp(link, other.link, t)!,
    );
  }
}

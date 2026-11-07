import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

class MatrixLogoIcon extends StatelessWidget {
  const MatrixLogoIcon({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    return SvgPicture.asset(
      'assets/icons/matrix.svg',
      width: theme.size,
      height: theme.size,
      colorFilter: ColorFilter.mode(theme.color!, BlendMode.srcIn),
    );
  }
}

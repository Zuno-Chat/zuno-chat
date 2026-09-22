import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'zuno_colors.dart';

class ZunoSplash extends StatelessWidget {
  const ZunoSplash({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: zunoAmber,
      body: Center(
        child: SvgPicture.asset(
          'assets/logo/zuno-mark-ink.svg',
          width: 96,
          height: 96,
        ),
      ),
    );
  }
}

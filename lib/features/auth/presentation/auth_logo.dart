import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class AuthLogo extends StatelessWidget {
  const AuthLogo({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset(
            'assets/logo/zuno-mark-amber.svg',
            width: 60,
            height: 60,
          ),
          const SizedBox(height: 10),
          Text(
            'Zuno',
            style: Theme.of(context).textTheme.titleLarge!
                .copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

class WhySecurityPage extends StatelessWidget {
  const WhySecurityPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Text(text, style: theme.textTheme.titleMedium),
    );
    Widget para(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: theme.textTheme.bodyMedium),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('How this works')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          24,
          8,
          24,
          32 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          para(
            'Your messages are encrypted on your device before they are sent, '
            'and only the devices in the chat can decrypt them. Not Zuno, and '
            'not the server they pass through.',
          ),
          para(
            'Encryption protects what you say. It does not hide who you talk '
            'to, and it cannot stop a screenshot or a compromised device.',
          ),
          heading('Why a recovery code'),
          para(
            'The ability to decrypt your messages lives on your devices, not '
            'on the server. That is what keeps them private. It also means '
            'that if you lose every device you own, your old messages stay '
            'locked forever.',
          ),
          para(
            'A recovery code is the way back. Twelve words, saved somewhere '
            'safe. Enter them on a new device and your messages come back.',
          ),
          heading('Why new devices ask for approval'),
          para(
            'When you sign in somewhere new, your other devices have no way to '
            'tell it apart from a stranger signing in as you. Approving it, by '
            'scanning a code between the two, is how they find out.',
          ),
          para(
            'Until then, the new device cannot read anything older than '
            'itself. That is deliberate: if it were not really you, it would '
            'get nothing.',
          ),
          heading('Why confirming people matters'),
          para(
            'Zuno asks the server which devices belong to your friend. A '
            'dishonest server could answer with one of its own and read along. '
            'Encryption alone does not stop that, because the wrong source was '
            'asked.',
          ),
          para(
            'Confirming someone, in person by scanning or on a call by '
            'comparing pictures, checks their details through a channel the '
            'server does not control. It only needs doing once per person, '
            'even if they change devices later.',
          ),
          heading('When Zuno interrupts you'),
          para(
            'Almost never. A new sign-in on your own account, and a person '
            'whose security details changed after you confirmed them. Both '
            'mean something you can act on. Everything else stays out of your '
            'way.',
          ),
        ],
      ),
    );
  }
}

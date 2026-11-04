import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../../core/l10n/display_text.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/account/account_page_browser.dart';
import '../../../core/matrix/auth/uia_cancel.dart';
import '../../../core/security/zuno_text_field.dart';
import '../../../core/ui/confirm_dialog.dart';
import '../../../core/ui/inline_feedback.dart';

const _approvalStages = ['m.oauth', 'org.matrix.cross_signing_reset'];

final _passwordSent = Expando<bool>('uia password sent');
final _approvalAsked = Expando<bool>('uia approval asked');
final _asking = Expando<bool>('uia asked');

Future<String?> askPasswordForUia(
  BuildContext context, {
  @displayText String? title,
  @displayText String? message,
  @displayText String? error,
}) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      final l10n = context.l10n;
      final field = AutofillGroup(
        onDisposeAction: AutofillContextAction.cancel,
        child: ZunoTextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          autofillHints: const [AutofillHints.password],
          decoration: InputDecoration(
            labelText: l10n.commonPassword,
            errorText: error,
          ),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
      );
      return AlertDialog(
        title: Text(title ?? l10n.settingsUiaDefaultTitle),
        content: message == null
            ? field
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [Text(message), const SizedBox(height: 16), field],
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(l10n.settingsUiaConfirm),
          ),
        ],
      );
    },
  );
}

Future<bool> _askApproval(
  BuildContext context, {
  required String server,
  required bool notYet,
}) {
  final l10n = context.l10n;
  final body = l10n.settingsUiaApproveBody(server);
  return confirm(
    context,
    title: l10n.settingsUiaApproveTitle,
    body: body,
    content: notYet
        ? Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InlineError(l10n.settingsUiaApproveNotYet),
              const SizedBox(height: 8),
              Text(body),
            ],
          )
        : null,
    confirmLabel: l10n.commonContinue,
    tone: ConfirmTone.primary,
    barrierDismissible: false,
  );
}

Uri? _approvalLink(UiaRequest uia) {
  for (final stage in _approvalStages) {
    if (!uia.nextStages.contains(stage)) continue;
    final link = switch (uia.params[stage]) {
      {'url': final String url} => Uri.tryParse(url),
      _ => null,
    };
    if (link != null && link.isScheme('https')) return link;
  }
  return null;
}

Future<void> answerUia(
  BuildContext context,
  UiaRequest uia, {
  required String userId,
  @displayText String? title,
  @displayText String? message,
  String? Function()? preparedPassword,
}) async {
  if (uia.state != UiaRequestState.waitForUser || _asking[uia] == true) return;
  if (uia.nextStages.contains(AuthenticationTypes.password)) {
    await _answerWithPassword(
      context,
      uia,
      userId: userId,
      title: title,
      message: message,
      preparedPassword: preparedPassword,
    );
    return;
  }
  final link = _approvalLink(uia);
  if (link == null) {
    uia.cancel(UnanswerableUiaStages({...uia.nextStages}));
    return;
  }
  await _answerWithApproval(
    context,
    uia,
    link,
    server: userId.domain ?? userId,
  );
}

Future<void> _answerWithPassword(
  BuildContext context,
  UiaRequest uia, {
  required String userId,
  required String? title,
  required String? message,
  required String? Function()? preparedPassword,
}) async {
  _asking[uia] = true;
  final String? password;
  try {
    password =
        preparedPassword?.call() ??
        await askPasswordForUia(
          context,
          title: title,
          message: message,
          error: _passwordSent[uia] == true
              ? context.l10n.commonWrongPassword
              : null,
        );
  } finally {
    _asking[uia] = false;
  }
  if (!context.mounted || password == null || password.isEmpty) {
    uia.cancel();
    return;
  }
  _passwordSent[uia] = true;
  await uia.completeStage(
    AuthenticationPassword(
      session: uia.session,
      password: password,
      identifier: AuthenticationUserIdentifier(user: userId),
    ),
  );
}

Future<void> _answerWithApproval(
  BuildContext context,
  UiaRequest uia,
  Uri link, {
  required String server,
}) async {
  _asking[uia] = true;
  var approved = false;
  try {
    await openAccountPage(context, link);
    if (context.mounted) {
      approved = await _askApproval(
        context,
        server: server,
        notYet: _approvalAsked[uia] == true,
      );
    }
  } finally {
    _asking[uia] = false;
  }
  if (!context.mounted || !approved) {
    uia.cancel();
    return;
  }
  _approvalAsked[uia] = true;
  await uia.completeStage(AuthenticationData(session: uia.session));
}

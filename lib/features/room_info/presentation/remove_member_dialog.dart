import 'package:flutter/material.dart';

Future<bool> confirmRemoveMember(
  BuildContext context, {
  required String name,
  required bool ban,
  required String place,
  String? note,
}) async {
  final consequence = ban
      ? 'They are removed from the $place and cannot rejoin unless unbanned.'
      : 'They are removed from the $place and can rejoin if invited again.';
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(ban ? 'Ban $name?' : 'Remove $name?'),
      content: Text(note == null ? consequence : '$consequence $note'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(ban ? 'Ban' : 'Remove'),
        ),
      ],
    ),
  );
  return confirmed == true;
}

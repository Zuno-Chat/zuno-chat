import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:matrix/matrix.dart';

import '../errors/caught_errors.dart';
import '../l10n/l10n.dart';
import '../ui/notice.dart';
import '../ui/sheet.dart';
import 'media_processing_exception.dart';
import 'photo_location.dart';
import 'picker_access.dart';

const _avatarMaxDimension = 512;

Future<MatrixImageFile> prepareAvatarPhoto(
  Uint8List bytes, {
  required String name,
  required NativeImplementations nativeImplementations,
}) {
  final stripped = withoutLocation(bytes);
  if (stripped == null) {
    throw const MediaProcessingException('Cannot use this photo');
  }
  return MatrixImageFile.shrink(
    bytes: stripped,
    name: name,
    maxDimension: _avatarMaxDimension,
    nativeImplementations: nativeImplementations,
  );
}

Future<MatrixImageFile?> pickAvatarPhoto(
  ImageSource source,
  NativeImplementations nativeImplementations,
) async {
  final picked = await ImagePicker().pickImage(
    source: source,
    imageQuality: 90,
  );
  if (picked == null) return null;
  return prepareAvatarPhoto(
    await picked.readAsBytes(),
    name: picked.name,
    nativeImplementations: nativeImplementations,
  );
}

enum AvatarAction { camera, gallery, remove }

Future<AvatarAction?> chooseAvatarAction(
  BuildContext context, {
  required bool canRemove,
}) {
  final l10n = context.l10n;
  return showActionSheet(
    context,
    actions: [
      SheetAction(
        AvatarAction.camera,
        icon: Icons.photo_camera_outlined,
        label: l10n.commonTakePhoto,
      ),
      SheetAction(
        AvatarAction.gallery,
        icon: Icons.photo_library_outlined,
        label: l10n.commonChooseFromGallery,
      ),
      if (canRemove)
        SheetAction(
          AvatarAction.remove,
          icon: Icons.delete_outline,
          label: l10n.commonRemovePhoto,
        ),
    ],
  );
}

Future<void> applyAvatarAction(
  BuildContext context,
  AvatarAction action, {
  required NativeImplementations nativeImplementations,
  required Future<void> Function(MatrixImageFile? photo) apply,
  required String label,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  try {
    final photo = switch (action) {
      AvatarAction.remove => null,
      AvatarAction.camera => await pickAvatarPhoto(
        ImageSource.camera,
        nativeImplementations,
      ),
      AvatarAction.gallery => await pickAvatarPhoto(
        ImageSource.gallery,
        nativeImplementations,
      ),
    };
    if (photo == null && action != AvatarAction.remove) return;
    await apply(photo);
    messenger.say(l10n.commonPhotoUpdated);
  } catch (e, s) {
    if (isPickerAccessDenied(e)) {
      messenger.say(l10n.commonPhotoNotSaved);
      return;
    }
    reportCaught(label, e, s);
    messenger.sayFailed(l10n, e, failed: l10n.commonPhotoNotSaved);
  }
}

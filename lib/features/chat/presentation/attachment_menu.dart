import 'package:clock/clock.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:matrix/matrix.dart';

import '../../../core/errors/caught_errors.dart';
import '../../../core/files/file_system.dart';
import '../../../core/files/picked_file.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/location/live_location_availability.dart';
import '../../../core/location/live_location_sharing.dart';
import '../../../core/location/location_message.dart';
import '../../../core/matrix/media/media_quality.dart';
import '../../../core/matrix/media/picker_access.dart';
import '../../../core/matrix/media/video/looks_like_video.dart';
import '../../../core/platform/platform_capabilities.dart';
import '../../../core/settings/app_preferences_provider.dart';
import '../../../core/share/inbound_share.dart';
import '../../../core/ui/notice.dart';
import '../../../core/ui/sheet.dart';
import '../../location/presentation/live_location_text.dart';
import '../../location/presentation/location_share_sheet.dart';
import '../data/room_sender.dart';
import 'media_caption_composer_page.dart';

enum _Attachment { camera, gallery, videoCamera, file, location }

SheetAction<_Attachment> _sheetAction(
  AppLocalizations l10n,
  _Attachment choice,
) => switch (choice) {
  _Attachment.camera => SheetAction(
    choice,
    icon: Icons.photo_camera_outlined,
    label: l10n.commonTakePhoto,
  ),
  _Attachment.gallery => SheetAction(
    choice,
    icon: Icons.photo_library_outlined,
    label: l10n.commonChooseFromGallery,
  ),
  _Attachment.videoCamera => SheetAction(
    choice,
    icon: Icons.videocam_outlined,
    label: l10n.chatRecordVideo,
  ),
  _Attachment.file => SheetAction(
    choice,
    icon: Icons.attach_file_outlined,
    label: l10n.chatChooseFile,
  ),
  _Attachment.location => SheetAction(
    choice,
    icon: Icons.location_on_outlined,
    label: l10n.chatLocation,
  ),
};

Future<void> showAttachmentMenu(
  BuildContext context,
  WidgetRef ref,
  Room room, {
  required void Function(bool fetching) onFetchingFile,
}) async {
  final l10n = context.l10n;
  final choice = await showActionSheet<_Attachment>(
    context,
    actions: [
      for (final option in _Attachment.values) _sheetAction(l10n, option),
    ],
  );
  if (choice == null || !context.mounted) return;
  final flow = _AttachmentFlow(context, ref, room);
  await flow.guarded(
    choice,
    () => switch (choice) {
      _Attachment.camera ||
      _Attachment.videoCamera => flow.sendCaptured(choice),
      _Attachment.gallery => flow.pickGalleryMedia(),
      _Attachment.file => flow.pickFiles(onFetchingFile),
      _Attachment.location => _sendLocation(context, ref, room),
    },
  );
}

Future<void> sendSharedFiles(
  BuildContext context,
  WidgetRef ref,
  Room room,
  List<SharedFile> files,
) => _AttachmentFlow(context, ref, room).sendShared(files);

String _accessDenied(AppLocalizations l10n, Object error) =>
    error is PlatformException && error.code == 'camera_access_denied'
    ? l10n.chatCameraAccessDenied
    : l10n.chatPhotoAccessDenied;

String _didNotOpen(AppLocalizations l10n, _Attachment choice) =>
    switch (choice) {
      _Attachment.camera ||
      _Attachment.videoCamera => l10n.chatCameraDidNotOpen,
      _Attachment.gallery => l10n.chatPhotosDidNotOpen,
      _Attachment.file => l10n.chatFilesDidNotOpen,
      _Attachment.location => l10n.chatLocationNotSent,
    };

Future<void> _sendLocation(
  BuildContext context,
  WidgetRef ref,
  Room room,
) async {
  final sharing = ref.read(liveLocationSharingProvider);
  final choice = await showLocationShareSheet(
    context,
    liveLocation: ref.read(platformCapabilitiesProvider).liveLocation
        ? liveLocationAvailability(
            room,
            sharingHere: sharing.isSharingIn(room.id),
          )
        : LiveLocationAvailability.unavailable,
    inChat: room.isDirectChat,
  );
  if (choice == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  switch (choice) {
    case SendPin(:final geo):
      try {
        await sendLocationPin(room, geo, at: clock.now());
      } catch (e, s) {
        reportCaughtType('send location pin', e, s);
        messenger.sayFailed(l10n, e, failed: l10n.chatLocationNotSent);
      }
    case ShareLive(:final first, :final duration):
      try {
        await sharing.start(room, duration, first);
      } on LiveShareStartException catch (error) {
        final text = liveShareStartFailureText(l10n, error.reason);
        if (error.reason == LiveShareStartFailure.failed) {
          messenger.sayFailed(l10n, error.cause, failed: text);
        } else {
          messenger.say(text);
        }
      }
  }
}

class _AttachmentFlow {
  _AttachmentFlow(BuildContext context, WidgetRef ref, Room room)
    : _chat = context,
      _navigator = Navigator.of(context),
      _messenger = ScaffoldMessenger.of(context),
      _l10n = context.l10n,
      _sender = ref.read(roomSenderProvider(room)),
      _limits = pickerImageLimits(
        nativeImageResize: ref
            .read(platformCapabilitiesProvider)
            .nativeImageResize,
        reduceMediaSize: ref.read(reduceMediaSizeProvider),
      );

  final BuildContext _chat;
  final NavigatorState _navigator;
  final ScaffoldMessengerState _messenger;
  final AppLocalizations _l10n;
  final RoomSender _sender;
  final ({double? maxDimension, int? quality}) _limits;

  Future<T?> guarded<T>(_Attachment choice, Future<T> Function() action) async {
    try {
      return await action();
    } catch (e, s) {
      if (!_chat.mounted) return null;
      if (isPickerAccessDenied(e)) {
        _messenger.say(_accessDenied(_l10n, e));
      } else {
        reportCaught('attach ${choice.name}', e, s);
        _messenger.sayFailed(_l10n, e, failed: _didNotOpen(_l10n, choice));
      }
      return null;
    }
  }

  Future<PickedMedia?> capture(_Attachment camera) async {
    if (camera == _Attachment.videoCamera) {
      final file = await ImagePicker().pickVideo(source: ImageSource.camera);
      return file == null
          ? null
          : PickedVideo(path: file.path, name: file.name);
    }
    final file = await ImagePicker().pickImage(
      source: ImageSource.camera,
      maxWidth: _limits.maxDimension,
      maxHeight: _limits.maxDimension,
      imageQuality: _limits.quality,
    );
    return file == null ? null : PickedImage(path: file.path, name: file.name);
  }

  Future<void> sendCaptured(_Attachment camera) async =>
      _composeAndSend([?await capture(camera)]);

  Future<void> pickGalleryMedia() async {
    final picked = await ImagePicker().pickMultipleMedia(
      maxWidth: _limits.maxDimension,
      maxHeight: _limits.maxDimension,
      imageQuality: _limits.quality,
    );
    await _composeAndSend([for (final file in picked) _pickedMedia(file)]);
  }

  Future<void> pickFiles(void Function(bool fetching) onFetching) async {
    final files = await trackPickerCopy(
      (onFileLoading) => FilePicker.pickFiles(onFileLoading: onFileLoading),
      onCopying: onFetching,
    );
    await _sender.holdCopies([for (final file in files) ?file.path], (_) async {
      for (final file in files) {
        await _sender.sendFile(await file.readAsBytes(), name: file.name);
      }
    });
  }

  Future<void> sendShared(List<SharedFile> files) async {
    if (files.isEmpty) return;
    final copies = await copySharedFilesToCache(files);
    await _sender.holdCopies([for (final copy in copies) copy.path], (_) async {
      if (!_chat.mounted) return;
      final unopened = files.length - copies.length;
      if (unopened > 0) _messenger.say(_l10n.chatUnopenedShares(unopened));
      final (:media, :others) = await partitionSharedFiles(copies);
      await _composeAndSend([for (final file in media) _pickedMedia(file)]);
      for (final file in others) {
        await _sender.sendFile(
          await fileSystem.file(file.path).readAsBytes(),
          name: file.name,
          mimeType: file.mimeType,
        );
      }
    });
  }

  Future<PickedMedia?> _addCaptured() async {
    final choice = await showActionSheet<_Attachment>(
      _chat,
      actions: [
        for (final option in [_Attachment.camera, _Attachment.videoCamera])
          _sheetAction(_l10n, option),
      ],
    );
    if (choice == null) return null;
    return guarded<PickedMedia?>(choice, () => capture(choice));
  }

  Future<void> _composeAndSend(List<PickedMedia> picked) =>
      _sender.holdCopies([for (final item in picked) item.path], (hold) async {
        if (picked.isEmpty || !_chat.mounted) return;
        final composed = await _navigator.push<List<ComposedMedia>>(
          MaterialPageRoute(
            builder: (_) => MediaCaptionComposerPage(
              items: picked,
              onAdd: () async {
                final item = await _addCaptured();
                if (item != null) hold(item.path);
                return item;
              },
            ),
          ),
        );
        if (composed != null) await _sender.sendComposed(composed);
      });
}

PickedMedia _pickedMedia(XFile file) => looksLikeVideo(file)
    ? PickedVideo(path: file.path, name: file.name)
    : PickedImage(path: file.path, name: file.name);

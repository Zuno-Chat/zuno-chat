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
import '../../../core/l10n/display_text.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/location/live_location_availability.dart';
import '../../../core/location/live_location_sharing.dart';
import '../../../core/location/location_message.dart';
import '../../../core/matrix/looks_like_video.dart';
import '../../../core/matrix/media_quality.dart';
import '../../../core/matrix/picker_access.dart';
import '../../../core/platform/platform_capabilities.dart';
import '../../../core/settings/app_preferences_provider.dart';
import '../../../core/share/inbound_share.dart';
import '../../../core/ui/sheet.dart';
import '../../location/presentation/live_location_text.dart';
import '../../location/presentation/location_share_sheet.dart';
import '../data/room_sender.dart';
import 'image_caption_composer_page.dart';
import 'media_caption_composer_page.dart';
import 'video_caption_composer_page.dart';

enum _Attachment { camera, gallery, videoCamera, file, location }

Future<void> showAttachmentMenu(
  BuildContext context,
  WidgetRef ref,
  Room room, {
  required void Function(bool fetching) onFetchingFile,
}) async {
  final choice = await showSheet<_Attachment>(
    context: context,
    builder: (context) => SafeArea(
      child: Wrap(
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: Text(context.l10n.commonTakePhoto),
            onTap: () => Navigator.of(context).pop(_Attachment.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(context.l10n.commonChooseFromGallery),
            onTap: () => Navigator.of(context).pop(_Attachment.gallery),
          ),
          ListTile(
            leading: const Icon(Icons.videocam_outlined),
            title: Text(context.l10n.chatRecordVideo),
            onTap: () => Navigator.of(context).pop(_Attachment.videoCamera),
          ),
          ListTile(
            leading: const Icon(Icons.attach_file_outlined),
            title: Text(context.l10n.chatChooseFile),
            onTap: () => Navigator.of(context).pop(_Attachment.file),
          ),
          ListTile(
            leading: const Icon(Icons.location_on_outlined),
            title: Text(context.l10n.chatLocation),
            onTap: () => Navigator.of(context).pop(_Attachment.location),
          ),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  final flow = _AttachmentFlow(context, ref, room);
  try {
    switch (choice) {
      case _Attachment.camera:
        await flow.pickPhoto(ImageSource.camera);
      case _Attachment.gallery:
        await flow.pickGalleryMedia();
      case _Attachment.videoCamera:
        await flow.pickVideo(ImageSource.camera);
      case _Attachment.file:
        await flow.pickFiles(onFetchingFile);
      case _Attachment.location:
        await _sendLocation(context, ref, room);
    }
  } catch (e, s) {
    if (!isPickerAccessDenied(e)) reportCaught('attach ${choice.name}', e, s);
    if (context.mounted) {
      _say(
        ScaffoldMessenger.of(context),
        _attachmentFailure(context.l10n, choice, e),
      );
    }
  }
}

Future<void> sendSharedFiles(
  BuildContext context,
  WidgetRef ref,
  Room room,
  List<SharedFile> files,
) => _AttachmentFlow(context, ref, room).sendShared(files);

String _attachmentFailure(
  AppLocalizations l10n,
  _Attachment choice,
  Object error,
) {
  final code = error is PlatformException ? error.code : null;
  return switch (choice) {
    _Attachment.camera || _Attachment.videoCamera =>
      code == 'camera_access_denied'
          ? l10n.chatCameraAccessDenied
          : l10n.chatCameraDidNotOpen,
    _Attachment.gallery =>
      code == 'photo_access_denied'
          ? l10n.chatPhotoAccessDenied
          : l10n.chatPhotosDidNotOpen,
    _Attachment.file => l10n.chatFilesDidNotOpen,
    _Attachment.location => l10n.chatLocationNotSent,
  };
}

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
        _say(messenger, l10n.chatLocationNotSent);
      }
    case ShareLive(:final first, :final duration):
      try {
        await sharing.start(room, duration, first);
      } on LiveShareStartException catch (error) {
        _say(messenger, liveShareStartFailureText(l10n, error.reason));
      }
  }
}

void _say(ScaffoldMessengerState messenger, @displayText String message) =>
    messenger.showSnackBar(SnackBar(content: Text(message)));

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

  Future<void> pickPhoto(ImageSource source) async {
    final file = await ImagePicker().pickImage(
      source: source,
      maxWidth: _limits.maxDimension,
      maxHeight: _limits.maxDimension,
      imageQuality: _limits.quality,
    );
    if (file == null) return;
    await _composeAndSend([file], isVideo: (_) => false);
  }

  Future<void> pickGalleryMedia() async {
    final picked = await ImagePicker().pickMultipleMedia(
      maxWidth: _limits.maxDimension,
      maxHeight: _limits.maxDimension,
      imageQuality: _limits.quality,
    );
    await _composeAndSend(picked);
  }

  Future<void> pickVideo(ImageSource source) async {
    final picked = await ImagePicker().pickVideo(source: source);
    if (picked == null) return;
    await _composeAndSend([picked], isVideo: (_) => true);
  }

  Future<void> pickFiles(void Function(bool fetching) onFetching) async {
    final files = await trackPickerCopy(
      (onFileLoading) => FilePicker.pickFiles(onFileLoading: onFileLoading),
      onCopying: onFetching,
    );
    await _sender.holdCopies([for (final file in files) ?file.path], () async {
      for (final file in files) {
        await _sender.sendFile(await file.readAsBytes(), name: file.name);
      }
    });
  }

  Future<void> sendShared(List<SharedFile> files) async {
    if (files.isEmpty) return;
    final copies = await copySharedFilesToCache(files);
    await _sender.holdCopies([for (final copy in copies) copy.path], () async {
      if (!_chat.mounted) return;
      final unopened = files.length - copies.length;
      if (unopened > 0) _say(_messenger, _l10n.chatUnopenedShares(unopened));
      final (:media, :others) = await partitionSharedFiles(copies);
      if (media.isNotEmpty) await _composeAndSend(media);
      for (final file in others) {
        await _sender.sendFile(
          await fileSystem.file(file.path).readAsBytes(),
          name: file.name,
          mimeType: file.mimeType,
        );
      }
    });
  }

  Future<void> _composeAndSend(
    List<XFile> picked, {
    bool Function(XFile file) isVideo = looksLikeVideo,
  }) => _sender.holdCopies([for (final file in picked) file.path], () async {
    if (picked.isEmpty || !_chat.mounted) return;
    final composed = await _compose(picked, isVideo);
    if (composed == null) return;
    await _sender.sendComposed(composed);
  });

  Future<List<ComposedMedia>?> _compose(
    List<XFile> picked,
    bool Function(XFile file) isVideo,
  ) async {
    final videos = picked.where(isVideo).toList();
    if (videos.isEmpty) {
      final images = await _navigator.push<List<ComposedImage>>(
        MaterialPageRoute(
          builder: (_) => ImageCaptionComposerPage(
            images: [
              for (final file in picked) (path: file.path, name: file.name),
            ],
          ),
        ),
      );
      return images?.map(ComposedImageResult.new).toList();
    }
    if (picked.length == 1) {
      final video = await _navigator.push<ComposedVideo>(
        MaterialPageRoute(
          builder: (_) => VideoCaptionComposerPage(
            path: videos.single.path,
            name: videos.single.name,
          ),
        ),
      );
      return video == null ? null : [ComposedVideoResult(video)];
    }
    return _navigator.push<List<ComposedMedia>>(
      MaterialPageRoute(
        builder: (_) => MediaCaptionComposerPage(
          items: [
            for (final file in picked)
              isVideo(file)
                  ? PickedVideo(path: file.path, name: file.name)
                  : PickedImage(path: file.path, name: file.name),
          ],
        ),
      ),
    );
  }
}

import '../media/video_codec.dart';

const _opusParams = {'useinbandfec': '1', 'usedtx': '0'};

String withSendParams(String sdp) => mapSdpSections(
  sdp,
  (section) => withSentVideoSectionParams(
    withFmtpParams(
      section,
      (codec) => codec.toLowerCase() == 'opus' ? _opusParams : null,
    ),
  ),
);

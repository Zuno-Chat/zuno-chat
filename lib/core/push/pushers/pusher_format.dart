import 'pusher_info.dart';

const pusherFormat = 'event_id_only';

typedef PusherFit = ({bool gateway, bool format});

PusherFit pusherFit(PusherInfo pusher, {required Uri? gatewayUrl}) => (
  gateway: gatewayUrl == null || Uri.tryParse(pusher.url ?? '') == gatewayUrl,
  format: pusher.format == pusherFormat,
);

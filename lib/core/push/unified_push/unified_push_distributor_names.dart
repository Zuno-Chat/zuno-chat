const _knownUnifiedPushDistributors = {
  'io.heckel.ntfy': 'ntfy',
  'org.unifiedpush.distributor.nextpush': 'NextPush',
  'org.unifiedpush.distributor.sunup': 'Sunup',
  'org.unifiedpush.distributor.fcm': 'gCompat-UP',
  'eu.siacs.conversations': 'Conversations',
};

String unifiedPushDistributorDisplayName(String distributorId) =>
    _knownUnifiedPushDistributors[distributorId] ?? distributorId;

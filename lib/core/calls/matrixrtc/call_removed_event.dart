const callRemovedEventType = 'im.zuno.call.removed';

String callRemovedStateKey(String userId) => '_$userId';

String? removedUserOf(String stateKey) =>
    stateKey.startsWith('_@') ? stateKey.substring(1) : null;

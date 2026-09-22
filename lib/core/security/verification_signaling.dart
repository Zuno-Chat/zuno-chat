bool isVerificationSignalingMessage(String? msgtype) =>
    msgtype != null && msgtype.startsWith('m.key.verification.');

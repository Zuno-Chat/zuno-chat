package im.zuno.chat

import android.content.pm.ServiceInfo

object CallServiceDecision {
    private const val MICROPHONE = ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE

    fun foregroundServiceType(wantsCamera: Boolean, cameraGranted: Boolean): Int =
        if (wantsCamera && cameraGranted) {
            MICROPHONE or ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA
        } else {
            MICROPHONE
        }

    fun fallbackType(refused: Int): Int? = MICROPHONE.takeIf { refused != MICROPHONE }
}

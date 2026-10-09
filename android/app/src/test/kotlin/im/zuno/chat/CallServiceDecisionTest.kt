package im.zuno.chat

import android.content.pm.ServiceInfo
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class CallServiceDecisionTest {
    private val microphone = ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
    private val camera = ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA

    @Test
    fun `a video call with camera access runs for the microphone and the camera`() {
        assertEquals(
            microphone or camera,
            CallServiceDecision.foregroundServiceType(wantsCamera = true, cameraGranted = true),
        )
    }

    @Test
    fun `a video call without camera access runs for the microphone alone`() {
        assertEquals(
            microphone,
            CallServiceDecision.foregroundServiceType(wantsCamera = true, cameraGranted = false),
        )
    }

    @Test
    fun `a voice call runs for the microphone alone, camera access or not`() {
        assertEquals(
            microphone,
            CallServiceDecision.foregroundServiceType(wantsCamera = false, cameraGranted = true),
        )
        assertEquals(
            microphone,
            CallServiceDecision.foregroundServiceType(wantsCamera = false, cameraGranted = false),
        )
    }

    @Test
    fun `a camera type the system refuses falls back to the microphone alone`() {
        assertEquals(microphone, CallServiceDecision.fallbackType(refused = microphone or camera))
    }

    @Test
    fun `a refused microphone type has nothing narrower to fall back to`() {
        assertNull(CallServiceDecision.fallbackType(refused = microphone))
    }
}

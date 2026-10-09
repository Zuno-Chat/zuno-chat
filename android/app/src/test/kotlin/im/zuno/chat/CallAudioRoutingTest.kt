package im.zuno.chat

import android.media.AudioDeviceInfo
import android.media.AudioManager
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class CallAudioRoutingTest {
    @Test
    fun `each call device maps to its route, and devices that cannot carry a call map to none`() {
        assertEquals(
            CallAudioRoute.Earpiece,
            CallAudioRouting.routeOf(AudioDeviceInfo.TYPE_BUILTIN_EARPIECE),
        )
        assertEquals(
            CallAudioRoute.Speaker,
            CallAudioRouting.routeOf(AudioDeviceInfo.TYPE_BUILTIN_SPEAKER),
        )
        for (type in listOf(
            AudioDeviceInfo.TYPE_WIRED_HEADSET,
            AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
            AudioDeviceInfo.TYPE_USB_HEADSET,
        )) {
            assertEquals(CallAudioRoute.WiredHeadset, CallAudioRouting.routeOf(type))
        }
        for (type in listOf(
            AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
            AudioDeviceInfo.TYPE_BLE_HEADSET,
            AudioDeviceInfo.TYPE_HEARING_AID,
        )) {
            assertEquals(CallAudioRoute.Bluetooth, CallAudioRouting.routeOf(type))
        }
        assertNull(CallAudioRouting.routeOf(AudioDeviceInfo.TYPE_BLUETOOTH_A2DP))
        assertNull(CallAudioRouting.routeOf(AudioDeviceInfo.TYPE_HDMI))
    }

    @Test
    fun `headsets are the wired and bluetooth devices, never the phone itself`() {
        assertEquals(
            setOf(CallAudioRoute.WiredHeadset, CallAudioRoute.Bluetooth),
            CallAudioRouting.headsets(
                listOf(
                    AudioDeviceInfo.TYPE_BUILTIN_EARPIECE,
                    AudioDeviceInfo.TYPE_BUILTIN_SPEAKER,
                    AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
                    AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
                    AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
                ),
            ),
        )
        assertEquals(
            emptySet<CallAudioRoute>(),
            CallAudioRouting.headsets(
                listOf(
                    AudioDeviceInfo.TYPE_BUILTIN_EARPIECE,
                    AudioDeviceInfo.TYPE_BUILTIN_SPEAKER,
                ),
            ),
        )
    }

    @Test
    fun `a route picks its own device, preferring LE audio over classic bluetooth`() {
        val available = listOf(
            AudioDeviceInfo.TYPE_BUILTIN_EARPIECE,
            AudioDeviceInfo.TYPE_BUILTIN_SPEAKER,
            AudioDeviceInfo.TYPE_USB_HEADSET,
            AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
            AudioDeviceInfo.TYPE_BLE_HEADSET,
        )

        assertEquals(
            AudioDeviceInfo.TYPE_BUILTIN_EARPIECE,
            CallAudioRouting.deviceFor(CallAudioRoute.Earpiece, available),
        )
        assertEquals(
            AudioDeviceInfo.TYPE_BUILTIN_SPEAKER,
            CallAudioRouting.deviceFor(CallAudioRoute.Speaker, available),
        )
        assertEquals(
            AudioDeviceInfo.TYPE_USB_HEADSET,
            CallAudioRouting.deviceFor(CallAudioRoute.WiredHeadset, available),
        )
        assertEquals(
            AudioDeviceInfo.TYPE_BLE_HEADSET,
            CallAudioRouting.deviceFor(CallAudioRoute.Bluetooth, available),
        )
    }

    @Test
    fun `a route whose device is gone picks nothing, leaving the system default`() {
        val phoneOnly = listOf(
            AudioDeviceInfo.TYPE_BUILTIN_EARPIECE,
            AudioDeviceInfo.TYPE_BUILTIN_SPEAKER,
        )

        assertNull(CallAudioRouting.deviceFor(CallAudioRoute.Bluetooth, phoneOnly))
        assertNull(CallAudioRouting.deviceFor(CallAudioRoute.WiredHeadset, phoneOnly))
        assertNull(
            CallAudioRouting.deviceFor(
                CallAudioRoute.Earpiece,
                listOf(AudioDeviceInfo.TYPE_BUILTIN_SPEAKER),
            ),
        )
    }

    @Test
    fun `before Android 12 the speaker turns speakerphone on and bluetooth opens SCO`() {
        assertEquals(
            LegacyCallRouting(speakerphone = true, bluetoothSco = false),
            CallAudioRouting.legacyRouting(CallAudioRoute.Speaker),
        )
        assertEquals(
            LegacyCallRouting(speakerphone = false, bluetoothSco = true),
            CallAudioRouting.legacyRouting(CallAudioRoute.Bluetooth),
        )
        for (route in listOf(CallAudioRoute.Earpiece, CallAudioRoute.WiredHeadset)) {
            assertEquals(
                LegacyCallRouting(speakerphone = false, bluetoothSco = false),
                CallAudioRouting.legacyRouting(route),
            )
        }
    }

    @Test
    @Suppress("DEPRECATION")
    fun `before Android 12 bluetooth is heard while SCO connects or is connected`() {
        assertEquals(
            CallAudioRoute.Bluetooth,
            CallAudioRouting.legacyEffectiveRoute(
                requested = CallAudioRoute.Bluetooth,
                scoState = AudioManager.SCO_AUDIO_STATE_CONNECTING,
                previousScoState = AudioManager.SCO_AUDIO_STATE_DISCONNECTED,
                wiredHeadset = false,
            ),
        )
        assertEquals(
            CallAudioRoute.Bluetooth,
            CallAudioRouting.legacyEffectiveRoute(
                requested = CallAudioRoute.Bluetooth,
                scoState = AudioManager.SCO_AUDIO_STATE_CONNECTED,
                previousScoState = AudioManager.SCO_AUDIO_STATE_CONNECTING,
                wiredHeadset = true,
            ),
        )
    }

    @Test
    @Suppress("DEPRECATION")
    fun `before Android 12 a bluetooth link that fails or drops falls back to the earpiece`() {
        for ((scoState, previousScoState) in listOf(
            AudioManager.SCO_AUDIO_STATE_DISCONNECTED to AudioManager.SCO_AUDIO_STATE_CONNECTING,
            AudioManager.SCO_AUDIO_STATE_DISCONNECTED to AudioManager.SCO_AUDIO_STATE_CONNECTED,
            AudioManager.SCO_AUDIO_STATE_ERROR to AudioManager.SCO_AUDIO_STATE_CONNECTED,
        )) {
            assertEquals(
                CallAudioRoute.Earpiece,
                CallAudioRouting.legacyEffectiveRoute(
                    requested = CallAudioRoute.Bluetooth,
                    scoState = scoState,
                    previousScoState = previousScoState,
                    wiredHeadset = false,
                ),
            )
        }
    }

    @Test
    @Suppress("DEPRECATION")
    fun `before Android 12 a dropped bluetooth link falls back to a connected wired headset`() {
        assertEquals(
            CallAudioRoute.WiredHeadset,
            CallAudioRouting.legacyEffectiveRoute(
                requested = CallAudioRoute.Bluetooth,
                scoState = AudioManager.SCO_AUDIO_STATE_DISCONNECTED,
                previousScoState = AudioManager.SCO_AUDIO_STATE_CONNECTED,
                wiredHeadset = true,
            ),
        )
    }

    @Test
    @Suppress("DEPRECATION")
    fun `before Android 12 bluetooth stays heard until SCO reports a link going down`() {
        assertEquals(
            CallAudioRoute.Bluetooth,
            CallAudioRouting.legacyEffectiveRoute(
                requested = CallAudioRoute.Bluetooth,
                scoState = AudioManager.SCO_AUDIO_STATE_DISCONNECTED,
                previousScoState = AudioManager.SCO_AUDIO_STATE_DISCONNECTED,
                wiredHeadset = false,
            ),
        )
        assertEquals(
            CallAudioRoute.Bluetooth,
            CallAudioRouting.legacyEffectiveRoute(
                requested = CallAudioRoute.Bluetooth,
                scoState = AudioManager.SCO_AUDIO_STATE_DISCONNECTED,
                previousScoState = AudioManager.SCO_AUDIO_STATE_ERROR,
                wiredHeadset = true,
            ),
        )
    }

    @Test
    @Suppress("DEPRECATION")
    fun `before Android 12 a route other than bluetooth is heard whatever SCO reports`() {
        assertEquals(
            CallAudioRoute.Speaker,
            CallAudioRouting.legacyEffectiveRoute(
                requested = CallAudioRoute.Speaker,
                scoState = AudioManager.SCO_AUDIO_STATE_DISCONNECTED,
                previousScoState = AudioManager.SCO_AUDIO_STATE_CONNECTED,
                wiredHeadset = true,
            ),
        )
        assertEquals(
            CallAudioRoute.Earpiece,
            CallAudioRouting.legacyEffectiveRoute(
                requested = CallAudioRoute.Earpiece,
                scoState = AudioManager.SCO_AUDIO_STATE_CONNECTED,
                previousScoState = AudioManager.SCO_AUDIO_STATE_CONNECTING,
                wiredHeadset = false,
            ),
        )
        assertEquals(
            CallAudioRoute.WiredHeadset,
            CallAudioRouting.legacyEffectiveRoute(
                requested = CallAudioRoute.WiredHeadset,
                scoState = AudioManager.SCO_AUDIO_STATE_ERROR,
                previousScoState = AudioManager.SCO_AUDIO_STATE_CONNECTED,
                wiredHeadset = true,
            ),
        )
    }

    @Test
    fun `the state Dart reads names the route only while call audio runs`() {
        assertEquals(
            mapOf("route" to "speaker", "headsets" to listOf("wiredHeadset", "bluetooth")),
            CallAudioRouting.state(
                CallAudioRoute.Speaker,
                setOf(CallAudioRoute.Bluetooth, CallAudioRoute.WiredHeadset),
            ),
        )
        assertEquals(
            mapOf("headsets" to emptyList<String>()),
            CallAudioRouting.state(null, emptySet()),
        )
    }

    @Test
    fun `routes cross the channel by the names Dart uses`() {
        for (route in CallAudioRoute.entries) {
            assertEquals(route, CallAudioRoute.fromWire(route.wire))
        }
        assertEquals(
            listOf("earpiece", "speaker", "wiredHeadset", "bluetooth"),
            CallAudioRoute.entries.map { it.wire },
        )
        assertNull(CallAudioRoute.fromWire("hdmi"))
        assertNull(CallAudioRoute.fromWire(null))
    }
}

package im.zuno.chat

import android.annotation.SuppressLint
import android.media.AudioDeviceInfo
import android.media.AudioManager

enum class CallAudioRoute(val wire: String) {
    Earpiece("earpiece"),
    Speaker("speaker"),
    WiredHeadset("wiredHeadset"),
    Bluetooth("bluetooth"),
    ;

    companion object {
        fun fromWire(name: String?): CallAudioRoute? = entries.firstOrNull { it.wire == name }
    }
}

data class LegacyCallRouting(val speakerphone: Boolean, val bluetoothSco: Boolean)

@SuppressLint("InlinedApi")
object CallAudioRouting {
    private val wiredTypes = listOf(
        AudioDeviceInfo.TYPE_WIRED_HEADSET,
        AudioDeviceInfo.TYPE_USB_HEADSET,
        AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
    )
    private val bluetoothTypes = listOf(
        AudioDeviceInfo.TYPE_BLE_HEADSET,
        AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
        AudioDeviceInfo.TYPE_HEARING_AID,
    )

    @Suppress("DEPRECATION")
    private val scoLinkUp = listOf(
        AudioManager.SCO_AUDIO_STATE_CONNECTING,
        AudioManager.SCO_AUDIO_STATE_CONNECTED,
    )

    fun routeOf(type: Int): CallAudioRoute? = when (type) {
        AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> CallAudioRoute.Earpiece
        AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> CallAudioRoute.Speaker
        in wiredTypes -> CallAudioRoute.WiredHeadset
        in bluetoothTypes -> CallAudioRoute.Bluetooth
        else -> null
    }

    fun headsets(types: Collection<Int>): Set<CallAudioRoute> = types
        .mapNotNull(::routeOf)
        .filter { it == CallAudioRoute.WiredHeadset || it == CallAudioRoute.Bluetooth }
        .toSet()

    fun deviceFor(route: CallAudioRoute, available: Collection<Int>): Int? {
        val wanted = when (route) {
            CallAudioRoute.Earpiece -> listOf(AudioDeviceInfo.TYPE_BUILTIN_EARPIECE)
            CallAudioRoute.Speaker -> listOf(AudioDeviceInfo.TYPE_BUILTIN_SPEAKER)
            CallAudioRoute.WiredHeadset -> wiredTypes
            CallAudioRoute.Bluetooth -> bluetoothTypes
        }
        return wanted.firstOrNull { it in available }
    }

    fun legacyRouting(route: CallAudioRoute) = LegacyCallRouting(
        speakerphone = route == CallAudioRoute.Speaker,
        bluetoothSco = route == CallAudioRoute.Bluetooth,
    )

    fun legacyEffectiveRoute(
        requested: CallAudioRoute,
        scoState: Int,
        previousScoState: Int,
        wiredHeadset: Boolean,
    ): CallAudioRoute {
        val linkLost = scoState !in scoLinkUp && previousScoState in scoLinkUp
        return when {
            requested != CallAudioRoute.Bluetooth || !linkLost -> requested
            wiredHeadset -> CallAudioRoute.WiredHeadset
            else -> CallAudioRoute.Earpiece
        }
    }

    fun state(route: CallAudioRoute?, headsets: Set<CallAudioRoute>): Map<String, Any?> = buildMap {
        if (route != null) put("route", route.wire)
        put("headsets", CallAudioRoute.entries.filter { it in headsets }.map { it.wire })
    }
}

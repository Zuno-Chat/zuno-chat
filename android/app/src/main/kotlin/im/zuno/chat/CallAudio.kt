package im.zuno.chat

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioAttributes
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioFocusRequest
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.annotation.RequiresApi
import androidx.core.content.ContextCompat
import java.util.concurrent.Executor

class CallAudio(private val context: Context, private val report: (Map<String, Any?>) -> Unit) {
    private val audioManager = context.getSystemService(AudioManager::class.java)
    private val main = Handler(Looper.getMainLooper())
    private val callAttributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
        .build()
    private val focusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
        .setAudioAttributes(callAttributes)
        .setAcceptsDelayedFocusGain(true)
        .setOnAudioFocusChangeListener({}, main)
        .build()
    private val devicesChanged = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>?) = reportChange()

        override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>?) =
            reportChange()
    }

    @Suppress("DEPRECATION")
    private val scoChanged = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (isInitialStickyBroadcast) return
            scoState = intent.getIntExtra(
                AudioManager.EXTRA_SCO_AUDIO_STATE,
                AudioManager.SCO_AUDIO_STATE_ERROR,
            )
            previousScoState = intent.getIntExtra(
                AudioManager.EXTRA_SCO_AUDIO_PREVIOUS_STATE,
                AudioManager.SCO_AUDIO_STATE_ERROR,
            )
            reportChange()
        }
    }
    private var communicationDeviceChanged: Any? = null
    private var active = false
    private var route = CallAudioRoute.Earpiece
    private var awaitedDevice: Int? = null
    private val routeWaitOver = Runnable {
        awaitedDevice = null
        updateTone()
    }
    private var holdsFocus = false
    private var savedMicrophoneMute = false
    private var scoRequested = false

    @Suppress("DEPRECATION")
    private var scoState = AudioManager.SCO_AUDIO_STATE_DISCONNECTED

    @Suppress("DEPRECATION")
    private var previousScoState = AudioManager.SCO_AUDIO_STATE_DISCONNECTED
    private val wantedTones = mutableMapOf<CallTone, String>()
    private var playing: PlayingTone? = null
    private var reportedRoute: CallAudioRoute? = null
    private var reportedHeadsets = emptySet<CallAudioRoute>()

    val state: Map<String, Any?>
        get() {
            val headsets = headsets()
            return CallAudioRouting.state(if (active) currentRoute(headsets) else null, headsets)
        }

    fun start(route: CallAudioRoute) {
        if (active) {
            setRoute(route)
            return
        }
        this.route = route
        active = true
        savedMicrophoneMute = audioManager.isMicrophoneMute
        audioManager.isMicrophoneMute = false
        holdsFocus = CallAudioDecision.focusGranted(audioManager.requestAudioFocus(focusRequest))
        audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            followCommunicationDevice()
        } else {
            followSco()
        }
        applyRoute()
        rememberState()
        audioManager.registerAudioDeviceCallback(devicesChanged, main)
        updateTone()
    }

    fun setRoute(route: CallAudioRoute) {
        this.route = route
        if (!active) return
        applyRoute()
        updateTone()
    }

    fun stop() {
        if (!active) return
        active = false
        updateTone()
        audioManager.unregisterAudioDeviceCallback(devicesChanged)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            stopFollowingCommunicationDevice()
            audioManager.clearCommunicationDevice()
            main.removeCallbacks(routeWaitOver)
            awaitedDevice = null
        } else {
            context.unregisterReceiver(scoChanged)
            clearLegacyRouting()
        }
        audioManager.isMicrophoneMute = savedMicrophoneMute
        audioManager.mode = AudioManager.MODE_NORMAL
        if (holdsFocus) audioManager.abandonAudioFocusRequest(focusRequest)
        holdsFocus = false
    }

    fun setToneWanted(tone: CallTone, assetPath: String?) {
        if (assetPath != null) wantedTones[tone] = assetPath else wantedTones.remove(tone)
        updateTone()
    }

    fun release() {
        wantedTones.clear()
        updateTone()
        stop()
    }

    private fun currentRoute(headsets: Set<CallAudioRoute>): CallAudioRoute =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            audioManager.communicationDevice?.type?.let(CallAudioRouting::routeOf) ?: route
        } else {
            CallAudioRouting.legacyEffectiveRoute(
                requested = route,
                scoState = scoState,
                previousScoState = previousScoState,
                wiredHeadset = CallAudioRoute.WiredHeadset in headsets,
            )
        }

    private fun headsets(): Set<CallAudioRoute> = CallAudioRouting.headsets(
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            audioManager.availableCommunicationDevices.map { it.type }
        } else {
            audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS).map { it.type }
        },
    )

    private fun applyRoute() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            applyCommunicationDevice()
        } else {
            applyLegacyRouting()
            reportState()
        }
    }

    @RequiresApi(Build.VERSION_CODES.S)
    private fun applyCommunicationDevice() {
        val devices = audioManager.availableCommunicationDevices
        val type = CallAudioRouting.deviceFor(route, devices.map { it.type })
        val device = devices.firstOrNull { it.type == type }
        val applied = device != null && audioManager.setCommunicationDevice(device)
        if (!applied) audioManager.clearCommunicationDevice()
        main.removeCallbacks(routeWaitOver)
        awaitedDevice = if (applied) type else null
        if (!routeSettled()) main.postDelayed(routeWaitOver, ROUTE_WAIT_MS)
    }

    private fun routeSettled(): Boolean = Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
        CallAudioDecision.routeSettled(awaitedDevice, audioManager.communicationDevice?.type)

    @Suppress("DEPRECATION")
    private fun applyLegacyRouting() {
        val routing = CallAudioRouting.legacyRouting(route)
        requestSco(routing.bluetoothSco)
        audioManager.isSpeakerphoneOn = routing.speakerphone
    }

    @Suppress("DEPRECATION")
    private fun clearLegacyRouting() {
        requestSco(false)
        audioManager.isSpeakerphoneOn = false
    }

    @Suppress("DEPRECATION")
    private fun requestSco(wanted: Boolean) {
        when (CallAudioDecision.scoAction(wanted, scoRequested)) {
            ScoAction.Start -> {
                scoState = AudioManager.SCO_AUDIO_STATE_DISCONNECTED
                previousScoState = AudioManager.SCO_AUDIO_STATE_DISCONNECTED
                audioManager.startBluetoothSco()
                audioManager.isBluetoothScoOn = true
                scoRequested = true
            }

            ScoAction.Stop -> {
                audioManager.isBluetoothScoOn = false
                audioManager.stopBluetoothSco()
                scoRequested = false
            }

            ScoAction.None -> Unit
        }
    }

    @Suppress("DEPRECATION")
    private fun followSco() {
        ContextCompat.registerReceiver(
            context,
            scoChanged,
            IntentFilter(AudioManager.ACTION_SCO_AUDIO_STATE_UPDATED),
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
    }

    @RequiresApi(Build.VERSION_CODES.S)
    private fun followCommunicationDevice() {
        val listener = AudioManager.OnCommunicationDeviceChangedListener {
            updateTone()
            reportState()
        }
        audioManager.addOnCommunicationDeviceChangedListener(Executor { main.post(it) }, listener)
        communicationDeviceChanged = listener
    }

    @RequiresApi(Build.VERSION_CODES.S)
    private fun stopFollowingCommunicationDevice() {
        val listener =
            communicationDeviceChanged as? AudioManager.OnCommunicationDeviceChangedListener
                ?: return
        audioManager.removeOnCommunicationDeviceChangedListener(listener)
        communicationDeviceChanged = null
    }

    private fun reportState() {
        if (!active) return
        report(rememberState())
    }

    private fun reportChange() {
        if (!active) return
        val headsets = headsets()
        val changed = CallAudioDecision.reportsChange(
            route = currentRoute(headsets),
            headsets = headsets,
            reportedRoute = reportedRoute,
            reportedHeadsets = reportedHeadsets,
        )
        if (changed) reportState()
    }

    private fun rememberState(): Map<String, Any?> {
        val headsets = headsets()
        val current = currentRoute(headsets)
        reportedRoute = current
        reportedHeadsets = headsets
        return CallAudioRouting.state(current, headsets)
    }

    private fun updateTone() {
        val wanted = CallAudioDecision.wantedTone(wantedTones.keys)
        when (CallAudioDecision.tone(wanted, active, routeSettled(), playing?.tone)) {
            ToneAction.Start -> wanted?.let(::startTone)

            ToneAction.Restart -> {
                stopTone()
                wanted?.let(::startTone)
            }

            ToneAction.Stop -> stopTone()

            ToneAction.None -> Unit
        }
    }

    private fun startTone(wanted: CallTone) {
        playing = try {
            PlayingTone(wanted, playTone(wantedTones.getValue(wanted)))
        } catch (error: Exception) {
            CaughtErrors.record(context, "call tone", error)
            null
        }
    }

    private fun playTone(assetPath: String): AudioTrack {
        val tone = context.assets.open(assetPath).use { CallToneWave.parse(it.readBytes()) }
        val pcm = tone.samples
        val track = AudioTrack.Builder()
            .setAudioAttributes(callAttributes)
            .setAudioFormat(
                AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setSampleRate(tone.sampleRate)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build(),
            )
            .setTransferMode(AudioTrack.MODE_STATIC)
            .setBufferSizeInBytes(pcm.size * Short.SIZE_BYTES)
            .build()
        try {
            check(track.write(pcm, 0, pcm.size) == pcm.size) { "call tone not written" }
            check(track.setLoopPoints(0, pcm.size, -1) == AudioTrack.SUCCESS) {
                "call tone not looped"
            }
            track.play()
        } catch (error: RuntimeException) {
            track.release()
            throw error
        }
        return track
    }

    private fun stopTone() {
        playing?.track?.release()
        playing = null
    }

    private class PlayingTone(val tone: CallTone, val track: AudioTrack)

    private companion object {
        const val ROUTE_WAIT_MS = 2_000L
    }
}

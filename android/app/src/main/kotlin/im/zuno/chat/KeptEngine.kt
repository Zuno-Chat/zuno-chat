package im.zuno.chat

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.util.Rational
import io.flutter.embedding.engine.FlutterEngine

class HostState(context: Context) {
    val context: Context = context.applicationContext
    private val powerManager = context.applicationContext.getSystemService(
        Context.POWER_SERVICE,
    ) as PowerManager
    var preventScreenshots = false
    var showOverLockscreen = false
    var frameworkHandlesBack = false
    var pipEligible = false
    var pipAspect = Rational(3, 4)
    var pipCamera = false
    val callAudio = CallAudio(this.context) { state ->
        AppEngine.callsChannel?.invokeMethod("audioRouteChanged", state)
    }
    private var proximityWakeLock: PowerManager.WakeLock? = null

    fun setProximityScreenOff(enabled: Boolean) {
        if (!enabled) {
            proximityWakeLock?.let { if (it.isHeld) it.release() }
            proximityWakeLock = null
            return
        }
        if (proximityWakeLock?.isHeld == true) return
        val level = PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK
        if (!powerManager.isWakeLockLevelSupported(level)) return
        proximityWakeLock = powerManager
            .newWakeLock(level, PROXIMITY_WAKE_LOCK_TAG)
            .apply { acquire() }
    }

    fun release() {
        setProximityScreenOff(false)
        callAudio.release()
    }

    private companion object {
        const val PROXIMITY_WAKE_LOCK_TAG = "zuno:call_proximity"
    }
}

object KeptEngine {
    class Kept(
        val engine: FlutterEngine,
        val fcmEngineId: Int?,
        val network: NetworkAvailabilityStreamHandler?,
        val host: HostState,
    ) {
        fun releaseHost() {
            AppEngine.detach(engine)
            fcmEngineId?.let { FcmRouter.detachApp(it) }
            LiveLocationChannel.detach(engine, host.context)
            network?.stop()
            host.release()
        }
    }

    private const val RELEASE_GRACE_MS = 5_000L
    private val main = Handler(Looper.getMainLooper())
    private val releaseLater = Runnable { release() }
    private var kept: Kept? = null

    private val reasons = EngineKeepReasons()

    val keepAlive: Boolean get() = reasons.any

    fun holds(reason: EngineKeepReason): Boolean = reasons.holds(reason)

    fun hold(reason: EngineKeepReason) {
        reasons.hold(reason)
        main.removeCallbacks(releaseLater)
    }

    fun release(reason: EngineKeepReason) {
        reasons.release(reason)
        if (reasons.any || kept == null) return
        main.removeCallbacks(releaseLater)
        main.postDelayed(releaseLater, RELEASE_GRACE_MS)
    }

    fun keep(engine: Kept) {
        kept = engine
    }

    fun adopt(): Kept? {
        main.removeCallbacks(releaseLater)
        return kept.also { kept = null }
    }

    private fun release() {
        val released = kept ?: return
        kept = null
        released.releaseHost()
        PlaceholderVideo.releaseAll()
        released.engine.destroy()
    }
}

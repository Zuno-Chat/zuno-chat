package im.zuno.chat

import android.app.KeyguardManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Intent
import android.content.res.Configuration
import android.graphics.BitmapFactory
import android.graphics.drawable.Icon
import android.media.AudioManager
import android.media.ToneGenerator
import android.net.ConnectivityManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PersistableBundle
import android.os.PowerManager
import android.provider.Settings
import android.util.Rational
import android.view.WindowManager
import androidx.annotation.RequiresApi
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import androidx.lifecycle.Lifecycle
import com.google.android.gms.common.GoogleApiAvailability
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var shareChannel: MethodChannel? = null
    private var networkStreamHandler: NetworkAvailabilityStreamHandler? = null

    private fun applyShowOverLockscreenIfLocked() {
        val keyguardManager = getSystemService(KEYGUARD_SERVICE) as? KeyguardManager
        if (keyguardManager?.isKeyguardLocked == true) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        applyShowOverLockscreenIfLocked()
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        ZunoPushService.appEngineAlive = false
        callsChannel = null
        networkStreamHandler?.stop()
        networkStreamHandler = null
        setProximityScreenOff(false)
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ZunoPushService.appEngineAlive = true

        val methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel = methodChannel
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "pinShortcut" -> {
                    val id = call.argument<String>("id")
                    val label = call.argument<String>("label")
                    val roomId = call.argument<String>("roomId")
                    if (id == null || label == null || roomId == null) {
                        result.error("bad_args", "id, label and roomId are required", null)
                        return@setMethodCallHandler
                    }
                    result.success(pinShortcut(id, label, roomId, call.argument<ByteArray>("iconBytes")))
                }
                "takeLaunchRoomId" -> result.success(takeLaunchRoomId())
                else -> result.notImplemented()
            }
        }

        pendingRoomId = intent?.getStringExtra(EXTRA_ROOM_ID)

        val shareChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SHARE_CHANNEL)
        this.shareChannel = shareChannel
        shareChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "takeLaunchShare" -> result.success(takeLaunchShare())
                "copyToCache" -> copySharedToCache(
                    call.argument<List<String>>("uris").orEmpty(),
                    call.argument<List<String>>("names").orEmpty(),
                ) { paths -> result.success(paths) }
                else -> result.notImplemented()
            }
        }
        pendingShare = ShareActivity.channelPayload(intent)

        val networkStreamHandler = NetworkAvailabilityStreamHandler(
            getSystemService(ConnectivityManager::class.java),
        )
        this.networkStreamHandler = networkStreamHandler
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, NETWORK_CHANNEL)
            .setStreamHandler(networkStreamHandler)

        val callsChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CALLS_CHANNEL)
        Companion.callsChannel = callsChannel
        callsChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "setShowOverLockscreen" -> {
                    setShowOverLockscreen(call.argument<Boolean>("show") == true)
                    result.success(null)
                }
                "setProximityScreenOff" -> {
                    setProximityScreenOff(call.argument<Boolean>("enabled") == true)
                    result.success(null)
                }
                "startCallForegroundService" -> {
                    callActive = true
                    CallForegroundService.start(
                        this,
                        title = call.argument<String>("title") ?: "Ongoing call",
                        text = call.argument<String>("text") ?: "",
                        withCamera = call.argument<Boolean>("withCamera") == true,
                    )
                    result.success(null)
                }
                "stopCallForegroundService" -> {
                    callActive = false
                    CallForegroundService.stop(this)
                    result.success(null)
                }
                "startRingbackTone" -> {
                    startRingbackTone()
                    result.success(null)
                }
                "stopRingbackTone" -> {
                    stopRingbackTone()
                    result.success(null)
                }
                "canUseFullScreenIntent" -> {
                    val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
                    val allowed = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                        manager.canUseFullScreenIntent()
                    } else {
                        true
                    }
                    result.success(allowed)
                }
                "openFullScreenIntentSettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                        startActivity(
                            Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT).apply {
                                data = Uri.parse("package:$packageName")
                            },
                        )
                    }
                    result.success(null)
                }
                "setPictureInPicture" -> {
                    pipEligible = call.argument<Boolean>("eligible") == true
                    pipAspect = Rational(
                        call.argument<Int>("aspectWidth") ?: 3,
                        call.argument<Int>("aspectHeight") ?: 4,
                    )
                    applyPictureInPictureParams()
                    if (PictureInPictureDecision.shouldHide(pipEligible, isInPictureInPictureMode)) {
                        hidePictureInPicture()
                    }
                    result.success(null)
                }
                "setPreventScreenshots" -> {
                    if (call.argument<Boolean>("enabled") == true) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    result.success(null)
                }
                "copySensitive" -> {
                    val text = call.argument<String>("text")
                    if (text == null) {
                        result.error("bad_args", "text is required", null)
                        return@setMethodCallHandler
                    }
                    val clipboard =
                        getSystemService(CLIPBOARD_SERVICE) as? ClipboardManager
                    if (clipboard == null) {
                        result.error("unavailable", "no clipboard service", null)
                        return@setMethodCallHandler
                    }
                    val clip = ClipData.newPlainText("", text)
                    clip.description.extras = PersistableBundle().apply {
                        putBoolean(ClipDescription.EXTRA_IS_SENSITIVE, true)
                    }
                    clipboard.setPrimaryClip(clip)
                    result.success(null)
                }
                "clearClipboardIfMatches" -> {
                    val text = call.argument<String>("text")
                    val clipboard =
                        getSystemService(CLIPBOARD_SERVICE) as? ClipboardManager
                    val current = clipboard?.primaryClip
                        ?.takeIf { it.itemCount > 0 }
                        ?.getItemAt(0)
                        ?.coerceToText(this)
                        ?.toString()
                    if (clipboard != null && text != null && current == text) {
                        val empty = ClipData.newPlainText("", "")
                        empty.description.extras = PersistableBundle().apply {
                            putBoolean(ClipDescription.EXTRA_IS_SENSITIVE, true)
                        }
                        clipboard.setPrimaryClip(empty)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        val videoChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VIDEO_CHANNEL)
        videoChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "probe" -> {
                    val path = call.argument<String>("path")
                    if (path == null) result.success(null) else VideoTools.probe(path) { result.success(it) }
                }
                "remux" -> {
                    val input = call.argument<String>("input")
                    val output = call.argument<String>("output")
                    if (input == null || output == null) {
                        result.success(false)
                    } else {
                        VideoTools.remux(input, output) { result.success(it) }
                    }
                }
                "thumbnail" -> {
                    val path = call.argument<String>("path")
                    val maxDimension = call.argument<Int>("maxDimension")
                    val quality = call.argument<Int>("quality")
                    if (path == null || maxDimension == null || quality == null) {
                        result.success(null)
                    } else {
                        VideoTools.thumbnail(path, maxDimension, quality) { result.success(it) }
                    }
                }
                else -> result.notImplemented()
            }
        }

        val imageChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, IMAGE_CHANNEL)
        imageChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "resize" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    val maxDimension = call.argument<Int>("maxDimension")
                    val quality = call.argument<Int>("quality")
                    if (bytes == null || maxDimension == null || quality == null) {
                        result.success(null)
                    } else {
                        ImageResizer.resize(bytes, maxDimension, quality) { result.success(it) }
                    }
                }
                else -> result.notImplemented()
            }
        }

        val uploadChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, UPLOAD_CHANNEL)
        uploadChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    UploadForegroundService.start(this)
                    result.success(null)
                }
                "update" -> {
                    UploadForegroundService.update(
                        this,
                        label = call.argument<String>("label") ?: "Uploading…",
                        percent = call.argument<Int>("percent"),
                    )
                    result.success(null)
                }
                "stop" -> {
                    UploadForegroundService.stop(this)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        val backgroundSyncChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BACKGROUND_SYNC_CHANNEL)
        backgroundSyncChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "startBackgroundSyncService" -> {
                    BackgroundSyncService.start(this)
                    result.success(null)
                }
                "stopBackgroundSyncService" -> {
                    BackgroundSyncService.stop(this)
                    result.success(null)
                }
                "isIgnoringBatteryOptimizations" -> {
                    val powerManager = getSystemService(POWER_SERVICE) as PowerManager
                    result.success(powerManager.isIgnoringBatteryOptimizations(packageName))
                }
                "requestIgnoreBatteryOptimizations" -> {
                    startActivity(
                        Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                            data = Uri.parse("package:$packageName")
                        },
                    )
                    result.success(null)
                }
                "isPackageIgnoringBatteryOptimizations" -> {
                    val target = call.argument<String>("package")
                    val powerManager = getSystemService(POWER_SERVICE) as PowerManager
                    result.success(target != null && powerManager.isIgnoringBatteryOptimizations(target))
                }
                "openAppSettings" -> {
                    val target = call.argument<String>("package")
                    if (target == null) {
                        result.error("bad_args", "package is required", null)
                        return@setMethodCallHandler
                    }
                    startActivity(
                        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                            data = Uri.parse("package:$target")
                        },
                    )
                    result.success(null)
                }
                "isBackgroundDataRestricted" -> {
                    val connectivityManager =
                        getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager
                    result.success(
                        connectivityManager.restrictBackgroundStatus ==
                            ConnectivityManager.RESTRICT_BACKGROUND_STATUS_ENABLED,
                    )
                }
                "openBackgroundDataSettings" -> {
                    val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        Intent(Settings.ACTION_IGNORE_BACKGROUND_DATA_RESTRICTIONS_SETTINGS)
                    } else {
                        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                    }
                    startActivity(intent.apply { data = Uri.parse("package:$packageName") })
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        val playServicesChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PLAY_SERVICES_CHANNEL)
        playServicesChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "checkPlayServices" -> {
                    val code = GoogleApiAvailability.getInstance()
                        .isGooglePlayServicesAvailable(this)
                    result.success(PlayServicesDecision.decide(code).name)
                }
                "fixPlayServices" -> {
                    GoogleApiAvailability.getInstance()
                        .makeGooglePlayServicesAvailable(this)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        val deviceSafetyChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DEVICE_SAFETY_CHANNEL)
        deviceSafetyChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "check" -> {
                    val mainThread = Handler(Looper.getMainLooper())
                    Thread {
                        val risks = runCatching { DeviceSafety(applicationContext).check() }
                            .getOrDefault(emptyList())
                        mainThread.post { result.success(risks) }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun setShowOverLockscreen(show: Boolean) {
        setShowWhenLocked(show)
        setTurnScreenOn(show)
    }

    private var proximityWakeLock: PowerManager.WakeLock? = null

    private fun setProximityScreenOff(enabled: Boolean) {
        if (!enabled) {
            proximityWakeLock?.let { if (it.isHeld) it.release() }
            proximityWakeLock = null
            return
        }
        if (proximityWakeLock?.isHeld == true) return
        val level = PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK
        val powerManager = getSystemService(POWER_SERVICE) as PowerManager
        if (!powerManager.isWakeLockLevelSupported(level)) return
        proximityWakeLock = powerManager
            .newWakeLock(level, PROXIMITY_WAKE_LOCK_TAG)
            .apply { acquire() }
    }

    private val pipEntryMode = PictureInPictureDecision.entryMode(Build.VERSION.SDK_INT)
    private var pipEligible = false
    private var pipAspect = Rational(3, 4)
    private var pipSelfHidden = false
    private var callActive = false
    private var hangUpPendingBeforeDestroy = false

    private fun applyPictureInPictureParams() {
        if (pipEntryMode == PipEntryMode.Unsupported) return
        try {
            setPictureInPictureParams(buildPictureInPictureParams())
        } catch (error: IllegalArgumentException) {
        } catch (error: IllegalStateException) {
        }
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun buildPictureInPictureParams(): PictureInPictureParams {
        val builder = PictureInPictureParams.Builder()
            .setAspectRatio(pipAspect)
            .setActions(listOf(hangUpRemoteAction()))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setAutoEnterEnabled(pipEligible)
            builder.setSeamlessResizeEnabled(false)
        }
        return builder.build()
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun hangUpRemoteAction(): RemoteAction {
        val hangUpIntent = PendingIntent.getBroadcast(
            this,
            PIP_HANG_UP_REQUEST_CODE,
            Intent(this, CallActionReceiver::class.java).setAction(CallActionReceiver.ACTION_HANG_UP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return RemoteAction(
            Icon.createWithResource(this, R.drawable.ic_pip_hang_up),
            "Hang up",
            "Hang up",
            hangUpIntent,
        )
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (!pipEligible) return
        if (pipEntryMode != PipEntryMode.EnterOnLeave) return
        try {
            enterPictureInPictureMode(buildPictureInPictureParams())
        } catch (error: IllegalStateException) {
        } catch (error: IllegalArgumentException) {
        }
    }

    private fun hidePictureInPicture() {
        pipSelfHidden = true
        moveTaskToBack(false)
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        callsChannel?.invokeMethod("pictureInPictureChanged", isInPictureInPictureMode)
        if (isInPictureInPictureMode) {
            pipSelfHidden = false
            return
        }
        val exit = PictureInPictureDecision.onLeft(
            lifecycleCreated = lifecycle.currentState == Lifecycle.State.CREATED,
            selfHidden = pipSelfHidden,
        )
        pipSelfHidden = false
        if (exit == PipExit.ClosedByUser) requestHangUpBeforeDestroy()
    }

    private fun requestHangUpBeforeDestroy() {
        hangUpPendingBeforeDestroy = true
        callsChannel?.invokeMethod(CallActionReceiver.HANG_UP_METHOD, null)
    }

    override fun shouldDestroyEngineWithHost(): Boolean {
        if (!hangUpPendingBeforeDestroy) return super.shouldDestroyEngineWithHost()
        val engine = flutterEngine ?: return true
        val context = applicationContext
        Handler(Looper.getMainLooper()).postDelayed({
            engine.destroy()
            CallForegroundService.stop(context)
        }, HANG_UP_GRACE_MS)
        return false
    }

    private var ringbackTone: ToneGenerator? = null

    private fun startRingbackTone() {
        stopRingbackTone()
        try {
            val generator = ToneGenerator(AudioManager.STREAM_VOICE_CALL, 80)
            generator.startTone(ToneGenerator.TONE_SUP_RINGTONE)
            ringbackTone = generator
        } catch (error: RuntimeException) {
            ringbackTone = null
        }
    }

    private fun stopRingbackTone() {
        ringbackTone?.let {
            it.stopTone()
            it.release()
        }
        ringbackTone = null
    }

    override fun onDestroy() {
        stopRingbackTone()
        setProximityScreenOff(false)
        if (CallHangUpDecision.onHostDestroyed(callActive, hangUpPendingBeforeDestroy)) {
            requestHangUpBeforeDestroy()
        }
        super.onDestroy()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        applyShowOverLockscreenIfLocked()
        ShareActivity.channelPayload(intent)?.let { share ->
            shareChannel?.invokeMethod("share", share)
            return
        }
        val roomId = intent.getStringExtra(EXTRA_ROOM_ID) ?: return
        channel?.invokeMethod("openRoom", roomId)
    }

    private fun takeLaunchRoomId(): String? {
        val id = pendingRoomId
        pendingRoomId = null
        return id
    }

    private fun takeLaunchShare(): Map<String, Any?>? {
        val share = pendingShare
        pendingShare = null
        return share
    }

    private fun copySharedToCache(
        uris: List<String>,
        names: List<String>,
        onDone: (List<String?>) -> Unit,
    ) {
        val root = File(cacheDir, "shared")
        val mainThread = Handler(Looper.getMainLooper())
        Thread {
            root.deleteRecursively()
            val batch = File(root, UUID.randomUUID().toString())
            val paths = uris.mapIndexed { i, uri ->
                copySharedFile(File(batch, i.toString()), uri, names.getOrNull(i) ?: "shared")
            }
            mainThread.post { onDone(paths) }
        }.start()
    }

    private fun copySharedFile(dir: File, uri: String, name: String): String? = runCatching {
        dir.mkdirs()
        val target = File(dir, InboundShareDecision.safeFileName(name))
        if (!target.canonicalPath.startsWith(dir.canonicalPath + File.separator)) {
            return@runCatching null
        }
        contentResolver.openInputStream(Uri.parse(uri))?.use { source ->
            target.outputStream().use { source.copyTo(it) }
            target.path
        }
    }.getOrNull()

    private fun pinShortcut(id: String, label: String, roomId: String, iconBytes: ByteArray?): Boolean {
        if (!ShortcutManagerCompat.isRequestPinShortcutSupported(this)) return false

        val intent = Intent(this, MainActivity::class.java).apply {
            action = Intent.ACTION_VIEW
            putExtra(EXTRA_ROOM_ID, roomId)
        }

        val icon = if (iconBytes != null) {
            IconCompat.createWithBitmap(BitmapFactory.decodeByteArray(iconBytes, 0, iconBytes.size))
        } else {
            IconCompat.createWithResource(this, applicationInfo.icon)
        }

        val shortcut = ShortcutInfoCompat.Builder(this, id)
            .setShortLabel(label)
            .setIcon(icon)
            .setIntent(intent)
            .build()

        return ShortcutManagerCompat.requestPinShortcut(this, shortcut, null)
    }

    companion object {
        private const val CHANNEL = "zuno/shortcuts"
        private const val SHARE_CHANNEL = "zuno/share"
        private const val NETWORK_CHANNEL = "zuno/network"
        private const val CALLS_CHANNEL = "zuno/calls"
        private const val BACKGROUND_SYNC_CHANNEL = "zuno/background_sync"
        private const val UPLOAD_CHANNEL = "zuno/upload_service"
        private const val IMAGE_CHANNEL = "zuno/image"
        private const val VIDEO_CHANNEL = "zuno/video"
        private const val PLAY_SERVICES_CHANNEL = "zuno/play_services"
        private const val DEVICE_SAFETY_CHANNEL = "zuno/device_safety"
        private const val EXTRA_ROOM_ID = "room_id"
        private const val PIP_HANG_UP_REQUEST_CODE = 4102
        private const val HANG_UP_GRACE_MS = 5_000L
        private const val PROXIMITY_WAKE_LOCK_TAG = "zuno:call_proximity"
        private var pendingRoomId: String? = null
        private var pendingShare: Map<String, Any?>? = null
        var callsChannel: MethodChannel? = null
    }
}

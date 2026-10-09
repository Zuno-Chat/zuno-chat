package im.zuno.chat

import android.app.ActivityManager
import android.app.KeyguardManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.BitmapFactory
import android.graphics.drawable.Icon
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
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import com.cloudwebrtc.webrtc.audio.AudioSwitchManager
import im.zuno.chat.zuno_call_style.RingDecisions
import im.zuno.chat.zuno_notifications.AppLaunchIntent
import im.zuno.chat.zuno_notifications.RoomLaunchIntent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.lang.ref.WeakReference
import java.util.UUID
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var shareChannel: MethodChannel? = null
    private var callsChannel: MethodChannel? = null
    private var networkStreamHandler: NetworkAvailabilityStreamHandler? = null
    private var fcmEngineId: Int? = null
    private var adopted: KeptEngine.Kept? = null
    private lateinit var host: HostState
    private var duplicate = false
    private var restoredFrameworkHandlesBack = false

    override fun onCreate(savedInstanceState: Bundle?) {
        val running = runningInstance?.get()?.takeUnless { it.isFinishing || it.isDestroyed }
        if (running != null) {
            duplicate = true
            super.onCreate(savedInstanceState)
            handOverTo(running)
            return
        }
        runningInstance = WeakReference(this)
        val launch = intent
        if (launch != null &&
            !LaunchIntentDecision.carriesLaunchTarget(launch.flags, savedInstanceState != null)
        ) {
            intent = Intent(launch).apply {
                action = Intent.ACTION_MAIN
                data = null
                clipData = null
                replaceExtras(Bundle())
            }
        }
        super.onCreate(savedInstanceState)
        showRingOverLockscreen(intent)
    }

    override fun onDestroy() {
        if (runningInstance?.get() === this) runningInstance = null
        super.onDestroy()
    }

    private fun handOverTo(running: MainActivity) {
        val launch = intent
        finish()
        val decision = LaunchIntentDecision.onDuplicate(
            launch.action,
            launch.flags,
            handedOver = launch.getBooleanExtra(EXTRA_HANDED_OVER, false),
            sameTask = running.taskId == taskId,
        )
        if (decision == DuplicateLaunch.HandOver) {
            startActivity(
                Intent(launch)
                    .putExtra(EXTRA_HANDED_OVER, true)
                    .addFlags(AppLaunchIntent.TO_RUNNING_APP),
            )
        }
    }

    private fun showRingOverLockscreen(launch: Intent?) {
        if (launch == null) return
        val notificationId = launch.getIntExtra(RingDecisions.NOTIFICATION_ID_EXTRA, -1)
        if (!RingDecisions.ringLaunch(launch.action, notificationId)) return
        val keyguardManager = getSystemService(KEYGUARD_SERVICE) as? KeyguardManager
        if (keyguardManager?.isKeyguardLocked == true) setShowOverLockscreen(true)
    }

    override fun provideFlutterEngine(context: Context): FlutterEngine? {
        if (duplicate) return FlutterEngine(context, null, false)
        val kept = KeptEngine.adopt() ?: return null
        adopted = kept
        return kept.engine
    }

    private fun engineFate(): HostEngineFate =
        HostEngineDecision.onHostDetached(KeptEngine.keepAlive, adopted != null)

    override fun shouldDestroyEngineWithHost(): Boolean {
        if (duplicate) return true
        return when (engineFate()) {
            HostEngineFate.Keep -> false
            HostEngineFate.Destroy -> true
            HostEngineFate.Default -> super.shouldDestroyEngineWithHost()
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        if (!duplicate) {
            val detached =
                KeptEngine.Kept(flutterEngine, fcmEngineId, networkStreamHandler, host)
            if (engineFate() == HostEngineFate.Keep) {
                KeptEngine.keep(detached)
            } else {
                detached.releaseHost()
            }
            fcmEngineId = null
            networkStreamHandler = null
        }
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun setFrameworkHandlesBack(frameworkHandlesBack: Boolean) {
        if (::host.isInitialized) {
            host.frameworkHandlesBack = frameworkHandlesBack
        } else {
            restoredFrameworkHandlesBack = frameworkHandlesBack
        }
        claimBack()
    }

    override fun getBackCallbackState(): Boolean =
        if (::host.isInitialized) host.frameworkHandlesBack else restoredFrameworkHandlesBack

    private fun claimBack() {
        super.setFrameworkHandlesBack(
            PictureInPictureDecision.claimsBack(
                getBackCallbackState(),
                ::host.isInitialized && host.pipEligible,
            ),
        )
    }

    override fun popSystemNavigator(): Boolean {
        if (!::host.isInitialized) return false
        val callHeld = KeptEngine.holds(EngineKeepReason.Call)
        return when (PictureInPictureDecision.onRootBack(host.pipEligible, callHeld)) {
            RootBack.EnterPictureInPicture -> {
                if (!enterPictureInPicture()) moveTaskToBack(true)
                true
            }

            RootBack.MoveToBack -> {
                moveTaskToBack(true)
                true
            }

            RootBack.Default -> false
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        AudioSwitchManager.setAudioSessionManagementEnabled(false)
        super.configureFlutterEngine(flutterEngine)
        if (duplicate) return
        val kept = adopted
        host = kept?.host ?: HostState(this).also {
            it.frameworkHandlesBack = restoredFrameworkHandlesBack
        }
        AppEngine.attach(flutterEngine)
        fcmEngineId = kept?.fcmEngineId?.also { FcmRouter.rebindApp(it, this) }
            ?: FcmRouter.attachApp(flutterEngine, this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ZunoPushService.WAKELOCK_CHANNEL)
            .setMethodCallHandler(ZunoPushService.wakeLockHandler(this))

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
                    result.success(
                        pinShortcut(id, label, roomId, call.argument<ByteArray>("iconBytes")),
                    )
                }

                "takeLaunchRoomId" -> result.success(takeLaunchRoomId())

                else -> result.notImplemented()
            }
        }

        if (kept == null) pendingRoomId = intent?.getStringExtra(RoomLaunchIntent.EXTRA_ROOM_ID)

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
        if (kept == null) pendingShare = ShareActivity.channelPayload(intent)
        pruneSharedCache()

        networkStreamHandler = kept?.network ?: NetworkAvailabilityStreamHandler(
            getSystemService(ConnectivityManager::class.java),
        ).also {
            EventChannel(flutterEngine.dartExecutor.binaryMessenger, NETWORK_CHANNEL)
                .setStreamHandler(it)
        }

        LiveLocationChannel.register(flutterEngine, this)

        val callsChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CALLS_CHANNEL)
        this.callsChannel = callsChannel
        AppEngine.bindCalls(flutterEngine, callsChannel)
        callsChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "setShowOverLockscreen" -> {
                    setShowOverLockscreen(call.argument<Boolean>("show") == true)
                    result.success(null)
                }

                "setProximityScreenOff" -> {
                    host.setProximityScreenOff(call.argument<Boolean>("enabled") == true)
                    result.success(null)
                }

                "startCallForegroundService" -> {
                    KeptEngine.hold(EngineKeepReason.Call)
                    CallForegroundService.start(
                        applicationContext,
                        title = call.argument<String>("title") ?: "Ongoing call",
                        text = call.argument<String>("text") ?: "",
                        withCamera = call.argument<Boolean>("withCamera") == true,
                    )
                    result.success(null)
                }

                "stopCallForegroundService" -> {
                    KeptEngine.release(EngineKeepReason.Call)
                    CallForegroundService.stop(applicationContext)
                    result.success(null)
                }

                "startCallAudio" -> {
                    host.callAudio.start(
                        CallAudioRoute.fromWire(call.argument<String>("route"))
                            ?: CallAudioRoute.Earpiece,
                    )
                    result.success(host.callAudio.state)
                }

                "stopCallAudio" -> {
                    host.callAudio.stop()
                    result.success(null)
                }

                "audioRoute" -> result.success(host.callAudio.state)

                "setAudioRoute" -> {
                    CallAudioRoute.fromWire(call.argument<String>("route"))
                        ?.let(host.callAudio::setRoute)
                    result.success(null)
                }

                "startRingbackTone" -> {
                    host.callAudio.setRingbackWanted(true)
                    result.success(null)
                }

                "stopRingbackTone" -> {
                    host.callAudio.setRingbackWanted(false)
                    result.success(null)
                }

                "canUseFullScreenIntent" -> {
                    val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
                    val allowed = if (Build.VERSION.SDK_INT >=
                        Build.VERSION_CODES.UPSIDE_DOWN_CAKE
                    ) {
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

                "openNotificationSettings" -> {
                    startActivity(
                        Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                            putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                        },
                    )
                    result.success(null)
                }

                "openChannelSettings" -> {
                    val channelId = call.argument<String>("channelId")
                    val intent = if (channelId != null) {
                        Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS).apply {
                            putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                            putExtra(Settings.EXTRA_CHANNEL_ID, channelId)
                        }
                    } else {
                        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                            data = Uri.parse("package:$packageName")
                        }
                    }
                    startActivity(intent)
                    result.success(null)
                }

                "setPictureInPicture" -> {
                    host.pipEligible = call.argument<Boolean>("eligible") == true
                    host.pipAspect = Rational(
                        call.argument<Int>("aspectWidth") ?: 3,
                        call.argument<Int>("aspectHeight") ?: 4,
                    )
                    applyPictureInPictureParams()
                    claimBack()
                    if (PictureInPictureDecision.shouldHide(
                            host.pipEligible,
                            isInPictureInPictureMode,
                        )
                    ) {
                        hidePictureInPicture()
                    }
                    result.success(null)
                }

                "attachPlaceholderVideo" -> {
                    val streamId = call.argument<String>("streamId")
                    result.success(
                        streamId?.let { PlaceholderVideo.attach(flutterEngine, it) },
                    )
                }

                "releasePlaceholderVideo" -> {
                    call.argument<String>("trackId")?.let { PlaceholderVideo.release(it) }
                    result.success(null)
                }

                "setPreventScreenshots" -> {
                    host.preventScreenshots = call.argument<Boolean>("enabled") == true
                    applyPreventScreenshots()
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
                    if (path ==
                        null
                    ) {
                        result.success(null)
                    } else {
                        VideoTools.probe(path) { result.success(it) }
                    }
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

        val uploadChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, UPLOAD_CHANNEL)
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

        val backgroundSyncChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BACKGROUND_SYNC_CHANNEL)
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
                    result.success(
                        target != null && powerManager.isIgnoringBatteryOptimizations(target),
                    )
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

                "hasAutostartSettings" -> {
                    result.success(autostartComponents().isNotEmpty())
                }

                "openAutostartSettings" -> {
                    result.success(openAutostartSettings())
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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, APP_DATA_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "wipe" -> {
                        val activityManager = getSystemService(ACTIVITY_SERVICE) as ActivityManager
                        result.success(activityManager.clearApplicationUserData())
                    }

                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PUSH_DIAG_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "snapshot") {
                    result.success(PushDiagSnapshot.read(this))
                } else {
                    result.notImplemented()
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

        if (kept != null) {
            applyPreventScreenshots()
            if (host.showOverLockscreen) setShowOverLockscreen(true)
            applyPictureInPictureParams()
            intent?.let { deliverLaunch(it) }
        }
        claimBack()
    }

    private fun applyPreventScreenshots() {
        if (host.preventScreenshots) {
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }

    private fun setShowOverLockscreen(show: Boolean) {
        host.showOverLockscreen = show
        setShowWhenLocked(show)
        setTurnScreenOn(show)
    }

    private val pipEntryMode = PictureInPictureDecision.entryMode(Build.VERSION.SDK_INT)
    private var started = false

    override fun onStart() {
        super.onStart()
        started = true
        reportPictureInPictureCamera()
    }

    override fun onStop() {
        super.onStop()
        started = false
        reportPictureInPictureCamera()
    }

    private fun reportPictureInPictureCamera() {
        if (!::host.isInitialized) return
        val keeps = PictureInPictureDecision.keepsCamera(isInPictureInPictureMode, started)
        if (host.pipCamera == keeps) return
        host.pipCamera = keeps
        callsChannel?.invokeMethod("pictureInPictureCameraChanged", keeps)
    }

    private fun applyPictureInPictureParams() {
        try {
            setPictureInPictureParams(buildPictureInPictureParams())
        } catch (error: IllegalArgumentException) {
        } catch (error: IllegalStateException) {
        }
    }

    private fun buildPictureInPictureParams(): PictureInPictureParams {
        val builder = PictureInPictureParams.Builder()
            .setAspectRatio(host.pipAspect)
            .setActions(listOf(hangUpRemoteAction()))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setAutoEnterEnabled(host.pipEligible)
            builder.setSeamlessResizeEnabled(false)
        }
        return builder.build()
    }

    private fun hangUpRemoteAction(): RemoteAction {
        val hangUpIntent = PendingIntent.getBroadcast(
            this,
            PIP_HANG_UP_REQUEST_CODE,
            Intent(
                this,
                CallActionReceiver::class.java,
            ).setAction(CallActionReceiver.ACTION_HANG_UP),
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
        if (!host.pipEligible) return
        if (pipEntryMode != PipEntryMode.EnterOnLeave) return
        enterPictureInPicture()
    }

    private fun enterPictureInPicture(): Boolean = try {
        enterPictureInPictureMode(buildPictureInPictureParams())
    } catch (error: IllegalStateException) {
        false
    } catch (error: IllegalArgumentException) {
        false
    }

    private fun hidePictureInPicture() {
        moveTaskToBack(false)
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        callsChannel?.invokeMethod("pictureInPictureChanged", isInPictureInPictureMode)
        reportPictureInPictureCamera()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        showRingOverLockscreen(intent)
        deliverLaunch(intent)
    }

    private fun deliverLaunch(intent: Intent) {
        if (intent.action == CallForegroundService.ACTION_OPEN_CALL) {
            callsChannel?.invokeMethod("openCallScreen", null)
            return
        }
        ShareActivity.channelPayload(intent)?.let { share ->
            shareChannel?.invokeMethod("share", share)
            return
        }
        val roomId = intent.getStringExtra(RoomLaunchIntent.EXTRA_ROOM_ID) ?: return
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

    private fun pruneSharedCache() {
        val sharedCache = File(cacheDir, SHARED_CACHE_DIR)
        sharedCacheWork.execute {
            val cutoff = System.currentTimeMillis() - SHARED_CACHE_LIFETIME_MS
            sharedCache.listFiles()
                ?.filter { it.lastModified() < cutoff }
                ?.forEach { it.deleteRecursively() }
        }
    }

    private fun copySharedToCache(
        uris: List<String>,
        names: List<String>,
        onDone: (List<String?>) -> Unit,
    ) {
        val batch = File(File(cacheDir, SHARED_CACHE_DIR), UUID.randomUUID().toString())
        val mainThread = Handler(Looper.getMainLooper())
        sharedCacheWork.execute {
            val paths = uris.mapIndexed { i, uri ->
                copySharedFile(File(batch, i.toString()), uri, names.getOrNull(i) ?: "shared")
            }
            mainThread.post { onDone(paths) }
        }
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

    private fun pinShortcut(
        id: String,
        label: String,
        roomId: String,
        iconBytes: ByteArray?,
    ): Boolean {
        if (!ShortcutManagerCompat.isRequestPinShortcutSupported(this)) return false

        val intent = RoomLaunchIntent.forRoom(this, roomId)

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

    private fun autostartComponents(): List<Pair<String, String>> =
        AutostartDecision.availableFor(Build.MANUFACTURER) { (pkg, cls) ->
            packageManager.resolveActivity(
                Intent().setComponent(ComponentName(pkg, cls)),
                0,
            ) != null
        }

    private fun openAutostartSettings(): Boolean {
        for ((pkg, cls) in autostartComponents()) {
            try {
                startActivity(Intent().setComponent(ComponentName(pkg, cls)))
                return true
            } catch (_: Exception) {
            }
        }
        startActivity(
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.parse("package:$packageName")
            },
        )
        return false
    }

    companion object {
        private const val CHANNEL = "zuno/shortcuts"
        private const val SHARE_CHANNEL = "zuno/share"
        private const val SHARED_CACHE_DIR = "shared"
        private const val SHARED_CACHE_LIFETIME_MS = 24 * 60 * 60 * 1000L
        private val sharedCacheWork: ExecutorService = Executors.newSingleThreadExecutor()
        private const val NETWORK_CHANNEL = "zuno/network"
        private const val CALLS_CHANNEL = "zuno/calls"
        private const val BACKGROUND_SYNC_CHANNEL = "zuno/background_sync"
        private const val UPLOAD_CHANNEL = "zuno/upload_service"
        private const val IMAGE_CHANNEL = "zuno/image"
        private const val VIDEO_CHANNEL = "zuno/video"
        private const val DEVICE_SAFETY_CHANNEL = "zuno/device_safety"
        private const val APP_DATA_CHANNEL = "zuno/app_data"
        private const val PUSH_DIAG_CHANNEL = "zuno/push_diag"
        private const val PIP_HANG_UP_REQUEST_CODE = 4102
        private const val EXTRA_HANDED_OVER = "im.zuno.chat.HANDED_OVER"
        private var runningInstance: WeakReference<MainActivity>? = null
        private var pendingRoomId: String? = null
        private var pendingShare: Map<String, Any?>? = null
    }
}

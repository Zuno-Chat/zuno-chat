package im.zuno.chat

import android.Manifest
import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.location.Location
import android.location.LocationManager
import android.os.Build
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import androidx.core.location.LocationListenerCompat
import androidx.core.location.LocationManagerCompat
import androidx.core.location.LocationRequestCompat
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import im.zuno.chat.zuno_notifications.RoomLaunchIntent
import java.lang.ref.WeakReference

data class LiveLocationNotice(
    val title: String,
    val text: String,
    val endsAtMs: Long,
    val roomId: String?,
)

class LiveLocationService : Service() {
    private var fused: FusedLocationProviderClient? = null
    private var providers: BroadcastReceiver? = null
    private val fusedCallback = object : LocationCallback() {
        override fun onLocationResult(result: LocationResult) {
            result.lastLocation?.let(::deliver)
        }
    }
    private val platformListener = LocationListenerCompat(::deliver)

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = WeakReference(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notice = lastNotice ?: LiveLocationNotice(
            title = "Live location",
            text = "",
            endsAtMs = System.currentTimeMillis(),
            roomId = null,
        )
        ensureChannel(this)
        try {
            ServiceCompat.startForeground(
                this,
                NOTIFICATION_ID,
                buildNotification(this, notice),
                foregroundServiceType(),
            )
        } catch (error: SecurityException) {
            fail("denied")
            return START_NOT_STICKY
        } catch (error: IllegalStateException) {
            fail("failed")
            return START_NOT_STICKY
        }
        foregrounded = true
        if (!wanted) {
            stopping = true
            stopSelf()
            return START_NOT_STICKY
        }
        requestUpdates(currentMode)
        watchProviders()
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        removeUpdates()
        providers?.let(::unregisterReceiver)
        providers = null
        if (instance?.get() === this) instance = null
        foregrounded = false
        when {
            !stopping -> tellDart("failed")
            !failed -> releaseHeldWakeLock()
        }
        stopping = false
        failed = false
        super.onDestroy()
    }

    @SuppressLint("MissingPermission")
    private fun requestUpdates(mode: LiveLocationMode) {
        if (!hasPermission(this)) {
            fail("denied")
            return
        }
        if (!LocationManagerCompat.isLocationEnabled(locationManager())) {
            fail("services_off")
            return
        }
        removeUpdates()
        val request = LiveLocationRequestDecision.requestFor(mode)
        try {
            if (playServicesAvailable(this)) {
                requestFused(mode, request)
            } else {
                requestPlatform(mode, request)
            }
        } catch (error: SecurityException) {
            fail("denied")
        }
    }

    @SuppressLint("MissingPermission")
    private fun requestFused(mode: LiveLocationMode, request: LiveLocationRequest) {
        val client =
            fused ?: LocationServices.getFusedLocationProviderClient(this).also { fused = it }
        val priority = if (request.highAccuracy) {
            Priority.PRIORITY_HIGH_ACCURACY
        } else {
            Priority.PRIORITY_BALANCED_POWER_ACCURACY
        }
        client.requestLocationUpdates(
            LocationRequest.Builder(priority, request.intervalMs)
                .setMinUpdateIntervalMillis(request.intervalMs)
                .setMinUpdateDistanceMeters(request.minDistanceMeters)
                .build(),
            fusedCallback,
            Looper.getMainLooper(),
        ).addOnFailureListener {
            if (instance?.get() !== this || stopping || mode != currentMode) {
                return@addOnFailureListener
            }
            client.removeLocationUpdates(fusedCallback)
            try {
                requestPlatform(mode, request)
            } catch (error: SecurityException) {
                fail("denied")
            }
        }
    }

    @SuppressLint("MissingPermission")
    private fun requestPlatform(mode: LiveLocationMode, request: LiveLocationRequest) {
        val manager = locationManager()
        val provider = LiveLocationRequestDecision.providerFor(
            mode,
            manager.getProviders(true).toSet(),
            Build.VERSION.SDK_INT,
        )
        if (provider == null) {
            fail("services_off")
            return
        }
        val quality = if (request.highAccuracy) {
            LocationRequestCompat.QUALITY_HIGH_ACCURACY
        } else {
            LocationRequestCompat.QUALITY_BALANCED_POWER_ACCURACY
        }
        LocationManagerCompat.requestLocationUpdates(
            manager,
            provider,
            LocationRequestCompat.Builder(request.intervalMs)
                .setQuality(quality)
                .setMinUpdateIntervalMillis(request.intervalMs)
                .setMinUpdateDistanceMeters(request.minDistanceMeters)
                .build(),
            ContextCompat.getMainExecutor(this),
            platformListener,
        )
    }

    private fun removeUpdates() {
        fused?.removeLocationUpdates(fusedCallback)
        LocationManagerCompat.removeUpdates(locationManager(), platformListener)
    }

    private fun locationManager(): LocationManager =
        getSystemService(LOCATION_SERVICE) as LocationManager

    private fun watchProviders() {
        if (providers != null) return
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                if (!stopping) requestUpdates(currentMode)
            }
        }
        ContextCompat.registerReceiver(
            this,
            receiver,
            IntentFilter(LocationManager.PROVIDERS_CHANGED_ACTION),
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
        providers = receiver
    }

    private fun deliver(location: Location) {
        val endsAtMs = lastNotice?.endsAtMs
        if (endsAtMs != null &&
            LiveLocationRequestDecision.isPastEnd(System.currentTimeMillis(), endsAtMs)
        ) {
            fail("ended")
            return
        }
        val seq = ++sequence
        acquireWakeLock(this)
        val delivered = LiveLocationChannel.emit(
            mapOf(
                "lat" to location.latitude,
                "lon" to location.longitude,
                "accuracy" to if (location.hasAccuracy()) location.accuracy.toDouble() else null,
                "ts" to location.time,
                "seq" to seq,
            ),
        )
        if (!delivered) releaseWakeLock(seq)
    }

    private fun fail(code: String) {
        if (stopping) return
        stopping = true
        tellDart(code)
        stopSelf()
    }

    private fun tellDart(code: String) {
        failed = true
        sequence++
        acquireWakeLock(this)
        LiveLocationChannel.emit(mapOf("error" to code))
    }

    companion object {
        private const val CHANNEL_ID = "live_location"
        private const val NOTIFICATION_ID = 4005
        private const val STOP_REQUEST_CODE = 4105
        private const val OPEN_REQUEST_CODE = 4106
        private const val WAKE_LOCK_TAG = "zuno:live_location"
        private const val WAKE_LOCK_TIMEOUT_MS = 15_000L

        private var instance: WeakReference<LiveLocationService>? = null
        private var currentMode = LiveLocationMode.Coarse
        private var lastNotice: LiveLocationNotice? = null
        private var wanted = false
        private var foregrounded = false
        private var stopping = false
        private var failed = false
        private var sequence = 0
        private var wakeLock: PowerManager.WakeLock? = null

        fun hasPermission(context: Context): Boolean = listOf(
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_COARSE_LOCATION,
        ).any {
            ContextCompat.checkSelfPermission(context, it) == PackageManager.PERMISSION_GRANTED
        }

        fun start(context: Context, mode: LiveLocationMode, notice: LiveLocationNotice) {
            currentMode = mode
            lastNotice = notice
            wanted = true
            stopping = false
            ContextCompat.startForegroundService(
                context,
                Intent(context, LiveLocationService::class.java),
            )
        }

        fun setMode(mode: LiveLocationMode) {
            if (mode == currentMode) return
            currentMode = mode
            instance?.get()?.requestUpdates(mode)
        }

        fun updateNotice(context: Context, notice: LiveLocationNotice) {
            lastNotice = notice
            if (!wanted || instance?.get() == null) return
            try {
                NotificationManagerCompat.from(context)
                    .notify(NOTIFICATION_ID, buildNotification(context, notice))
            } catch (error: SecurityException) {
                return
            }
        }

        fun releaseWakeLock(seq: Int) {
            if (LiveLocationRequestDecision.releasesWakeLock(seq, sequence)) releaseHeldWakeLock()
        }

        fun stop(context: Context) {
            if (!wanted) return
            wanted = false
            stopping = true
            if (foregrounded) {
                context.stopService(Intent(context, LiveLocationService::class.java))
            }
        }

        private fun foregroundServiceType(): Int =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
            } else {
                0
            }

        private fun playServicesAvailable(context: Context): Boolean =
            GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(context) ==
                ConnectionResult.SUCCESS

        private fun acquireWakeLock(context: Context) {
            val lock = wakeLock
                ?: (context.applicationContext.getSystemService(POWER_SERVICE) as PowerManager)
                    .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKE_LOCK_TAG)
                    .apply { setReferenceCounted(false) }
                    .also { wakeLock = it }
            lock.acquire(WAKE_LOCK_TIMEOUT_MS)
        }

        private fun releaseHeldWakeLock() {
            wakeLock?.let { if (it.isHeld) it.release() }
        }

        private fun ensureChannel(context: Context) {
            NotificationChannels.ensure(
                context,
                NotificationGroup.BACKGROUND,
                CHANNEL_ID,
                "Live location",
                "Shows while you share your live location",
                NotificationManager.IMPORTANCE_LOW,
            )
        }

        private fun buildNotification(context: Context, notice: LiveLocationNotice): Notification {
            val open = notice.roomId?.let { RoomLaunchIntent.forRoom(context, it) }
                ?: context.packageManager.getLaunchIntentForPackage(context.packageName)
            val contentIntent = open?.let {
                PendingIntent.getActivity(
                    context,
                    OPEN_REQUEST_CODE,
                    it,
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
                )
            }
            val stopIntent = PendingIntent.getBroadcast(
                context,
                STOP_REQUEST_CODE,
                Intent(context, LiveLocationActionReceiver::class.java)
                    .setAction(LiveLocationActionReceiver.ACTION_STOP),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            return NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_stat_zuno_mark)
                .setContentTitle(notice.title)
                .setContentText(notice.text)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setSilent(true)
                .setCategory(NotificationCompat.CATEGORY_LOCATION_SHARING)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
                .setWhen(notice.endsAtMs)
                .setShowWhen(true)
                .setUsesChronometer(true)
                .setChronometerCountDown(true)
                .setContentIntent(contentIntent)
                .addAction(0, "Stop sharing", stopIntent)
                .build()
        }
    }
}

package im.zuno.chat

import android.net.ConnectivityManager
import android.net.Network
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

class NetworkAvailabilityStreamHandler(
    private val connectivityManager: ConnectivityManager,
) : EventChannel.StreamHandler {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var callback: ConnectivityManager.NetworkCallback? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        stop()
        val tracker = DefaultNetworkTracker<Network>()
        val networkCallback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) = onMain {
                events.success(tracker.onAvailable(network))
            }

            override fun onLost(network: Network) = onMain {
                tracker.onLost(network)?.let(events::success)
            }

            private fun onMain(block: () -> Unit) {
                mainHandler.post { if (callback === this) block() }
            }
        }
        callback = networkCallback
        if (connectivityManager.activeNetwork == null) events.success(false)
        connectivityManager.registerDefaultNetworkCallback(networkCallback)
    }

    override fun onCancel(arguments: Any?) = stop()

    fun stop() {
        callback?.let(connectivityManager::unregisterNetworkCallback)
        callback = null
    }
}

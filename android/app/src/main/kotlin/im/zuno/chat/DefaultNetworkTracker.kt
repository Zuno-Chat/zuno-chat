package im.zuno.chat

class DefaultNetworkTracker<T> {
    private var current: T? = null

    fun onAvailable(network: T): Boolean {
        current = network
        return true
    }

    fun onLost(network: T): Boolean? {
        if (network != current) return null
        current = null
        return false
    }
}

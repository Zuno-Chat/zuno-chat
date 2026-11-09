package im.zuno.chat.zuno_http

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class QuicSettingsTest {
    @Test
    fun `nothing goes out as 0-RTT early data`() {
        assertEquals(false, quicSettings().enableTlsZeroRtt)
    }

    @Test
    fun `every other QUIC setting keeps Cronet's default`() {
        val settings = quicSettings()

        assertNull(settings.idleConnectionTimeoutSeconds)
        assertNull(settings.closeSessionsOnIpChange)
        assertNull(settings.goawaySessionsOnIpChange)
        assertEquals(emptySet<String>(), settings.quicHostAllowlist)
        assertEquals(emptySet<String>(), settings.enabledQuicVersions)
    }
}

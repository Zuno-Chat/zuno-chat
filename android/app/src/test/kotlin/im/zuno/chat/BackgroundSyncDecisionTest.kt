package im.zuno.chat

import android.content.pm.ServiceInfo
import org.junit.Assert.assertEquals
import org.junit.Test

class BackgroundSyncDecisionTest {
    @Test
    fun `android 14 and later use a service type with no daily limit`() {
        assertEquals(ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE, BackgroundSyncDecision.foregroundServiceType(34))
        assertEquals(ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE, BackgroundSyncDecision.foregroundServiceType(36))
    }

    @Test
    fun `older versions keep data sync, which has no limit there`() {
        assertEquals(ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC, BackgroundSyncDecision.foregroundServiceType(33))
        assertEquals(ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC, BackgroundSyncDecision.foregroundServiceType(29))
    }
}

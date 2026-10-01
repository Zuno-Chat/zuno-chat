package im.zuno.chat

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PushEnginePluginsTest {
    @Test
    fun `push engines never get plugins with process-wide side effects`() {
        val names = PushEnginePlugins.names
        for (risky in listOf("flutter_webrtc", "geolocator", "unifiedpush", "audioplayers")) {
            assertFalse(risky, names.contains(risky))
        }
    }

    @Test
    fun `push engines get everything the push path calls`() {
        val names = PushEnginePlugins.names
        for (needed in listOf(
            "flutter_local_notifications",
            "flutter_secure_storage",
            "path_provider",
            "shared_preferences",
            "sqflite_sqlcipher",
            "package_info_plus",
            "zuno_call_style",
            "zuno_notifications",
            "zuno_vibration",
        )) {
            assertTrue(needed, names.contains(needed))
        }
    }
}

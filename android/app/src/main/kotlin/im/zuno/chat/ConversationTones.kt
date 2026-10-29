package im.zuno.chat

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.SoundPool
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

object ConversationToneDecision {
    fun plays(ringerMode: Int, audioMode: Int): Boolean =
        ringerMode == AudioManager.RINGER_MODE_NORMAL && audioMode == AudioManager.MODE_NORMAL
}

object ConversationTones {
    private const val CHANNEL = "zuno/conversation_tones"
    private var pool: Pool? = null

    fun register(messenger: BinaryMessenger, context: Context) {
        val app = context.applicationContext
        val pool = pool ?: Pool(app).also { pool = it }
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            val tone = call.argument<String>("tone")
            if (call.method != "play" || !pool.has(tone)) {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val audio = app.getSystemService(AudioManager::class.java)
            if (audio != null && ConversationToneDecision.plays(audio.ringerMode, audio.mode)) {
                pool.play(tone)
            }
            result.success(null)
        }
    }

    private class Pool(context: Context) {
        private val soundPool = SoundPool.Builder()
            .setMaxStreams(2)
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
            .build()
        private val loaded = mutableSetOf<Int>()

        init {
            soundPool.setOnLoadCompleteListener { _, id, status -> if (status == 0) loaded.add(id) }
        }

        private val sounds = mapOf(
            "incoming" to soundPool.load(context, R.raw.conversation_in, 1),
            "sent" to soundPool.load(context, R.raw.conversation_out, 1),
        )

        fun has(tone: String?): Boolean = tone in sounds

        fun play(tone: String?) {
            val id = sounds[tone] ?: return
            if (id in loaded) soundPool.play(id, 1f, 1f, 0, 0, 1f)
        }
    }
}

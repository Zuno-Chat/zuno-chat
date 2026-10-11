package im.zuno.chat

import android.os.Build

object SensitiveClipboardDecision {
    fun canRead(sdkInt: Int, focused: Boolean): Boolean = sdkInt < Build.VERSION_CODES.Q || focused

    fun clears(copied: String?, current: String?): Boolean = copied != null && current == copied
}

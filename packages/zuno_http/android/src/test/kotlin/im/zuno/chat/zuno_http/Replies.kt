package im.zuno.chat.zuno_http

import io.flutter.plugin.common.MethodChannel

internal data class Failure(val code: String, val details: Any? = null)

internal class Reply : MethodChannel.Result {
    val answers = mutableListOf<Any?>()

    val single: Any? get() = answers.single()

    override fun success(result: Any?) {
        answers += result
    }

    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
        answers += Failure(errorCode, errorDetails)
    }

    override fun notImplemented() {
        answers += "notImplemented"
    }
}

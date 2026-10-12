package im.zuno.chat

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ContentResolver
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.File
import java.io.FileNotFoundException
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class FileExportPlugin :
    FlutterPlugin,
    ActivityAware,
    MethodChannel.MethodCallHandler,
    PluginRegistry.ActivityResultListener {
    private class Pending(val source: File, val result: MethodChannel.Result)

    private val main = Handler(Looper.getMainLooper())
    private lateinit var resolver: ContentResolver
    private var channel: MethodChannel? = null
    private var activity: ActivityPluginBinding? = null
    private var pending: Pending? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        resolver = binding.applicationContext.contentResolver
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        cancelPending()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding
        binding.addActivityResultListener(this)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    override fun onDetachedFromActivityForConfigChanges() {
        activity?.removeActivityResultListener(this)
        activity = null
    }

    override fun onDetachedFromActivity() {
        onDetachedFromActivityForConfigChanges()
        cancelPending()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "exportFile") {
            result.notImplemented()
            return
        }
        val path = call.argument<String>("path")
        val mimeType = call.argument<String>("mimeType")
        val host = activity?.activity
        when {
            path == null || mimeType == null ->
                result.error("bad_args", "path and mimeType are required", null)

            !File(path).canRead() -> result.error("no_file", "nothing to export", null)

            host == null -> result.error("no_window", "nothing to present from", null)

            pending != null -> result.success(false)

            else -> present(host, File(path), mimeType, result)
        }
    }

    private fun present(
        host: Activity,
        source: File,
        mimeType: String,
        result: MethodChannel.Result,
    ) {
        val create = Intent(Intent.ACTION_CREATE_DOCUMENT)
            .addCategory(Intent.CATEGORY_OPENABLE)
            .setType(mimeType)
            .putExtra(Intent.EXTRA_TITLE, source.name)
        pending = Pending(source, result)
        try {
            host.startActivityForResult(create, REQUEST_CODE)
        } catch (error: ActivityNotFoundException) {
            pending = null
            result.error("no_picker", error.message, null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val pending = pending ?: return true
        this.pending = null
        val target = data?.data
        if (resultCode != Activity.RESULT_OK || target == null) {
            pending.result.success(false)
            return true
        }
        writes.execute {
            val failure = try {
                write(pending.source, target)
                null
            } catch (error: Exception) {
                runCatching { DocumentsContract.deleteDocument(resolver, target) }
                error
            }
            main.post {
                if (failure == null) {
                    pending.result.success(true)
                } else {
                    pending.result.error("write_failed", failure.message, null)
                }
            }
        }
        return true
    }

    private fun write(source: File, target: Uri) {
        val output = resolver.openOutputStream(target)
            ?: throw FileNotFoundException("the chosen file cannot be written")
        output.use { out -> source.inputStream().use { it.copyTo(out, BUFFER_BYTES) } }
    }

    private fun cancelPending() {
        pending?.result?.success(false)
        pending = null
    }

    companion object {
        private const val CHANNEL = "zuno/files"
        private const val REQUEST_CODE = 0x5A46
        private const val BUFFER_BYTES = 64 * 1024
        private val writes: ExecutorService = Executors.newSingleThreadExecutor()
    }
}

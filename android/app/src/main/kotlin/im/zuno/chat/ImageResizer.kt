package im.zuno.chat

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.os.Handler
import android.os.Looper
import androidx.exifinterface.media.ExifInterface
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

object ImageResizer {
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    fun resize(bytes: ByteArray, maxDimension: Int, quality: Int, onResult: (Map<String, Any>?) -> Unit) {
        executor.execute {
            val result = try {
                resizeNow(bytes, maxDimension, quality)
            } catch (error: Exception) {
                null
            } catch (error: OutOfMemoryError) {
                null
            }
            mainHandler.post { onResult(result) }
        }
    }

    private fun resizeNow(bytes: ByteArray, maxDimension: Int, quality: Int): Map<String, Any>? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        val png = bounds.outMimeType == "image/png"
        val target = ImageResizeDecision.targetSize(bounds.outWidth, bounds.outHeight, maxDimension)
        val options = BitmapFactory.Options().apply {
            inSampleSize = ImageResizeDecision.sampleSize(bounds.outWidth, bounds.outHeight, target)
        }
        val decoded = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options) ?: return null
        val upright = applyOrientation(decoded, orientationOf(bytes))
        return encodeScaled(upright, maxDimension, quality, png)
    }

    fun encodeScaled(bitmap: Bitmap, maxDimension: Int, quality: Int, png: Boolean): Map<String, Any>? {
        val target = ImageResizeDecision.targetSize(bitmap.width, bitmap.height, maxDimension)
        val scaled = if (bitmap.width == target.width && bitmap.height == target.height) {
            bitmap
        } else {
            Bitmap.createScaledBitmap(bitmap, target.width, target.height, true).also {
                if (it !== bitmap) bitmap.recycle()
            }
        }
        val out = ByteArrayOutputStream()
        val format = if (png) Bitmap.CompressFormat.PNG else Bitmap.CompressFormat.JPEG
        val ok = scaled.compress(format, quality, out)
        val width = scaled.width
        val height = scaled.height
        scaled.recycle()
        if (!ok) return null
        return mapOf(
            "bytes" to out.toByteArray(),
            "width" to width,
            "height" to height,
            "mimeType" to if (png) "image/png" else "image/jpeg",
        )
    }

    private fun orientationOf(bytes: ByteArray): Int = try {
        ExifInterface(ByteArrayInputStream(bytes))
            .getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
    } catch (error: Exception) {
        ExifInterface.ORIENTATION_NORMAL
    }

    private fun applyOrientation(bitmap: Bitmap, orientation: Int): Bitmap {
        val matrix = Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
            ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
            ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.postScale(-1f, 1f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.postScale(1f, -1f)
            ExifInterface.ORIENTATION_TRANSPOSE -> {
                matrix.postRotate(90f)
                matrix.postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_TRANSVERSE -> {
                matrix.postRotate(270f)
                matrix.postScale(-1f, 1f)
            }
            else -> return bitmap
        }
        val rotated = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
        if (rotated !== bitmap) bitmap.recycle()
        return rotated
    }
}

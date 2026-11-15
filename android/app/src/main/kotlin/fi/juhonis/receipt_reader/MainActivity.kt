package fi.juhonis.receipt_reader

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.app.Activity
import android.content.Intent
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val ocr = ReceiptOcr()
    private var pending: MethodChannel.Result? = null
    private val reader = Executors.newSingleThreadExecutor()
    private val requestImage = 4101
    private val maxBytes = 20 * 1024 * 1024

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "receipt_reader/ocr")
            .setMethodCallHandler { call, result ->
                if (call.method == "recognize") ocr.recognize(call.arguments as? ByteArray, result)
                else result.notImplemented()
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "receipt_reader/import")
            .setMethodCallHandler { call, result ->
                if (call.method != "pickImage") {
                    result.notImplemented()
                } else if (pending != null) {
                    result.error("busy", "Import already active", null)
                } else {
                    pending = result
                    try {
                        startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "image/*"
                            putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("image/jpeg", "image/png"))
                            putExtra(Intent.EXTRA_LOCAL_ONLY, true)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }, requestImage)
                    } catch (_: Exception) {
                        pending = null
                        result.error("read_failed", "Unable to open picker", null)
                    }
                }
            }
    }

    @Deprecated("Activity result compatibility with FlutterActivity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != requestImage) return
        val result = pending ?: return
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            pending = null
            result.success(null)
            return
        }
        // No cache file, persistent URI grant, filename logging, or write access.
        reader.execute {
            try {
                val bytes = contentResolver.openInputStream(uri)?.use { input ->
                    val output = ByteArrayOutputStream()
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        if (output.size() + count > maxBytes) throw ImageTooLarge()
                        output.write(buffer, 0, count)
                    }
                    output.toByteArray()
                } ?: throw IllegalStateException()
                runOnUiThread { pending = null; if (!isDestroyed) result.success(bytes) }
            } catch (_: ImageTooLarge) {
                runOnUiThread { pending = null; if (!isDestroyed) result.error("too_large", "Image exceeds limit", null) }
            } catch (_: Exception) {
                runOnUiThread { pending = null; if (!isDestroyed) result.error("read_failed", "Unable to read image", null) }
            }
        }
    }

    override fun onDestroy() {
        ocr.close()
        pending = null
        reader.shutdownNow()
        super.onDestroy()
    }

    private class ImageTooLarge : Exception()
}

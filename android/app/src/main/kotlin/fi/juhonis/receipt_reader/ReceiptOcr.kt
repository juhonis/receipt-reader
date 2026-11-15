package fi.juhonis.receipt_reader

import android.graphics.BitmapFactory
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

/** One in-memory request. No file paths, receipt logging, or model downloads. */
class ReceiptOcr {
    private var busy = false
    private var closed = false

    fun close() { closed = true }

    fun recognize(bytes: ByteArray?, result: MethodChannel.Result) {
        if (closed || busy) {
            result.error("busy", "Recognition unavailable", null)
            return
        }
        if (bytes == null || bytes.size > 100 * 1024 * 1024) {
            result.error("invalid_image", "Invalid image", null)
            return
        }
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0 ||
            bounds.outWidth > 12000 || bounds.outHeight > 12000 ||
            bounds.outWidth.toLong() * bounds.outHeight > 24000000) {
            result.error("invalid_image", "Invalid image dimensions", null)
            return
        }
        val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
        if (bitmap == null) {
            result.error("invalid_image", "Unable to decode image", null)
            return
        }
        busy = true
        val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
        try {
            recognizer.process(InputImage.fromBitmap(bitmap, 0))
                .addOnCompleteListener { task ->
                    try {
                        if (!closed) {
                            if (!task.isSuccessful) {
                                result.error("ocr_failed", "Recognition failed", null)
                            } else {
                                val blocks = JSONArray()
                                for (block in task.result.textBlocks) {
                                    val lines = JSONArray()
                                    for (line in block.lines) {
                                        val words = JSONArray()
                                        for (word in line.elements) {
                                            val box = word.boundingBox ?: throw IllegalStateException()
                                            words.put(JSONObject().put("text", word.text).put("box",
                                                JSONObject().put("left", box.left).put("top", box.top)
                                                    .put("right", box.right).put("bottom", box.bottom)))
                                        }
                                        lines.put(JSONObject().put("words", words))
                                    }
                                    blocks.put(JSONObject().put("lines", lines))
                                }
                                result.success(JSONObject().put("schemaVersion", 1).put("image",
                                    JSONObject().put("width", bitmap.width).put("height", bitmap.height)
                                        .put("orientation", "upright")).put("blocks", blocks).toString())
                            }
                        }
                    } catch (_: Exception) {
                        if (!closed) result.error("ocr_failed", "Invalid recognition result", null)
                    } finally {
                        recognizer.close()
                        bitmap.recycle()
                        busy = false
                    }
                }
        } catch (_: Exception) {
            recognizer.close()
            bitmap.recycle()
            busy = false
            if (!closed) result.error("ocr_failed", "Recognition failed", null)
        }
    }
}

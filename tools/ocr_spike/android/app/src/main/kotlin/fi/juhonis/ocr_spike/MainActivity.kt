package fi.juhonis.ocr_spike

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.googlecode.tesseract.android.TessBaseAPI
import android.graphics.BitmapFactory
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val worker = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ocr_spike/tesseract")
            .setMethodCallHandler { call, result ->
                if (call.method != "recognize") {
                    result.notImplemented()
                } else {
                    worker.execute {
                        try {
                            recognize()
                            runOnUiThread { result.success(null) }
                        } catch (_: Exception) {
                            // No native exception or receipt text in shared Android logs.
                            runOnUiThread { result.error("tesseract_failed", "Native OCR failed", null) }
                        }
                    }
                }
            }
    }

    private fun box(bounds: IntArray) = JSONObject()
        .put("left", bounds[0]).put("top", bounds[1])
        .put("right", bounds[2]).put("bottom", bounds[3])

    private fun recognize() {
        val dataRoot = File(filesDir, "tesseract")
        val data = File(dataRoot, "tessdata").apply { mkdirs() }
        for (language in listOf("fin", "eng")) {
            assets.open("tessdata/$language.traineddata").use { input ->
                File(data, "$language.traineddata").outputStream().use { input.copyTo(it) }
            }
        }
        val api = TessBaseAPI()
        try {
            check(api.init(dataRoot.absolutePath, "fin+eng", TessBaseAPI.OEM_LSTM_ONLY))
            val inputs = File(filesDir, "inputs").listFiles { f -> f.extension == "png" }
                ?.sortedBy { it.name } ?: error("Missing inputs")
            check(inputs.isNotEmpty())
            val output = File(filesDir, "results").apply { mkdirs() }
            for (psm in listOf(3, 6)) {
                api.setPageSegMode(psm)
                for (input in inputs) {
                    val bitmap = BitmapFactory.decodeFile(input.absolutePath) ?: error("Invalid PNG")
                    try {
                        val started = System.nanoTime()
                        api.setImage(bitmap)
                        val text = api.getUTF8Text()
                        val elapsed = (System.nanoTime() - started) / 1_000_000
                        val blocks = JSONArray()
                        val iterator = api.getResultIterator()
                        if (iterator != null) {
                            try {
                                iterator.begin()
                                var block: JSONObject? = null
                                var line: JSONObject? = null
                                do {
                                    val word = iterator.getUTF8Text(3)?.trim().orEmpty()
                                    if (word.isEmpty()) continue
                                    if (block == null || iterator.isAtBeginningOf(0)) {
                                        block = JSONObject().put("text", iterator.getUTF8Text(0))
                                            .put("box", box(iterator.getBoundingBox(0)))
                                            .put("lines", JSONArray())
                                        blocks.put(block)
                                        line = null
                                    }
                                    if (line == null || iterator.isAtBeginningOf(2)) {
                                        line = JSONObject().put("text", iterator.getUTF8Text(2))
                                            .put("box", box(iterator.getBoundingBox(2)))
                                            .put("words", JSONArray())
                                        block.getJSONArray("lines").put(line)
                                    }
                                    line.getJSONArray("words").put(JSONObject().put("text", word)
                                        .put("box", box(iterator.getBoundingBox(3)))
                                        .put("corners", JSONObject.NULL))
                                } while (iterator.next(3))
                            } finally {
                                iterator.delete()
                            }
                        }
                        val result = JSONObject().put("schemaVersion", 1)
                            .put("sampleId", input.nameWithoutExtension)
                            .put("engine", "tesseract-${api.getVersion()}")
                            .put("adapterVersion", "tesseract4android-4.9.0")
                            .put("configuration", JSONObject().put("psm", psm).put("languages", "fin+eng"))
                            .put("image", JSONObject().put("width", bitmap.width)
                                .put("height", bitmap.height).put("orientation", "upright"))
                            .put("elapsedMs", elapsed).put("text", text).put("blocks", blocks)
                        File(output, "${input.nameWithoutExtension}-psm$psm.json").writeText(result.toString())
                        api.clear()
                    } finally {
                        bitmap.recycle()
                    }
                }
            }
        } finally {
            api.recycle()
        }
    }

    override fun onDestroy() {
        worker.shutdown()
        super.onDestroy()
    }
}

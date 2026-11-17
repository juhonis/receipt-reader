package fi.juhonis.receipt_reader

import android.app.Activity
import android.content.Intent
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

/** SAF access grants only: no paths, passwords, plaintext files or persistent grants. */
class BackupDocuments(private val activity: Activity) {
    private val worker = Executors.newSingleThreadExecutor()
    private var pending: MethodChannel.Result? = null
    private var output: ByteArray? = null
    private val maxBytes = 64 * 1024 * 1024 + 54

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "read" && call.method != "write") { result.notImplemented(); return }
        if (pending != null) { result.error("busy", "Backup operation active", null); return }
        val writing = call.method == "write"
        val bytes = if (writing) call.arguments as? ByteArray else null
        if (writing && (bytes == null || bytes.size > maxBytes || bytes.size < 54 ||
            !bytes.copyOfRange(0, 8).contentEquals("RRBACKUP".toByteArray(Charsets.US_ASCII)))) {
            result.error("invalid_backup", "Invalid backup", null); return
        }
        pending = result
        output = bytes
        try {
            val intent = Intent(if (writing) Intent.ACTION_CREATE_DOCUMENT else Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = if (writing) "application/octet-stream" else "*/*"
                putExtra(Intent.EXTRA_LOCAL_ONLY, true)
                addFlags(if (writing) Intent.FLAG_GRANT_WRITE_URI_PERMISSION else Intent.FLAG_GRANT_READ_URI_PERMISSION)
                if (writing) putExtra(Intent.EXTRA_TITLE, "receipts-${System.currentTimeMillis()}.rrbackup")
            }
            activity.startActivityForResult(intent, if (writing) 4202 else 4201)
        } catch (_: Exception) {
            pending = null; output = null
            result.error("backup_file", "Unable to open backup picker", null)
        }
    }

    fun onResult(request: Int, resultCode: Int, data: Intent?): Boolean {
        if (request != 4201 && request != 4202) return false
        val result = pending ?: return true
        val bytes = output
        output = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            pending = null; result.success(if (request == 4202) false else null); return true
        }
        worker.execute {
            try {
                val value: Any = if (request == 4202) {
                    activity.contentResolver.openOutputStream(uri, "w")?.use { stream ->
                        stream.write(bytes ?: throw IllegalStateException()); stream.flush()
                    } ?: throw IllegalStateException()
                    true
                } else {
                    activity.contentResolver.openInputStream(uri)?.use { stream ->
                        val buffer = ByteArray(64 * 1024)
                        val read = ByteArrayOutputStream()
                        while (true) {
                            val n = stream.read(buffer)
                            if (n < 0) break
                            if (read.size() + n > maxBytes) throw TooLarge()
                            read.write(buffer, 0, n)
                        }
                        read.toByteArray()
                    } ?: throw IllegalStateException()
                }
                activity.runOnUiThread { pending = null; if (!activity.isDestroyed) result.success(value) }
            } catch (_: TooLarge) {
                activity.runOnUiThread { pending = null; if (!activity.isDestroyed) result.error("too_large", "Backup exceeds limit", null) }
            } catch (_: Exception) {
                activity.runOnUiThread { pending = null; if (!activity.isDestroyed) result.error("backup_file", "Unable to access backup", null) }
            }
        }
        return true
    }

    fun close() { pending = null; output = null; worker.shutdownNow() }
    private class TooLarge : Exception()
}
package fi.juhonis.receipt_reader

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

// Activity results cannot carry multi-megabyte photos. This process-only handoff
// never writes a file, saved-instance state, intent image extra or MediaStore row.
internal object CameraMemory {
    data class Outcome(val bytes: ByteArray? = null, val error: String? = null)
    private var token: String? = null
    private var outcome: Outcome? = null

    @Synchronized fun begin(): String? {
        if (token != null) return null
        return UUID.randomUUID().toString().also { token = it }
    }
    @Synchronized fun active(id: String) = token == id
    @Synchronized fun complete(id: String, value: Outcome): Boolean {
        if (token != id || outcome != null) return false
        outcome = value
        return true
    }
    @Synchronized fun take(id: String): Outcome? {
        if (token != id) return null
        val value = outcome
        token = null
        outcome = null
        return value
    }
    @Synchronized fun clear(id: String) {
        take(id)?.bytes?.fill(0)
    }
}

internal class ReceiptCamera(private val activity: Activity) {
    private var pending: MethodChannel.Result? = null
    private var token: String? = null
    val active get() = pending != null

    fun capture(result: MethodChannel.Result) {
        if (active) {
            result.error("busy", "Capture already active", null)
            return
        }
        pending = result
        try {
            if (activity.checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
                activity.requestPermissions(arrayOf(Manifest.permission.CAMERA), permissionRequest)
            } else launch()
        } catch (_: Exception) { fail("camera_unavailable") }
    }

    fun onPermissionResult(requestCode: Int, grants: IntArray): Boolean {
        if (requestCode != permissionRequest) return false
        if (grants.firstOrNull() == PackageManager.PERMISSION_GRANTED) launch()
        else fail("camera_denied")
        return true
    }

    private fun launch() {
        if (pending == null || activity.isFinishing || activity.isDestroyed) {
            close()
            return
        }
        val id = CameraMemory.begin()
        if (id == null) {
            fail("busy")
            return
        }
        token = id
        try {
            activity.startActivityForResult(
                Intent(activity, ReceiptCameraActivity::class.java).putExtra("captureToken", id), captureRequest)
        } catch (_: Exception) {
            CameraMemory.clear(id)
            token = null
            fail("camera_unavailable")
        }
    }

    fun onResult(requestCode: Int): Boolean {
        if (requestCode != captureRequest) return false
        val value = token?.let { CameraMemory.take(it) }
        token = null
        val result = pending
        pending = null
        try {
            if (value?.error != null) result?.error(value.error, "Capture unavailable", null)
            else result?.success(value?.bytes)
        } finally {
            // MethodChannel encodes synchronously; Flutter owns its independent copy.
            value?.bytes?.fill(0)
        }
        return true
    }

    private fun fail(code: String) {
        val result = pending
        pending = null
        result?.error(code, "Capture unavailable", null)
    }

    fun close() {
        token?.let { CameraMemory.clear(it) }
        token = null
        pending = null
    }

    companion object {
        private const val permissionRequest = 4102
        private const val captureRequest = 4103
    }
}

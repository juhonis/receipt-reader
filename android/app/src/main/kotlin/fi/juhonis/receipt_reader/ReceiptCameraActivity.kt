package fi.juhonis.receipt_reader

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.ImageFormat
import android.graphics.Matrix
import android.graphics.SurfaceTexture
import android.hardware.camera2.*
import android.media.ImageReader
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Size
import android.view.*
import android.widget.*
import kotlin.math.abs
import kotlin.math.min

/** App-owned camera preview and bounded, in-memory JPEG capture. No storage APIs. */
class ReceiptCameraActivity : Activity(), TextureView.SurfaceTextureListener {
    private val main = Handler(Looper.getMainLooper())
    private lateinit var token: String
    private lateinit var preview: TextureView
    private lateinit var shutter: Button
    private lateinit var light: Button
    private lateinit var status: TextView
    private var camera: CameraDevice? = null
    private var session: CameraCaptureSession? = null
    private var images: ImageReader? = null
    private var previewSurface: Surface? = null
    private var previewSize = Size(640, 480)
    private var characteristics: CameraCharacteristics? = null
    private var opening = false
    private var capturing = false
    private var torch = false
    private var resumed = false
    private var generation = 0
    private var captureTimeout: Runnable? = null
    private var deviceOrientation = 0
    private var orientation: OrientationEventListener? = null

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        token = intent.getStringExtra("captureToken") ?: ""
        if (!CameraMemory.active(token)) { finish(); return }
        // Do not let Android retain camera preview pixels in the recents thumbnail.
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        val root = LinearLayout(this).apply {
            this.orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.BLACK)
            setOnApplyWindowInsetsListener { view, insets ->
                if (android.os.Build.VERSION.SDK_INT >= 30) {
                    val bars = insets.getInsets(WindowInsets.Type.systemBars() or WindowInsets.Type.displayCutout())
                    view.setPadding(bars.left, bars.top, bars.right, bars.bottom)
                } else {
                    @Suppress("DEPRECATION")
                    view.setPadding(insets.systemWindowInsetLeft, insets.systemWindowInsetTop,
                        insets.systemWindowInsetRight, insets.systemWindowInsetBottom)
                }
                insets
            }
        }
        status = TextView(this).apply {
            setTextColor(Color.WHITE)
            textSize = 16f
            gravity = Gravity.CENTER
            setPadding(20, 16, 20, 16)
            text = getString(R.string.camera_hint)
        }
        root.addView(status)
        preview = TextureView(this).apply { surfaceTextureListener = this@ReceiptCameraActivity }
        root.addView(preview, LinearLayout.LayoutParams(-1, 0, 1f))
        val controls = LinearLayout(this).apply {
            gravity = Gravity.CENTER
            setPadding(12, 12, 12, 12)
        }
        controls.addView(Button(this).apply {
            text = getString(R.string.camera_cancel)
            setOnClickListener { finish() }
        }, LinearLayout.LayoutParams(0, -2, 1f))
        shutter = Button(this).apply {
            text = getString(R.string.camera_capture)
            isEnabled = false
            setOnClickListener { capture() }
        }
        controls.addView(shutter, LinearLayout.LayoutParams(0, -2, 1f))
        light = Button(this).apply {
            text = getString(R.string.camera_light_off)
            isEnabled = false
            setOnClickListener {
                torch = !torch
                text = getString(if (torch) R.string.camera_light_on else R.string.camera_light_off)
                repeatPreview()
            }
        }
        controls.addView(light, LinearLayout.LayoutParams(0, -2, 1f))
        root.addView(controls)
        setContentView(root)
        orientation = object : OrientationEventListener(this) {
            override fun onOrientationChanged(value: Int) {
                if (value != ORIENTATION_UNKNOWN) deviceOrientation = ((value + 45) / 90 * 90) % 360
            }
        }
    }

    override fun onResume() {
        super.onResume()
        if (!::preview.isInitialized) return
        resumed = true
        orientation?.enable()
        if (preview.isAvailable) openCamera()
    }

    override fun onPause() {
        resumed = false
        orientation?.disable()
        closeCamera()
        // Leaving capture cancels it rather than keeping a background camera/photo.
        if (!isFinishing) finish()
        super.onPause()
    }

    override fun onDestroy() {
        closeCamera()
        orientation?.disable()
        super.onDestroy()
    }

    override fun finish() {
        if (::token.isInitialized) CameraMemory.complete(token, CameraMemory.Outcome())
        super.finish()
    }

    override fun onConfigurationChanged(config: Configuration) {
        super.onConfigurationChanged(config)
        preview.post { transform() }
    }

    private fun complete(value: CameraMemory.Outcome) {
        if (!CameraMemory.complete(token, value)) value.bytes?.fill(0)
        finish()
    }

    private fun openCamera() {
        if (!resumed || opening || camera != null || isFinishing) return
        if (checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            complete(CameraMemory.Outcome(error = "camera_denied")); return
        }
        opening = true
        val attempt = ++generation
        try {
            val manager = getSystemService(CAMERA_SERVICE) as CameraManager
            val id = manager.cameraIdList.firstOrNull {
                manager.getCameraCharacteristics(it).get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_BACK
            } ?: throw IllegalStateException()
            val info = manager.getCameraCharacteristics(id)
            characteristics = info
            val map = info.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP) ?: throw IllegalStateException()
            val jpeg = map.getOutputSizes(ImageFormat.JPEG).filter {
                it.width.toLong() * it.height <= 12_000_000 && it.width <= 12000 && it.height <= 12000
            }.maxByOrNull { it.width.toLong() * it.height } ?: throw IllegalStateException()
            val ratio = jpeg.width.toDouble() / jpeg.height
            previewSize = map.getOutputSizes(SurfaceTexture::class.java).filter {
                it.width <= 1920 && it.height <= 1440
            }.minByOrNull {
                abs(it.width.toDouble() / it.height - ratio) * 10000 + abs(it.width - 1280)
            } ?: throw IllegalStateException()
            images = ImageReader.newInstance(jpeg.width, jpeg.height, ImageFormat.JPEG, 1).apply {
                setOnImageAvailableListener({ reader ->
                    try {
                        val bytes = reader.acquireNextImage()?.use { image ->
                            val buffer = image.planes[0].buffer
                            if (buffer.remaining() > 20 * 1024 * 1024) throw IllegalArgumentException()
                            ByteArray(buffer.remaining()).also { buffer.get(it) }
                        } ?: return@setOnImageAvailableListener
                        if (resumed && capturing && !isFinishing) complete(CameraMemory.Outcome(bytes))
                        else bytes.fill(0)
                    } catch (_: Exception) {
                        if (resumed && !isFinishing) complete(CameraMemory.Outcome(error = "capture_failed"))
                    }
                }, main)
            }
            manager.openCamera(id, object : CameraDevice.StateCallback() {
                override fun onOpened(device: CameraDevice) {
                    if (!resumed || isFinishing || generation != attempt || !preview.isAvailable) {
                        device.close(); return
                    }
                    opening = false
                    camera = device
                    try { startPreview() } catch (_: Exception) { unavailable() }
                }
                override fun onDisconnected(device: CameraDevice) {
                    device.close(); if (generation == attempt) unavailable()
                }
                override fun onError(device: CameraDevice, error: Int) {
                    device.close(); if (generation == attempt) unavailable()
                }
            }, main)
        } catch (_: Exception) { unavailable() }
    }

    @Suppress("DEPRECATION")
    private fun startPreview() {
        val device = camera ?: return
        val texture = preview.surfaceTexture ?: throw IllegalStateException()
        texture.setDefaultBufferSize(previewSize.width, previewSize.height)
        val surface = Surface(texture)
        previewSurface = surface
        transform()
        device.createCaptureSession(listOf(surface, images!!.surface), object : CameraCaptureSession.StateCallback() {
            override fun onConfigured(value: CameraCaptureSession) {
                if (!resumed || isFinishing || camera !== device || previewSurface !== surface) {
                    value.close(); return
                }
                session = value
                repeatPreview()
            }
            override fun onConfigureFailed(value: CameraCaptureSession) { value.close(); unavailable() }
        }, main)
    }

    private fun settings(request: CaptureRequest.Builder) {
        request.set(CaptureRequest.CONTROL_MODE, CaptureRequest.CONTROL_MODE_AUTO)
        val modes = characteristics?.get(CameraCharacteristics.CONTROL_AF_AVAILABLE_MODES)
        if (modes?.contains(CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE) == true) {
            request.set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE)
        }
        request.set(CaptureRequest.CONTROL_AE_MODE, CaptureRequest.CONTROL_AE_MODE_ON)
        request.set(CaptureRequest.FLASH_MODE, if (torch) CaptureRequest.FLASH_MODE_TORCH else CaptureRequest.FLASH_MODE_OFF)
    }

    private fun repeatPreview() {
        try {
            val request = camera?.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW) ?: return
            request.addTarget(previewSurface ?: return)
            settings(request)
            session?.setRepeatingRequest(request.build(), object : CameraCaptureSession.CaptureCallback() {
                override fun onCaptureCompleted(value: CameraCaptureSession, request: CaptureRequest, result: TotalCaptureResult) {
                    if (!capturing && resumed && !isFinishing) {
                        shutter.isEnabled = true
                        light.isEnabled = characteristics?.get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
                    }
                }
            }, main)
        } catch (_: Exception) { unavailable() }
    }

    private fun capture() {
        if (capturing || camera == null || session == null) return
        capturing = true
        shutter.isEnabled = false
        light.isEnabled = false
        status.text = getString(R.string.camera_capturing)
        try {
            val request = camera!!.createCaptureRequest(CameraDevice.TEMPLATE_STILL_CAPTURE)
            request.addTarget(images!!.surface)
            settings(request)
            val sensor = characteristics?.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 0
            request.set(CaptureRequest.JPEG_ORIENTATION, (sensor + deviceOrientation) % 360)
            request.set(CaptureRequest.JPEG_QUALITY, 95.toByte())
            session!!.capture(request.build(), object : CameraCaptureSession.CaptureCallback() {
                override fun onCaptureFailed(value: CameraCaptureSession, request: CaptureRequest, failure: CaptureFailure) {
                    if (resumed && !isFinishing) complete(CameraMemory.Outcome(error = "capture_failed"))
                }
            }, main)
            captureTimeout = Runnable {
                if (capturing && resumed && !isFinishing) complete(CameraMemory.Outcome(error = "capture_failed"))
            }.also { main.postDelayed(it, 15000) }
        } catch (_: Exception) { complete(CameraMemory.Outcome(error = "capture_failed")) }
    }

    @Suppress("DEPRECATION")
    private fun transform() {
        if (preview.width == 0 || preview.height == 0) return
        val degrees = when (windowManager.defaultDisplay.rotation) {
            Surface.ROTATION_90 -> 90
            Surface.ROTATION_180 -> 180
            Surface.ROTATION_270 -> 270
            else -> 0
        }
        // Camera2's SurfaceTexture producer already applies sensor orientation.
        // Undo the TextureView stretch in those upright coordinates, then account
        // only for display rotation. Applying sensor rotation here rotates twice.
        val sensor = characteristics?.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 90
        val naturalWidth = if (sensor % 180 != 0) previewSize.height else previewSize.width
        val naturalHeight = if (sensor % 180 != 0) previewSize.width else previewSize.height
        val rotation = (360 - degrees) % 360
        val swapped = rotation % 180 != 0
        val width = if (swapped) naturalHeight else naturalWidth
        val height = if (swapped) naturalWidth else naturalHeight
        val scale = min(preview.width.toFloat() / width, preview.height.toFloat() / height)
        preview.setTransform(Matrix().apply {
            setScale(naturalWidth.toFloat() / preview.width, naturalHeight.toFloat() / preview.height)
            postTranslate(-naturalWidth / 2f, -naturalHeight / 2f)
            postRotate(rotation.toFloat())
            postScale(scale, scale)
            postTranslate(preview.width / 2f, preview.height / 2f)
        })
    }

    private fun unavailable() {
        opening = false
        if (resumed && !isFinishing) complete(CameraMemory.Outcome(error = "camera_unavailable"))
    }

    private fun closeCamera() {
        generation++
        captureTimeout?.let { main.removeCallbacks(it) }
        captureTimeout = null
        if (::shutter.isInitialized) shutter.isEnabled = false
        try { session?.close() } catch (_: Exception) { }
        session = null
        camera?.close()
        camera = null
        images?.close()
        images = null
        previewSurface?.release()
        previewSurface = null
        opening = false
    }

    override fun onSurfaceTextureAvailable(texture: SurfaceTexture, width: Int, height: Int) = openCamera()
    override fun onSurfaceTextureSizeChanged(texture: SurfaceTexture, width: Int, height: Int) = transform()
    override fun onSurfaceTextureDestroyed(texture: SurfaceTexture): Boolean {
        val interrupted = capturing
        closeCamera()
        if (interrupted && resumed && !isFinishing) complete(CameraMemory.Outcome(error = "capture_failed"))
        return true
    }
    override fun onSurfaceTextureUpdated(texture: SurfaceTexture) { }
}

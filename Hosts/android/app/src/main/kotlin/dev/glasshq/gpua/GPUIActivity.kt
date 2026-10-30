package dev.glasshq.gpua

import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.view.Choreographer
import android.view.KeyEvent
import android.view.Surface
import android.view.WindowManager
import java.lang.ref.WeakReference
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * JNI bridge singleton binding the Kotlin Activity/SurfaceView shell to the Swift
 * `GPUIAndroid` shared library (`@_cdecl("Java_dev_glasshq_gpua_GPUINative_*")`).
 */
object GPUINative {
    private var librariesLoaded = false
    internal var activeActivityRef: WeakReference<GPUIActivity>? = null

    fun ensureLoaded(libraryName: String = "GPUIAndroid") {
        if (librariesLoaded) return
        synchronized(this) {
            if (librariesLoaded) return
            try {
                System.loadLibrary("wgpu_native")
            } catch (_: UnsatisfiedLinkError) {
                // Linked statically or bundled inside the primary Swift shared library.
            }
            System.loadLibrary(libraryName)
            librariesLoaded = true
        }
    }

    // Lifecycle phase constants matching `AndroidLifecyclePhase` in `Sources/GPUIAndroid/lifecycle.swift`.
    const val LIFECYCLE_CREATED: Int = 0
    const val LIFECYCLE_STARTED: Int = 1
    const val LIFECYCLE_RESUMED: Int = 2
    const val LIFECYCLE_PAUSED: Int = 3
    const val LIFECYCLE_STOPPED: Int = 4
    const val LIFECYCLE_DESTROYED: Int = 5

    @JvmStatic
    external fun nativeInit(
        density: Float,
        widthPx: Int,
        heightPx: Int,
        refreshRateHz: Float
    )

    @JvmStatic
    external fun nativeOnSurfaceCreated(
        surface: Surface,
        widthPx: Int,
        heightPx: Int,
        format: Int
    )

    @JvmStatic
    external fun nativeOnSurfaceChanged(
        format: Int,
        widthPx: Int,
        heightPx: Int,
        density: Float,
        refreshRateHz: Float
    )

    @JvmStatic
    external fun nativeOnSurfaceDestroyed()

    @JvmStatic
    external fun nativeOnTouchEvent(
        action: Int,
        pointerIds: IntArray,
        xs: FloatArray,
        ys: FloatArray,
        pressures: FloatArray,
        toolTypes: IntArray,
        metaState: Int,
        buttonState: Int,
        vScroll: Float,
        hScroll: Float,
        eventTimeMillis: Long
    )

    @JvmStatic
    external fun nativeOnKeyEvent(
        action: Int,
        keyCode: Int,
        metaState: Int,
        repeatCount: Int,
        unicodeChar: Int,
        scanCode: Int
    ): Boolean

    @JvmStatic
    external fun nativeOnInsetsChanged(
        topPx: Int,
        leftPx: Int,
        bottomPx: Int,
        rightPx: Int
    )

    @JvmStatic
    external fun nativeOnAppearanceChanged(isDark: Boolean)

    @JvmStatic
    external fun nativeOnLifecycleState(state: Int)

    @JvmStatic
    external fun nativeOnFrame(frameTimeNanos: Long)

    @JvmStatic
    external fun nativeCommitText(text: String)

    @JvmStatic
    external fun nativeDeleteSurroundingText(beforeLength: Int, afterLength: Int)

    @JvmStatic
    external fun nativeOnThermalStatusChanged(status: Int)

    @JvmStatic
    external fun nativeOnOpenUrl(url: String)

    // MARK: - Host Upcalls Invoked from CAndroidSys (`candroid_host_*`)

    @JvmStatic
    fun hostSetClipboardText(text: String) {
        val activity = activeActivityRef?.get() ?: return
        activity.runOnUiThread {
            val clipboard = activity.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
            clipboard?.setPrimaryClip(ClipData.newPlainText("GPUA", text))
        }
    }

    @JvmStatic
    fun hostGetClipboardText(): String? {
        val activity = activeActivityRef?.get() ?: return null
        val clipboard = activity.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
            ?: return null
        val clip = clipboard.primaryClip ?: return null
        if (clip.itemCount <= 0) return null
        return clip.getItemAt(0)?.coerceToText(activity)?.toString()
    }

    @JvmStatic
    fun hostOpenUrl(url: String) {
        val activity = activeActivityRef?.get() ?: return
        activity.runOnUiThread {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            runCatching { activity.startActivity(intent) }
        }
    }

    @JvmStatic
    fun hostSetImeVisible(visible: Boolean) {
        val activity = activeActivityRef?.get() ?: return
        activity.runOnUiThread {
            activity.surfaceView?.setSoftKeyboardVisible(visible)
        }
    }

    @JvmStatic
    fun hostRequestFrame() {
        val activity = activeActivityRef?.get() ?: return
        activity.runOnUiThread {
            activity.scheduleVsyncFrame()
        }
    }

    @JvmStatic
    fun hostFinishActivity() {
        val activity = activeActivityRef?.get() ?: return
        activity.runOnUiThread {
            activity.finish()
        }
    }

    private const val KEYSTORE_ALIAS = "dev.glasshq.gpua.credentials.aes256"
    private const val CREDENTIAL_PREFS = "dev.glasshq.gpua.credentials"

    private fun getOrCreateCredentialKey(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (keyStore.getKey(KEYSTORE_ALIAS, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(
                KEYSTORE_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build()
        )
        return generator.generateKey()
    }

    @JvmStatic
    fun hostWriteCredential(url: String, username: String, passwordBase64: String): Boolean {
        val activity = activeActivityRef?.get() ?: return false
        return runCatching {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, getOrCreateCredentialKey())
            val payload = "$username\n$passwordBase64".toByteArray(Charsets.UTF_8)
            val encrypted = cipher.doFinal(payload)
            val combined = Base64.encodeToString(cipher.iv, Base64.NO_WRAP) + ":" +
                Base64.encodeToString(encrypted, Base64.NO_WRAP)
            activity.getSharedPreferences(CREDENTIAL_PREFS, Context.MODE_PRIVATE)
                .edit()
                .putString(url, combined)
                .commit()
        }.getOrDefault(false)
    }

    @JvmStatic
    fun hostReadCredential(url: String): Array<String>? {
        val activity = activeActivityRef?.get() ?: return null
        return runCatching {
            val stored = activity.getSharedPreferences(CREDENTIAL_PREFS, Context.MODE_PRIVATE)
                .getString(url, null) ?: return null
            val sep = stored.indexOf(':')
            if (sep <= 0) return null
            val iv = Base64.decode(stored.substring(0, sep), Base64.NO_WRAP)
            val ciphertext = Base64.decode(stored.substring(sep + 1), Base64.NO_WRAP)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, getOrCreateCredentialKey(), GCMParameterSpec(128, iv))
            val decoded = String(cipher.doFinal(ciphertext), Charsets.UTF_8)
            val newline = decoded.indexOf('\n')
            if (newline < 0) return null
            arrayOf(decoded.substring(0, newline), decoded.substring(newline + 1))
        }.getOrNull()
    }

    @JvmStatic
    fun hostDeleteCredential(url: String): Boolean {
        val activity = activeActivityRef?.get() ?: return false
        return runCatching {
            activity.getSharedPreferences(CREDENTIAL_PREFS, Context.MODE_PRIVATE)
                .edit()
                .remove(url)
                .commit()
        }.getOrDefault(false)
    }
}

/**
 * Thin Android Activity shell hosting [GPUISurfaceView] and forwarding lifecycle,
 * edge-to-edge display metrics, dark-mode configuration, thermal status, and deep links to Swift.
 */
class GPUIActivity : Activity(), Choreographer.FrameCallback {
    internal var surfaceView: GPUISurfaceView? = null
    private var frameCallbackPending: Boolean = false
    private var thermalListener: PowerManager.OnThermalStatusChangedListener? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Enable edge-to-edge drawing; safe-area insets are forwarded to GPUI via GPUISurfaceView.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.setDecorFitsSystemWindows(false)
            window.attributes.layoutInDisplayCutoutMode =
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
        } else {
            window.attributes.layoutInDisplayCutoutMode =
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        }

        GPUINative.ensureLoaded()
        GPUINative.activeActivityRef = WeakReference(this)

        val dm = resources.displayMetrics
        val refreshRate = currentDisplayRefreshRateHz()
        GPUINative.nativeInit(dm.density, dm.widthPixels, dm.heightPixels, refreshRate)
        GPUINative.nativeOnAppearanceChanged(isSystemDarkTheme(resources.configuration))
        GPUINative.nativeOnLifecycleState(GPUINative.LIFECYCLE_CREATED)

        val view = GPUISurfaceView(this)
        surfaceView = view
        setContentView(view)

        registerThermalObserver()
        forwardIntentUrlIfPresent(intent)
    }

    override fun onNewIntent(intent: Intent?) {
        super.onNewIntent(intent)
        setIntent(intent)
        forwardIntentUrlIfPresent(intent)
    }

    override fun onStart() {
        super.onStart()
        GPUINative.nativeOnLifecycleState(GPUINative.LIFECYCLE_STARTED)
    }

    override fun onResume() {
        super.onResume()
        surfaceView?.requestFocus()
        GPUINative.nativeOnLifecycleState(GPUINative.LIFECYCLE_RESUMED)
        scheduleVsyncFrame()
    }

    override fun onPause() {
        GPUINative.nativeOnLifecycleState(GPUINative.LIFECYCLE_PAUSED)
        super.onPause()
    }

    override fun onStop() {
        GPUINative.nativeOnLifecycleState(GPUINative.LIFECYCLE_STOPPED)
        super.onStop()
    }

    override fun onDestroy() {
        unregisterThermalObserver()
        if (frameCallbackPending) {
            Choreographer.getInstance().removeFrameCallback(this)
            frameCallbackPending = false
        }
        GPUINative.nativeOnLifecycleState(GPUINative.LIFECYCLE_DESTROYED)
        if (GPUINative.activeActivityRef?.get() === this) {
            GPUINative.activeActivityRef = null
        }
        surfaceView = null
        super.onDestroy()
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        GPUINative.nativeOnAppearanceChanged(isSystemDarkTheme(newConfig))
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val handled = GPUINative.nativeOnKeyEvent(
            event.action,
            event.keyCode,
            event.metaState,
            event.repeatCount,
            event.unicodeChar,
            event.scanCode
        )
        return if (handled) true else super.dispatchKeyEvent(event)
    }

    internal fun scheduleVsyncFrame() {
        if (!frameCallbackPending) {
            frameCallbackPending = true
            Choreographer.getInstance().postFrameCallback(this)
        }
    }

    override fun doFrame(frameTimeNanos: Long) {
        frameCallbackPending = false
        GPUINative.nativeOnFrame(frameTimeNanos)
    }

    internal fun currentDisplayRefreshRateHz(): Float {
        val display = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            this.display
        } else {
            @Suppress("DEPRECATION")
            windowManager.defaultDisplay
        }
        return display?.refreshRate ?: 60.0f
    }

    private fun isSystemDarkTheme(config: Configuration): Boolean {
        val nightBits = config.uiMode and Configuration.UI_MODE_NIGHT_MASK
        return nightBits == Configuration.UI_MODE_NIGHT_YES
    }

    private fun forwardIntentUrlIfPresent(incoming: Intent?) {
        if (incoming?.action == Intent.ACTION_VIEW) {
            val dataUri = incoming.dataString
            if (!dataUri.isNullOrEmpty()) {
                GPUINative.nativeOnOpenUrl(dataUri)
            }
        }
    }

    private fun registerThermalObserver() {
        val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return
        val listener = PowerManager.OnThermalStatusChangedListener { status ->
            runOnUiThread {
                GPUINative.nativeOnThermalStatusChanged(status)
            }
        }
        thermalListener = listener
        powerManager.addThermalStatusListener(mainExecutor, listener)
    }

    private fun unregisterThermalObserver() {
        val listener = thermalListener ?: return
        thermalListener = null
        val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
        powerManager?.removeThermalStatusListener(listener)
    }
}

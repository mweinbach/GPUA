package dev.glasshq.gpua

import android.content.Context
import android.os.Build
import android.text.InputType
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.WindowInsets
import android.view.inputmethod.BaseInputConnection
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputConnection
import android.view.inputmethod.InputMethodManager

/**
 * Hardware-accelerated [SurfaceView] forwarding `SurfaceHolder` lifecycle, multi-pointer
 * touch/stylus/mouse events, `WindowInsets` safe areas, and soft-keyboard IME commits to Swift.
 */
class GPUISurfaceView(context: Context) : SurfaceView(context), SurfaceHolder.Callback {

    init {
        isFocusable = true
        isFocusableInTouchMode = true
        holder.addCallback(this)

        setOnApplyWindowInsetsListener { _, windowInsets ->
            dispatchWindowInsets(windowInsets)
            windowInsets
        }
    }

    override fun surfaceCreated(holder: SurfaceHolder) {
        val frame = holder.surfaceFrame
        GPUINative.nativeOnSurfaceCreated(
            holder.surface,
            frame.width(),
            frame.height(),
            0
        )
    }

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
        val density = resources.displayMetrics.density
        val refreshRate = (context as? GPUIActivity)?.currentDisplayRefreshRateHz() ?: 60.0f
        GPUINative.nativeOnSurfaceChanged(format, width, height, density, refreshRate)
    }

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        // Synchronously tears down the Vulkan WGPUSurface before SurfaceHolder releases buffers.
        GPUINative.nativeOnSurfaceDestroyed()
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        forwardMotionEvent(event, vScroll = 0.0f, hScroll = 0.0f)
        return true
    }

    override fun onHoverEvent(event: MotionEvent): Boolean {
        forwardMotionEvent(event, vScroll = 0.0f, hScroll = 0.0f)
        return true
    }

    override fun onGenericMotionEvent(event: MotionEvent): Boolean {
        if (event.actionMasked == MotionEvent.ACTION_SCROLL) {
            val vScroll = event.getAxisValue(MotionEvent.AXIS_VSCROLL)
            val hScroll = event.getAxisValue(MotionEvent.AXIS_HSCROLL)
            forwardMotionEvent(event, vScroll = vScroll, hScroll = hScroll)
            return true
        }
        return super.onGenericMotionEvent(event)
    }

    override fun onCheckIsTextEditor(): Boolean = true

    override fun onCreateInputConnection(outAttrs: EditorInfo): InputConnection {
        outAttrs.inputType = InputType.TYPE_CLASS_TEXT or
            InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
        outAttrs.imeOptions = EditorInfo.IME_FLAG_NO_FULLSCREEN or
            EditorInfo.IME_ACTION_DONE
        return object : BaseInputConnection(this, false) {
            override fun commitText(text: CharSequence?, newCursorPosition: Int): Boolean {
                val committed = text?.toString()
                if (!committed.isNullOrEmpty()) {
                    GPUINative.nativeCommitText(committed)
                }
                return true
            }

            override fun deleteSurroundingText(beforeLength: Int, afterLength: Int): Boolean {
                if (beforeLength > 0 || afterLength > 0) {
                    GPUINative.nativeDeleteSurroundingText(beforeLength, afterLength)
                    return true
                }
                return super.deleteSurroundingText(beforeLength, afterLength)
            }

            override fun sendKeyEvent(event: KeyEvent): Boolean {
                val handled = GPUINative.nativeOnKeyEvent(
                    event.action,
                    event.keyCode,
                    event.metaState,
                    event.repeatCount,
                    event.unicodeChar,
                    event.scanCode
                )
                return if (handled) true else super.sendKeyEvent(event)
            }
        }
    }

    internal fun setSoftKeyboardVisible(visible: Boolean) {
        val imm = context.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
            ?: return
        if (visible) {
            requestFocus()
            imm.showSoftInput(this, InputMethodManager.SHOW_IMPLICIT)
        } else {
            imm.hideSoftInputFromWindow(windowToken, 0)
        }
    }

    private fun forwardMotionEvent(event: MotionEvent, vScroll: Float, hScroll: Float) {
        val count = event.pointerCount
        if (count <= 0) return

        val pointerIds = IntArray(count)
        val xs = FloatArray(count)
        val ys = FloatArray(count)
        val pressures = FloatArray(count)
        val toolTypes = IntArray(count)

        for (i in 0 until count) {
            pointerIds[i] = event.getPointerId(i)
            xs[i] = event.getX(i)
            ys[i] = event.getY(i)
            pressures[i] = event.getPressure(i)
            toolTypes[i] = event.getToolType(i)
        }

        GPUINative.nativeOnTouchEvent(
            event.action,
            pointerIds,
            xs,
            ys,
            pressures,
            toolTypes,
            event.metaState,
            event.buttonState,
            vScroll,
            hScroll,
            event.eventTime
        )
    }

    private fun dispatchWindowInsets(windowInsets: WindowInsets) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val mask = WindowInsets.Type.systemBars() or
                WindowInsets.Type.displayCutout() or
                WindowInsets.Type.ime()
            val insets = windowInsets.getInsets(mask)
            GPUINative.nativeOnInsetsChanged(
                insets.top,
                insets.left,
                insets.bottom,
                insets.right
            )
        } else {
            @Suppress("DEPRECATION")
            GPUINative.nativeOnInsetsChanged(
                windowInsets.systemWindowInsetTop,
                windowInsets.systemWindowInsetLeft,
                windowInsets.systemWindowInsetBottom,
                windowInsets.systemWindowInsetRight
            )
        }
    }
}

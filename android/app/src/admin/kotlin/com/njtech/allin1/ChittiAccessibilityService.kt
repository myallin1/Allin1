package com.njtech.allin1

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.graphics.PixelFormat
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.ImageView
import android.net.Uri
import android.provider.Settings
import java.util.Locale

class ChittiAccessibilityService : AccessibilityService() {

    companion object {
        @JvmField
        var instance: ChittiAccessibilityService? = null
    }

    private var windowManager: WindowManager? = null
    private var floatingBubble: ImageView? = null
    private var layoutParams: WindowManager.LayoutParams? = null
    private var speechRecognizer: SpeechRecognizer? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        setupFloatingBubble()
    }

    override fun onUnbind(intent: Intent?): Boolean {
        removeFloatingBubble()
        instance = null
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        removeFloatingBubble()
        speechRecognizer?.destroy()
        instance = null
        super.onDestroy()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // No-op - we only act on-demand via voice commands
    }

    override fun onInterrupt() {
        // No-op
    }

    private fun setupFloatingBubble() {
        mainHandler.post {
            try {
                windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
                
                // Ensure overlay permission is granted to prevent BadTokenException crash
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
                    val intent = Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName")).apply {
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    }
                    startActivity(intent)
                    return@post
                }
                
                val scale = resources.displayMetrics.density
                val sizePx = (58 * scale + 0.5f).toInt() // Call button size (58dp)

                floatingBubble = ImageView(this)
                
                // Try loading Chitti's WebP/GIF asset from Flutter
                try {
                    val assetManager = assets
                    val inputStream = assetManager.open("flutter_assets/assets/ai/ai_robot.webp")
                    val bitmap = BitmapFactory.decodeStream(inputStream)
                    floatingBubble?.setImageBitmap(bitmap)
                } catch (e: Exception) {
                    // Fallback to launcher icon
                    floatingBubble?.setImageResource(R.mipmap.ic_launcher)
                }

                floatingBubble?.scaleType = ImageView.ScaleType.FIT_CENTER

                // Setup layout params for drawing over other apps
                layoutParams = WindowManager.LayoutParams(
                    sizePx,
                    sizePx,
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                        WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                    } else {
                        WindowManager.LayoutParams.TYPE_PHONE
                    },
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
                    PixelFormat.TRANSLUCENT
                )

                layoutParams?.gravity = Gravity.TOP or Gravity.START
                layoutParams?.x = 100
                layoutParams?.y = 500

                // Touch listener for dragging and clicking
                floatingBubble?.setOnTouchListener(object : View.OnTouchListener {
                    private var initialX = 0
                    private var initialY = 0
                    private var initialTouchX = 0f
                    private var initialTouchY = 0f
                    private var isMoving = false

                    override fun onTouch(v: View?, event: MotionEvent): Boolean {
                        val lp = layoutParams ?: return false
                        when (event.action) {
                            MotionEvent.ACTION_DOWN -> {
                                initialX = lp.x
                                initialY = lp.y
                                initialTouchX = event.rawX
                                initialTouchY = event.rawY
                                isMoving = false
                                return true
                            }
                            MotionEvent.ACTION_MOVE -> {
                                val dx = (event.rawX - initialTouchX).toInt()
                                val dy = (event.rawY - initialTouchY).toInt()
                                if (Math.abs(dx) > 10 || Math.abs(dy) > 10) {
                                    isMoving = true
                                }
                                if (isMoving) {
                                    lp.x = initialX + dx
                                    lp.y = initialY + dy
                                    windowManager?.updateViewLayout(floatingBubble, lp)
                                }
                                return true
                            }
                            MotionEvent.ACTION_UP -> {
                                if (!isMoving) {
                                    v?.performClick()
                                }
                                return true
                            }
                        }
                        return false
                    }
                })

                floatingBubble?.setOnClickListener {
                    triggerVoiceListening()
                }

                windowManager?.addView(floatingBubble, layoutParams)
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    private fun removeFloatingBubble() {
        mainHandler.post {
            try {
                if (floatingBubble != null && windowManager != null) {
                    windowManager?.removeView(floatingBubble)
                    floatingBubble = null
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    private fun triggerVoiceListening() {
        mainHandler.post {
            // Visual feedback: dim Chitti slightly to show listening mode
            floatingBubble?.alpha = 0.5f

            speechRecognizer?.destroy()
            speechRecognizer = SpeechRecognizer.createSpeechRecognizer(this)

            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, Locale.getDefault())
                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            }

            speechRecognizer?.setRecognitionListener(object : RecognitionListener {
                override fun onReadyForSpeech(params: Bundle?) {}
                override fun onBeginningOfSpeech() {}
                override fun onRmsChanged(rmsdB: Float) {}
                override fun onBufferReceived(buffer: ByteArray?) {}
                override fun onEndOfSpeech() {
                    floatingBubble?.alpha = 1.0f
                }
                override fun onError(error: Int) {
                    floatingBubble?.alpha = 1.0f
                }
                override fun onResults(results: Bundle?) {
                    floatingBubble?.alpha = 1.0f
                    val voiceResults = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                    if (!voiceResults.isNullOrEmpty()) {
                        val command = voiceResults[0]
                        // NEW (Aug 30 2026 — Nizam: "home page la chitti
                        // thotta yethume nadakala"). ROOT CAUSE: speech
                        // recognition here is native and works fine from
                        // any screen, but the reply it triggers
                        // (GuruOverlayService.show(), in
                        // ChittiAccessibilityBridge.onVoiceCommandReceived)
                        // is a FLUTTER overlay scoped to this app's own
                        // Activity — it can never be visible while the
                        // launcher/home screen or another app is what's
                        // actually on screen. Bringing MainActivity to the
                        // foreground FIRST, same FLAG_ACTIVITY_NEW_TASK
                        // pattern PhoneCallService already uses for calls,
                        // is what makes the answer actually visible instead
                        // of silently rendering into a backgrounded app.
                        try {
                            val launchIntent = applicationContext.packageManager
                                .getLaunchIntentForPackage(applicationContext.packageName)
                            launchIntent?.let {
                                it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                                it.putExtra("voice_command", command)
                                applicationContext.startActivity(it)
                            }
                        } catch (e: Exception) {
                            e.printStackTrace()
                        }
                        try {
                            val mainActivityClass = Class.forName("com.njtech.allin1.MainActivity")
                            val callbackField = mainActivityClass.getField("voiceCommandCallback")
                            val callback = callbackField.get(null) as? kotlin.jvm.functions.Function1<String, Unit>
                            callback?.invoke(command)
                        } catch (e: Exception) {
                            e.printStackTrace()
                        }
                    }
                }
                override fun onPartialResults(partialResults: Bundle?) {}
                override fun onEvent(eventType: Int, params: Bundle?) {}
            })

            speechRecognizer?.startListening(intent)
        }
    }

    // Accessibility Actions
    fun performClick(text: String): Boolean {
        val rootNode = rootInActiveWindow ?: return false
        val nodes = rootNode.findAccessibilityNodeInfosByText(text)
        if (nodes.isNullOrEmpty()) return false
        for (node in nodes) {
            if (node.isClickable) {
                node.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                return true
            }
            var parent = node.parent
            while (parent != null) {
                if (parent.isClickable) {
                    parent.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                    return true
                }
                parent = parent.parent
            }
        }
        return false
    }

    fun performInput(label: String, text: String): Boolean {
        val rootNode = rootInActiveWindow ?: return false
        val nodes = rootNode.findAccessibilityNodeInfosByText(label)
        if (nodes.isNullOrEmpty()) return false
        for (node in nodes) {
            val parent = node.parent ?: continue
            for (i in 0 until parent.childCount) {
                val child = parent.getChild(i) ?: continue
                if (child.className == "android.widget.EditText" || child.isEditable) {
                    val arguments = Bundle()
                    arguments.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
                    child.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, arguments)
                    return true
                }
            }
        }
        return false
    }

    fun performScroll(direction: String): Boolean {
        val rootNode = rootInActiveWindow ?: return false
        val action = when (direction.lowercase()) {
            "down" -> AccessibilityNodeInfo.ACTION_SCROLL_FORWARD
            "up" -> AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD
            else -> AccessibilityNodeInfo.ACTION_SCROLL_FORWARD
        }
        return rootNode.performAction(action)
    }

    fun readScreen(): String {
        val rootNode = rootInActiveWindow ?: return "Screen is empty"
        val sb = StringBuilder()
        traverseNode(rootNode, sb)
        return sb.toString()
    }

    private fun traverseNode(node: AccessibilityNodeInfo?, sb: StringBuilder) {
        if (node == null) return
        val text = node.text
        val desc = node.contentDescription
        if (!text.isNullOrEmpty()) {
            sb.append(text).append("\n")
        } else if (!desc.isNullOrEmpty()) {
            sb.append(desc).append("\n")
        }
        for (i in 0 until node.childCount) {
            traverseNode(node.getChild(i), sb)
        }
    }
}

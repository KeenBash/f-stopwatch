package com.f.s.f_stopwatch

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.ImageButton
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.core.graphics.drawable.DrawableCompat

/**
 * 前台服务：以系统悬浮窗(TYPE_APPLICATION_OVERLAY)显示总时间与操作按钮。
 * - 顶部右上角锁定按钮：解锁后可拖动整个悬浮窗，再次点击固定位置。
 * - 暂停/计次/重置使用统一图标按钮；支持重置。
 * - 支持字体颜色、大小、背景透明度配置。
 * - 拖动位置保存在本地，重启后恢复。
 * 计时逻辑在 Dart 侧，悬浮窗仅负责展示与回传按钮点击。
 */
class OverlayService : Service() {

    private var overlayView: LinearLayout? = null
    private var overlayAdded: Boolean = false
    private var overlayLayoutParams: WindowManager.LayoutParams? = null

    // 配置
    private var fontColor: Int = Color.WHITE
    private var sizeScale: Float = 1f
    private var bgAlpha: Int = 200

    private var unlocked: Boolean = false
    private var toggleBtn: ImageButton? = null
    private var lockBtn: ImageButton? = null
    private var vibrate: Boolean = false

    // 最近一次展示的内容：配置变更重建悬浮窗时沿用，避免重建瞬间闪回 00:00.00
    private var lastTotal: String = "00:00.00"
    private var lastSecondary: String = ""
    private var lastPaused: Boolean = true

    // 计次列表浮窗
    private var listView: LinearLayout? = null
    private var listAdded: Boolean = false
    private var listShown: Boolean = false
    private var listLp: WindowManager.LayoutParams? = null
    private var lastLaps: List<String> = emptyList()
    private var listHolder: LinearLayout? = null

    companion object {
        private const val CHANNEL_ID = "f_stopwatch_overlay"
        private const val NOTIF_ID = 1001
        private const val PREFS = "float_overlay"
        private const val KEY_X = "pos_x"
        private const val KEY_Y = "pos_y"

        private var instance: OverlayService? = null
        private var timeView: TextView? = null
        private var secondaryView: TextView? = null

        fun start(ctx: Context) {
            val i = Intent(ctx, OverlayService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                ctx.startForegroundService(i)
            } else {
                ctx.startService(i)
            }
        }

        fun stop(ctx: Context) {
            ctx.stopService(Intent(ctx, OverlayService::class.java))
        }

        /** 更新悬浮窗总时间。 */
        fun updateTotal(text: String) {
            if (instance?.overlayAdded != true) return
            instance?.lastTotal = text
            instance?.runOnUiThread { timeView?.text = text }
        }

        /** 同步暂停/运行状态，刷新暂停/开始图标。 */
        fun updateRunning(paused: Boolean) {
            if (instance?.overlayAdded != true) return
            instance?.lastPaused = paused
            instance?.runOnUiThread {
                val t = instance?.toggleBtn ?: return@runOnUiThread
                val res = if (paused) R.drawable.ic_play else R.drawable.ic_pause
                t.setImageResource(res)
                instance?.tint(t.drawable, instance?.fontColor ?: Color.WHITE)
            }
        }

        /** 更新悬浮窗配置。 */
        fun updateConfig(fontColor: Int, sizeScale: Float, bgAlpha: Int, vibrate: Boolean) {
            instance?.runOnUiThread {
                instance?.applyConfig(fontColor, sizeScale, bgAlpha, vibrate)
            }
        }

        /** 更新辅助小字行（本次计时/第N次），空串则隐藏。 */
        fun updateSecondary(text: String) {
            if (instance?.overlayAdded != true) return
            instance?.lastSecondary = text
            instance?.runOnUiThread {
                val v = secondaryView ?: return@runOnUiThread
                if (text.isBlank()) {
                    v.visibility = android.view.View.GONE
                } else {
                    v.text = text
                    v.visibility = android.view.View.VISIBLE
                }
            }
        }

        /** 将悬浮窗恢复到默认位置（状态栏下方）。 */
        fun resetPosition() {
            instance?.runOnUiThread { instance?.resetPosition() }
        }

        /** 原生悬浮窗当前是否在运行。 */
        fun isAlive(): Boolean = instance?.overlayAdded == true

        /** 更新计次列表内容；列表浮窗若在展示则同步刷新。 */
        fun updateLaps(lines: List<String>) {
            instance?.runOnUiThread {
                instance?.lastLaps = lines.toList()
                instance?.refreshListContent()
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            createChannel()
            startForeground(NOTIF_ID, buildNotification())
        }
        // 进程被系统回收后由 START_STICKY 重建时 intent 为 null：
        // 此时 Dart 引擎已不在，添加悬浮窗只会显示一个永远停走的 00:00.00，
        // 反而让用户以为计时被归零，因此直接结束服务。
        if (intent == null) {
            stopSelf()
            return START_NOT_STICKY
        }
        addOverlay()
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        removeOverlay()
        removeListWindow()
        instance = null
        super.onDestroy()
    }

    private fun runOnUiThread(block: () -> Unit) {
        Handler(Looper.getMainLooper()).post(block)
    }

    private fun createChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "F-Stopwatch 悬浮窗",
            NotificationManager.IMPORTANCE_LOW
        )
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("F-Stopwatch")
            .setContentText("悬浮窗已启动")
            .setSmallIcon(android.R.drawable.ic_menu_recent_history)
            .setContentIntent(contentIntent)
            .setOngoing(true)
            .build()
    }

    // ---------- 悬浮窗构建 ----------

    private fun addOverlay() {
        removeOverlay() // 保证不重复添加
        instance = this

        val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val hasSavedPos = prefs.contains(KEY_X) && prefs.contains(KEY_Y)
        val savedX = if (hasSavedPos) prefs.getInt(KEY_X, dp(8)) else dp(8)
        val savedY = if (hasSavedPos) {
            prefs.getInt(KEY_Y, statusBarHeight() + dp(8))
        } else {
            statusBarHeight() + dp(8)
        }

        // 顶部行：锁定 | 列表 | 关闭（水平居中）
        lockBtn = ImageButton(this).apply {
            contentDescription = "切换拖动"
            setBackgroundColor(Color.TRANSPARENT)
            setPadding(dp(4), dp(4), dp(4), dp(4))
            scaleType = android.widget.ImageView.ScaleType.FIT_CENTER
            layoutParams = LinearLayout.LayoutParams(
                dp(40 * sizeScale),
                dp(40 * sizeScale)
            )
            setOnClickListener { unlocked = !unlocked; updateLockIcon() }
        }
        updateLockIcon()

        val listBtn = ImageButton(this).apply {
            contentDescription = "计次列表"
            setBackgroundColor(Color.TRANSPARENT)
            setPadding(dp(4), dp(4), dp(4), dp(4))
            scaleType = android.widget.ImageView.ScaleType.FIT_CENTER
            setImageResource(R.drawable.ic_list)
            tint(this.drawable, fontColor)
            layoutParams = LinearLayout.LayoutParams(
                dp(40 * sizeScale),
                dp(40 * sizeScale)
            )
            setOnClickListener { toggleListJob() }
        }

        val closeBtn = ImageButton(this).apply {
            contentDescription = "关闭悬浮窗"
            setBackgroundColor(Color.TRANSPARENT)
            setPadding(dp(4), dp(4), dp(4), dp(4))
            scaleType = android.widget.ImageView.ScaleType.FIT_CENTER
            setImageResource(R.drawable.ic_close)
            tint(this.drawable, fontColor)
            layoutParams = LinearLayout.LayoutParams(
                dp(40 * sizeScale),
                dp(40 * sizeScale)
            )
            setOnClickListener {
                listShown = false
                removeListWindow()
                vibrateClick()
                OverlayController.emitButton("stop")
            }
        }

        listShown = false
        removeListWindow()

        val topRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            addView(weightedSlot(lockBtn), spreadLp())
            addView(weightedSlot(listBtn), spreadLp())
            addView(weightedSlot(closeBtn), spreadLp())
        }

        timeView = TextView(this).apply {
            textSize = 32f * sizeScale
            typeface = Typeface.MONOSPACE
            setTextColor(fontColor)
            gravity = Gravity.CENTER
            text = lastTotal
        }

        // 辅助小字行（本次计时 / 第N次），沿用上次内容
        secondaryView = TextView(this).apply {
            textSize = 13f * sizeScale
            typeface = Typeface.MONOSPACE
            setTextColor(fontColor)
            gravity = Gravity.CENTER
            text = lastSecondary
            visibility = if (lastSecondary.isBlank()) android.view.View.GONE
            else android.view.View.VISIBLE
        }

        // 操作按钮行：暂停/计次/重置（统一图标风格）
        toggleBtn = iconButton(
            if (lastPaused) R.drawable.ic_play else R.drawable.ic_pause
        ) { vibrateClick(); OverlayController.emitButton("toggle") }
        val lapBtn = iconButton(R.drawable.ic_flag) { vibrateClick(); OverlayController.emitButton("lap") }
        val resetBtn = iconButton(R.drawable.ic_reset) { vibrateClick(); OverlayController.emitButton("reset") }

        val btnRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            addView(weightedSlot(toggleBtn), spreadLp())
            addView(weightedSlot(lapBtn), spreadLp())
            addView(weightedSlot(resetBtn), spreadLp())
        }

        val view = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            val bg = Color.argb(bgAlpha.coerceIn(0, 255), 0x22, 0x22, 0x22)
            setBackgroundColor(bg)
            setPadding(dp(4), dp(4), dp(4), dp(8))
            minimumWidth = dp(240)
            addView(topRow, LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ))
            addView(timeView, LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply { gravity = Gravity.CENTER_HORIZONTAL })
            addView(secondaryView, LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply { gravity = Gravity.CENTER_HORIZONTAL })
            addView(
                btnRow,
                LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT
                ).apply { topMargin = dp(2) }
            )
        }
        overlayView = view

        val layerType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            WindowManager.LayoutParams.TYPE_PHONE
        }
        val params = WindowManager.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
            layerType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = savedX
            y = savedY
        }
        overlayLayoutParams = params
        clampToScreen(params, view.width, view.height)
        windowManager.addView(view, params)
        attachDrag(view, params)
        overlayAdded = true
        // 布局完成后用实测宽高做一次边界钳制（仅取值变化时更新）
        view.post {
            val p = overlayLayoutParams ?: return@post
            val oldX = p.x
            val oldY = p.y
            clampToScreen(p, view.width, view.height)
            if (p.x != oldX || p.y != oldY) {
                runCatching { windowManager.updateViewLayout(view, p) }
            }
        }
    }

    /** 读取系统状态栏高度，失败时回退到 dp(24)。 */
    private fun statusBarHeight(): Int {
        val id = resources.getIdentifier("status_bar_height", "dimen", "android")
        return if (id > 0) {
            runCatching { resources.getDimensionPixelSize(id) }.getOrElse { dp(24) }
        } else {
            dp(24)
        }
    }

    /**
     * 把 params.x/y 钳制到屏幕范围内，保证至少约 60px 悬浮窗可见可抓住。
     */
    private fun clampToScreen(params: WindowManager.LayoutParams, viewW: Int, viewH: Int) {
        val w = if (viewW > 0) viewW else dp(200)
        val h = if (viewH > 0) viewH else dp(120)
        val screenW: Int
        val screenH: Int
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val b = windowManager.currentWindowMetrics.bounds
            screenW = b.width()
            screenH = b.height()
        } else {
            @Suppress("DEPRECATION")
            val p = android.graphics.Point()
            runCatching { windowManager.defaultDisplay.getSize(p) }
            var ww = p.x
            var hh = p.y
            if (ww <= 0 || hh <= 0) {
                val dm = resources.displayMetrics
                ww = dm.widthPixels
                hh = dm.heightPixels
            }
            screenW = ww
            screenH = hh
        }
        val minX = -(w - dp(60)).coerceAtLeast(0)
        val maxX = (screenW - dp(60)).coerceAtLeast(minX)
        params.x = params.x.coerceIn(minX, maxX)
        val maxY = (screenH - h).coerceAtLeast(0)
        params.y = params.y.coerceIn(0, maxY)
    }

    /** 将悬浮窗恢复到默认位置（状态栏下方）并保存。 */
    private fun resetPosition() {
        val p = overlayLayoutParams ?: return
        val defaultX = dp(8)
        val defaultY = statusBarHeight() + dp(8)
        p.x = defaultX
        p.y = defaultY
        runCatching { windowManager.updateViewLayout(overlayView, p) }
        persistPos(defaultX, defaultY)
    }

    /** 锁定/解锁状态切换后刷新锁定按钮图标。 */
    private fun updateLockIcon() {
        val lb = lockBtn ?: return
        val res = if (unlocked) R.drawable.ic_lock_open else R.drawable.ic_lock
        lb.setImageResource(res)
        tint(lb.drawable, fontColor)
    }

    /** 创建统一样式的图标按钮。 */
    private fun iconButton(res: Int, onClick: () -> Unit): ImageButton =
        ImageButton(this).apply {
            contentDescription = "overlay_icon"
            setBackgroundColor(Color.TRANSPARENT)
            setPadding(dp(6), dp(6), dp(6), dp(6))
            scaleType = android.widget.ImageView.ScaleType.FIT_CENTER
            setImageResource(res)
            tint(this.drawable, fontColor)
            setOnClickListener { onClick() }
            layoutParams = iconLp()
        }

    private fun iconLp(): LinearLayout.LayoutParams {
        val size = dp(44 * sizeScale)
        return LinearLayout.LayoutParams(size, size)
    }

    private fun tint(d: android.graphics.drawable.Drawable?, color: Int) {
        if (d == null) return
        val wrapped = DrawableCompat.wrap(d)
        DrawableCompat.setTint(wrapped, color)
    }

    /** 悬浮窗按钮点击触感反馈：直接调用系统 Vibrator，不依赖窗口焦点(国产ROM更稳定)。 */
    private fun vibrateClick() {
        if (!vibrate) return
        runCatching {
            val vib = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vib.vibrate(VibrationEffect.createOneShot(35, VibrationEffect.DEFAULT_AMPLITUDE))
            } else {
                @Suppress("DEPRECATION")
                vib.vibrate(35)
            }
        }
    }

    // ---------- 拖动 + 锁定 ----------

    private fun attachDrag(view: View, params: WindowManager.LayoutParams) {
        var startRawX = 0f
        var startRawY = 0f
        var winStartX = 0f
        var winStartY = 0f
        var moved = false
        val slop = android.view.ViewConfiguration.get(this).scaledTouchSlop.toFloat()

        view.setOnTouchListener { v, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    startRawX = event.rawX
                    startRawY = event.rawY
                    moved = false
                    // 始终不在这层消费按下事件，保证子按钮能收到点击；仅解锁后拖动时接管
                    false
                }
                MotionEvent.ACTION_MOVE -> {
                    if (!unlocked) return@setOnTouchListener false
                    val dx = event.rawX - startRawX
                    val dy = event.rawY - startRawY
                    if (!moved && (Math.abs(dx) > slop || Math.abs(dy) > slop)) {
                        moved = true
                        winStartX = params.x.toFloat()
                        winStartY = params.y.toFloat()
                    }
                    if (moved) {
                        params.x = (winStartX + dx).toInt()
                        params.y = (winStartY + dy).toInt()
                        clampToScreen(params, v.width, v.height)
                        windowManager.updateViewLayout(v, params)
                        true // 已发生拖动，接管手势(会触发子按钮 CANCEL，阻止误点击)
                    } else {
                        false
                    }
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    // 仅在被接管(拖动)后停止时保存位置；纯点击由子按钮处理
                    if (moved) {
                        persistPos(params.x, params.y)
                        false
                    } else {
                        false
                    }
                }
                else -> false
            }
        }
    }

    private fun persistPos(x: Int, y: Int) {
        runCatching {
            getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit().putInt(KEY_X, x).putInt(KEY_Y, y).apply()
        }
    }

    // ---------- 计次列表浮窗 ----------

    private fun toggleListJob() {
        if (listAdded) {
            removeListWindow()
            listShown = false
        } else {
            buildListWindow()
            listShown = true
        }
    }

    private fun appOverlayType(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            WindowManager.LayoutParams.TYPE_PHONE
        }

    private fun buildListWindow() {
        removeListWindow()
        val bg = Color.argb(bgAlpha.coerceIn(0, 255), 0x22, 0x22, 0x22)

        listHolder = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(bg)
            setPadding(dp(10), dp(6), dp(10), dp(8))
        }

        ScrollView(this).apply {
            isFillViewport = false
            val inner = LinearLayout(this@OverlayService).apply {
                orientation = LinearLayout.VERTICAL
            }
            if (lastLaps.isEmpty()) {
                inner.addView(
                    tv("暂无计次"),
                    wc()
                )
            } else {
                lastLaps.forEach { line -> inner.addView(tv(line), wc()) }
            }
            addView(inner, ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ))
            // 高度固定为约 10 行，内容超出时可滚动
            listHolder!!.addView(this, LinearLayout.LayoutParams(
                dp(250 * sizeScale),
                visibleHeight(lastLaps.size)
            ))
        }

        val view = listHolder!!
        val params = WindowManager.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
            appOverlayType(),
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
        }
        listView = view
        listLp = params
        windowManager.addView(view, params)
        listAdded = true
        // 布局完成后按主浮窗下方定位并钳制到屏幕内
        view.post {
            if (!listAdded) return@post
            positionListWindow(view.width, view.height)
        }
    }

    private fun refreshListContent() {
        if (!listAdded || listHolder == null) return
        val wasShown = listShown
        if (wasShown) {
            val p0 = listLp ?: return
            val holder = listHolder!!
            holder.removeAllViews()
            val inner = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
            if (lastLaps.isEmpty()) inner.addView(tv("暂无计次"), wc())
            else lastLaps.forEach { line -> inner.addView(tv(line), wc()) }
            ScrollView(this).apply {
                addView(inner, ViewGroup.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT
                ))
            }.let { holder.addView(it, LinearLayout.LayoutParams(dp(250 * sizeScale), visibleHeight(lastLaps.size))) }
            listLp?.apply {
                height = ViewGroup.LayoutParams.WRAP_CONTENT
            }
            runCatching { windowManager.updateViewLayout(listView, p0) }
            listView?.post { positionListWindow(listView!!.width, listView!!.height) }
        }
    }

    /** 列表弹窗高度：按约 10 行固定，最多不超过 320dp；行数少则按实际缩小。 */
    private fun visibleHeight(rowCount: Int): Int {
        val row = dp(20 * sizeScale)
        val natural = rowCount * row + dp(16)
        val capped = kotlin.math.min(rowCount, 10) * row + dp(16)
        return capped.coerceIn(dp(60), dp(320)).coerceAtMost(kotlin.math.max(natural, dp(60)))
    }

    private fun positionListWindow(viewW: Int, viewH: Int) {
        val mainLp = overlayLayoutParams ?: return
        val lp = listLp ?: return
        val v = listView ?: return
        if (!listAdded) return
        val w = if (viewW > 0) viewW else dp(250)
        val h = if (viewH > 0) viewH else dp(120)
        val ovW = overlayView?.width?.takeIf { it > 0 } ?: dp(200)
        val ovH = overlayView?.height?.takeIf { it > 0 } ?: dp(140)
        var x = mainLp.x + (ovW - w) / 2
        var y = mainLp.y + ovH + dp(6)
        val screenW: Int
        val screenH: Int
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val b = windowManager.currentWindowMetrics.bounds
            screenW = b.width()
            screenH = b.height()
        } else {
            val p = android.graphics.Point()
            runCatching { windowManager.defaultDisplay.getSize(p) }
            screenW = if (p.x > 0) p.x else resources.displayMetrics.widthPixels
            screenH = if (p.y > 0) p.y else resources.displayMetrics.heightPixels
        }
        x = x.coerceIn(dp(8), (screenW - w).coerceAtLeast(dp(8)))
        y = y.coerceIn(0, (screenH - h).coerceAtLeast(0))
        lp.x = x
        lp.y = y
        runCatching { windowManager.updateViewLayout(v, lp) }
    }

    private fun removeListWindow() {
        val v = listView
        if (listAdded && v != null) {
            listAdded = false
            listView = null
            listHolder = null
            listLp = null
            runCatching { windowManager.removeView(v) }
        }
    }

    private fun tv(text: String): TextView = TextView(this).apply {
        this.text = text
        textSize = 12f * sizeScale
        typeface = Typeface.MONOSPACE
        setTextColor(fontColor)
        setPadding(0, dp(2), 0, dp(2))
    }

    private fun wc(): LinearLayout.LayoutParams =
        LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)

    /** 把子按钮包进一个等宽三分槽内，使 3 个按钮均匀分布为"偏左/居中/偏右"。 */
    private fun weightedSlot(child: View?): View {
        val slot = LinearLayout(this)
        slot.orientation = LinearLayout.HORIZONTAL
        slot.gravity = Gravity.CENTER
        if (child != null) {
            slot.addView(child, LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ))
        }
        return slot
    }

    private fun spreadLp(): LinearLayout.LayoutParams =
        LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)

    // ---------- 配置 ----------

    private fun applyConfig(fontColor: Int, sizeScale: Float, bgAlpha: Int, vibrate: Boolean) {
        this.fontColor = fontColor
        this.sizeScale = sizeScale
        this.bgAlpha = bgAlpha
        this.vibrate = vibrate
        // 配置变化时重建悬浮窗以应用尺寸/颜色/透明度
        val p = overlayLayoutParams
        val oldX = p?.x ?: 0
        val oldY = p?.y ?: 0
        addOverlay()
        overlayLayoutParams?.x = oldX
        overlayLayoutParams?.y = oldY
        persistPos(oldX, oldY)
        // 列表浮窗若在展示则随主浮窗重建、沿用新背景透明度
        if (listShown) buildListWindow()
    }

    private fun removeOverlay() {
        val v = overlayView
        if (overlayAdded && v != null) {
            overlayAdded = false
            overlayView = null
            runCatching { windowManager.removeView(v) }
        }
    }

    private val windowManager: WindowManager
        get() = getSystemService(WINDOW_SERVICE) as WindowManager

    private fun dp(value: Float): Int = (value * resources.displayMetrics.density).toInt()

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()
}
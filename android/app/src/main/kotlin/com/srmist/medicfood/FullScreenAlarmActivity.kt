package com.srmist.medicfood

import android.app.KeyguardManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.util.Log
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import org.json.JSONObject
import android.graphics.Color
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.util.TypedValue
import android.graphics.Typeface
import android.widget.Space
import android.text.TextUtils

class FullScreenAlarmActivity : AppCompatActivity() {
    private lateinit var mainLayout: LinearLayout
    private var wakeLock: PowerManager.WakeLock? = null
    private var alarmId: Int = -1
    private var payload: String = ""
    private var actionReceiver: BroadcastReceiver? = null
    private var closeReceiver: BroadcastReceiver? = null
    private var isActionHandled = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Get forceFullScreen flag from intent
        val forceFullScreen = intent.getBooleanExtra("forceFullScreen", false)
        
        // Check fullScreen setting only if not forced
        if (!forceFullScreen) {
            val settings = getSharedPreferences("notification_settings", Context.MODE_PRIVATE)
            val fullScreenEnabled = settings.getBoolean("fullScreen", true)
            Log.i("FullScreenAlarmActivity", "FullScreen enabled: $fullScreenEnabled, forced: $forceFullScreen")
            if (!fullScreenEnabled) {
                Log.w("FullScreenAlarmActivity", "FullScreen disabled, finishing activity")
                finish()
                return
            }
        } else {
            Log.i("FullScreenAlarmActivity", "FullScreen forced by notification service")
        }

        // Set flags BEFORE any other window operations
        setupFullScreenFlags()
        
        // Get data from intent
        payload = intent.getStringExtra("payload") ?: ""
        alarmId = intent.getLongExtra("alarmId", -1L).toInt()
        
        // Setup receivers
        setupActionReceiver()
        setupCloseReceiver()
        
        // Acquire wake lock
        acquireWakeLock()

        // Create and set layout - NO SCROLLING
        mainLayout = createFixedFullScreenLayout()
        setContentView(mainLayout)
        
        if (payload.isNotEmpty()) {
            displayMedicineDetails(payload)
        }

        Log.i("FullScreenAlarmActivity", "Fixed FullScreen activity created successfully for alarm: $alarmId")
    }

    private fun setupActionReceiver() {
        actionReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                val action = intent?.action
                val receivedAlarmId = intent?.getLongExtra("alarmId", -1L)?.toInt() ?: -1
                
                Log.i("FullScreenAlarmActivity", "Action received: $action for alarm: $receivedAlarmId")
                
                if (receivedAlarmId == alarmId && !isActionHandled) {
                    isActionHandled = true
                    Log.i("FullScreenAlarmActivity", "Handling synchronized action: $action")
                    finish()
                }
            }
        }
        
        val filter = IntentFilter().apply {
            addAction("com.srmist.medicfood.ALARM_ACTION_SYNC")
        }
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(actionReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(actionReceiver, filter)
        }
    }

    private fun setupCloseReceiver() {
        closeReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                val action = intent?.action
                
                when (action) {
                    "com.srmist.medicfood.CLOSE_FULLSCREEN" -> {
                        val receivedAlarmId = intent?.getLongExtra("alarmId", -1L)?.toInt() ?: -1
                        if (receivedAlarmId == alarmId || receivedAlarmId == -1) {
                            Log.i("FullScreenAlarmActivity", "Closing fullscreen for alarm: $receivedAlarmId")
                            finish()
                        }
                    }
                    "com.srmist.medicfood.CLOSE_FULLSCREEN_ON_RESUME" -> {
                        Log.i("FullScreenAlarmActivity", "Closing fullscreen - main activity resumed")
                        finish()
                    }
                }
            }
        }
        
        val filter = IntentFilter().apply {
            addAction("com.srmist.medicfood.CLOSE_FULLSCREEN")
            addAction("com.srmist.medicfood.CLOSE_FULLSCREEN_ON_RESUME")
        }
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(closeReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(closeReceiver, filter)
        }
    }

    private fun setupFullScreenFlags() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
            keyguardManager.requestDismissKeyguard(this, null)
        }

        window.apply {
            clearFlags(WindowManager.LayoutParams.FLAG_TRANSLUCENT_STATUS)
            clearFlags(WindowManager.LayoutParams.FLAG_TRANSLUCENT_NAVIGATION)
            
            addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            addFlags(WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD)
            addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED)
            addFlags(WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON)
            addFlags(WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN)
            addFlags(WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS)
            addFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN)
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                attributes.layoutInDisplayCutoutMode = 
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
            
            decorView.systemUiVisibility = (
                View.SYSTEM_UI_FLAG_LAYOUT_STABLE or
                View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_FULLSCREEN or
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
            )
            
            Log.i("FullScreenAlarmActivity", "All fullscreen flags applied successfully")
        }
    }

    private fun acquireWakeLock() {
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(
            PowerManager.SCREEN_BRIGHT_WAKE_LOCK or 
            PowerManager.ACQUIRE_CAUSES_WAKEUP or 
            PowerManager.ON_AFTER_RELEASE,
            "FullScreenAlarmActivity::WakeLock"
        ).apply {
            acquire(10 * 60 * 1000L)
        }
        Log.i("FullScreenAlarmActivity", "WakeLock acquired")
    }
    
    private fun dpToPx(dp: Float): Int {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP, dp, resources.displayMetrics
        ).toInt()
    }
    
    private fun createFixedFullScreenLayout(): LinearLayout {
        // Main container - Fixed layout, no scrolling
        val mainContainer = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            
            // Beautiful calming gradient background
            background = android.graphics.drawable.GradientDrawable().apply {
                colors = intArrayOf(
                    Color.parseColor("#667eea"), // Soft purple-blue
                    Color.parseColor("#764ba2"), // Gentle purple
                    Color.parseColor("#5B72C4")  // Calming blue
                )
                gradientType = android.graphics.drawable.GradientDrawable.LINEAR_GRADIENT
                orientation = android.graphics.drawable.GradientDrawable.Orientation.TOP_BOTTOM
            }
            
            gravity = Gravity.CENTER
            setPadding(dpToPx(20f), dpToPx(40f), dpToPx(20f), dpToPx(20f))
        }
        
        // Add spacing for status bar
        val topSpacer = Space(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dpToPx(20f)
            )
        }
        mainContainer.addView(topSpacer)
        
        // Medicine name at the top - LARGEST TEXT
        val medicineNameText = TextView(this).apply {
            id = android.R.id.text2
            text = "Loading Medicine..."
            textSize = 36f // VERY LARGE for medicine name
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            typeface = Typeface.DEFAULT_BOLD
            letterSpacing = 0.02f
            setShadowLayer(8f, 0f, 4f, Color.parseColor("#60000000"))
            setPadding(dpToPx(16f), dpToPx(16f), dpToPx(16f), dpToPx(24f))
            maxLines = 3
            ellipsize = TextUtils.TruncateAt.END
            
            // Glass morphism background for medicine name
            background = android.graphics.drawable.GradientDrawable().apply {
                setColor(Color.parseColor("#30FFFFFF"))
                cornerRadius = dpToPx(20f).toFloat()
                setStroke(dpToPx(2f), Color.parseColor("#50FFFFFF"))
            }
            elevation = dpToPx(12f).toFloat()
            
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                setMargins(0, 0, 0, dpToPx(24f))
            }
        }
        mainContainer.addView(medicineNameText)
        
        // Content container for middle section
        val contentContainer = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            
            background = android.graphics.drawable.GradientDrawable().apply {
                setColor(Color.parseColor("#25FFFFFF"))
                cornerRadius = dpToPx(24f).toFloat()
                setStroke(dpToPx(1f), Color.parseColor("#40FFFFFF"))
            }
            elevation = dpToPx(16f).toFloat()
            
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                0,
                1.0f // Take available space between medicine name and buttons
            )
            
            setPadding(dpToPx(24f), dpToPx(24f), dpToPx(24f), dpToPx(24f))
        }
        
        // Gentle reminder text
        val reminderText = TextView(this).apply {
            text = "💊 Time for your medicine"
            textSize = 20f
            setTextColor(Color.parseColor("#E8F4FD"))
            gravity = Gravity.CENTER
            typeface = Typeface.DEFAULT
            setPadding(dpToPx(12f), 0, dpToPx(12f), dpToPx(16f))
            maxLines = 2
            ellipsize = TextUtils.TruncateAt.END
        }
        contentContainer.addView(reminderText)
        
        // Beautiful medicine icon
        val iconContainer = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            background = android.graphics.drawable.GradientDrawable().apply {
                shape = android.graphics.drawable.GradientDrawable.OVAL
                colors = intArrayOf(
                    Color.parseColor("#40FFFFFF"),
                    Color.parseColor("#60FFFFFF")
                )
                gradientType = android.graphics.drawable.GradientDrawable.RADIAL_GRADIENT
                gradientRadius = dpToPx(60f).toFloat()
            }
            val iconSize = dpToPx(120f)
            layoutParams = LinearLayout.LayoutParams(iconSize, iconSize).apply {
                setMargins(0, dpToPx(20f), 0, dpToPx(20f))
            }
            elevation = dpToPx(8f).toFloat()
        }
        
        val pillIcon = TextView(this).apply {
            text = "💊"
            textSize = 56f
            gravity = Gravity.CENTER
        }
        iconContainer.addView(pillIcon)
        contentContainer.addView(iconContainer)
        
        // Medicine details - concise and fixed height
        val detailsText = TextView(this).apply {
            id = android.R.id.text1
            textSize = 16f
            setTextColor(Color.parseColor("#F0FFFFFF"))
            gravity = Gravity.CENTER
            setLineSpacing(dpToPx(4f).toFloat(), 1.3f)
            typeface = Typeface.DEFAULT
            setShadowLayer(2f, 0f, 2f, Color.parseColor("#40000000"))
            setPadding(dpToPx(16f), dpToPx(12f), dpToPx(16f), dpToPx(12f))
            maxLines = 4 // Limit to 4 lines to prevent overflow
            ellipsize = TextUtils.TruncateAt.END
            
            background = android.graphics.drawable.GradientDrawable().apply {
                setColor(Color.parseColor("#20FFFFFF"))
                cornerRadius = dpToPx(16f).toFloat()
                setStroke(dpToPx(1f), Color.parseColor("#30FFFFFF"))
            }
            elevation = dpToPx(4f).toFloat()
            
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                setMargins(dpToPx(8f), dpToPx(16f), dpToPx(8f), dpToPx(16f))
            }
        }
        contentContainer.addView(detailsText)
        
        // Image container for medicine images - initially hidden until we know images are available
        val imageContainer = LinearLayout(this).apply {
            id = android.R.id.custom // Custom ID for image container
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dpToPx(320f) // Increased from 240f to 320f for even larger images
            )
            setPadding(dpToPx(12f), dpToPx(12f), dpToPx(12f), dpToPx(12f)) // Increased padding
            visibility = View.GONE // Initially hidden until we know images are available
            
            // Add elevation and background for better appearance
            elevation = dpToPx(12f).toFloat() // Increased elevation
            background = android.graphics.drawable.GradientDrawable().apply {
                setColor(Color.parseColor("#20FFFFFF")) // Back to original opacity
                cornerRadius = dpToPx(16f).toFloat() // Increased corner radius
                setStroke(dpToPx(1f), Color.parseColor("#40FFFFFF")) // Back to original stroke
            }
        }
        contentContainer.addView(imageContainer)
        
        mainContainer.addView(contentContainer)
        
        // Fixed button container at bottom
        val buttonContainer = createFixedButtonContainer()
        mainContainer.addView(buttonContainer)
        
        return mainContainer
    }
    
    // Get the configured snooze duration from SharedPreferences
    private fun getConfiguredSnoozeDuration(): Int {
        val settings = getSharedPreferences("notification_settings", Context.MODE_PRIVATE)
        return settings.getInt("snoozeDuration", 5) // Default to 5 minutes
    }
    
    private fun createFixedButtonContainer(): LinearLayout {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            background = android.graphics.drawable.GradientDrawable().apply {
                colors = intArrayOf(
                    Color.parseColor("#E0667eea"),
                    Color.parseColor("#667eea")
                )
                gradientType = android.graphics.drawable.GradientDrawable.LINEAR_GRADIENT
                orientation = android.graphics.drawable.GradientDrawable.Orientation.TOP_BOTTOM
            }
            setPadding(dpToPx(20f), dpToPx(20f), dpToPx(20f), dpToPx(24f))
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
            tag = "buttonContainer"
        }
    }
    
    private fun createImagesLayout(frontImagePath: String, backImagePath: String): LinearLayout {
        val imagesLayout = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.MATCH_PARENT
            )
        }

        if (frontImagePath.isNotEmpty()) {
            try {
                val frontImageView = createMedicineImageView(frontImagePath, "Front")
                val frontWrapper = createImageWrapper(frontImageView, "Front Side")
                imagesLayout.addView(frontWrapper)
            } catch (e: Exception) {
                Log.e("FullScreenAlarmActivity", "Error loading front image: ${e.message}")
            }
        }

        if (frontImagePath.isNotEmpty() && backImagePath.isNotEmpty()) {
            val spacer = Space(this).apply {
                layoutParams = LinearLayout.LayoutParams(
                    dpToPx(12f),
                    LinearLayout.LayoutParams.MATCH_PARENT
                )
            }
            imagesLayout.addView(spacer)
        }

        if (backImagePath.isNotEmpty()) {
            try {
                val backImageView = createMedicineImageView(backImagePath, "Back")
                val backWrapper = createImageWrapper(backImageView, "Back Side")
                imagesLayout.addView(backWrapper)
            } catch (e: Exception) {
                Log.e("FullScreenAlarmActivity", "Error loading back image: ${e.message}")
            }
        }

        return imagesLayout
    }

    private fun createMedicineImageView(imagePath: String, label: String): android.widget.ImageView {
        return android.widget.ImageView(this).apply {
            try {
                // Log path details for debugging
                Log.d("FullScreenAlarmActivity", "Loading image from path: $imagePath")
                
                val imageFile = java.io.File(imagePath)
                if (imageFile.exists()) {
                    Log.d("FullScreenAlarmActivity", "Image file exists, size: ${imageFile.length()} bytes")
                    
                    val options = android.graphics.BitmapFactory.Options().apply {
                        inJustDecodeBounds = true
                    }
                    android.graphics.BitmapFactory.decodeFile(imagePath, options)
                    Log.d("FullScreenAlarmActivity", "Image dimensions: ${options.outWidth}x${options.outHeight}")
                    
                    // Calculate sample size based on target size - increased for bigger images
                    options.inJustDecodeBounds = false
                    options.inSampleSize = calculateInSampleSize(options, 800, 800) // Increased from 512x512
                    Log.d("FullScreenAlarmActivity", "Using sample size: ${options.inSampleSize}")
                    
                    val bitmap = android.graphics.BitmapFactory.decodeFile(imagePath, options)
                    if (bitmap != null) {
                        Log.d("FullScreenAlarmActivity", "Successfully decoded bitmap: ${bitmap.width}x${bitmap.height}")
                        setImageBitmap(bitmap)
                        contentDescription = "$label image of medicine - tap to expand"
                        scaleType = android.widget.ImageView.ScaleType.CENTER_CROP // Changed to CENTER_CROP for better centering
                    } else {
                        Log.e("FullScreenAlarmActivity", "Failed to decode bitmap, using placeholder")
                        setImageResource(android.R.drawable.ic_menu_gallery)
                        contentDescription = "Medicine image not available"
                    }
                } else {
                    Log.e("FullScreenAlarmActivity", "Image file does not exist at path: $imagePath")
                    setImageResource(android.R.drawable.ic_menu_gallery)
                    contentDescription = "Medicine image not available"
                }
            } catch (e: Exception) {
                Log.e("FullScreenAlarmActivity", "Error loading image: ${e.message}", e)
                setImageResource(android.R.drawable.ic_menu_gallery)
                contentDescription = "Error loading medicine image"
            }
            
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.MATCH_PARENT
            )
            
            background = android.graphics.drawable.GradientDrawable().apply {
                setColor(Color.parseColor("#FFFFFF"))
                cornerRadius = dpToPx(12f).toFloat() // Increased corner radius
            }
            
            adjustViewBounds = true
            setPadding(dpToPx(4f), dpToPx(4f), dpToPx(4f), dpToPx(4f)) // Increased padding
            
            // Add tap to expand functionality
            setOnClickListener {
                showFullScreenImage(imagePath, label)
            }
            
            // Add visual feedback for tap
            isClickable = true
            isFocusable = true
        }
    }
    
    // Helper method to calculate optimal sample size for loading large images
    private fun calculateInSampleSize(options: android.graphics.BitmapFactory.Options, reqWidth: Int, reqHeight: Int): Int {
        val height = options.outHeight
        val width = options.outWidth
        var inSampleSize = 1
        
        if (height > reqHeight || width > reqWidth) {
            val halfHeight = height / 2
            val halfWidth = width / 2
            
            while ((halfHeight / inSampleSize) >= reqHeight && (halfWidth / inSampleSize) >= reqWidth) {
                inSampleSize *= 2
            }
        }
        
        return inSampleSize.coerceAtMost(2) // Limit max sample size to 2 for better quality
    }

    private fun createImageWrapper(imageView: android.widget.ImageView, label: String): LinearLayout {
        val wrapper = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                0,
                LinearLayout.LayoutParams.MATCH_PARENT,
                1.0f
            )
            
            elevation = dpToPx(8f).toFloat() // Increased elevation
            
            background = android.graphics.drawable.GradientDrawable().apply {
                setColor(Color.parseColor("#25FFFFFF")) // Back to original opacity
                cornerRadius = dpToPx(16f).toFloat() // Increased corner radius
                setStroke(dpToPx(1f), Color.parseColor("#40FFFFFF")) // Back to original stroke
            }
            
            setPadding(dpToPx(4f), dpToPx(4f), dpToPx(4f), dpToPx(4f)) // Increased padding
        }
        
        val imageContainer = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER // Ensure center alignment
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                0,
                0.95f // Increased from 0.9f to 0.95f to give even more space to image
            )
        }
        
        imageContainer.addView(imageView)
        wrapper.addView(imageContainer)
        
        val labelView = TextView(this).apply {
            text = "$label - Tap to expand" // Added tap hint
            textSize = 11f // Slightly larger text
            setTextColor(Color.parseColor("#E0FFFFFF")) // Back to original color
            gravity = Gravity.CENTER
            setPadding(0, dpToPx(4f), 0, 0) // Increased padding
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
            maxLines = 1
            ellipsize = TextUtils.TruncateAt.END
            typeface = Typeface.DEFAULT_BOLD // Make label bold
        }
        
        wrapper.addView(labelView)
        return wrapper
    }

    private fun displayMedicineDetails(payload: String) {
        try {
            val jsonObject = JSONObject(payload)
            val medicineName = jsonObject.optString("medicineName", "Medicine")
            val instructions = jsonObject.optString("instructions", "")
            
            Log.i("FullScreenAlarmActivity", "Payload received: $payload")
            Log.i("FullScreenAlarmActivity", "Displaying medicine: $medicineName")
            
            // OPTIMIZED IMAGE LOADING: Local storage first, database paths as fallback
            var frontImagePath = ""
            var backImagePath = ""
            
            // Step 1: Try to load images from local storage first (optimized approach)
            Log.i("FullScreenAlarmActivity", "Step 1: Checking local storage for images...")
            val localImages = findAnyAvailableImages()
            if (localImages.isNotEmpty()) {
                // Use local images if available (newest first)
                if (localImages.isNotEmpty()) {
                    frontImagePath = localImages.first()
                    Log.i("FullScreenAlarmActivity", "Found front image in local storage: $frontImagePath")
                }
                if (localImages.size > 1) {
                    backImagePath = localImages[1]
                    Log.i("FullScreenAlarmActivity", "Found back image in local storage: $backImagePath")
                }
            }
            
            // Step 2: If no local images, try database paths as fallback
            if (frontImagePath.isEmpty() || backImagePath.isEmpty()) {
                Log.i("FullScreenAlarmActivity", "Step 2: Checking database paths as fallback...")
                
                // Get database paths from payload
                val dbFrontImagePath = jsonObject.optString("frontImagePath", "")
                val dbBackImagePath = jsonObject.optString("backImagePath", "")
                
                Log.i("FullScreenAlarmActivity", "Database front image path: $dbFrontImagePath")
                Log.i("FullScreenAlarmActivity", "Database back image path: $dbBackImagePath")
                
                // Try to load front image from database path if not already found locally
                if (frontImagePath.isEmpty() && dbFrontImagePath.isNotEmpty()) {
                    val frontFile = java.io.File(dbFrontImagePath)
                    if (frontFile.exists()) {
                        val fileSize = frontFile.length()
                        if (fileSize > 0) {
                            frontImagePath = dbFrontImagePath
                            Log.i("FullScreenAlarmActivity", "Front image loaded from database path: $frontImagePath (size: $fileSize bytes)")
                        } else {
                            Log.w("FullScreenAlarmActivity", "Front image file exists but has zero size: $dbFrontImagePath")
                        }
                    } else {
                        Log.w("FullScreenAlarmActivity", "Front image file doesn't exist at database path: $dbFrontImagePath")
                        // Try to find the image in the medicine_images directory
                        val alternativePath = findImageInDirectory(dbFrontImagePath)
                        if (alternativePath != null) {
                            frontImagePath = alternativePath
                            Log.i("FullScreenAlarmActivity", "Found alternative front image from database path: $frontImagePath")
                        }
                    }
                }
                
                // Try to load back image from database path if not already found locally
                if (backImagePath.isEmpty() && dbBackImagePath.isNotEmpty()) {
                    val backFile = java.io.File(dbBackImagePath)
                    if (backFile.exists()) {
                        val fileSize = backFile.length()
                        if (fileSize > 0) {
                            backImagePath = dbBackImagePath
                            Log.i("FullScreenAlarmActivity", "Back image loaded from database path: $backImagePath (size: $fileSize bytes)")
                        } else {
                            Log.w("FullScreenAlarmActivity", "Back image file exists but has zero size: $dbBackImagePath")
                        }
                    } else {
                        Log.w("FullScreenAlarmActivity", "Back image file doesn't exist at database path: $dbBackImagePath")
                        // Try to find the image in the medicine_images directory
                        val alternativePath = findImageInDirectory(dbBackImagePath)
                        if (alternativePath != null) {
                            backImagePath = alternativePath
                            Log.i("FullScreenAlarmActivity", "Found alternative back image from database path: $backImagePath")
                        }
                    }
                }
            }
            
            // Step 3: Final fallback - search for any available images if still none found
            if (frontImagePath.isEmpty() && backImagePath.isEmpty()) {
                Log.i("FullScreenAlarmActivity", "Step 3: Final fallback - searching for any available images...")
                val availableImages = findAnyAvailableImages()
                if (availableImages.isNotEmpty()) {
                    if (frontImagePath.isEmpty() && availableImages.isNotEmpty()) {
                        frontImagePath = availableImages.first()
                        Log.i("FullScreenAlarmActivity", "Using first available image as front (final fallback): $frontImagePath")
                    }
                    if (backImagePath.isEmpty() && availableImages.size > 1) {
                        backImagePath = availableImages[1]
                        Log.i("FullScreenAlarmActivity", "Using second available image as back (final fallback): $backImagePath")
                    }
                }
            }
            
            // Log final image loading results
            Log.i("FullScreenAlarmActivity", "Final image loading results:")
            Log.i("FullScreenAlarmActivity", "  - Front image: ${if (frontImagePath.isNotEmpty()) frontImagePath else "Not found"}")
            Log.i("FullScreenAlarmActivity", "  - Back image: ${if (backImagePath.isNotEmpty()) backImagePath else "Not found"}")
            
            // Set medicine name at the top
            val medicineNameText = findViewById<TextView>(android.R.id.text2)
            medicineNameText.text = medicineName
            
            // Set details text
            val detailsText = findViewById<TextView>(android.R.id.text1)
            
            val detailsBuilder = StringBuilder()
            if (instructions.isNotEmpty()) {
                detailsBuilder.append("📝 Instructions: ").append(instructions)
            } else {
                detailsBuilder.append("Please take your medicine")
            }
            
            detailsText.text = detailsBuilder.toString()
            
            // Add images if available or hide the container if no images
            val imageContainer = findViewById<LinearLayout>(android.R.id.custom)
            if (imageContainer != null) {
                if (frontImagePath.isNotEmpty() || backImagePath.isNotEmpty()) {
                    Log.i("FullScreenAlarmActivity", "Setting up image container with images")
                    imageContainer.visibility = View.VISIBLE
                    imageContainer.removeAllViews() // Clear any existing views
                    val imagesLayout = createImagesLayout(frontImagePath, backImagePath)
                    
                    // Add all children from imagesLayout to imageContainer
                    while (imagesLayout.childCount > 0) {
                        val child = imagesLayout.getChildAt(0)
                        imagesLayout.removeViewAt(0)
                        imageContainer.addView(child)
                    }
                    
                    // Request layout after adding views to ensure correct display
                    imageContainer.requestLayout()
                    Log.i("FullScreenAlarmActivity", "Images added to container")
                } else {
                    Log.w("FullScreenAlarmActivity", "No images found in any source")
                    imageContainer.visibility = View.GONE
                }
            } else {
                Log.w("FullScreenAlarmActivity", "Image container not found")
            }
            
            // Setup action buttons
            setupEnhancedActionButtons()
            
        } catch (e: Exception) {
            Log.e("FullScreenAlarmActivity", "Error displaying medicine details: ${e.message}", e)
        }
    }
    
    // Helper method to find any available images in the medicine_images directory
    private fun findAnyAvailableImages(): List<String> {
        val availableImages = mutableListOf<String>()
        try {
            val appDir = getApplicationInfo().dataDir
            val medicineImagesDir = java.io.File(appDir, "medicine_images")
            
            if (medicineImagesDir.exists() && medicineImagesDir.isDirectory) {
                val files = medicineImagesDir.listFiles()
                
                if (files != null) {
                    for (file in files) {
                        if (file.isFile) {
                            val fileSize = file.length()
                            if (fileSize > 0) {
                                // Check if it's an image file by extension
                                val extension = file.extension.toLowerCase()
                                if (listOf("jpg", "jpeg", "png", "gif", "bmp", "webp").contains(extension)) {
                                    availableImages.add(file.absolutePath)
                                    Log.d("FullScreenAlarmActivity", "Found available image: ${file.absolutePath} (size: $fileSize bytes)")
                                }
                            }
                        }
                    }
                    
                    // Sort by modification time (newest first)
                    availableImages.sortByDescending { java.io.File(it).lastModified() }
                }
            }
        } catch (e: Exception) {
            Log.e("FullScreenAlarmActivity", "Error searching for available images: ${e.message}")
        }
        return availableImages
    }

    // Helper method to create images layout from file paths
    private fun createImagesLayoutFromFiles(imagePaths: List<String>): LinearLayout {
        val imagesLayout = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.MATCH_PARENT
            )
        }

        for ((index, imagePath) in imagePaths.take(2).withIndex()) {
            try {
                val label = if (index == 0) "Front" else "Back"
                val imageView = createMedicineImageView(imagePath, label)
                val wrapper = createImageWrapper(imageView, "$label Side")
                imagesLayout.addView(wrapper)
                
                // Add spacer between images
                if (index == 0 && imagePaths.size > 1) {
                    val spacer = Space(this).apply {
                        layoutParams = LinearLayout.LayoutParams(
                            dpToPx(12f),
                            LinearLayout.LayoutParams.MATCH_PARENT
                        )
                    }
                    imagesLayout.addView(spacer)
                }
            } catch (e: Exception) {
                Log.e("FullScreenAlarmActivity", "Error loading image from path: ${e.message}")
            }
        }

        return imagesLayout
    }

    // Helper method to find images in the medicine_images directory
    private fun findImageInDirectory(originalPath: String): String? {
        try {
            val appDir = getApplicationInfo().dataDir
            val medicineImagesDir = java.io.File(appDir, "medicine_images")
            
            if (medicineImagesDir.exists() && medicineImagesDir.isDirectory) {
                val fileName = java.io.File(originalPath).name
                val files = medicineImagesDir.listFiles()
                
                if (files != null) {
                    // Look for files with similar names
                    for (file in files) {
                        if (file.isFile && file.name.contains(fileName.split("_").lastOrNull() ?: "")) {
                            val fileSize = file.length()
                            if (fileSize > 0) {
                                Log.d("FullScreenAlarmActivity", "Found potential image file: ${file.absolutePath} (size: $fileSize bytes)")
                                return file.absolutePath
                            }
                        }
                    }
                    
                    // If no exact match, try to find any image file in the directory
                    for (file in files) {
                        if (file.isFile) {
                            val fileSize = file.length()
                            if (fileSize > 0) {
                                Log.d("FullScreenAlarmActivity", "Found alternative image file: ${file.absolutePath} (size: $fileSize bytes)")
                                return file.absolutePath
                            }
                        }
                    }
                }
            }
        } catch (e: Exception) {
            Log.e("FullScreenAlarmActivity", "Error searching for image in directory: ${e.message}")
        }
        return null
    }

    private fun setupEnhancedActionButtons() {
        try {
            // Find button container by tag
            val buttonContainer = mainLayout.findViewWithTag<LinearLayout>("buttonContainer")
            
            if (buttonContainer == null) {
                Log.e("FullScreenAlarmActivity", "Button container not found")
                return
            }
            
            buttonContainer.removeAllViews()
            
            // Primary take medicine button
            val takeButton = Button(this).apply {
                text = "✅ I WILL TAKE MY MEDICINE"
                textSize = 18f
                typeface = Typeface.DEFAULT_BOLD
                
                background = android.graphics.drawable.GradientDrawable().apply {
                    colors = intArrayOf(
                        Color.parseColor("#56ab2f"),
                        Color.parseColor("#a8e6cf")
                    )
                    gradientType = android.graphics.drawable.GradientDrawable.LINEAR_GRADIENT
                    cornerRadius = dpToPx(28f).toFloat()
                    setStroke(dpToPx(2f), Color.parseColor("#80FFFFFF"))
                }
                
                setTextColor(Color.WHITE)
                setPadding(dpToPx(28f), dpToPx(18f), dpToPx(28f), dpToPx(18f))
                elevation = dpToPx(10f).toFloat()
                letterSpacing = 0.02f
                maxLines = 1
                ellipsize = TextUtils.TruncateAt.END
                
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    dpToPx(64f)
                ).apply { 
                    setMargins(0, dpToPx(8f), 0, dpToPx(18f))
                }
                
                setOnClickListener {
                    if (!isActionHandled) {
                        handleAction("take_medicine")
                    }
                }
            }
            buttonContainer.addView(takeButton)
            
            // Secondary actions row
            val buttonRow = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT
                )
                weightSum = 2f
            }
            
            // Snooze button
            val snoozeButton = Button(this).apply {
                text = "⏰ SNOOZE\n${getConfiguredSnoozeDuration()} MIN"
                textSize = 14f
                typeface = Typeface.DEFAULT_BOLD
                
                background = android.graphics.drawable.GradientDrawable().apply {
                    colors = intArrayOf(
                        Color.parseColor("#ffeaa7"),
                        Color.parseColor("#fdcb6e")
                    )
                    gradientType = android.graphics.drawable.GradientDrawable.LINEAR_GRADIENT
                    cornerRadius = dpToPx(22f).toFloat()
                    setStroke(dpToPx(1f), Color.parseColor("#80FFFFFF"))
                }
                
                setTextColor(Color.parseColor("#2d3436"))
                setPadding(dpToPx(16f), dpToPx(12f), dpToPx(16f), dpToPx(12f))
                elevation = dpToPx(8f).toFloat()
                gravity = Gravity.CENTER
                maxLines = 2
                ellipsize = TextUtils.TruncateAt.END
                
                layoutParams = LinearLayout.LayoutParams(
                    0,
                    dpToPx(60f),
                    1.0f
                ).apply { 
                    setMargins(0, dpToPx(8f), dpToPx(8f), dpToPx(12f))
                }
                
                setOnClickListener {
                    if (!isActionHandled) {
                        handleAction("snooze")
                    }
                }
            }
            buttonRow.addView(snoozeButton)
            
            // Stop button
            val stopButton = Button(this).apply {
                text = "❌ STOP\nALARM"
                textSize = 14f
                typeface = Typeface.DEFAULT_BOLD
                
                background = android.graphics.drawable.GradientDrawable().apply {
                    colors = intArrayOf(
                        Color.parseColor("#fab1a0"),
                        Color.parseColor("#e17055")
                    )
                    gradientType = android.graphics.drawable.GradientDrawable.LINEAR_GRADIENT
                    cornerRadius = dpToPx(22f).toFloat()
                    setStroke(dpToPx(1f), Color.parseColor("#80FFFFFF"))
                }
                
                setTextColor(Color.WHITE)
                setPadding(dpToPx(16f), dpToPx(12f), dpToPx(16f), dpToPx(12f))
                elevation = dpToPx(8f).toFloat()
                gravity = Gravity.CENTER
                maxLines = 2
                ellipsize = TextUtils.TruncateAt.END
                
                layoutParams = LinearLayout.LayoutParams(
                    0,
                    dpToPx(60f),
                    1.0f
                ).apply { 
                    setMargins(dpToPx(8f), dpToPx(8f), 0, dpToPx(12f))
                }
                
                setOnClickListener {
                    if (!isActionHandled) {
                        handleAction("stop")
                    }
                }
            }
            buttonRow.addView(stopButton)
            
            buttonContainer.addView(buttonRow)
            
            // Instruction text
            val instructionText = TextView(this).apply {
                text = "Choose your action above"
                textSize = 13f
                setTextColor(Color.parseColor("#C0FFFFFF"))
                gravity = Gravity.CENTER
                setPadding(dpToPx(16f), dpToPx(8f), dpToPx(16f), 0)
                typeface = Typeface.DEFAULT
                maxLines = 1
                ellipsize = TextUtils.TruncateAt.END
            }
            buttonContainer.addView(instructionText)
            
            Log.i("FullScreenAlarmActivity", "Buttons setup completed successfully")
            
        } catch (e: Exception) {
            Log.e("FullScreenAlarmActivity", "Error setting up buttons: ${e.message}")
        }
    }
    
    private fun handleAction(action: String) {
        if (isActionHandled) {
            Log.w("FullScreenAlarmActivity", "Action already handled, ignoring duplicate")
            return
        }
        
        isActionHandled = true
        Log.i("FullScreenAlarmActivity", "Handling action: $action for alarm: $alarmId")
        
        val serviceIntent = Intent(this, NotificationService::class.java).apply {
            this.action = when (action) {
                "take_medicine" -> NotificationService.ACTION_TAKE_MEDICINE
                "snooze" -> NotificationService.ACTION_SNOOZE_ALARM
                "stop" -> NotificationService.ACTION_STOP_ALARM
                else -> NotificationService.ACTION_STOP_ALARM
            }
            putExtra("payload", payload)
            putExtra("alarmId", alarmId.toLong())
            putExtra("from_fullscreen", true)
            
            // Add snooze duration if action is snooze
            if (action == "snooze") {
                val snoozeDuration = getConfiguredSnoozeDuration()
                putExtra("snoozeDuration", snoozeDuration)
                Log.i("FullScreenAlarmActivity", "Snoozing with duration: $snoozeDuration minutes")
            }
        }
        
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(serviceIntent)
            } else {
                startService(serviceIntent)
            }
            
            val syncIntent = Intent("com.srmist.medicfood.ALARM_ACTION_SYNC").apply {
                putExtra("payload", payload)
                putExtra("alarmId", alarmId)
                putExtra("actionType", action)
            }
            sendBroadcast(syncIntent)
            
            Log.i("FullScreenAlarmActivity", "Action handled successfully: $action")
        } catch (e: Exception) {
            Log.e("FullScreenAlarmActivity", "Error handling action", e)
        }
        
        finish()
    }
    
    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        Log.i("FullScreenAlarmActivity", "Back button pressed - ignoring")
    }
    
    private fun showFullScreenImage(imagePath: String, label: String) {
        try {
            // Create a new dialog for full screen image
            val dialog = android.app.Dialog(this, android.R.style.Theme_Black_NoTitleBar_Fullscreen)
            
            // Create the layout for the dialog
            val dialogLayout = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                layoutParams = ViewGroup.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT
                )
                background = android.graphics.drawable.ColorDrawable(Color.BLACK)
                gravity = Gravity.CENTER
            }
            
            // Create the image view for full screen display
            val fullScreenImageView = android.widget.ImageView(this).apply {
                layoutParams = ViewGroup.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT
                )
                scaleType = android.widget.ImageView.ScaleType.FIT_CENTER
                adjustViewBounds = true
                
                // Load the image
                try {
                    val imageFile = java.io.File(imagePath)
                    if (imageFile.exists()) {
                        val options = android.graphics.BitmapFactory.Options().apply {
                            inJustDecodeBounds = false
                            inSampleSize = 1 // Load at full resolution for full screen
                        }
                        val bitmap = android.graphics.BitmapFactory.decodeFile(imagePath, options)
                        if (bitmap != null) {
                            setImageBitmap(bitmap)
                        } else {
                            setImageResource(android.R.drawable.ic_menu_gallery)
                        }
                    } else {
                        setImageResource(android.R.drawable.ic_menu_gallery)
                    }
                } catch (e: Exception) {
                    Log.e("FullScreenAlarmActivity", "Error loading full screen image: ${e.message}")
                    setImageResource(android.R.drawable.ic_menu_gallery)
                }
                
                // Add tap to close functionality
                setOnClickListener {
                    dialog.dismiss()
                }
                
                isClickable = true
                isFocusable = true
            }
            
            // Add close button at the top
            val closeButton = Button(this).apply {
                text = "✕"
                textSize = 24f
                setTextColor(Color.WHITE)
                background = android.graphics.drawable.GradientDrawable().apply {
                    setColor(Color.parseColor("#80000000"))
                    shape = android.graphics.drawable.GradientDrawable.OVAL
                }
                layoutParams = LinearLayout.LayoutParams(
                    dpToPx(48f),
                    dpToPx(48f)
                ).apply {
                    gravity = Gravity.TOP or Gravity.END
                    setMargins(0, dpToPx(40f), dpToPx(20f), 0)
                }
                
                setOnClickListener {
                    dialog.dismiss()
                }
            }
            
            // Add label text
            val labelText = TextView(this).apply {
                text = "$label - Tap to close"
                textSize = 16f
                setTextColor(Color.WHITE)
                gravity = Gravity.CENTER
                background = android.graphics.drawable.GradientDrawable().apply {
                    setColor(Color.parseColor("#80000000"))
                    cornerRadius = dpToPx(20f).toFloat()
                }
                setPadding(dpToPx(16f), dpToPx(8f), dpToPx(16f), dpToPx(8f))
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT
                ).apply {
                    gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
                    setMargins(0, dpToPx(40f), 0, 0)
                }
            }
            
            // Add views to dialog layout
            dialogLayout.addView(labelText)
            dialogLayout.addView(closeButton)
            dialogLayout.addView(fullScreenImageView)
            
            // Set the dialog content and show it
            dialog.setContentView(dialogLayout)
            dialog.show()
            
            Log.i("FullScreenAlarmActivity", "Full screen image dialog shown for: $label")
            
        } catch (e: Exception) {
            Log.e("FullScreenAlarmActivity", "Error showing full screen image: ${e.message}", e)
        }
    }
    
    override fun onDestroy() {
        super.onDestroy()
        
        try {
            actionReceiver?.let { unregisterReceiver(it) }
            closeReceiver?.let { unregisterReceiver(it) }
        } catch (e: Exception) {
            Log.e("FullScreenAlarmActivity", "Error unregistering receivers", e)
        }
        
        if (wakeLock?.isHeld == true) {
            wakeLock?.release()
        }
        
        Log.i("FullScreenAlarmActivity", "Activity destroyed")
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            window.decorView.systemUiVisibility = (
                View.SYSTEM_UI_FLAG_LAYOUT_STABLE or
                View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_FULLSCREEN or
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
            )
        }
    }
}

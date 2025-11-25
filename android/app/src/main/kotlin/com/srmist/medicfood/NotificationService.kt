package com.srmist.medicfood

import android.app.*
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Color
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.*
import android.provider.Settings
import android.util.Log
import androidx.core.app.NotificationCompat     
import org.json.JSONObject
import android.content.BroadcastReceiver
import android.media.AudioFocusRequest
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        context?.let {
            when (intent?.action) {
                ACTION_TRIGGER_EFFECTS -> {
                    val payload = intent.getStringExtra("payload")
                    // Fix: Use getLongExtra and convert to Int safely
                    val alarmId = intent.getLongExtra("alarmId", -1L).toInt()
                    
                    Log.i("AlarmReceiver", "AlarmManager triggered for ID: $alarmId")
                    
                    val serviceIntent = Intent(context, NotificationService::class.java).apply {
                        action = NotificationService.ACTION_TRIGGER_EFFECTS
                        putExtra("payload", payload)
                        putExtra("alarmId", alarmId.toLong()) // Store as Long
                        putExtra("triggered_by_alarm", true)
                    }
                    
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        context.startForegroundService(serviceIntent)
                    } else {
                        context.startService(serviceIntent)
                    }
                }
            }
        }
    }
    
    companion object {
        const val ACTION_TRIGGER_EFFECTS = "com.srmist.medicfood.ALARM_TRIGGER_EFFECTS"
    }
}

class NotificationActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        context?.let {
            Log.i("NotificationActionReceiver", "Action received: ${intent?.action}")
            
            // Fix: Use getLongExtra and convert to Int safely
            val alarmId = intent?.getLongExtra("alarmId", -1L)?.toInt() ?: -1
            
            // Broadcast the action to sync with FullScreenAlarmActivity
            val syncIntent = Intent("com.srmist.medicfood.ALARM_ACTION_SYNC").apply {
                action = intent?.action
                putExtra("payload", intent?.getStringExtra("payload"))
                putExtra("alarmId", alarmId.toLong()) // Store as Long
            }
            context.sendBroadcast(syncIntent)
            
            val serviceIntent = Intent(context, NotificationService::class.java).apply {
                action = intent?.action
                putExtra("payload", intent?.getStringExtra("payload"))
                putExtra("alarmId", alarmId.toLong()) // Store as Long
                putExtra("background_action", true)
            }
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent)
            } else {
                context.startService(serviceIntent)
            }
            
            // Immediately cancel all notifications to prevent duplicates
            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.cancelAll()
        }
    }
}

class NotificationService : Service(), MethodChannel.MethodCallHandler {
    private var mediaPlayer: MediaPlayer? = null
    private var vibrator: Vibrator? = null
    private val vibrationHandler = Handler(Looper.getMainLooper())
    private var vibrationRunnable: Runnable? = null
    private val autoStopHandler = Handler(Looper.getMainLooper())
    private var autoStopRunnable: Runnable? = null
    private var isAlarmActive = false
    private var audioManager: AudioManager? = null
    private var audioFocusRequest: AudioFocusRequest? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var currentAlarmId: Int = -1
    private var currentActivity: Activity? = null
    private var isActivityVisible = false
    
    // Track all scheduled alarms to prevent duplicates
    private val scheduledAlarms = mutableSetOf<Int>()
    
    // NEW: Queue for pending alarms that should be shown
    private val pendingAlarms = mutableListOf<AlarmData>()
    
    // NEW: Data class to hold alarm information
    data class AlarmData(
        val alarmId: Int,
        val payload: String,
        val triggerTime: Long,
        val triggeredByAlarm: Boolean = false
    )
    
    // SharedPreferences for settings
    private lateinit var settings: SharedPreferences

    // Binder for local service binding
    private val binder = LocalBinder()
    
    // Add this as a class property at the top of the class
    private var methodChannel: MethodChannel? = null
    
    inner class LocalBinder : Binder() {
        val service: NotificationService
            get() = this@NotificationService
    }

    companion object {
        private const val CHANNEL_ID = "medication_alarm_service"
        private const val SERVICE_CHANNEL_ID = "foreground_service"
        private const val NOTIFICATION_ID = 1001
        private const val ALARM_NOTIFICATION_ID = 2001
        const val OVERLAY_PERMISSION_REQUEST_CODE = 1234
        const val AUDIO_PERMISSION_REQUEST_CODE = 1235
        const val CUSTOM_SOUND_REQUEST_CODE = 1236
        
        // Settings keys
        private const val SETTINGS_PREFS = "notification_settings"
        private const val KEY_VIBRATION = "vibration"
        private const val KEY_SOUND = "sound"
        private const val KEY_USE_DEFAULT_ALARM = "useDefaultAlarm"
        private const val KEY_CUSTOM_SOUND_PATH = "customSoundPath"
        private const val KEY_VOICE_FILE_PATH = "voiceFilePath"
        private const val KEY_NOTIFICATIONS_ENABLED = "notifications_enabled"
        private const val KEY_OVERLAY_ENABLED = "overlay_enabled"
        private const val KEY_FULL_SCREEN = "fullScreen"
        private const val KEY_SNOOZE_DURATION = "snoozeDuration"
        
        // Action Constants
        const val ACTION_STOP_ALARM = "com.srmist.medicfood.STOP_ALARM"
        const val ACTION_SNOOZE_ALARM = "com.srmist.medicfood.SNOOZE_ALARM"
        const val ACTION_TAKE_MEDICINE = "com.srmist.medicfood.TAKE_MEDICINE"
        const val ACTION_TRIGGER_EFFECTS = "com.srmist.medicfood.TRIGGER_EFFECTS"
        const val ACTION_POSTPONE_MEDICINE = "com.srmist.medicfood.POSTPONE_MEDICINE"
        const val ACTION_MARK_MISSED = "com.srmist.medicfood.MARK_MISSED"
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannels()
        
        // Initialize SharedPreferences for settings with default fullScreen = true
        settings = getSharedPreferences(SETTINGS_PREFS, Context.MODE_PRIVATE)
        
        // Ensure fullScreen is enabled by default
        if (!settings.contains(KEY_FULL_SCREEN)) {
            settings.edit().putBoolean(KEY_FULL_SCREEN, true).apply()
            Log.i("NotificationService", "Set fullScreen default to true")
        }
        
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "NotificationService::WakeLock"
        )
        
        vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val vibratorManager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
            vibratorManager.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
        
        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        
        // Initialize method channel
        try {
            val flutterEngine = io.flutter.embedding.engine.FlutterEngineCache.getInstance().get("my_engine_id")
            if (flutterEngine != null) {
                methodChannel = MethodChannel(flutterEngine.dartExecutor, "notification_service")
                methodChannel?.setMethodCallHandler(this)
                Log.i("NotificationService", "Method channel initialized successfully")
            } else {
                Log.e("NotificationService", "Flutter engine not found, method channel not initialized")
            }
        } catch (e: Exception) {
            Log.e("NotificationService", "Error initializing method channel", e)
        }
        
        Log.i("NotificationService", "Service created successfully with fullScreen enabled")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Always start foreground immediately
        startForeground(NOTIFICATION_ID, createServiceNotification())
        
        val action = intent?.action
        // Fix: Use getLongExtra and convert to Int safely
        val alarmId = intent?.getLongExtra("alarmId", -1L)?.toInt() ?: -1
        val payload = intent?.getStringExtra("payload")
        val triggeredByAlarm = intent?.getBooleanExtra("triggered_by_alarm", false) ?: false
        
        Log.i("NotificationService", "Service command - Action: $action, AlarmID: $alarmId, TriggeredByAlarm: $triggeredByAlarm")
        
        when (action) {
            ACTION_TRIGGER_EFFECTS -> {
                if (payload != null && alarmId != -1) {
                    // Check if this alarm was already stopped
                    if (alarmId == currentAlarmId && !isAlarmActive) {
                        Log.i("NotificationService", "Alarm $alarmId was already stopped, ignoring")
                        return START_STICKY
                    }
                    
                    handleEffectTrigger(alarmId, payload, triggeredByAlarm)
                }
            }
            ACTION_STOP_ALARM, ACTION_TAKE_MEDICINE -> {
                Log.i("NotificationService", "Stop/Take action for alarm: $alarmId")
                stopAllEffects()
                markMedicineAsTaken(payload)
            }
            ACTION_SNOOZE_ALARM -> {
                Log.i("NotificationService", "Snooze action for alarm: $alarmId")
                stopAllEffects()
                scheduleSnooze(alarmId, payload)
            }
        }
        
        return START_STICKY
    }

    // Method channel implementation with proper type handling
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "scheduleEffectTrigger" -> {
                try {
                    // Fix: Handle both Int and Long for alarmId
                    val alarmId = when (val rawAlarmId = call.argument<Any>("alarmId")) {
                        is Int -> rawAlarmId
                        is Long -> rawAlarmId.toInt()
                        else -> return result.error("INVALID_ARGS", "Missing or invalid alarmId", null)
                    }
                    
                    // Fix: Always expect Long for triggerTime
                    val triggerTime = call.argument<Long>("triggerTime") 
                        ?: return result.error("INVALID_ARGS", "Missing triggerTime", null)
                    
                    val payload = call.argument<String>("payload") 
                        ?: return result.error("INVALID_ARGS", "Missing payload", null)
                    
                    scheduleAlarmManagerTrigger(alarmId, triggerTime, payload)
                    result.success(true)
                } catch (e: Exception) {
                    Log.e("NotificationService", "Error in scheduleEffectTrigger", e)
                    result.error("SCHEDULE_ERROR", e.message, null)
                }
            }
            "cancelAllEffectTriggers" -> {
                try {
                    cancelAllAlarmManagerTriggers()
                    result.success(true)
                } catch (e: Exception) {
                    result.error("CANCEL_ERROR", e.message, null)
                }
            }
            "getSnoozedAlarms" -> {
                try {
                    val alarmsList = getSnoozedAlarmsFromPrefs()
                    result.success(alarmsList)
                } catch (e: Exception) {
                    Log.e("NotificationService", "Error getting snoozed alarms", e)
                    result.error("SNOOZE_ERROR", "Failed to get snoozed alarms: ${e.message}", null)
                }
            }
            "checkOverlayPermission" -> {
                try {
                    result.success(Settings.canDrawOverlays(this))
                } catch (e: Exception) {
                    result.error("PERMISSION_ERROR", e.message, null)
                }
            }
            "requestOverlayPermission" -> {
                try {
                    currentActivity?.let { activity ->
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val intent = Intent(
                                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                Uri.parse("package:${activity.packageName}")
                            )
                            activity.startActivityForResult(intent, OVERLAY_PERMISSION_REQUEST_CODE)
                            result.success(true)
                        } else {
                            result.success(true)
                        }
                    } ?: result.error("NO_ACTIVITY", "Activity reference not set", null)
                } catch (e: Exception) {
                    result.error("PERMISSION_ERROR", e.message, null)
                }
            }
            "getNotificationSettings" -> {
                try {
                    val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    val notificationsEnabled = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                        notificationManager.areNotificationsEnabled()
                    } else {
                        true
                    }
                    
                    val overlayEnabled = Settings.canDrawOverlays(this)
                    
                    val settingsMap = mapOf(
                        "notifications_enabled" to notificationsEnabled,
                        "overlay_enabled" to overlayEnabled,
                        "fullScreen" to getStoredSetting(KEY_FULL_SCREEN, true),
                        "vibration" to getStoredSetting(KEY_VIBRATION, true),
                        "sound" to getStoredSetting(KEY_SOUND, true),
                        "useDefaultAlarm" to getStoredSetting(KEY_USE_DEFAULT_ALARM, true),
                        "customSoundPath" to getStoredSetting(KEY_CUSTOM_SOUND_PATH, ""),
                        "voiceFilePath" to getStoredSetting(KEY_VOICE_FILE_PATH, ""),
                        "snoozeDuration" to getStoredSetting(KEY_SNOOZE_DURATION, 5)
                    )
                    
                    result.success(settingsMap)
                } catch (e: Exception) {
                    result.error("SETTINGS_ERROR", e.message, null)
                }
            }
            "handleMedicineAction" -> {
                try {
                    val action = call.argument<String>("action") 
                        ?: return result.error("INVALID_ARGS", "Missing action", null)
                    val payload = call.argument<String>("payload") 
                        ?: return result.error("INVALID_ARGS", "Missing payload", null)
                    
                    when (action) {
                        "taken" -> markMedicineAsTaken(payload)
                        "missed" -> markMedicineAsMissed(payload)
                        "skipped" -> markMedicineAsSkipped(payload)
                        else -> {
                            Log.w("NotificationService", "Unknown medicine action: $action")
                            result.error("UNKNOWN_ACTION", "Unknown medicine action: $action", null)
                            return
                        }
                    }
                    
                    result.success(true)
                } catch (e: Exception) {
                    result.error("MEDICINE_ACTION_ERROR", e.message, null)
                }
            }
            "updateSettings" -> {
                try {
                    val settingsMap = call.arguments as? Map<String, Any>
                    if (settingsMap == null) {
                        result.error("INVALID_ARGS", "Settings map is required", null)
                        return
                    }
                    
                    Log.i("NotificationService", "Updating settings: $settingsMap")
                    
                    settingsMap.forEach { (key, value) ->
                        when (key) {
                            KEY_VIBRATION, KEY_SOUND, KEY_USE_DEFAULT_ALARM, KEY_FULL_SCREEN -> {
                                if (value is Boolean) {
                                    storeSetting(key, value)
                                    Log.i("NotificationService", "Updated boolean setting $key: $value")
                                }
                            }
                            KEY_SNOOZE_DURATION -> {
                                when (value) {
                                    is Int -> {
                                        storeSetting(key, value)
                                        Log.i("NotificationService", "Updated snooze duration: $value minutes")
                                    }
                                    is Double -> {
                                        storeSetting(key, value.toInt())
                                        Log.i("NotificationService", "Updated snooze duration (from Double): ${value.toInt()} minutes")
                                    }
                                    is String -> {
                                        try {
                                            val intValue = value.toInt()
                                            storeSetting(key, intValue)
                                            Log.i("NotificationService", "Updated snooze duration (from String): $intValue minutes")
                                        } catch (e: Exception) {
                                            Log.e("NotificationService", "Invalid snooze duration: $value")
                                        }
                                    }
                                    else -> {
                                        Log.e("NotificationService", "Invalid type for snooze duration: ${value?.javaClass}")
                                    }
                                }
                            }
                            KEY_CUSTOM_SOUND_PATH -> {
                                if (value is String) {
                                    storeSetting(key, value)
                                    Log.i("NotificationService", "Updated custom sound path: $value")
                                    
                                    // Send event back to Flutter to confirm the sound was set
                                    try {
                                        val eventData = mapOf(
                                            "customSoundPath" to value,
                                            "timestamp" to System.currentTimeMillis()
                                        )
                                        
                                        // Use the methodChannel if available, otherwise log the error
                                        methodChannel?.invokeMethod("customSoundUpdated", eventData)
                                            ?: Log.e("NotificationService", "Method channel not set, can't send customSoundUpdated event")
                                        
                                    } catch (e: Exception) {
                                        Log.e("NotificationService", "Error sending sound update event", e)
                                    }
                                    
                                    // Validate the sound file can be played
                                    validateSoundFile(value)
                                }
                            }
                            KEY_VOICE_FILE_PATH -> {
                                if (value is String) {
                                    storeSetting(key, value)
                                    Log.i("NotificationService", "Updated voice file path: $value")
                                    
                                    // Validate the voice file can be played
                                    validateSoundFile(value)
                                }
                            }
                        }
                    }
                    
                    result.success(true)
                } catch (e: Exception) {
                    Log.e("NotificationService", "Error updating settings", e)
                    result.error("UPDATE_ERROR", e.message, null)
                }
            }
            "handleAction" -> {
                try {
                    val action = call.argument<String>("action") 
                        ?: return result.error("INVALID_ARGS", "Missing action", null)
                    val payload = call.argument<String>("payload") 
                        ?: return result.error("INVALID_ARGS", "Missing payload", null)
                    
                    try {
                        val payloadJson = JSONObject(payload)
                        // Fix: Handle alarmId as both Int and Long
                        val alarmId = when (val rawId = payloadJson.opt("alarmId")) {
                            is Int -> rawId
                            is Long -> rawId.toInt()
                            else -> -1
                        }
                        
                        handleAlarmAction(action, payload, alarmId)
                        result.success(true)
                    } catch (e: Exception) {   
                        Log.e("NotificationService", "Error parsing payload for action", e)
                        result.error("PAYLOAD_ERROR", e.message, null)
                    }
                } catch (e: Exception) {
                    result.error("ACTION_ERROR", e.message, null)
                }
            }
            "cancelAlarm" -> {
                try {
                    // Fix: Handle both Int and Long for alarmId
                    val alarmId = when (val rawAlarmId = call.argument<Any>("alarmId")) {
                        is Int -> rawAlarmId
                        is Long -> rawAlarmId.toInt()
                        else -> return result.error("INVALID_ARGS", "Missing or invalid alarmId", null)
                    }
                    
                    cancelAlarmManagerTrigger(alarmId)
                    scheduledAlarms.remove(alarmId)
                    
                    Log.i("NotificationService", "Cancelled specific alarm: $alarmId")
                    result.success(true)
                } catch (e: Exception) {
                    result.error("CANCEL_ERROR", e.message, null)
                }
            }
            "checkOverlayPermissionDirect" -> {
                try {
                    val hasPermission = checkOverlayPermissionDirect()
                    Log.i("NotificationService", "Returning overlay permission status: $hasPermission")
                    result.success(hasPermission)
                } catch (e: Exception) {
                    result.error("PERMISSION_ERROR", e.message, null)
                }
            }
            "getRealAppActionsData" -> {
                try {
                    // Get real app actions data and return to Flutter
                    val actionsData = getRealAppActionsData()
                    result.success(actionsData)
                } catch (e: Exception) {
                    Log.e("NotificationService", "Error getting real app actions data", e)
                    result.error("DATA_ERROR", e.message, null)
                }
            }
            "getQueueStatus" -> {
                try {
                    val queueStatus = mapOf(
                        "currentAlarmId" to currentAlarmId,
                        "isAlarmActive" to isAlarmActive,
                        "pendingAlarmsCount" to pendingAlarms.size,
                        "scheduledAlarmsCount" to scheduledAlarms.size,
                        "pendingAlarms" to pendingAlarms.map { it.alarmId }
                    )
                    result.success(queueStatus)
                } catch (e: Exception) {
                    Log.e("NotificationService", "Error getting queue status", e)
                    result.error("QUEUE_ERROR", e.message, null)
                }
            }
            else -> {
                Log.w("NotificationService", "Method not implemented: ${call.method}")
                result.notImplemented()
            }
        }
    }

    // Fix the scheduleAlarmManagerTrigger method
    private fun scheduleAlarmManagerTrigger(alarmId: Int, triggerTime: Long, payload: String) {
        try {
            // Check permissions first
            if (!checkAndRequestExactAlarmPermission()) {
                Log.e("NotificationService", "Exact alarm permission not granted")
                return
            }
            
            // Cancel existing alarm with same ID first
            cancelAlarmManagerTrigger(alarmId)
            
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val intent = Intent(this, AlarmReceiver::class.java).apply {
                action = AlarmReceiver.ACTION_TRIGGER_EFFECTS
                putExtra("payload", payload)
                putExtra("alarmId", alarmId.toLong()) // Store as Long
                putExtra("scheduleTime", System.currentTimeMillis())
            }
            
            val pendingIntent = PendingIntent.getBroadcast(
                this,
                alarmId,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            
            // Use multiple scheduling methods for reliability
            when {
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.M -> {
                    alarmManager.setExactAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        triggerTime,
                        pendingIntent
                    )
                }
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT -> {
                    alarmManager.setExact(
                        AlarmManager.RTC_WAKEUP,
                        triggerTime,
                        pendingIntent
                    )
                }
                else -> {
                    alarmManager.set(
                        AlarmManager.RTC_WAKEUP,
                        triggerTime,
                        pendingIntent
                    )
                }
            }
            
            scheduledAlarms.add(alarmId)
            
            Log.i("NotificationService", "AlarmManager trigger scheduled for ID: $alarmId at ${java.util.Date(triggerTime)}")
            
        } catch (e: Exception) {
            Log.e("NotificationService", "Error scheduling alarm trigger", e)
            throw e
        }
    }

    // Keep all your existing private methods with the same fixes applied to any alarmId handling
    private fun handleEffectTrigger(alarmId: Int, payload: String, triggeredByAlarm: Boolean) {
        try {
            Log.i("NotificationService", "Effect trigger received for alarm: $alarmId")
            
            // Add this alarm to the pending queue
            val alarmData = AlarmData(alarmId, payload, System.currentTimeMillis(), triggeredByAlarm)
            pendingAlarms.add(alarmData)
            
            Log.i("NotificationService", "Added alarm $alarmId to pending queue. Queue size: ${pendingAlarms.size}")
            
            // If no alarm is currently active, process the next alarm
            if (!isAlarmActive) {
                processNextAlarm()
            } else {
                Log.i("NotificationService", "Alarm $currentAlarmId is currently active, alarm $alarmId will be queued")
            }
            
        } catch (e: Exception) {
            Log.e("NotificationService", "Error handling effect trigger", e)
        }
    }
    
    // NEW: Method to process the next alarm in the queue
    private fun processNextAlarm() {
        if (pendingAlarms.isEmpty()) {
            Log.i("NotificationService", "No pending alarms to process")
            return
        }
        
        val alarmData = pendingAlarms.removeAt(0)
        val alarmId = alarmData.alarmId
        val payload = alarmData.payload
        val triggeredByAlarm = alarmData.triggeredByAlarm
        
        Log.i("NotificationService", "Processing next alarm: $alarmId from queue. Remaining: ${pendingAlarms.size}")
        
        try {
            val jsonObject = JSONObject(payload)
            val settingsObj = jsonObject.opt("settings")
            val payloadSettings = when (settingsObj) {
                is JSONObject -> settingsObj
                is String -> JSONObject(settingsObj.toString())
                else -> JSONObject()
            }
            
            val medicineName = jsonObject.optString("medicineName", "Medicine")
            val dosage = jsonObject.optString("dosage", "")
            val time = jsonObject.optString("time", jsonObject.optString("scheduled_time", ""))

            currentAlarmId = alarmId
            isAlarmActive = true
            
            Log.i("NotificationService", "Starting alarm effects for ID: $alarmId")

            if (triggeredByAlarm) {
                acquireWakeLock()
            }

            showAlarmNotification(alarmId, medicineName, dosage, payload, forceFullScreen = true)
            
            val useVibration = payloadSettings.optBoolean("vibration", getStoredSetting(KEY_VIBRATION, true))
            val useSound = payloadSettings.optBoolean("sound", getStoredSetting(KEY_SOUND, true))
            val useDefaultAlarm = payloadSettings.optBoolean("useDefaultAlarm", getStoredSetting(KEY_USE_DEFAULT_ALARM, true))
            val customSoundPath = payloadSettings.optString("customSoundPath", getStoredSetting(KEY_CUSTOM_SOUND_PATH, ""))
            val voiceFilePath = payloadSettings.optString("voiceFilePath", "")
            
            Log.i("NotificationService", "Voice file path from payload: '$voiceFilePath'")
            
            // Check if voice file exists and is accessible
            val correctedVoicePath = verifyAndFixVoicePath(voiceFilePath)
            val voiceFileExists = correctedVoicePath.isNotEmpty() && File(correctedVoicePath).exists()
            
            Log.i("NotificationService", "Voice file exists: $voiceFileExists")
            if (voiceFileExists) {
                Log.i("NotificationService", "Using voice file: $correctedVoicePath")
            }
            
            if (useVibration) {
                startContinuousVibration()
            }

            if (useSound) {
                playAlarmSound(
                    useDefault = useDefaultAlarm,
                    customPath = customSoundPath,
                    voicePath = correctedVoicePath
                )
            }

            autoStopRunnable = Runnable {
                if (isAlarmActive && currentAlarmId == alarmId) {
                    Log.i("NotificationService", "Auto-stopping alarm $alarmId after 5 minutes")
                    stopAllEffects()
                }
            }
            autoStopHandler.postDelayed(autoStopRunnable!!, 5 * 60 * 1000L)

        } catch (e: Exception) {
            Log.e("NotificationService", "Error processing alarm $alarmId", e)
            currentAlarmId = alarmId
            isAlarmActive = true
            showAlarmNotification(alarmId, "Medicine", "Take now", payload, forceFullScreen = true)
            playDefaultAlarm()
        }
    }

    private fun showAlarmNotification(alarmId: Int, medicineName: String, dosage: String, payload: String, forceFullScreen: Boolean = false) {
        try {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.cancel(ALARM_NOTIFICATION_ID)

            val fullScreenIntent = Intent(this, FullScreenAlarmActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or 
                       Intent.FLAG_ACTIVITY_CLEAR_TOP or
                       Intent.FLAG_ACTIVITY_SINGLE_TOP or
                       Intent.FLAG_ACTIVITY_NO_USER_ACTION or
                       Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS
                putExtra("payload", payload)
                putExtra("alarmId", alarmId.toLong()) // Store as Long
                putExtra("forceFullScreen", true)
            }

            val fullScreenPendingIntent = PendingIntent.getActivity(
                this,
                alarmId,
                fullScreenIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val takeMedicineIntent = Intent(this, NotificationActionReceiver::class.java).apply {
                action = ACTION_TAKE_MEDICINE
                putExtra("payload", payload)
                putExtra("alarmId", alarmId.toLong())
            }
            val takeMedicinePendingIntent = PendingIntent.getBroadcast(
                this,
                alarmId * 10 + 1,
                takeMedicineIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val snoozeIntent = Intent(this, NotificationActionReceiver::class.java).apply {
                action = ACTION_SNOOZE_ALARM
                putExtra("payload", payload)
                putExtra("alarmId", alarmId.toLong())
            }
            val snoozePendingIntent = PendingIntent.getBroadcast(
                this,
                alarmId * 10 + 2,
                snoozeIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val stopIntent = Intent(this, NotificationActionReceiver::class.java).apply {
                action = ACTION_STOP_ALARM
                putExtra("payload", payload)
                putExtra("alarmId", alarmId.toLong())
            }
            val stopPendingIntent = PendingIntent.getBroadcast(
                this,
                alarmId * 10 + 3,
                stopIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val useFullScreen = forceFullScreen || getStoredSetting(KEY_FULL_SCREEN, true)
            
            val notification = NotificationCompat.Builder(this, CHANNEL_ID)
                .setContentTitle("💊 Medicine Time: $medicineName")
                .setContentText("Dosage: $dosage")
                .setSmallIcon(android.R.drawable.ic_dialog_alert)
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .apply {
                    if (useFullScreen) {
                        setFullScreenIntent(fullScreenPendingIntent, true)
                        Log.i("NotificationService", "Fullscreen intent set for notification")
                    }
                }
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setOngoing(true)
                .setAutoCancel(false)
                .addAction(android.R.drawable.ic_menu_send, "Take Medicine", takeMedicinePendingIntent)
                .addAction(android.R.drawable.ic_popup_reminder, "Snooze", snoozePendingIntent)
                .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Stop", stopPendingIntent)
                .setStyle(NotificationCompat.BigTextStyle()
                    .bigText("💊 MEDICINE REMINDER\n\nMedicine: $medicineName\nDosage: $dosage\n\n⏰ Please take your medicine now!"))
                .build()

            notificationManager.notify(ALARM_NOTIFICATION_ID, notification)
            
            Log.i("NotificationService", "Alarm notification shown for ID: $alarmId with fullscreen: $useFullScreen")

            if (useFullScreen) {
                try {
                    startActivity(fullScreenIntent)
                    Log.i("NotificationService", "Fullscreen activity started for alarm: $alarmId")
                } catch (e: Exception) {
                    Log.e("NotificationService", "Failed to start fullscreen activity", e)
                }
            }

        } catch (e: Exception) {
            Log.e("NotificationService", "Error showing alarm notification", e)
        }
    }

    // Keep all other existing methods with proper error handling...
    // [Include all your other private methods like stopAllEffects(), cancelAlarmManagerTrigger(), etc.]
    
    private fun stopAllEffects() {
        try {
            Log.i("NotificationService", "STOPPING ALL EFFECTS - Current alarm: $currentAlarmId")
            
            val stoppedAlarmId = currentAlarmId
            isAlarmActive = false
            currentAlarmId = -1
            
            // Stop vibration
            vibrationRunnable?.let { vibrationHandler.removeCallbacks(it) }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator?.cancel()
            } else {
                @Suppress("DEPRECATION")
                vibrator?.cancel()
            }
            
            // Stop sound
            mediaPlayer?.let { player ->
                if (player.isPlaying) {
                    player.stop()
                }
                player.release()
            }
            mediaPlayer = null
            
            // Release audio focus
            audioFocusRequest?.let { request ->
                audioManager?.abandonAudioFocusRequest(request)
            }
            audioFocusRequest = null
            
            // Cancel auto-stop
            autoStopRunnable?.let { autoStopHandler.removeCallbacks(it) }
            autoStopRunnable = null
            
            // Release wake lock
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
            }
            
            // Cancel notification
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.cancel(ALARM_NOTIFICATION_ID)
            
            Log.i("NotificationService", "All effects stopped for alarm: $stoppedAlarmId")
            
            // NEW: Process next alarm in queue if available
            if (pendingAlarms.isNotEmpty()) {
                Log.i("NotificationService", "Processing next alarm after stopping $stoppedAlarmId")
                // Add a small delay to ensure the current alarm is fully stopped
                Handler(Looper.getMainLooper()).postDelayed({
                    processNextAlarm()
                }, 1000) // 1 second delay
            } else {
                Log.i("NotificationService", "No more pending alarms")
            }
            
        } catch (e: Exception) {
            Log.e("NotificationService", "Error stopping effects", e)
        }
    }

    private fun cancelAlarmManagerTrigger(alarmId: Int) {
        try {
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val intent = Intent(this, AlarmReceiver::class.java).apply {
                action = AlarmReceiver.ACTION_TRIGGER_EFFECTS
            }
            val pendingIntent = PendingIntent.getBroadcast(
                this,
                alarmId,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            alarmManager.cancel(pendingIntent)
            pendingIntent.cancel()
            
            Log.i("NotificationService", "Cancelled AlarmManager trigger for alarm: $alarmId")
        } catch (e: Exception) {
            Log.e("NotificationService", "Error cancelling alarm trigger", e)
        }
    }

    private fun cancelAllAlarmManagerTriggers() {
        try {
            Log.i("NotificationService", "Cancelling all AlarmManager triggers")
            
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            
            // Cancel all scheduled alarms
            scheduledAlarms.forEach { alarmId ->
                val intent = Intent(this, AlarmReceiver::class.java).apply {
                    action = AlarmReceiver.ACTION_TRIGGER_EFFECTS
                    putExtra("alarmId", alarmId.toLong())
                }
                
                val pendingIntent = PendingIntent.getBroadcast(
                    this,
                    alarmId,
                    intent,
                    PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
                )
                
                pendingIntent?.let {
                    alarmManager.cancel(it)
                    it.cancel()
                    Log.i("NotificationService", "Cancelled alarm: $alarmId")
                }
            }
            
            scheduledAlarms.clear()
            
            // NEW: Clear pending alarms queue
            pendingAlarms.clear()
            Log.i("NotificationService", "Cleared pending alarms queue")
            
        } catch (e: Exception) {
            Log.e("NotificationService", "Error cancelling all triggers", e)
        }
    }

    // Add all other existing helper methods...
    private fun checkAndRequestExactAlarmPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            if (!alarmManager.canScheduleExactAlarms()) {
                currentActivity?.let { activity ->
                    val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM)
                    activity.startActivity(intent)
                }
                false
            } else {
                true
            }
        } else {
            true
        }
    }

    private fun getStoredSetting(key: String, defaultValue: Boolean): Boolean {
        return settings.getBoolean(key, when (key) {
            KEY_FULL_SCREEN -> true
            else -> defaultValue
        })
    }

    private fun getStoredSetting(key: String, defaultValue: String): String {
        return settings.getString(key, defaultValue) ?: defaultValue
    }

    private fun getStoredSetting(key: String, defaultValue: Int): Int {
        return settings.getInt(key, defaultValue)
    }

    private fun storeSetting(key: String, value: Boolean) {
        settings.edit().putBoolean(key, value).apply()
        Log.i("NotificationService", "Stored setting $key = $value")
    }

    private fun storeSetting(key: String, value: String) {
        settings.edit().putString(key, value).apply()
        Log.i("NotificationService", "Stored setting $key = $value")
    }
    
    private fun storeSetting(key: String, value: Int) {
        settings.edit().putInt(key, value).apply()
        Log.i("NotificationService", "Stored setting $key = $value")
    }

    // Add all other missing methods like createNotificationChannels, playAlarmSound, etc.
    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            val alarmChannel = NotificationChannel(
                CHANNEL_ID,
                "Medication Alarms",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Critical medication alerts"
                setShowBadge(true)
                enableVibration(false)
                enableLights(true)
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
                setBypassDnd(true)
                setSound(null, null)
            }

            val serviceChannel = NotificationChannel(
                SERVICE_CHANNEL_ID,
                "Medication Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Background medication monitoring"
                setShowBadge(false)
                enableVibration(false)
                enableLights(false)
                setSound(null, null)
            }

            notificationManager.createNotificationChannel(alarmChannel)
            notificationManager.createNotificationChannel(serviceChannel)
        }
    }

    private fun createServiceNotification(): android.app.Notification {
        return NotificationCompat.Builder(this, SERVICE_CHANNEL_ID)
            .setContentTitle("💊 Medication Service")
            .setContentText("Monitoring medication reminders")
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .setShowWhen(false)
            .build()
    }

    private fun updateServiceNotification(title: String, text: String) {
        val notification = NotificationCompat.Builder(this, SERVICE_CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .setShowWhen(false)
            .build()
        
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(NOTIFICATION_ID, notification)
    }

    private fun acquireWakeLock() {
        try {
            if (wakeLock?.isHeld != true) {
                wakeLock?.acquire(10 * 60 * 1000L)
                Log.i("NotificationService", "WakeLock acquired")
            }
        } catch (e: Exception) {
            Log.e("NotificationService", "Error acquiring wake lock", e)
        }
    }

    private fun startContinuousVibration() {
        try {
            val pattern = longArrayOf(0, 1000, 500, 1000, 500)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator?.vibrate(VibrationEffect.createWaveform(pattern, 0))
            } else {
                @Suppress("DEPRECATION")
                vibrator?.vibrate(pattern, 0)
            }
            Log.i("NotificationService", "Vibration started")
        } catch (e: Exception) {
            Log.e("NotificationService", "Vibration error", e)
        }
    }

    private fun playAlarmSound(useDefault: Boolean = true, customPath: String = "", voicePath: String = "") {
        try {
            // Stop any existing sound
            stopSound()
            
            // Check if sound is enabled
            if (!getStoredSetting(KEY_SOUND, true)) {
                Log.i("NotificationService", "Sound disabled in settings")
                return
            }
            
            // Request audio focus before playing
            if (!requestAudioFocus()) {
                Log.w("NotificationService", "Failed to gain audio focus, but continuing anyway")
            }
            
            // CORRECTED Priority order: Voice recording > Custom sound > Default alarm
            when {
                // First priority: Voice recording (highest priority when available)
                voicePath.isNotEmpty() && File(voicePath).exists() -> {
                    try {
                        Log.i("NotificationService", "Playing voice recording (highest priority): $voicePath")
                        
                        // Verify file is readable and not empty
                        val voiceFile = File(voicePath)
                        if (!voiceFile.canRead()) {
                            Log.e("NotificationService", "Voice file is not readable: $voicePath")
                            playAlarmSound(useDefault, customPath, "") // Fallback without voice
                            return
                        }
                        
                        if (voiceFile.length() == 0L) {
                            Log.e("NotificationService", "Voice file is empty: $voicePath")
                            playAlarmSound(useDefault, customPath, "") // Fallback without voice
                            return
                        }
                        
                        mediaPlayer = MediaPlayer().apply {
                            setDataSource(voicePath)
                            
                            // Configure AudioAttributes for alarm playback
                            setAudioAttributes(
                                AudioAttributes.Builder()
                                    .setUsage(AudioAttributes.USAGE_ALARM)
                                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                                    .setFlags(AudioAttributes.FLAG_AUDIBILITY_ENFORCED)
                                    .build()
                            )
                            
                            isLooping = true
                            setVolume(1.0f, 1.0f)
                            
                            try {
                                prepareAsync()
                                setOnPreparedListener { mp ->
                                    try {
                                        mp.start()
                                        Log.i("NotificationService", "Voice recording started successfully: $voicePath")
                                    } catch (e: Exception) {
                                        Log.e("NotificationService", "Error starting voice recording playback", e)
                                        mp.release()
                                        playAlarmSound(useDefault, customPath, "") // Fallback without voice
                                    }
                                }
                                setOnErrorListener { mp, what, extra ->
                                    Log.e("NotificationService", "Error playing voice recording (what=$what, extra=$extra), falling back to custom sound")
                                    try {
                                        mp.release()
                                    } catch (e: Exception) {
                                        Log.e("NotificationService", "Error releasing MediaPlayer", e)
                                    }
                                    playAlarmSound(useDefault, customPath, "") // Fallback without voice
                                    true
                                }
                                setOnCompletionListener { mp ->
                                    // If looping is enabled, this shouldn't be called, but handle it anyway
                                    Log.i("NotificationService", "Voice recording playback completed")
                                }
                            } catch (e: Exception) {
                                Log.e("NotificationService", "Error preparing voice recording, falling back to custom sound", e)
                                try {
                                    release()
                                } catch (releaseEx: Exception) {
                                    Log.e("NotificationService", "Error releasing MediaPlayer after prepare error", releaseEx)
                                }
                                playAlarmSound(useDefault, customPath, "") // Fallback without voice
                            }
                        }
                    } catch (e: Exception) {
                        Log.e("NotificationService", "Error with voice recording file, falling back to custom sound", e)
                        playAlarmSound(useDefault, customPath, "") // Fallback without voice
                    }
                }
                
                // Second priority: Custom sound (when not using default)
                !useDefault && customPath.isNotEmpty() && File(customPath).exists() -> {
                    try {
                        Log.i("NotificationService", "Playing custom sound: $customPath")
                        mediaPlayer = MediaPlayer().apply {
                            setDataSource(customPath)
                            
                            // Configure AudioAttributes for alarm playback
                            setAudioAttributes(
                                AudioAttributes.Builder()
                                    .setUsage(AudioAttributes.USAGE_ALARM)
                                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                                    .setFlags(AudioAttributes.FLAG_AUDIBILITY_ENFORCED)
                                    .build()
                            )
                            
                            isLooping = true
                            setVolume(1.0f, 1.0f)
                            
                            try {
                                prepareAsync()
                                setOnPreparedListener { mp ->
                                    mp.start()
                                    Log.i("NotificationService", "Custom sound started: $customPath")
                                }
                                setOnErrorListener { mp, what, extra ->
                                    Log.e("NotificationService", "Error playing custom sound, falling back to default", null)
                                    mp.release()
                                    playDefaultAlarm()
                                    true
                                }
                            } catch (e: Exception) {
                                Log.e("NotificationService", "Error preparing custom sound, falling back to default", e)
                                playDefaultAlarm()
                            }
                        }
                    } catch (e: Exception) {
                        Log.e("NotificationService", "Error with custom sound file, falling back to default", e)
                        playDefaultAlarm()
                    }
                }
                
                // Third priority: Default alarm (when useDefault is true or other options fail)
                else -> {
                    Log.i("NotificationService", "Playing default alarm sound")
                    playDefaultAlarm()
                }
            }
        } catch (e: Exception) {
            Log.e("NotificationService", "Error playing alarm sound", e)
        }
    }

    private fun playDefaultAlarm() {
        try {
            // Get the default alarm sound URI
            val defaultAlarmUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            
            // If no alarm sound found, try notification sound
            val soundUri = defaultAlarmUri ?: 
                          RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            
            mediaPlayer = MediaPlayer().apply {
                setDataSource(applicationContext, soundUri)
                
                // Configure AudioAttributes for alarm playback
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .setFlags(AudioAttributes.FLAG_AUDIBILITY_ENFORCED)
                        .build()
                )
                
                isLooping = true
                setVolume(1.0f, 1.0f)
                prepare()
                start()
                Log.i("NotificationService", "Default alarm sound started")
            }
        } catch (e: Exception) {
            Log.e("NotificationService", "Error playing default alarm", e)
        }
    }
    
    private fun requestAudioFocus(): Boolean {
        return try {
            audioManager?.let { manager ->
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    // Use AudioFocusRequest for Android O and above
                    val audioAttributes = AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                    
                    audioFocusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
                        .setAudioAttributes(audioAttributes)
                        .setAcceptsDelayedFocusGain(true)
                        .setOnAudioFocusChangeListener { focusChange ->
                            when (focusChange) {
                                AudioManager.AUDIOFOCUS_GAIN -> {
                                    Log.i("NotificationService", "Audio focus gained")
                                    mediaPlayer?.let { player ->
                                        if (!player.isPlaying) {
                                            try {
                                                player.start()
                                            } catch (e: Exception) {
                                                Log.e("NotificationService", "Error resuming playback after focus gain", e)
                                            }
                                        }
                                    }
                                }
                                AudioManager.AUDIOFOCUS_LOSS, AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                                    Log.w("NotificationService", "Audio focus lost")
                                    // Don't stop playback for alarms - they should continue
                                }
                            }
                        }
                        .build()
                    
                    val result = manager.requestAudioFocus(audioFocusRequest!!)
                    if (result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
                        Log.i("NotificationService", "Audio focus requested and granted")
                        true
                    } else {
                        Log.w("NotificationService", "Audio focus request denied: $result")
                        false
                    }
                } else {
                    // Use deprecated method for older Android versions
                    @Suppress("DEPRECATION")
                    val result = manager.requestAudioFocus(
                        null,
                        AudioManager.STREAM_ALARM,
                        AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK
                    )
                    if (result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
                        Log.i("NotificationService", "Audio focus requested and granted (legacy)")
                        true
                    } else {
                        Log.w("NotificationService", "Audio focus request denied (legacy): $result")
                        false
                    }
                }
            } ?: run {
                Log.e("NotificationService", "AudioManager is null, cannot request audio focus")
                false
            }
        } catch (e: Exception) {
            Log.e("NotificationService", "Error requesting audio focus", e)
            false
        }
    }

    private fun stopSound() {
        mediaPlayer?.apply {
            try {
                if (isPlaying) stop()
            } catch (e: Exception) {
                Log.e("NotificationService", "Error stopping MediaPlayer", e)
            } finally {
                release()
                mediaPlayer = null
            }
        }
    }

    private fun scheduleSnooze(originalAlarmId: Int, payload: String?, snoozeDuration: Int = 0) {
        if (payload == null) {
            Log.e("NotificationService", "Cannot snooze - no payload")
            return
        }
        
        try {
            // Parse the original payload 
            val originalPayload = JSONObject(payload)
            
            // Create a new ID for the snoozed alarm that's reliably consistent
            val snoozeAlarmId = originalAlarmId + 100000
            
            // Get snooze duration from parameter, payload, or preferences (default to 5 minutes)
            val finalSnoozeDuration = when {
                // Use the provided parameter if it's valid
                snoozeDuration > 0 -> snoozeDuration
                // Otherwise try to get from payload
                originalPayload.has("snoozeDuration") -> originalPayload.getInt("snoozeDuration")
                // Finally fall back to preferences
                else -> getSharedPreferences("notification_settings", Context.MODE_PRIVATE)
                    .getInt("snoozeDuration", 5)
            }
            
            Log.i("NotificationService", "Using snooze duration of $finalSnoozeDuration minutes")
            
            // Calculate trigger time based on the snooze duration
            val triggerTime = System.currentTimeMillis() + (finalSnoozeDuration * 60 * 1000)
            
            // Update payload with snooze information for better tracking
            originalPayload.put("isSnooze", true)
            originalPayload.put("snoozeTime", triggerTime)
            originalPayload.put("originalAlarmId", originalAlarmId)
            originalPayload.put("alarmId", snoozeAlarmId)
            originalPayload.put("snoozeDuration", finalSnoozeDuration)
            
            if (!originalPayload.has("snoozeCount")) {
                originalPayload.put("snoozeCount", 1)
            } else {
                originalPayload.put("snoozeCount", originalPayload.getInt("snoozeCount") + 1)
            }
            
            // Get the enhanced payload string
            val enhancedPayload = originalPayload.toString()
            
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val intent = Intent(this, AlarmReceiver::class.java).apply {
                action = AlarmReceiver.ACTION_TRIGGER_EFFECTS
                putExtra("payload", enhancedPayload)
                putExtra("alarmId", snoozeAlarmId.toLong())
                putExtra("isSnooze", true)
            }
            
            val pendingIntent = PendingIntent.getBroadcast(
                this,
                snoozeAlarmId,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            
            alarmManager.setExactAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                triggerTime,
                pendingIntent
            )
            
            scheduledAlarms.add(snoozeAlarmId)
            
            // Store snoozed alarm data in SharedPreferences for persistence
            val prefs = getSharedPreferences("NotificationPrefs", Context.MODE_PRIVATE)
            val snoozeKey = "snoozed_alarm_$snoozeAlarmId"
            prefs.edit().putString(snoozeKey, enhancedPayload).apply()
            
            Log.i("NotificationService", "Snooze data stored with key: $snoozeKey")
            Log.i("NotificationService", "Snooze scheduled for alarm $snoozeAlarmId in $finalSnoozeDuration minutes")
            
            showSnoozeConfirmation(finalSnoozeDuration)
            
        } catch (e: Exception) {
            Log.e("NotificationService", "Error scheduling snooze", e)
        }
    }

    private fun showSnoozeConfirmation(snoozeDuration: Int) {
        val snoozeTime = System.currentTimeMillis() + (snoozeDuration * 60 * 1000)
        val dateFormat = java.text.SimpleDateFormat("h:mm a", java.util.Locale.getDefault())
        val formattedTime = dateFormat.format(java.util.Date(snoozeTime))
        
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_popup_reminder)
            .setContentTitle("Reminder Snoozed")
            .setContentText("Your medication reminder will sound again at $formattedTime (in $snoozeDuration minutes)")
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setAutoCancel(true)
            .build()
            
        val notificationId = "snooze_confirmation".hashCode()
        notificationManager.notify(notificationId, notification)
        
        // Auto-dismiss the notification after 3 seconds
        Handler(Looper.getMainLooper()).postDelayed({
            notificationManager.cancel(notificationId)
        }, 3000)
        
        updateServiceNotification("Medication Service", "Reminder snoozed until $formattedTime")
    }

    private fun markMedicineAsTaken(payload: String?) {
        processMedicineAction("taken", payload)
    }

    private fun markMedicineAsMissed(payload: String?) {
        processMedicineAction("missed", payload)
    }

    private fun markMedicineAsSkipped(payload: String?) {
        processMedicineAction("skipped", payload)
    }

    private fun markMedicineAsPostponed(payload: String?) {
        processMedicineAction("postponed", payload)
    }

    // Unified method for handling medicine actions
    private fun processMedicineAction(actionType: String, payload: String?) {
        if (payload == null) {
            Log.e("NotificationService", "Cannot process $actionType action - null payload")
            return
        }
        
        try {
            // Parse the payload to get medicine information
            val jsonObject = JSONObject(payload)
            val medicineName = jsonObject.optString("medicineName", "Unknown Medicine")
            
            // Use standardizeMedicineId to ensure consistent format
            val rawMedicineId = jsonObject.opt("medicineId") ?: jsonObject.opt("id")
            val medicineId = standardizeMedicineId(rawMedicineId)
            
            val dosage = jsonObject.optString("dosage", "")
            val time = jsonObject.optString("time", jsonObject.optString("scheduled_time", ""))
            
            // Get current date in yyyy-MM-dd format
            val dateFormat = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.getDefault())
            val currentDate = dateFormat.format(java.util.Date())
            
            // Create adherence data to send to Flutter
            val adherenceData = mapOf(
                "action" to actionType,
                "medicineId" to medicineId,  // Now consistently a string
                "medicineName" to medicineName,
                "dosage" to dosage,
                "date" to currentDate,
                "time" to time,
                "timestamp" to System.currentTimeMillis().toString(),  // Send as string for consistency
                "payload" to payload
            )
            
            // Notify Flutter of the action
            notifyFlutterOfMedicineAction(actionType, medicineId, payload)
            
            // Show confirmation notification for taken actions
            if (actionType == "taken") {
                val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                
                val notification = NotificationCompat.Builder(this, CHANNEL_ID)
                    .setContentTitle("✅ Medicine Taken")
                    .setContentText("$medicineName recorded as taken")
                    .setSmallIcon(android.R.drawable.ic_menu_send)
                    .setPriority(NotificationCompat.PRIORITY_DEFAULT)
                    .setAutoCancel(true)
                    .setTimeoutAfter(5000)
                    .build()
                    
                val notificationId = ALARM_NOTIFICATION_ID + 2
                notificationManager.notify(notificationId, notification)
                
                Handler(Looper.getMainLooper()).postDelayed({
                    notificationManager.cancel(notificationId)
                }, 5000)
            }
            
            Log.i("NotificationService", "Processed $actionType action for $medicineName")
            
        } catch (e: Exception) {
            Log.e("NotificationService", "Error processing medicine action $actionType", e)
        }
    }

    private fun handleAlarmAction(action: String, payload: String?, alarmId: Int) {
        if (payload == null) {
            Log.e("NotificationService", "Cannot handle action - no payload")
            return
        }

        when (action) {
            ACTION_TAKE_MEDICINE -> {
                Log.i("NotificationService", "Take action for alarm: $alarmId")
                stopAllEffects()
                markMedicineAsTaken(payload)
            }
            ACTION_SNOOZE_ALARM -> {
                Log.i("NotificationService", "Snooze action for alarm: $alarmId")
                stopAllEffects()
                
                // Get custom snooze duration from extras if available
                // Fix: Use the snooze duration from settings instead of intent
                val snoozeDuration = getSnoozeMinutes()
                
                if (snoozeDuration > 0) {
                    Log.i("NotificationService", "Using configured snooze duration: $snoozeDuration minutes")
                    scheduleSnooze(alarmId, payload, snoozeDuration)
                } else {
                    scheduleSnooze(alarmId, payload)
                }
            }
            ACTION_STOP_ALARM -> {
                Log.i("NotificationService", "Stop action for alarm: $alarmId")
                stopAllEffects()
                // Instead of immediately marking as missed, show a follow-up reminder after 5 minutes
                createPostponedMedicineNotification(payload, alarmId)
                Log.i("NotificationService", "Scheduled follow-up notification for alarm $alarmId in 5 minutes")
            }
            ACTION_MARK_MISSED -> {
                Log.i("NotificationService", "Mark missed action for alarm: $alarmId")
                markMedicineAsMissed(payload)
            }
            else -> {
                Log.w("NotificationService", "Unknown action: $action")
            }
        }
    }

    // Create a notification allowing the user to mark as taken later
    private fun createPostponedMedicineNotification(payload: String?, alarmId: Int) {
        if (payload == null) return
        
        try {
            val jsonObject = JSONObject(payload)
            val medicineName = jsonObject.optString("medicineName", "Unknown Medicine")
            
            // Use standardizeMedicineId for consistent format
            val rawMedicineId = jsonObject.opt("medicineId") ?: jsonObject.opt("id")
            val medicineId = standardizeMedicineId(rawMedicineId)
            
            val dosage = jsonObject.optString("dosage", "")
            
            // Store this medicine ID as postponed
            val prefs = getSharedPreferences("postponed_medicines", Context.MODE_PRIVATE)
            prefs.edit().putString(
                medicineId, 
                System.currentTimeMillis().toString()
            ).apply()
            
            // Create take action intent
            val takeIntent = Intent(this, NotificationActionReceiver::class.java).apply {
                action = ACTION_TAKE_MEDICINE
                putExtra("payload", payload)
                putExtra("alarmId", alarmId.toLong())
            }
            val takePendingIntent = PendingIntent.getBroadcast(
                this, 
                (alarmId * 10 + 1), // Unique request code
                takeIntent, 
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            
            // Create miss action intent
            val missIntent = Intent(this, NotificationActionReceiver::class.java).apply {
                action = ACTION_MARK_MISSED
                putExtra("payload", payload)
                putExtra("alarmId", alarmId.toLong())
            }
            val missPendingIntent = PendingIntent.getBroadcast(
                this, 
                (alarmId * 10 + 2), // Unique request code
                missIntent, 
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            
            // Schedule the follow-up notification after 5 minutes
            val handler = Handler(Looper.getMainLooper())
            handler.postDelayed({
                // Create notification after 5 minutes
                val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                
                val notification = NotificationCompat.Builder(this, CHANNEL_ID)
                    .setSmallIcon(android.R.drawable.ic_dialog_info)
                    .setContentTitle("Did you take $medicineName?")
                    .setContentText("Please confirm if you took $medicineName $dosage")
                    .setPriority(NotificationCompat.PRIORITY_HIGH)
                    .setCategory(NotificationCompat.CATEGORY_REMINDER)
                    .addAction(android.R.drawable.ic_menu_send, "Yes, I took it", takePendingIntent)
                    .addAction(android.R.drawable.ic_menu_close_clear_cancel, "No, I missed it", missPendingIntent)
                    .setAutoCancel(true)
                    .build()
                    
                val postponedNotificationId = medicineId.hashCode() // Unique notification ID based on medicine ID
                notificationManager.notify(postponedNotificationId, notification)
                
                Log.i("NotificationService", "Showing follow-up notification for $medicineName after 5 minutes")
            }, 5 * 60 * 1000) // 5 minutes delay
            
            // Schedule auto-marking as missed after 2 hours and 5 minutes if no action is taken
            // (5 minutes for the follow-up notification + 2 hours for user to respond)
            val autoMarkHandler = Handler(Looper.getMainLooper())
            autoMarkHandler.postDelayed({
                // Check if still in postponed state
                val currentTime = System.currentTimeMillis()
                val postponedTime = prefs.getString(medicineId, null)?.toLongOrNull()
                
                if (postponedTime != null && (currentTime - postponedTime < 4 * 60 * 60 * 1000)) {
                    // Still postponed, and less than 4 hours passed - mark as missed
                    markMedicineAsMissed(payload)
                    val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    notificationManager.cancel(medicineId.hashCode()) // Cancel the follow-up notification
                    prefs.edit().remove(medicineId).apply()
                    Log.i("NotificationService", "Auto-marked $medicineName as missed after 2 hours and 5 minutes")
                }
            }, (2 * 60 * 60 * 1000) + (5 * 60 * 1000)) // 2 hours + 5 minutes
            
        } catch (e: Exception) {
            Log.e("NotificationService", "Error creating postponed medicine notification", e)
            // Fallback to marking as missed immediately
            markMedicineAsMissed(payload)
        }
    }

    fun setActivity(activity: Activity?) {
        currentActivity = activity
        isActivityVisible = activity != null
        Log.i("NotificationService", "Activity set: ${activity != null}")
    }

    fun setActivityVisible(visible: Boolean) {
        isActivityVisible = visible
        Log.i("NotificationService", "Activity visibility: $visible")
    }

    override fun onDestroy() {
        Log.i("NotificationService", "Service being destroyed")
        stopAllEffects()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder {
        return binder
    }

    /**
     * Validates if a sound file can be played without actually playing it
     */
    private fun validateSoundFile(filePath: String) {
        try {
            val media = MediaPlayer()
            media.setDataSource(filePath)
            
            // Try preparing without actually playing
            try {
                // Just prepare to check if file is valid
                media.prepare()
                Log.i("NotificationService", "Sound file is valid: $filePath")
            } finally {
                media.release()
            }
        } catch (e: Exception) {
            Log.e("NotificationService", "Invalid sound file: $filePath", e)
            // File is invalid, fall back to default alarm sound
            storeSetting(KEY_USE_DEFAULT_ALARM, true)
        }
    }

    // Add this method to set the method channel from MainActivity
    fun setMethodChannel(channel: MethodChannel) {
        methodChannel = channel
        Log.i("NotificationService", "Method channel set from MainActivity")
    }

    private fun checkOverlayPermissionDirect(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                val result = Settings.canDrawOverlays(this)
                Log.i("NotificationService", "Direct overlay permission check: $result")
                result
            } catch (e: Exception) {
                Log.e("NotificationService", "Error checking overlay permission", e)
                false
            }
        } else {
            Log.i("NotificationService", "Android version < M, overlay permission not required")
            true
        }
    }

    private fun parseAndShowNotification(payload: String, alarmId: Int, forceFullScreen: Boolean = false) {
        try {
            val jsonObject = JSONObject(payload)
            val medicineName = jsonObject.optString("medicineName", "Medicine")
            val dosage = jsonObject.optString("dosage", "")
            val timing = jsonObject.optString("timing", "")
            val instructions = jsonObject.optString("instructions", "")
            
            val frontImagePath = jsonObject.optString("frontImagePath", "")
            val backImagePath = jsonObject.optString("backImagePath", "")
            
            // Process image paths if they exist
            val processedFrontImagePath = if (frontImagePath.isNotEmpty()) verifyAndFixImagePath(frontImagePath) else ""
            val processedBackImagePath = if (backImagePath.isNotEmpty()) verifyAndFixImagePath(backImagePath) else ""
            
            // Update the payload with processed paths
            val updatedPayload = if (processedFrontImagePath != frontImagePath || processedBackImagePath != backImagePath) {
                jsonObject.put("frontImagePath", processedFrontImagePath)
                jsonObject.put("backImagePath", processedBackImagePath)
                jsonObject.toString()
            } else {
                payload
            }
            Log.i("NotificationService", "Parsed notification - Medicine: $medicineName, Has front image: ${processedFrontImagePath.isNotEmpty()}, Has back image: ${processedBackImagePath.isNotEmpty()}")
            
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val fullScreenIntent = Intent(this, FullScreenAlarmActivity::class.java).apply {
                // Flags to ensure the activity opens correctly
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or 
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or 
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra("payload", updatedPayload)
                putExtra("alarmId", alarmId.toLong())
                putExtra("forceFullScreen", forceFullScreen)
                
                // Add image paths separately for better reliability
                putExtra("frontImagePath", processedFrontImagePath)
                putExtra("backImagePath", processedBackImagePath)
            }
            
            // Proceed with rest of notification setup...
        } catch (e: Exception) {
            Log.e("NotificationService", "Error parsing and showing notification", e)
        }
    }

    // Helper method to verify and fix voice file paths
    private fun verifyAndFixVoicePath(voicePath: String): String {
        try {
            // Skip if path is empty
            if (voicePath.isEmpty()) return ""
            
            // Check if the file exists as provided
            val providedFile = File(voicePath)
            if (providedFile.exists() && providedFile.canRead() && providedFile.length() > 0) {
                Log.i("NotificationService", "Voice file exists at original path: $voicePath")
                return voicePath
            }
            
            // Try to find the file in external storage
            val externalDir = applicationContext.getExternalFilesDir(null)
            if (externalDir != null) {
                val filename = providedFile.name
                val externalFile = File(externalDir, "voice_recordings/$filename")
                if (externalFile.exists() && externalFile.canRead() && externalFile.length() > 0) {
                    Log.i("NotificationService", "Found voice file in external storage: ${externalFile.absolutePath}")
                    return externalFile.absolutePath
                }
                
            }
            
            // Try to find in app files directory as fallback
            val appDir = applicationContext.filesDir
            val appVoiceFile = File(appDir, "voice_recordings/${providedFile.name}")
            if (appVoiceFile.exists() && appVoiceFile.canRead() && appVoiceFile.length() > 0) {
                Log.i("NotificationService", "Found voice file in app directory: ${appVoiceFile.absolutePath}")
                return appVoiceFile.absolutePath
            }
            
            Log.w("NotificationService", "Voice file not found in any location: $voicePath")
            return voicePath
        } catch (e: Exception) {
            Log.e("NotificationService", "Error verifying voice file path: $voicePath", e)
            return voicePath
        }
    }

    // Helper method to verify and fix image paths
    private fun verifyAndFixImagePath(imagePath: String): String {
        try {
            // Skip if path is empty
            if (imagePath.isEmpty()) return ""
            
            // Check if the file exists as provided
            val providedFile = File(imagePath)
            if (providedFile.exists() && providedFile.canRead() && providedFile.length() > 0) {
                Log.i("NotificationService", "Image exists at original path: $imagePath")
                return imagePath
            }
            
            // Try to find the file in app's directories
            val filename = providedFile.name
            
            // Check in external files directory
            val externalDir = applicationContext.getExternalFilesDir(null)
            if (externalDir != null) {
                val medicineImagesExternal = File(externalDir, "medicine_images")
                val externalFile = File(medicineImagesExternal, filename)
                if (externalFile.exists() && externalFile.canRead() && externalFile.length() > 0) {
                    Log.i("NotificationService", "Found image in external directory: ${externalFile.absolutePath}")
                    return externalFile.absolutePath
                }
            }
            
            // Check in app files directory
            val appDir = applicationContext.filesDir
            val medicineImagesInternal = File(appDir, "medicine_images")
            val internalFile = File(medicineImagesInternal, filename)
            if (internalFile.exists() && internalFile.canRead() && internalFile.length() > 0) {
                Log.i("NotificationService", "Found image in internal directory: ${internalFile.absolutePath}")
                return internalFile.absolutePath
            }
            
            // Check if we can copy the file to make it accessible
            if (providedFile.exists() && providedFile.length() > 0) {
                try {
                    val medicineImagesDir = File(applicationContext.filesDir, "medicine_images")
                    if (!medicineImagesDir.exists()) {
                        medicineImagesDir.mkdirs()
                    }
                    val destinationFile = File(medicineImagesDir, filename)
                    providedFile.inputStream().use { input ->
                        destinationFile.outputStream().use { output ->
                            input.copyTo(output)
                        }
                    }
                    if (destinationFile.exists() && destinationFile.length() > 0) {
                        Log.i("NotificationService", "Copied image to accessible location: ${destinationFile.absolutePath}")
                        return destinationFile.absolutePath
                    }
                } catch (e: Exception) {
                    Log.e("NotificationService", "Failed to copy image file: ${e.message}")
                }
            }
            
            Log.w("NotificationService", "Could not find or fix image path: $imagePath")
            return imagePath // Return original path as fallback
        } catch (e: Exception) {
            Log.e("NotificationService", "Error processing image path: ${e.message}")
            return imagePath
        }
    }

    // New method to get real medication action data
    private fun getRealAppActionsData(): String {
        Log.i("NotificationService", "Getting real app medication actions data")
        
        try {
            // Get medication actions from shared preferences or database
            val prefs = getSharedPreferences("medication_actions", Context.MODE_PRIVATE)
            val actionsJson = prefs.getString("actions_history", null)
            
            // If we have saved actions, return them
            if (!actionsJson.isNullOrEmpty()) {
                Log.i("NotificationService", "Found existing medication actions data")
                return actionsJson
            }
            
            // Otherwise, create sample data
            Log.i("NotificationService", "No existing data found, generating sample data")
            return generateSampleMedicationActions()
        } catch (e: Exception) {
            Log.e("NotificationService", "Error retrieving actions data", e)
            throw e
        }
    }
    
    // Helper method to generate sample medication actions data if none exists
    private fun generateSampleMedicationActions(): String {
        Log.i("NotificationService", "Generating sample medication actions data")
        
        
        val today = java.time.LocalDate.now()
        val jsonObject = JSONObject()
        val actionsArray = org.json.JSONArray()
        
        // Sample medications - using string IDs for compatibility with Flutter
        val medications = listOf(
            mapOf(
                "medicineId" to "med_123",
                "medicineName" to "Lisinopril",
                "dosage" to "10mg",
                "frequency" to "once daily",
                "time" to "08:00"
            ),
            mapOf(
                "medicineId" to "med_124",
                "medicineName" to "Metformin",
                "dosage" to "500mg",
                "frequency" to "twice daily",
                "time" to "09:00"
            ),
            mapOf(
                "medicineId" to "med_125",
                "medicineName" to "Atorvastatin",
                "dosage" to "20mg",
                "frequency" to "once daily",
                "time" to "21:00"
            )
        )
        
        // Generate 2 weeks of sample data with varying adherence patterns
        for (daysAgo in 14 downTo 0) {
            val date = today.minusDays(daysAgo.toLong())
            val dateStr = date.toString() // Format: yyyy-MM-dd
            
            // For each medication, create action entries
            medications.forEach { med ->
                val medicineId = med["medicineId"].toString() // Ensure ID is a string
                val medicineName = med["medicineName"].toString()
                val time = med["time"].toString()
                val dosage = med["dosage"].toString()
                
                // Randomize actions (80% taken, 10% missed, 10% skipped)
                val rand = Math.random()
                val action = when {
                    rand < 0.8 -> "taken"
                    rand < 0.9 -> "missed"
                    else -> "skipped"
                }
                
                val actionId = "${medicineId}_${dateStr}_${time.replace(":", "_")}"
                
                // Create action JSON object
                val actionObject = JSONObject().apply {
                    put("actionId", actionId)
                    put("medicineId", medicineId)
                    put("medicineName", medicineName)
                    put("date", dateStr)
                    put("time", time)
                    put("action", action)
                    put("dosage", dosage)
                    put("recordedAt", "${dateStr}T${time}:00.000")
                }
                
                actionsArray.put(actionObject)
            }
        }
        
        jsonObject.put("actions", actionsArray)
        
        // Save generated data for future use
        val prefs = getSharedPreferences("medication_actions", Context.MODE_PRIVATE)
        prefs.edit().putString("actions_history", jsonObject.toString()).apply()
        
        Log.i("NotificationService", "Generated ${actionsArray.length()} sample medication actions")
        
        return jsonObject.toString()
    }

    // Helper method to ensure consistent ID format between Android and Flutter
    private fun standardizeMedicineId(id: Any?): String {
        return when (id) {
            is Int -> id.toString()
            is Long -> id.toString()
            is String -> id
            else -> ""
        }
    }

    // Method to notify Flutter of medicine actions
    private fun notifyFlutterOfMedicineAction(action: String, medicineId: String, payload: String) {
        try {
            // Parse the payload to get medicine name
            val jsonObject = JSONObject(payload)
            val medicineName = jsonObject.optString("medicineName", "Unknown Medicine")
            
            // Create data map with proper string ID
            val dataMap = mapOf(
                "action" to action,
                "medicineId" to medicineId,
                "medicineName" to medicineName,
                "payload" to payload,
                "timestamp" to System.currentTimeMillis().toString()
            )
            
            // Send to Flutter if method channel is available
            // Use replaceFirstChar to capitalize - safer than deprecated capitalize()
            val capitalizedAction = action.replaceFirstChar { 
                if (it.isLowerCase()) it.titlecase(java.util.Locale.getDefault()) else it.toString() 
            }
            methodChannel?.invokeMethod("medicineAction$capitalizedAction", dataMap)
            
            Log.i("NotificationService", "Notified Flutter of medicine action: $action for ID: $medicineId")
        } catch (e: Exception) {
            Log.e("NotificationService", "Error notifying Flutter: ${e.message}")
        }
    }

    /**
     * Retrieves all snoozed alarms from SharedPreferences
     * 
     * @return List of maps containing key and value pairs for snoozed alarms
     */
    private fun getSnoozedAlarmsFromPrefs(): List<Map<String, String>> {
        Log.i("NotificationService", "Getting snoozed alarms from SharedPreferences")
        
        val alarmsList = mutableListOf<Map<String, String>>()
        
        try {
            // Check all possible SharedPreferences where snoozed alarms might be stored
            val prefsList = listOf(
                getSharedPreferences("notification_settings", Context.MODE_PRIVATE),
                getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE),
                getSharedPreferences("NotificationPrefs", Context.MODE_PRIVATE),
                getSharedPreferences(packageName + "_preferences", Context.MODE_PRIVATE)
            )
            
            for (prefs in prefsList) {
                val allKeys = prefs.all.keys
                
                // Filter for snoozed alarm keys
                val snoozeKeys = allKeys.filter { 
                    it.startsWith("snoozed_alarm_") || 
                    it.contains("flutter.snoozed_alarm_") 
                }
                
                Log.i("NotificationService", "Found ${snoozeKeys.size} snoozed alarms in SharedPreferences")
                
                for (key in snoozeKeys) {
                    // Handle Flutter's prefix if needed
                    val normalizedKey = if (key.contains("flutter.")) {
                        key.substring(key.indexOf("snoozed_alarm_"))
                    } else {
                        key
                    }
                    
                    val value = prefs.getString(key, null)
                    if (value != null) {
                        Log.d("NotificationService", "Snoozed alarm found: $normalizedKey = $value")
                        alarmsList.add(mapOf(
                            "key" to normalizedKey,
                            "value" to value
                        ))
                    }
                }
            }
            
            Log.i("NotificationService", "Retrieved total of ${alarmsList.size} snoozed alarms")
            
        } catch (e: Exception) {
            Log.e("NotificationService", "Error getting snoozed alarms from prefs", e)
        }
        
        return alarmsList
    }

    // Get the configured snooze duration in minutes
    private fun getSnoozeMinutes(): Int {
        return getStoredSetting(KEY_SNOOZE_DURATION, 5)
    }
}


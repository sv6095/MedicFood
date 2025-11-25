package com.srmist.medicfood

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.ServiceConnection
import android.os.Build
import android.os.IBinder
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel
import android.content.pm.PackageManager

class MainActivity : FlutterActivity() {
    private var notificationService: NotificationService? = null
    private lateinit var channel: MethodChannel
    private lateinit var shareChannel: MethodChannel
    private var serviceBound = false
    private var actionReceiver: BroadcastReceiver? = null

    private val serviceConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
            Log.i("MainActivity", "Service connected successfully")
            val binder = service as? NotificationService.LocalBinder
            notificationService = binder?.service
            notificationService?.setActivity(this@MainActivity)
            notificationService?.setMethodChannel(channel)
            serviceBound = true
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            Log.w("MainActivity", "Service disconnected")
            notificationService = null
            serviceBound = false
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Cache the FlutterEngine for use in NotificationService
        FlutterEngineCache
            .getInstance()
            .put("my_engine_id", flutterEngine)
        Log.i("MainActivity", "FlutterEngine cached with ID: my_engine_id")
        
        // Set up method channels
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "notification_service")
        shareChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "share_channel")
        
        // Setup action synchronization receiver
        setupActionReceiver()
        
        // Create notification channels BEFORE starting service
        createNotificationChannels()
        
        // Start and bind to NotificationService
        startNotificationService()
        
        // Set up notification service method channel handler
        channel.setMethodCallHandler { call, result ->
            if (serviceBound && notificationService != null) {
                notificationService?.onMethodCall(call, result)
            } else {
                Log.e("MainActivity", "Service not bound for method: ${call.method}")
                // Try to start service if not bound
                startNotificationService()
                result.error("SERVICE_NOT_BOUND", "NotificationService is not bound", null)
            }
        }
        
        // Set up share method channel handler
        shareChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "share" -> {
                    val text = call.argument<String>("text") ?: ""
                    val subject = call.argument<String>("subject") ?: ""
                    shareText(text, subject, result)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun setupActionReceiver() {
        actionReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                val action = intent?.action
                val alarmId = intent?.getLongExtra("alarmId", -1L)?.toInt() ?: -1
                
                Log.i("MainActivity", "Action broadcast received: $action for alarm: $alarmId")
                
                // Close any fullscreen activity when action is taken
                val closeIntent = Intent("com.srmist.medicfood.CLOSE_FULLSCREEN").apply {
                    putExtra("alarmId", alarmId.toLong())
                    putExtra("action", action)
                }
                sendBroadcast(closeIntent)
            }
        }
        
        // Register receiver for action synchronization
        val filter = IntentFilter().apply {
            addAction("com.srmist.medicfood.ALARM_ACTION_SYNC")
        }
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(actionReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(actionReceiver, filter)
        }
    }

    // Permission requests are now handled in Flutter code

    private fun startNotificationService() {
        val serviceIntent = Intent(this, NotificationService::class.java)
        try {
            // Stop any existing service first
            stopService(serviceIntent)
            
            // Start new service
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(serviceIntent)
            } else {
                startService(serviceIntent)
            }
            
            // Bind to service
            val bindResult = bindService(serviceIntent, serviceConnection, Context.BIND_AUTO_CREATE)
            Log.i("MainActivity", "NotificationService started. Bind result: $bindResult")
            
        } catch (e: Exception) {
            Log.e("MainActivity", "Error starting NotificationService", e)
        }
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            
            // Clear existing channels first
            try {
                notificationManager.deleteNotificationChannel("medication_alarm_service")
                notificationManager.deleteNotificationChannel("foreground_service")
            } catch (e: Exception) {
                Log.w("MainActivity", "Error clearing existing channels", e)
            }

            // Create CRITICAL alarm channel
            val alarmChannel = NotificationChannel(
                "medication_alarm_service",
                "Medication Alarms",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Critical medication reminders that cannot be missed"
                setShowBadge(true)
                enableVibration(false) // We handle vibration manually
                enableLights(true)
                lightColor = android.graphics.Color.RED
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
                setBypassDnd(true) // Critical: bypass Do Not Disturb
                setSound(null, null) // We handle sound manually for better control
            }
            notificationManager.createNotificationChannel(alarmChannel)

            // Create LOW priority service channel
            val serviceChannel = NotificationChannel(
                "foreground_service",
                "Medication Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Background service for medication monitoring"
                setShowBadge(false)
                enableVibration(false)
                enableLights(false)
                setSound(null, null)
            }
            notificationManager.createNotificationChannel(serviceChannel)
            
            Log.i("MainActivity", "Notification channels created successfully")
        }
    }

    override fun onResume() {
        super.onResume()
        Log.i("MainActivity", "onResume called - Starting activity reference setup")
        // Ensure service is running and bound
        if (!serviceBound) {
            Log.i("MainActivity", "Service not bound, starting notification service")
            startNotificationService()
        }
        notificationService?.setActivity(this)
        notificationService?.setActivityVisible(true)
        
        // Close any fullscreen activities when main activity resumes
        val closeIntent = Intent("com.srmist.medicfood.CLOSE_FULLSCREEN_ON_RESUME")
        sendBroadcast(closeIntent)
        
        Log.i("MainActivity", "Activity resumed - Service bound: $serviceBound, NotificationService: ${notificationService != null}")
    }

    override fun onPause() {
        super.onPause()
        Log.i("MainActivity", "onPause called")
        notificationService?.setActivityVisible(false)
    }

    override fun onDestroy() {
        Log.i("MainActivity", "onDestroy called - Starting cleanup")
        try {
            actionReceiver?.let { 
                Log.i("MainActivity", "Unregistering action receiver")
                unregisterReceiver(it) 
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "Error unregistering action receiver", e)
        }
        
        try {
            if (serviceBound) {
                Log.i("MainActivity", "Unbinding service")
                unbindService(serviceConnection)
                serviceBound = false
            }
            Log.i("MainActivity", "Clearing activity reference in NotificationService")
            notificationService?.setActivity(null)
            notificationService = null
        } catch (e: Exception) {
            Log.e("MainActivity", "Error in onDestroy", e)
        }
        super.onDestroy()
    }

    // Permission results are now handled in Flutter code

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        Log.i("MainActivity", "onActivityResult called with requestCode: $requestCode, resultCode: $resultCode")
        // Permission results are now handled in Flutter code
    }
    
    private fun shareText(text: String, subject: String, result: MethodChannel.Result) {
        try {
            val shareIntent = Intent(Intent.ACTION_SEND).apply {
                type = "text/plain"
                putExtra(Intent.EXTRA_TEXT, text)
                putExtra(Intent.EXTRA_SUBJECT, subject)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            
            // Check if there are apps that can handle this intent
            val chooser = Intent.createChooser(shareIntent, "Share via")
            if (shareIntent.resolveActivity(packageManager) != null) {
                startActivity(chooser)
                result.success(true)
            } else {
                result.error("NO_APPS", "No apps available to share", null)
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "Error sharing text", e)
            result.error("SHARE_ERROR", "Failed to share: ${e.message}", null)
        }
    }
}

package chat.pantheon.hermes

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

import android.content.Context
import android.content.Intent
import android.os.Bundle

class MainActivity : FlutterFragmentActivity() {

    private var pendingNotificationIntent: Intent? = null

    override fun attachBaseContext(base: Context) {
        super.attachBaseContext(base)
    }


    override fun provideFlutterEngine(context: Context): FlutterEngine? {
        return provideEngine(this)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        // do nothing, because the engine was been configured in provideEngine
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        if (savedInstanceState == null &&
            engine?.dartExecutor?.isExecutingDart == true &&
            (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) == 0 &&
            (intent.action == "SELECT_NOTIFICATION" ||
                intent.action == "SELECT_FOREGROUND_NOTIFICATION_ACTION")) {
            // The retained Dart UI will not query launch details again. Deliver this
            // fresh tap once the new Activity has attached to its Flutter engine.
            pendingNotificationIntent = Intent(intent)
            setIntent(Intent(intent).setAction(Intent.ACTION_MAIN))
        }
        DirectShareShortcuts.handleIntent(intent)
        super.onCreate(savedInstanceState)
    }

    override fun onPostResume() {
        super.onPostResume()
        val notificationIntent = pendingNotificationIntent ?: return
        pendingNotificationIntent = null
        super.onNewIntent(notificationIntent)
        // The notification plugin stores the forwarded intent on the Activity.
        // Consume it so a later launch-details query cannot replay this tap.
        setIntent(Intent(notificationIntent).setAction(Intent.ACTION_MAIN))
    }

    override fun onNewIntent(intent: Intent) {
        pendingNotificationIntent = null
        DirectShareShortcuts.handleIntent(intent)
        setIntent(intent)
        super.onNewIntent(intent)
    }

    companion object {
        var engine: FlutterEngine? = null
        fun provideEngine(context: Context): FlutterEngine {
            val applicationContext = context.applicationContext
            val eng = engine ?: FlutterEngine(context, emptyArray(), true, false).also {
                DirectShareShortcuts.register(it, applicationContext)
            }
            engine = eng
            return eng
        }
    }
}

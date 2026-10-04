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
        if (intent.action in shareActions) {
            if ((intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0) {
                clearShareIntent()
            } else {
                IncomingShares.receive(applicationContext, intent)
                // Our queued receiver owns SEND; plugins and Flutter see a normal launch.
                clearShareIntent()
            }
        }
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
        // Shares have already been queued independently of Activity/plugin attachment.
        clearShareIntent()
        val notificationIntent = pendingNotificationIntent ?: return
        pendingNotificationIntent = null
        super.onNewIntent(notificationIntent)
        // The notification plugin stores the forwarded intent on the Activity.
        // Consume it so a later launch-details query cannot replay this tap.
        setIntent(Intent(notificationIntent).setAction(Intent.ACTION_MAIN))
    }

    override fun onNewIntent(intent: Intent) {
        pendingNotificationIntent = null
        if (intent.action in shareActions) {
            if ((intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) == 0) {
                IncomingShares.receive(applicationContext, intent)
            }
            setIntent(intent)
            clearShareIntent()
        }
        DirectShareShortcuts.handleIntent(intent)
        setIntent(intent)
        super.onNewIntent(intent)
        clearShareIntent()
    }

    private fun clearShareIntent() {
        if (intent.action !in shareActions) return
        // Mutate the original too: Android can reuse it when recreating the Activity.
        intent.action = Intent.ACTION_MAIN
        intent.setDataAndType(null, null)
        intent.replaceExtras(Bundle())
        intent.clipData = null
    }

    companion object {
        private val shareActions = setOf(Intent.ACTION_SEND, Intent.ACTION_SEND_MULTIPLE)
        var engine: FlutterEngine? = null
        fun provideEngine(context: Context): FlutterEngine {
            val applicationContext = context.applicationContext
            val eng = engine ?: FlutterEngine(context, emptyArray(), true, false).also {
                DirectShareShortcuts.register(it, applicationContext)
            }
            engine = eng
            IncomingShares.register(eng)
            return eng
        }
    }
}

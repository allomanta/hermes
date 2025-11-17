package chat.pantheon.hermes

import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.net.Uri
import android.util.Base64
import androidx.core.app.Person
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import chat.pantheon.hermes.R
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

object DirectShareShortcuts : MethodChannel.MethodCallHandler {
    private const val CHANNEL_NAME = "im.hermes.hermes/direct_share_shortcuts"
    private val SHARE_TARGET_CATEGORIES = setOf(
        "androidx.sharetarget.category.TEXT_SHARE_TARGET",
        "androidx.sharetarget.category.IMAGE_SHARE_TARGET",
        "androidx.sharetarget.category.VIDEO_SHARE_TARGET",
        "androidx.sharetarget.category.FILE_SHARE_TARGET"
    )

    private var channel: MethodChannel? = null
    private lateinit var appContext: Context
    private var pendingShortcutId: String? = null

    fun register(flutterEngine: FlutterEngine, context: Context) {
        if (channel != null) return
        appContext = context.applicationContext
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
        channel?.setMethodCallHandler(this)
    }

    fun handleIntent(intent: Intent?) {
        val shortcutId = intent?.getStringExtra(Intent.EXTRA_SHORTCUT_ID)
        if (!shortcutId.isNullOrEmpty()) {
            pendingShortcutId = shortcutId
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "takePendingShortcutRoomId" -> {
                result.success(pendingShortcutId)
                pendingShortcutId = null
            }
            "publishShareShortcuts" -> {
                @Suppress("UNCHECKED_CAST")
                val shortcuts = call.arguments as? List<Map<String, Any?>> ?: emptyList()
                publishShortcuts(shortcuts)
                result.success(null)
            }
            "removeShareShortcuts" -> {
                @Suppress("UNCHECKED_CAST")
                val shortcutIds = (call.arguments as? List<*>)
                    ?.mapNotNull { it as? String }
                    ?: emptyList()
                removeShareShortcuts(shortcutIds)
                result.success(null)
            }
            "clearShareShortcuts" -> {
                ShortcutManagerCompat.removeAllDynamicShortcuts(appContext)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun removeShareShortcuts(shortcutIds: List<String>) {
        if (!::appContext.isInitialized || shortcutIds.isEmpty()) return
        ShortcutManagerCompat.removeDynamicShortcuts(appContext, shortcutIds)
        ShortcutManagerCompat.removeLongLivedShortcuts(appContext, shortcutIds)
        val disableMessage = appContext.getString(R.string.shortcut_disabled_message)
        ShortcutManagerCompat.disableShortcuts(appContext, shortcutIds, disableMessage)
    }

    private fun publishShortcuts(shortcuts: List<Map<String, Any?>>) {
        if (!::appContext.isInitialized) return

        val existingShareShortcutIds = ShortcutManagerCompat
            .getDynamicShortcuts(appContext)
            .filter { shortcut ->
                val categories = shortcut.categories ?: return@filter false
                SHARE_TARGET_CATEGORIES.all { categories.contains(it) }
            }
            .map { it.id }
        if (existingShareShortcutIds.isNotEmpty()) {
            ShortcutManagerCompat.removeDynamicShortcuts(appContext, existingShareShortcutIds)
        }

        val maxShortcuts = ShortcutManagerCompat.getMaxShortcutCountPerActivity(appContext)
        val shortcutInfos = shortcuts
            .take(maxShortcuts)
            .mapNotNull { shortcut ->
                val id = shortcut["id"] as? String ?: return@mapNotNull null
                val shortLabel = shortcut["shortLabel"] as? String ?: return@mapNotNull null
                val longLabel = shortcut["longLabel"] as? String ?: shortLabel
                val action = shortcut["action"] as? String
                val isImportant = shortcut["isImportant"] as? Boolean ?: false
                val isBot = shortcut["isBot"] as? Boolean ?: false
                val isConversation = shortcut["isConversation"] as? Boolean ?: true

                val intent = Intent(Intent.ACTION_VIEW).setPackage(appContext.packageName)
                if (!action.isNullOrEmpty()) {
                    intent.data = Uri.parse(action)
                }

                val builder = ShortcutInfoCompat.Builder(appContext, id)
                    .setShortLabel(shortLabel)
                    .setLongLabel(longLabel)
                    .setLongLived(true)
                    .setIntent(intent)
                    .setCategories(SHARE_TARGET_CATEGORIES.toMutableSet())

                val icon = decodeIcon(shortcut["icon"] as? String)
                if (icon != null) {
                    builder.setIcon(icon)
                } else {
                    builder.setIcon(IconCompat.createWithResource(appContext, R.mipmap.ic_launcher))
                }

                if (isConversation) {
                    val person = Person.Builder()
                        .setKey(id)
                        .setName(shortLabel)
                        .setImportant(isImportant)
                        .setBot(isBot)
                        .build()
                    builder.setPerson(person)
                }

                builder.build()
            }
        shortcutInfos.forEach { shortcutInfo ->
            ShortcutManagerCompat.pushDynamicShortcut(appContext, shortcutInfo)
        }
    }

    private fun decodeIcon(icon: String?): IconCompat? {
        if (icon.isNullOrEmpty()) return null
        return try {
            val bytes = Base64.decode(icon, Base64.DEFAULT)
            val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
            IconCompat.createWithAdaptiveBitmap(bitmap)
        } catch (_: Exception) {
            null
        }
    }
}

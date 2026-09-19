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
        pendingShortcutId = if (intent != null &&
            (intent.action == Intent.ACTION_SEND || intent.action == Intent.ACTION_SEND_MULTIPLE)) {
            intent.getStringExtra(Intent.EXTRA_SHORTCUT_ID)
        } else null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "takePendingShortcut" -> {
                result.success(pendingShortcutId)
                pendingShortcutId = null
            }
            "publishShareShortcuts" -> {
                @Suppress("UNCHECKED_CAST")
                val shortcuts = call.arguments as? List<Map<String, Any?>> ?: emptyList()
                try {
                    result.success(publishShortcuts(shortcuts))
                } catch (error: RuntimeException) {
                    result.error("publish_failed", error.message, null)
                }
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
                removeShareShortcuts(existingShareShortcutIds())
                pendingShortcutId = null
                result.success(null)
            }
            "reportShareShortcutUsed" -> {
                val id = call.arguments as? String
                if (id != null) ShortcutManagerCompat.reportShortcutUsed(appContext, id)
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

    private fun existingShareShortcutIds(): List<String> = ShortcutManagerCompat
        .getShortcuts(appContext, ShortcutManagerCompat.FLAG_MATCH_DYNAMIC or
            ShortcutManagerCompat.FLAG_MATCH_CACHED or ShortcutManagerCompat.FLAG_MATCH_PINNED)
        .filter { shortcut ->
            shortcut.id.startsWith("hermes-share:") ||
                shortcut.categories?.containsAll(SHARE_TARGET_CATEGORIES) == true
        }
        .map { it.id }

    private fun publishShortcuts(shortcuts: List<Map<String, Any?>>): Boolean {
        if (!::appContext.isInitialized) return false

        val maxShortcuts = (ShortcutManagerCompat.getMaxShortcutCountPerActivity(appContext) -
            ShortcutManagerCompat.getShortcuts(appContext, ShortcutManagerCompat.FLAG_MATCH_MANIFEST).size)
            .coerceAtLeast(0)
        val shortcutInfos = shortcuts
            .take(minOf(5, maxShortcuts))
            .mapIndexedNotNull { rank, shortcut ->
                val id = shortcut["id"] as? String ?: return@mapIndexedNotNull null
                val shortLabel = shortcut["shortLabel"] as? String ?: return@mapIndexedNotNull null
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
                    .setRank(rank)
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
        val ids = shortcutInfos.map { it.id }
        val existingIds = existingShareShortcutIds()
        removeShareShortcuts(existingIds.filter { it !in ids })
        ShortcutManagerCompat.enableShortcuts(appContext, ids)
        val otherShortcuts = ShortcutManagerCompat.getDynamicShortcuts(appContext)
            .filter { it.id !in existingIds && it.id !in ids }
            .take((maxShortcuts - shortcutInfos.size).coerceAtLeast(0))
        // Updating ranks must not report every target as used on every sync.
        return ShortcutManagerCompat.setDynamicShortcuts(appContext, shortcutInfos + otherShortcuts)
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

package io.jonathanintheclouds.orbital

import android.net.Uri
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private var pendingResult: MethodChannel.Result? = null

    private val documentPickerLauncher: ActivityResultLauncher<Array<String>> =
        registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
            handlePickedDocument(uri)
        }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "orbital/document_picker"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickTextFile" -> {
                    if (pendingResult != null) {
                        result.error("busy", "A document picker request is already active.", null)
                        return@setMethodCallHandler
                    }
                    pendingResult = result
                    documentPickerLauncher.launch(arrayOf("*/*"))
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun handlePickedDocument(uri: Uri?) {
        val result = pendingResult ?: return
        pendingResult = null

        if (uri == null) {
            result.success(null)
            return
        }

        try {
            contentResolver.takePersistableUriPermission(
                uri,
                android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION
            )
        } catch (_: SecurityException) {
            // Not every provider grants persistable permissions. Continue with a one-shot read.
        }

        try {
            val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() }
                ?: throw IllegalStateException("Unable to read file.")
            val content = bytes.toString(Charsets.UTF_8)
            val name = queryDisplayName(uri) ?: "key"
            result.success(mapOf("name" to name, "content" to content))
        } catch (error: Exception) {
            result.error("read_failed", error.message, null)
        }
    }

    private fun queryDisplayName(uri: Uri): String? {
        contentResolver.query(uri, arrayOf(android.provider.OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val index = cursor.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                    if (index >= 0) {
                        return cursor.getString(index)
                    }
                }
            }
        return null
    }
}

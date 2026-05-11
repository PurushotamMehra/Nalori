package com.nalori.reader

import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.view.KeyEvent
import androidx.activity.result.ActivityResult
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream

class MainActivity : FlutterFragmentActivity() {
    private var pendingBookImportResult: MethodChannel.Result? = null
    private var readerControlsChannel: MethodChannel? = null
    private var isReaderVisible = false
    private var isReaderVolumePagingEnabled = false
    private lateinit var pickEpubLauncher: ActivityResultLauncher<Intent>

    override fun onCreate(savedInstanceState: Bundle?) {
        pickEpubLauncher = registerForActivityResult(
            ActivityResultContracts.StartActivityForResult(),
            ::handlePickedEpubResult
        )
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "quote_card/share"
        )
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "shareImage" -> {
                        try {
                            val path = call.argument<String>("path")
                                ?: throw IllegalArgumentException("Missing image path.")
                            val mimeType = call.argument<String>("mimeType") ?: "image/png"
                            val title = call.argument<String>("title") ?: "Quote card"
                            val text = call.argument<String>("text") ?: ""

                            shareImage(path, mimeType, title, text)
                            result.success(null)
                        } catch (error: Throwable) {
                            result.error("SHARE_FAILED", error.message, null)
                        }
                    }

                    "saveImage" -> {
                        try {
                            val path = call.argument<String>("path")
                                ?: throw IllegalArgumentException("Missing image path.")
                            val mimeType = call.argument<String>("mimeType") ?: "image/png"

                            val savedLocation = saveImage(path, mimeType)
                            result.success(savedLocation)
                        } catch (error: Throwable) {
                            result.error("SAVE_FAILED", error.message, null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "book_import"
        )
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickEpub" -> pickEpub(result)
                    else -> result.notImplemented()
                }
            }

        readerControlsChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "reader_controls"
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "setReaderControlsState" -> {
                        isReaderVisible = call.argument<Boolean>("readerVisible") ?: false
                        isReaderVolumePagingEnabled =
                            call.argument<Boolean>("volumePagingEnabled") ?: false
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (!isReaderVisible || !isReaderVolumePagingEnabled) {
            return super.dispatchKeyEvent(event)
        }

        val direction = when (event.keyCode) {
            KeyEvent.KEYCODE_VOLUME_UP -> -1
            KeyEvent.KEYCODE_VOLUME_DOWN -> 1
            else -> null
        } ?: return super.dispatchKeyEvent(event)

        when (event.action) {
            KeyEvent.ACTION_DOWN -> {
                if (event.repeatCount == 0) {
                    readerControlsChannel?.invokeMethod(
                        "volumePagePressStart",
                        direction
                    )
                }
            }

            KeyEvent.ACTION_UP -> {
                readerControlsChannel?.invokeMethod("volumePagePressEnd", direction)
            }
        }
        return true
    }

    private fun pickEpub(result: MethodChannel.Result) {
        if (pendingBookImportResult != null) {
            result.error("PICKER_ACTIVE", "An EPUB picker is already open.", null)
            return
        }

        pendingBookImportResult = result

        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = EPUB_MIME_TYPE
            putExtra(Intent.EXTRA_MIME_TYPES, arrayOf(EPUB_MIME_TYPE))
        }

        try {
            pickEpubLauncher.launch(intent)
        } catch (error: Throwable) {
            pendingBookImportResult = null
            result.error("PICKER_FAILED", error.message, null)
        }
    }

    private fun handlePickedEpubResult(activityResult: ActivityResult) {
        val result = pendingBookImportResult ?: return
        pendingBookImportResult = null

        val uri = activityResult.data?.data
        if (activityResult.resultCode != RESULT_OK || uri == null) {
            result.success(null)
            return
        }

        try {
            result.success(copyPickedEpubToCache(uri))
        } catch (error: Throwable) {
            result.error("IMPORT_FAILED", error.message, null)
        }
    }

    private fun shareImage(path: String, mimeType: String, title: String, text: String) {
        val source = File(path)
        require(source.exists()) { "Quote card image was not found." }

        val shareDir = File(cacheDir, "share_plus").apply {
            if (!exists()) mkdirs()
        }
        shareDir.listFiles()?.forEach { it.delete() }

        val safeName = source.name.ifBlank { "quote_card.png" }
        val sharedFile = File(shareDir, safeName)
        source.copyTo(sharedFile, overwrite = true)

        val uri = FileProvider.getUriForFile(
            this,
            "$packageName.flutter.share_provider",
            sharedFile
        )
        val sendIntent = Intent(Intent.ACTION_SEND).apply {
            type = mimeType
            putExtra(Intent.EXTRA_STREAM, uri)
            if (text.isNotBlank()) putExtra(Intent.EXTRA_TEXT, text)
            if (title.isNotBlank()) putExtra(Intent.EXTRA_TITLE, title)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }

        grantSharePermissions(sendIntent, uri)
        startActivity(Intent.createChooser(sendIntent, title))
    }

    private fun saveImage(path: String, mimeType: String): String {
        val source = File(path)
        require(source.exists()) { "Quote card image was not found." }

        val displayName = source.name.ifBlank { "quote_card.png" }
        val resolver = contentResolver
        val collection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        } else {
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        }

        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, displayName)
            put(MediaStore.Images.Media.MIME_TYPE, mimeType)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/Nalori")
                put(MediaStore.Images.Media.IS_PENDING, 1)
            }
        }

        val uri = resolver.insert(collection, values)
            ?: throw IllegalStateException("Could not create gallery item.")

        try {
            resolver.openOutputStream(uri)?.use { output ->
                FileInputStream(source).use { input ->
                    input.copyTo(output)
                }
            } ?: throw IllegalStateException("Could not open gallery item.")

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                values.clear()
                values.put(MediaStore.Images.Media.IS_PENDING, 0)
                resolver.update(uri, values, null, null)
            }
        } catch (error: Throwable) {
            resolver.delete(uri, null, null)
            throw error
        }

        return "Photos"
    }

    private fun grantSharePermissions(intent: Intent, uri: Uri) {
        val receivers = packageManager.queryIntentActivities(
            intent,
            PackageManager.MATCH_DEFAULT_ONLY
        )
        receivers.forEach { resolveInfo ->
            grantUriPermission(
                resolveInfo.activityInfo.packageName,
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION
            )
        }
    }

    private fun copyPickedEpubToCache(uri: Uri): String {
        val displayName = getDisplayName(uri)
        require(displayName.lowercase().endsWith(".epub")) {
            "Selected file is not an EPUB."
        }

        val importDir = File(cacheDir, "book_import").apply {
            if (!exists()) mkdirs()
        }
        importDir.listFiles()?.forEach { it.delete() }

        val safeName = displayName.replace(Regex("[^A-Za-z0-9_.-]+"), "_")
        val target = File(importDir, safeName)

        contentResolver.openInputStream(uri)?.use { input ->
            FileOutputStream(target).use { output ->
                input.copyTo(output)
            }
        } ?: throw IllegalStateException("Could not open selected EPUB.")

        return target.absolutePath
    }

    private fun getDisplayName(uri: Uri): String {
        contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (nameIndex >= 0 && cursor.moveToFirst()) {
                val name = cursor.getString(nameIndex)
                if (!name.isNullOrBlank()) return name
            }
        }

        val fallback = uri.lastPathSegment
            ?.substringAfterLast('/')
            ?.takeIf { it.isNotBlank() }

        return fallback ?: "selected_book.epub"
    }

    companion object {
        private const val EPUB_MIME_TYPE = "application/epub+zip"
    }
}

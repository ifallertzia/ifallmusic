package com.ifallmusic.app

import android.app.Activity
import android.content.ClipData
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.media.audiofx.EnvironmentalReverb
import android.media.audiofx.Equalizer
import android.media.audiofx.Virtualizer
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import kotlin.concurrent.thread

/**
 * Boot counter, scoped Downloads, share, and the system equalizer.
 * Does not create or replace the music player.
 */
class SaxifyBridge(private val activity: Activity) {
    private var equalizer: Equalizer? = null
    private var sessionId: Int = 0

    // ---- 8D spatial audio (Virtualizer + reverb on the live output) --------
    private var virtualizer: Virtualizer? = null
    private var reverb: EnvironmentalReverb? = null
    private val spatialProcessor = SpatialAudioProcessor()

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "backgroundApp" -> { activity.moveTaskToBack(true); result.success(null) }
                "bootState" -> result.success(SaxifyBoot.snapshot(activity))
                "markLaunchSuccess" -> {
                    SaxifyBoot.markSuccess(activity)
                    result.success(null)
                }
                "repairLocalCache" -> {
                    repairLocalCache(activity)
                    result.success(null)
                }
                // Keep the old method name safe for an older Dart layer: this
                // repair must never clear FlutterSharedPreferences, which hold
                // the user's likes, playlists, downloads and settings.
                "clearFlutterPrefs" -> {
                    repairLocalCache(activity)
                    result.success(null)
                }
                "saveToDownloads" -> io(result) {
                    saveToDownloads(
                        call.argument<String>("sourcePath") ?: "",
                        call.argument<String>("displayName") ?: "track_ifallmusic.mp3",
                        call.argument<String>("mime") ?: "audio/mpeg",
                    )
                }
                "deleteDownload" -> io(result) {
                    deleteDownload(call.argument<String>("uri"), call.argument<String>("path"))
                }
                "listDownloads" -> io(result) { listDownloads() }
                "listLocalAudio" -> io(result) { listLocalAudio() }
                "shareFile" -> {
                    shareFile(
                        call.argument<String>("path"),
                        call.argument<String>("uri"),
                        call.argument<String>("mime") ?: "*/*",
                        call.argument<String>("title") ?: "Share",
                    )
                    result.success(null)
                }
                "openContent" -> {
                    openContent(
                        call.argument<String>("uri") ?: "",
                        call.argument<String>("mime") ?: "*/*",
                    )
                    result.success(null)
                }
                "eqInit" -> result.success(eqInit(call.argument<Int>("sessionId") ?: 0))
                "eqSetEnabled" -> {
                    equalizer?.enabled = call.argument<Boolean>("enabled") == true
                    result.success(null)
                }
                "eqSetBand" -> {
                    val band = call.argument<Int>("band") ?: 0
                    val level = call.argument<Int>("level") ?: 0
                    equalizer?.setBandLevel(band.toShort(), level.toShort())
                    result.success(null)
                }
                "eqUsePreset" -> result.success(eqUsePreset(call.argument<String>("name") ?: ""))
                "eqRelease" -> {
                    releaseEq()
                    result.success(null)
                }
                "spatialApply" -> result.success(
                    spatialApply(
                        rotationHz = (call.argument<Double>("rotationHz") ?: 0.12),
                        depth = (call.argument<Double>("depth") ?: 0.9),
                        reverb = (call.argument<Double>("reverb") ?: 0.3),
                        width = (call.argument<Double>("width") ?: 0.35),
                    )
                )
                "spatialDisable" -> {
                    releaseSpatial()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("saxify", e.message, null)
        }
    }

    private fun io(result: MethodChannel.Result, work: () -> Any?) {
        thread(name = "saxify-io") {
            try {
                val value = work()
                activity.runOnUiThread {
                    if (!activity.isDestroyed) result.success(value)
                }
            } catch (e: Exception) {
                activity.runOnUiThread {
                    if (!activity.isDestroyed) result.error("saxify", e.message, null)
                }
            }
        }
    }

    private fun saveToDownloads(sourcePath: String, displayName: String, mime: String): Map<String, Any?> {
        val src = File(sourcePath)
        if (!src.exists()) throw IllegalArgumentException("Source file is missing")
        return if (Build.VERSION.SDK_INT >= 29) {
            saveMediaStore(src, displayName, mime)
        } else {
            saveLegacy(src, displayName)
        }
    }

    private fun saveMediaStore(src: File, displayName: String, mime: String): Map<String, Any?> {
        val resolver = activity.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, displayName)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/IfallMusic")
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val collection = MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val uri = resolver.insert(collection, values)
            ?: throw IllegalStateException("Could not create a Downloads entry")
        resolver.openOutputStream(uri)?.use { out ->
            FileInputStream(src).use { input -> input.copyTo(out) }
        } ?: throw IllegalStateException("Could not write the download")
        val done = ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }
        resolver.update(uri, done, null, null)
        return mapOf(
            "displayName" to displayName,
            "uri" to uri.toString(),
            "path" to src.absolutePath,
            "size" to src.length(),
            "modifiedMs" to System.currentTimeMillis(),
        )
    }

    @Suppress("DEPRECATION")
    private fun saveLegacy(src: File, displayName: String): Map<String, Any?> {
        val dir = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
            "IfallMusic",
        )
        if (!dir.exists() && !dir.mkdirs()) {
            throw IllegalStateException("Could not create Download/IfallMusic")
        }
        val dest = uniqueFile(dir, displayName)
        src.copyTo(dest, overwrite = true)
        return mapOf(
            "displayName" to dest.name,
            "uri" to Uri.fromFile(dest).toString(),
            "path" to dest.absolutePath,
            "size" to dest.length(),
            "modifiedMs" to dest.lastModified(),
        )
    }

    private fun deleteDownload(uri: String?, path: String?): Boolean {
        var removed = false
        if (!uri.isNullOrEmpty() && uri.startsWith("content:")) {
            removed = activity.contentResolver.delete(Uri.parse(uri), null, null) > 0
        }
        if (!path.isNullOrEmpty()) {
            val file = File(path)
            if (file.exists()) removed = file.delete() || removed
        }
        return removed
    }

    private fun listDownloads(): List<Map<String, Any?>> {
        if (Build.VERSION.SDK_INT < 29) {
            @Suppress("DEPRECATION")
            val dir = File(
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
                "IfallMusic",
            )
            if (!dir.exists()) return emptyList()
            return dir.listFiles()?.map { file ->
                mapOf(
                    "displayName" to file.name,
                    "path" to file.absolutePath,
                    "uri" to Uri.fromFile(file).toString(),
                    "size" to file.length(),
                    "modifiedMs" to file.lastModified(),
                )
            } ?: emptyList()
        }
        val collection = MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val projection = arrayOf(
            MediaStore.MediaColumns._ID,
            MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.SIZE,
            MediaStore.MediaColumns.DATE_MODIFIED,
            MediaStore.MediaColumns.RELATIVE_PATH,
        )
        val out = ArrayList<Map<String, Any?>>()
        activity.contentResolver.query(
            collection,
            projection,
            "${MediaStore.MediaColumns.RELATIVE_PATH} LIKE ? OR ${MediaStore.MediaColumns.RELATIVE_PATH} LIKE ?",
            arrayOf("%IfallMusic%", "%Saxify%"),
            "${MediaStore.MediaColumns.DATE_MODIFIED} DESC",
        )?.use { cursor ->
            val nameIdx = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
            val sizeIdx = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.SIZE)
            val modIdx = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DATE_MODIFIED)
            val idIdx = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
            while (cursor.moveToNext()) {
                val id = cursor.getLong(idIdx)
                val itemUri = Uri.withAppendedPath(collection, id.toString())
                out.add(
                    mapOf(
                        "displayName" to cursor.getString(nameIdx),
                        "uri" to itemUri.toString(),
                        "size" to cursor.getLong(sizeIdx),
                        "modifiedMs" to cursor.getLong(modIdx) * 1000,
                    ),
                )
            }
        }
        return out
    }

    private fun listLocalAudio(): List<Map<String, Any?>> {
        val collection = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
        val projection = arrayOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.ALBUM_ID,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ARTIST_ID,
            MediaStore.Audio.Media.DURATION,
            MediaStore.Audio.Media.SIZE,
            MediaStore.Audio.Media.YEAR,
            MediaStore.Audio.Media.TRACK,
            MediaStore.Audio.Media.DATE_ADDED,
            MediaStore.Audio.Media.MIME_TYPE,
        )
        val out = ArrayList<Map<String, Any?>>()
        activity.contentResolver.query(
            collection,
            projection,
            "${MediaStore.Audio.Media.IS_MUSIC}=1 AND ${MediaStore.Audio.Media.DURATION}>?",
            arrayOf("30000"),
            "${MediaStore.Audio.Media.TITLE} COLLATE NOCASE ASC",
        )?.use { cursor ->
            val idIdx = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
            val titleIdx = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
            val albumIdx = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)
            val albumIdIdx = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM_ID)
            val artistIdx = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
            val artistIdIdx = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST_ID)
            val durationIdx = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
            val sizeIdx = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.SIZE)
            val yearIdx = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.YEAR)
            val trackIdx = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.TRACK)
            val addedIdx = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATE_ADDED)
            val mimeIdx = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.MIME_TYPE)
            while (cursor.moveToNext()) {
                out.add(
                    mapOf(
                        "id" to cursor.getLong(idIdx),
                        "title" to (cursor.getString(titleIdx) ?: ""),
                        "album" to (cursor.getString(albumIdx) ?: ""),
                        "albumId" to cursor.getLong(albumIdIdx),
                        "artist" to (cursor.getString(artistIdx) ?: ""),
                        "artistId" to cursor.getLong(artistIdIdx),
                        "durationMs" to cursor.getLong(durationIdx),
                        "size" to cursor.getLong(sizeIdx),
                        "year" to cursor.getInt(yearIdx),
                        "track" to cursor.getInt(trackIdx),
                        "dateAdded" to cursor.getLong(addedIdx),
                        "mimeType" to (cursor.getString(mimeIdx) ?: ""),
                    ),
                )
            }
        }
        return out
    }

    private fun shareFile(path: String?, uri: String?, mime: String, title: String) {
        val shareUri = contentUri(path, uri)
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = mime
            putExtra(Intent.EXTRA_STREAM, shareUri)
            clipData = ClipData.newRawUri(title, shareUri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        activity.startActivity(Intent.createChooser(intent, title))
    }

    private fun openContent(raw: String, mime: String) {
        val uri = if (raw.startsWith("content:") || raw.startsWith("file:")) {
            Uri.parse(raw)
        } else {
            contentUri(raw, null)
        }
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, mime)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        activity.startActivity(intent)
    }

    private fun contentUri(path: String?, uri: String?): Uri {
        if (!uri.isNullOrEmpty() && uri.startsWith("content:")) return Uri.parse(uri)
        val file = File(path ?: throw IllegalArgumentException("No file to share"))
        return FileProvider.getUriForFile(activity, "${activity.packageName}.fileprovider", file)
    }

    private fun eqInit(id: Int): Map<String, Any> {
        if (id == 0) return emptyEq()
        val current = equalizer
        if (current != null && sessionId == id) return snapshot(current)
        releaseEq()
        val created = Equalizer(0, id)
        created.enabled = true
        equalizer = created
        sessionId = id
        return snapshot(created)
    }

    private fun snapshot(eq: Equalizer): Map<String, Any> {
        val bands = eq.numberOfBands.toInt()
        val range = eq.bandLevelRange
        val centers = ArrayList<Int>(bands)
        val levels = ArrayList<Int>(bands)
        for (i in 0 until bands) {
            // Android Equalizer.getCenterFreq returns millihertz. Not getCenterFrecuencias.
            centers.add(eq.getCenterFreq(i.toShort()))
            levels.add(eq.getBandLevel(i.toShort()).toInt())
        }
        val presets = ArrayList<String>(eq.numberOfPresets.toInt())
        for (i in 0 until eq.numberOfPresets.toInt()) {
            presets.add(eq.getPresetName(i.toShort()))
        }
        return mapOf(
            "bands" to bands,
            "min" to range[0].toInt(),
            "max" to range[1].toInt(),
            "centersMilliHz" to centers,
            "levels" to levels,
            "presets" to presets,
        )
    }

    private fun eqUsePreset(name: String): Boolean {
        val eq = equalizer ?: return false
        for (i in 0 until eq.numberOfPresets.toInt()) {
            if (eq.getPresetName(i.toShort()).equals(name, ignoreCase = true)) {
                eq.usePreset(i.toShort())
                return true
            }
        }
        return false
    }

    /**
     * Applies the live 8D parameters.
     *
     * Two layers run together:
     *  * [SpatialAudioProcessor] keeps the musical parameters (orbit speed,
     *    depth, reverb, width) and is the engine used when the app drives the
     *    audio pipeline itself (Media3 AudioProcessor / Oboe).
     *  * On the stock player we attach a [Virtualizer] for the "around your
     *    head" width and an [EnvironmentalReverb] for the room. Both are
     *    optional system effects: if the device refuses them we simply report
     *    `false` and playback is untouched.
     */
    private fun spatialApply(rotationHz: Double, depth: Double, reverb: Double, width: Double): Boolean {
        spatialProcessor.rotationHz = rotationHz
        spatialProcessor.depth = depth
        spatialProcessor.reverbMix = reverb
        spatialProcessor.width = width
        var applied = false
        try {
            if (virtualizer == null) {
                virtualizer = Virtualizer(0, audioSessionId()).apply { enabled = true }
            }
            virtualizer?.apply {
                setStrength((depth * 1000).toInt().coerceIn(0, 1000).toShort())
                enabled = true
            }
            applied = true
        } catch (_: Exception) {
            virtualizer = null
        }
        try {
            if (reverb == 0.0) {
                // `reverb` is also the Double parameter here — the field needs
                // the explicit receiver.
                this.reverb?.enabled = false
            } else {
                if (this.reverb == null) {
                    this.reverb = EnvironmentalReverb(0, audioSessionId()).apply { enabled = true }
                }
                this.reverb?.apply {
                    roomLevel = (-1200 + (reverb * 1200).toInt()).toShort()
                    roomHFLevel = -1500
                    decayTime = (600 + (reverb * 2400).toInt())
                    reflectionsLevel = (-2500 + (reverb * 1500).toInt()).toShort()
                    reflectionsDelay = 20
                    reverbLevel = (-2500 + (depth * 2200).toInt()).toShort()
                    reverbDelay = 40
                    diffusion = 1000
                    density = 1000
                    enabled = true
                }
                applied = true
            }
        } catch (_: Exception) {
            this.reverb = null
        }
        return applied
    }

    /**
     * The audio session the effects should attach to. `sessionId` is filled by
     * [eqInit]; when the system equalizer was never opened we fall back to the
     * global output mix (session 0), which is what Android documents for
     * "apply to everything the device is playing".
     */
    private fun audioSessionId(): Int = if (sessionId > 0) sessionId else 0

    private fun releaseSpatial() {
        try {
            virtualizer?.enabled = false
            virtualizer?.release()
        } catch (_: Exception) {
        }
        try {
            reverb?.enabled = false
            reverb?.release()
        } catch (_: Exception) {
        }
        virtualizer = null
        reverb = null
        spatialProcessor.reset()
    }

    private fun releaseEq() {
        try {
            equalizer?.release()
        } catch (_: Exception) {
        }
        equalizer = null
        sessionId = 0
    }

    private fun emptyEq(): Map<String, Any> = mapOf(
        "bands" to 0,
        "min" to -1500,
        "max" to 1500,
        "centersMilliHz" to emptyList<Int>(),
        "levels" to emptyList<Int>(),
        "presets" to emptyList<String>(),
    )

    private fun uniqueFile(dir: File, name: String): File {
        var file = File(dir, name)
        if (!file.exists()) return file
        val dot = name.lastIndexOf('.')
        val base = if (dot > 0) name.substring(0, dot) else name
        val ext = if (dot > 0) name.substring(dot) else ""
        var i = 2
        while (file.exists() && i < 40) {
            file = File(dir, "$base ($i)$ext")
            i++
        }
        return file
    }

    companion object {
        fun repairLocalCache(context: Context) {
            // Do not clear FlutterSharedPreferences here: that file contains
            // the listener's durable library and preferences. Safe mode only
            // needs the crash counter and derived recommendation cache reset.
            SaxifyBoot.reset(context)
            // listOfNotNull: getDatabasePath() is nullable, and a List<File?> would
            // make exists()/delete() illegal calls.
            val names = listOfNotNull(
                File(context.filesDir, "saxify_reco.db"),
                File(context.getDir("flutter", Context.MODE_PRIVATE), "saxify_reco.db"),
                context.getDatabasePath("saxify_reco.db"),
            ).distinct()
            for (file in names) {
                if (file.exists()) file.delete()
            }
        }
    }
}

package ru.arabica.app

import android.graphics.Bitmap
import android.media.MediaExtractor
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import android.util.Log
import java.io.ByteArrayOutputStream
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val VIDEO_UTILS_CHANNEL = "video_utils"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "native_video_player",
            NativeVideoPlayerFactory(flutterEngine.dartExecutor.binaryMessenger)
        )

        // Video utility channel for remuxing broken MP4 files from Samsung camera
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VIDEO_UTILS_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "remux" -> {
                        val inputPath = call.argument<String>("input")
                        val outputPath = call.argument<String>("output")
                        val frontCamera = call.argument<Boolean>("frontCamera") ?: false
                        if (inputPath == null || outputPath == null) {
                            result.error("ARGS", "input and output paths required", null)
                            return@setMethodCallHandler
                        }
                        Thread {
                            try {
                                val success = remuxVideo(inputPath, outputPath, frontCamera)
                                runOnUiThread {
                                    result.success(success)
                                }
                            } catch (e: Exception) {
                                Log.e("VideoUtils", "remux failed: ${e.message}")
                                runOnUiThread {
                                    result.success(false)
                                }
                            }
                        }.start()
                    }
                    "thumbnail" -> {
                        val url = call.argument<String>("url")
                        if (url == null) {
                            result.error("ARGS", "url required", null)
                            return@setMethodCallHandler
                        }
                        Thread {
                            try {
                                val retriever = MediaMetadataRetriever()
                                if (url.startsWith("http://") || url.startsWith("https://")) {
                                    retriever.setDataSource(url, HashMap<String, String>())
                                } else {
                                    retriever.setDataSource(url)
                                }
                                val bitmap = retriever.getFrameAtTime(0, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                                retriever.release()
                                if (bitmap != null) {
                                    val stream = ByteArrayOutputStream()
                                    bitmap.compress(Bitmap.CompressFormat.JPEG, 85, stream)
                                    val bytes = stream.toByteArray()
                                    runOnUiThread { result.success(bytes) }
                                } else {
                                    runOnUiThread { result.success(null) }
                                }
                            } catch (e: Exception) {
                                Log.e("VideoUtils", "thumbnail error: ${e.message}")
                                runOnUiThread { result.success(null) }
                            }
                        }.start()
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Remux MP4 if broken timestamps are detected OR if front camera is used.
     *
     * Some Samsung Exynos cameras record MP4 with wildly incorrect video
     * timescale (e.g. durationUs=55 billion for a 4-second clip).
     * Audio timestamps are always correct.
     *
     * Front camera fix: newer Samsung devices (2025+) store a horizontal
     * mirror flag in the MP4 tkhd transformation matrix. MediaMuxer does NOT
     * copy this matrix (only rotation via setOrientationHint), so remuxing
     * effectively strips the mirror — producing correct (non-mirrored) video.
     * On devices that don't add the mirror flag, remux is a harmless no-op
     * (identical pixels, no re-encoding).
     *
     * Detection: if video durationUs > 3× audio durationUs → broken timestamps.
     * If frontCamera=true → always remux to strip potential mirror matrix.
     * Returns false if no remux was needed or performed.
     */
    private fun remuxVideo(inputPath: String, outputPath: String, frontCamera: Boolean = false): Boolean {
        val extractor = MediaExtractor()
        extractor.setDataSource(inputPath)

        val trackCount = extractor.trackCount
        var videoTrackIdx = -1
        var audioTrackIdx = -1
        var videoDurationUs = 0L
        var audioDurationUs = 0L
        var rotation = 0

        for (i in 0 until trackCount) {
            val format = extractor.getTrackFormat(i)
            val mime = format.getString(android.media.MediaFormat.KEY_MIME) ?: ""
            Log.d("VideoUtils", "track $i: $mime, format=$format")
            if (mime.startsWith("video/") && videoTrackIdx < 0) {
                videoTrackIdx = i
                videoDurationUs = try { format.getLong(android.media.MediaFormat.KEY_DURATION) } catch (_: Exception) { 0L }
                rotation = try { format.getInteger("rotation-degrees") } catch (_: Exception) { 0 }
            } else if (mime.startsWith("audio/") && audioTrackIdx < 0) {
                audioTrackIdx = i
                audioDurationUs = try { format.getLong(android.media.MediaFormat.KEY_DURATION) } catch (_: Exception) { 0L }
            }
        }

        Log.d("VideoUtils", "remux check: videoDur=${videoDurationUs/1000}ms, audioDur=${audioDurationUs/1000}ms, frontCamera=$frontCamera, ratio=${if (audioDurationUs > 0) videoDurationUs / audioDurationUs else -1}")

        // Detection: timestamps are broken if video duration is wildly off
        val timestampsBroken = audioDurationUs > 0 && videoDurationUs > audioDurationUs * 3

        // Front camera: always remux to strip potential mirror matrix from tkhd
        val needsRemux = timestampsBroken || frontCamera

        if (!needsRemux) {
            Log.d("VideoUtils", "timestamps OK, not front camera — no remux needed")
            extractor.release()
            return false
        }

        Log.d("VideoUtils", "remux reason: ${if (timestampsBroken) "broken timestamps (${videoDurationUs/1000}ms vs ${audioDurationUs/1000}ms)" else "front camera mirror strip"}")

        // Pass 1: count video frames (only needed for broken timestamps)
        var videoFrameCount = 0
        var frameIntervalUs = 33_333L
        if (timestampsBroken && videoTrackIdx >= 0) {
            extractor.selectTrack(videoTrackIdx)
            val countBuf = java.nio.ByteBuffer.allocate(1024 * 1024)
            while (extractor.readSampleData(countBuf, 0) >= 0) {
                videoFrameCount++
                extractor.advance()
            }
            extractor.unselectTrack(videoTrackIdx)

            frameIntervalUs = if (videoFrameCount > 1 && audioDurationUs > 0) {
                audioDurationUs / videoFrameCount
            } else {
                33_333L
            }
            Log.d("VideoUtils", "$videoFrameCount frames, interval=${frameIntervalUs}μs (${1_000_000.0 / frameIntervalUs} fps)")
        }

        // Pass 2: remux (strips tkhd mirror matrix; fixes timestamps if broken)
        extractor.release()
        val ext2 = MediaExtractor()
        ext2.setDataSource(inputPath)

        val muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)

        // Rotation: only via setOrientationHint (strip from format to avoid double-write)
        // MediaMuxer does NOT copy the tkhd transformation matrix — this strips any
        // horizontal mirror flag that Samsung 2025+ front cameras add.
        if (rotation != 0) {
            muxer.setOrientationHint(rotation)
        }

        val trackMap = mutableMapOf<Int, Int>()
        for (i in 0 until trackCount) {
            val format = ext2.getTrackFormat(i)
            if (i == videoTrackIdx) {
                try { format.setInteger("rotation-degrees", 0) } catch (_: Exception) {}
                if (timestampsBroken && audioDurationUs > 0) {
                    format.setLong(android.media.MediaFormat.KEY_DURATION, audioDurationUs)
                }
            }
            trackMap[i] = muxer.addTrack(format)
        }
        muxer.start()

        val buffer = java.nio.ByteBuffer.allocate(1024 * 1024)
        val bufferInfo = android.media.MediaCodec.BufferInfo()

        // Select all tracks for interleaved reading
        for (i in 0 until trackCount) ext2.selectTrack(i)

        var videoFrameIdx = 0
        var audioBaseTs = -1L

        while (true) {
            val trackIdx = ext2.sampleTrackIndex
            if (trackIdx < 0) break
            val sampleSize = ext2.readSampleData(buffer, 0)
            if (sampleSize < 0) break

            bufferInfo.offset = 0
            bufferInfo.size = sampleSize
            bufferInfo.flags = ext2.sampleFlags

            val dstTrack = trackMap[trackIdx]
            if (dstTrack != null) {
                if (trackIdx == videoTrackIdx && timestampsBroken) {
                    // Recalculate timestamps only when they're broken
                    bufferInfo.presentationTimeUs = videoFrameIdx.toLong() * frameIntervalUs
                    videoFrameIdx++
                } else {
                    // Preserve original timestamps (front camera mirror strip or audio)
                    val ts = ext2.sampleTime
                    if (trackIdx != videoTrackIdx) {
                        if (audioBaseTs < 0) audioBaseTs = ts
                        bufferInfo.presentationTimeUs = if (timestampsBroken) ts - audioBaseTs else ts
                    } else {
                        bufferInfo.presentationTimeUs = ts
                    }
                }
                muxer.writeSampleData(dstTrack, buffer, bufferInfo)
            }
            ext2.advance()
        }

        muxer.stop()
        muxer.release()
        ext2.release()

        Log.d("VideoUtils", "remux done: rotation=$rotation, timestampsFix=$timestampsBroken, frontCamera=$frontCamera → $outputPath")
        return true
    }
}

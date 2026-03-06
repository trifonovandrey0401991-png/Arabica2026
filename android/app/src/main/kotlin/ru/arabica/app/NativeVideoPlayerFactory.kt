package ru.arabica.app

import android.content.Context
import android.graphics.Outline
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.util.Log
import android.view.TextureView
import android.view.View
import android.view.ViewOutlineProvider
import android.widget.FrameLayout
import android.widget.ImageView
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

private const val TAG = "NativeVideoPlayer"

class NativeVideoPlayerFactory(
    private val messenger: BinaryMessenger
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        @Suppress("UNCHECKED_CAST")
        val params = args as? Map<String, Any?>
        Log.d(TAG, "Factory.create viewId=$viewId")
        return NativeVideoPlayerView(context, viewId, params, messenger)
    }
}

/**
 * Native video player using ExoPlayer + TextureView.
 *
 * Forces software video decoder (OMX.google / c2.android) instead of hardware
 * Exynos decoder. This fixes video playback on Samsung Exynos devices where the
 * hardware decoder fails to render frames through Flutter's SurfaceTexture pipeline.
 *
 * For 180x180 video notes, software decoding has negligible CPU overhead.
 *
 * Layout: TextureView (video) + ImageView (thumbnail, hidden during playback)
 * Both clipped to circle via ViewOutlineProvider.
 */
class NativeVideoPlayerView(
    private val context: Context,
    viewId: Int,
    creationParams: Map<String, Any?>?,
    messenger: BinaryMessenger
) : PlatformView {

    private val container = FrameLayout(context)

    // TextureView: ExoPlayer renders video frames here
    private val textureView = TextureView(context)

    // ImageView: shows thumbnail before playback starts (on top of TextureView)
    private val imageView = ImageView(context).apply {
        scaleType = ImageView.ScaleType.CENTER_CROP
    }

    private var exoPlayer: ExoPlayer? = null
    private val channel = MethodChannel(messenger, "native_video_player_$viewId")
    private var isPrepared = false
    private var autoPlay = false
    private var looping = false
    private var isPlaying = false
    private var isMirrored = false

    init {
        // Circular clipping for both views
        val ovalOutline = object : ViewOutlineProvider() {
            override fun getOutline(view: View, outline: Outline) {
                outline.setOval(0, 0, view.width, view.height)
            }
        }

        textureView.outlineProvider = ovalOutline
        textureView.clipToOutline = true
        container.addView(textureView, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
        ))

        imageView.outlineProvider = ovalOutline
        imageView.clipToOutline = true
        container.addView(imageView, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
        ))

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "play" -> {
                    Log.d(TAG, "play: isPrepared=$isPrepared, isPlaying=$isPlaying")
                    if (isPrepared) {
                        // Hide thumbnail to reveal TextureView underneath
                        imageView.visibility = View.GONE
                        exoPlayer?.playWhenReady = true
                        isPlaying = true
                        Log.d(TAG, "play: started")
                    } else {
                        autoPlay = true
                        Log.d(TAG, "play: deferred (not yet prepared)")
                    }
                    result.success(null)
                }
                "pause" -> {
                    if (isPrepared) {
                        exoPlayer?.playWhenReady = false
                        isPlaying = false
                    }
                    result.success(null)
                }
                "seekTo" -> {
                    val ms = call.argument<Int>("position") ?: 0
                    if (isPrepared) exoPlayer?.seekTo(ms.toLong())
                    result.success(null)
                }
                "isPlaying" -> {
                    result.success(isPrepared && isPlaying)
                }
                "getPosition" -> {
                    val pos = exoPlayer?.currentPosition?.toInt() ?: 0
                    val dur = exoPlayer?.duration?.toInt() ?: 0
                    result.success(mapOf("position" to pos, "duration" to dur))
                }
                else -> result.notImplemented()
            }
        }

        val url = creationParams?.get("url") as? String
        val isFile = creationParams?.get("isFile") as? Boolean ?: false
        val mirror = creationParams?.get("mirror") as? Boolean ?: false
        looping = creationParams?.get("loop") as? Boolean ?: false
        Log.d(TAG, "init: url=$url, isFile=$isFile, loop=$looping, mirror=$mirror")

        // Mirror horizontally for front camera recordings
        if (mirror) {
            isMirrored = true
            textureView.scaleX = -1f
            imageView.scaleX = -1f
        }
        if (url != null) {
            initPlayer(url, isFile)
        }
    }

    @androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
    private fun initPlayer(url: String, isFile: Boolean) {
        try {
            releasePlayer()
            Log.d(TAG, "initPlayer: url=$url, isFile=$isFile")

            // Use default decoder selection (hardware preferred).
            // The original Exynos "SurfaceTexture rendering bug" was actually caused
            // by broken timestamps in Samsung camera recordings (55M seconds duration).
            // Now that remux fixes timestamps, hardware decoder works correctly.
            val player = ExoPlayer.Builder(context).build()
            exoPlayer = player

            // ExoPlayer manages TextureView lifecycle (Surface creation/destruction)
            player.setVideoTextureView(textureView)

            // Set media source
            val mediaItem = if (isFile) {
                MediaItem.fromUri(Uri.parse("file://$url"))
            } else {
                MediaItem.fromUri(Uri.parse(url))
            }
            player.setMediaItem(mediaItem)

            // Configure
            player.repeatMode = if (looping) Player.REPEAT_MODE_ONE else Player.REPEAT_MODE_OFF
            player.playWhenReady = false
            player.volume = 1f

            // Listen for state changes
            player.addListener(object : Player.Listener {
                override fun onPlaybackStateChanged(playbackState: Int) {
                    when (playbackState) {
                        Player.STATE_READY -> {
                            if (!isPrepared) {
                                isPrepared = true
                                val duration = player.duration
                                val width = player.videoSize.width
                                val height = player.videoSize.height
                                Log.d(TAG, "onReady: ${width}x${height}, duration=${duration}ms, autoPlay=$autoPlay")

                                channel.invokeMethod("onReady", mapOf(
                                    "duration" to duration.toInt(),
                                    "width" to width,
                                    "height" to height
                                ))

                                if (autoPlay) {
                                    imageView.visibility = View.GONE
                                    player.playWhenReady = true
                                    isPlaying = true
                                    Log.d(TAG, "onReady: auto-started")
                                }
                            }
                        }
                        Player.STATE_ENDED -> {
                            if (!looping) {
                                Log.d(TAG, "onCompleted")
                                isPlaying = false
                                channel.invokeMethod("onCompleted", null)
                            }
                        }
                    }
                }

                override fun onPlayerError(error: PlaybackException) {
                    Log.e(TAG, "onError: ${error.errorCodeName} — ${error.message}")
                    isPlaying = false
                    channel.invokeMethod("onError", mapOf("message" to (error.message ?: "Playback error")))
                }

                override fun onVideoSizeChanged(videoSize: androidx.media3.common.VideoSize) {
                    Log.d(TAG, "onVideoSizeChanged: ${videoSize.width}x${videoSize.height}")

                    // Apply "cover" scaling: fill container without distortion, crop overflow.
                    // TextureView stretches by default; we counteract by scaling the axis
                    // that would otherwise be compressed.
                    val vw = videoSize.width.toFloat()
                    val vh = videoSize.height.toFloat()
                    val cw = container.width.toFloat()
                    val ch = container.height.toFloat()
                    if (vw > 0 && vh > 0 && cw > 0 && ch > 0) {
                        val videoRatio = vw / vh
                        val containerRatio = cw / ch
                        val mirrorSign = if (isMirrored) -1f else 1f
                        if (videoRatio < containerRatio) {
                            // Video is taller than container — scale Y up
                            textureView.scaleX = 1f * mirrorSign
                            textureView.scaleY = containerRatio / videoRatio
                        } else if (videoRatio > containerRatio) {
                            // Video is wider than container — scale X up
                            textureView.scaleX = (videoRatio / containerRatio) * mirrorSign
                            textureView.scaleY = 1f
                        } else {
                            textureView.scaleX = 1f * mirrorSign
                            textureView.scaleY = 1f
                        }
                    }

                    channel.invokeMethod("onSizeChanged", mapOf(
                        "width" to videoSize.width,
                        "height" to videoSize.height
                    ))
                }

                override fun onRenderedFirstFrame() {
                    Log.d(TAG, ">>> onRenderedFirstFrame <<<")
                }
            })

            // Prepare (async)
            player.prepare()

            // Extract first frame as thumbnail
            extractThumbnail(url, isFile)
        } catch (e: Exception) {
            Log.e(TAG, "initPlayer error: ${e.message}")
            channel.invokeMethod("onError", mapOf("message" to (e.message ?: "Init error")))
        }
    }

    private fun extractThumbnail(url: String, isFile: Boolean) {
        Thread {
            try {
                val retriever = MediaMetadataRetriever()
                if (isFile) {
                    retriever.setDataSource(url)
                } else {
                    retriever.setDataSource(url, HashMap<String, String>())
                }
                val thumb = retriever.getFrameAtTime(0, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                retriever.release()
                if (thumb != null) {
                    imageView.post {
                        if (!isPlaying) {
                            imageView.setImageBitmap(thumb)
                            channel.invokeMethod("onThumbnailReady", null)
                            Log.d(TAG, "extractThumbnail: displayed ${thumb.width}x${thumb.height}")
                        }
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "extractThumbnail failed: ${e.message}")
            }
        }.start()
    }

    // --- PlatformView ---
    override fun getView(): View = container

    override fun dispose() {
        Log.d(TAG, "dispose")
        releasePlayer()
        channel.setMethodCallHandler(null)
    }

    private fun releasePlayer() {
        try {
            exoPlayer?.setVideoTextureView(null)
            exoPlayer?.release()
        } catch (_: Exception) {}
        exoPlayer = null
        isPrepared = false
        isPlaying = false
    }
}

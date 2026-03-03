import Flutter
import AVFoundation
import UIKit

class NativeVideoPlayerFactory: NSObject, FlutterPlatformViewFactory {
    private let messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }

    func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        return NativeVideoPlayerView(
            frame: frame,
            viewId: viewId,
            args: args as? [String: Any],
            messenger: messenger
        )
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }
}

// Custom UIView that keeps AVPlayerLayer sized correctly + circular clipping
private class PlayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    func setPlayer(_ player: AVPlayer?) {
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspectFill
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Circular clip
        let size = min(bounds.width, bounds.height)
        layer.cornerRadius = size / 2
        clipsToBounds = true
    }
}

class NativeVideoPlayerView: NSObject, FlutterPlatformView {
    private let containerView: UIView
    private let playerUIView: PlayerUIView
    private let thumbnailImageView: UIImageView
    private var player: AVPlayer?
    private let channel: FlutterMethodChannel
    private var statusObserver: NSKeyValueObservation?
    private var completionObserver: Any?
    private var looping: Bool = false
    private var isPlayingVideo: Bool = false

    init(frame: CGRect, viewId: Int64, args: [String: Any]?, messenger: FlutterBinaryMessenger) {
        containerView = UIView(frame: frame)
        containerView.backgroundColor = .black
        containerView.clipsToBounds = true

        playerUIView = PlayerUIView(frame: containerView.bounds)
        playerUIView.backgroundColor = .clear
        playerUIView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        thumbnailImageView = UIImageView(frame: containerView.bounds)
        thumbnailImageView.contentMode = .scaleAspectFill
        thumbnailImageView.clipsToBounds = true
        thumbnailImageView.backgroundColor = .clear
        thumbnailImageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        containerView.addSubview(playerUIView)
        containerView.addSubview(thumbnailImageView)

        channel = FlutterMethodChannel(
            name: "native_video_player_\(viewId)",
            binaryMessenger: messenger
        )

        super.init()

        channel.setMethodCallHandler { [weak self] call, result in
            self?.handleMethod(call: call, result: result)
        }

        looping = args?["loop"] as? Bool ?? false
        if let url = args?["url"] as? String {
            let isFile = args?["isFile"] as? Bool ?? false
            initPlayer(url: url, isFile: isFile)
        }
    }

    func view() -> UIView { containerView }

    private func initPlayer(url: String, isFile: Bool) {
        let playerItem: AVPlayerItem
        let asset: AVAsset

        if isFile {
            let fileUrl = URL(fileURLWithPath: url)
            asset = AVAsset(url: fileUrl)
            playerItem = AVPlayerItem(asset: asset)
        } else {
            guard let videoUrl = URL(string: url) else {
                channel.invokeMethod("onError", arguments: ["message": "Invalid URL: \(url)"])
                return
            }
            asset = AVAsset(url: videoUrl)
            playerItem = AVPlayerItem(asset: asset)
        }

        let avPlayer = AVPlayer(playerItem: playerItem)
        player = avPlayer
        playerUIView.setPlayer(avPlayer)

        // Extract first frame as thumbnail in background
        extractThumbnail(asset: asset)

        // Observe readyToPlay
        statusObserver = playerItem.observe(\.status, options: [.new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if item.status == .readyToPlay {
                    let durationMs = Int(CMTimeGetSeconds(item.duration) * 1000)
                    let size = item.presentationSize
                    self.channel.invokeMethod("onReady", arguments: [
                        "duration": durationMs,
                        "width": Int(size.width),
                        "height": Int(size.height)
                    ])
                } else if item.status == .failed {
                    self.channel.invokeMethod("onError", arguments: [
                        "message": item.error?.localizedDescription ?? "Playback failed"
                    ])
                }
            }
        }

        // Observe completion
        completionObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            if self.looping {
                self.player?.seek(to: .zero)
                self.player?.play()
            } else {
                self.isPlayingVideo = false
                self.channel.invokeMethod("onCompleted", arguments: nil)
            }
        }
    }

    private func extractThumbnail(asset: AVAsset) {
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: 360, height: 360)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let cgImage = try imageGenerator.copyCGImage(at: .zero, actualTime: nil)
                let thumbnail = UIImage(cgImage: cgImage)
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    if !self.isPlayingVideo {
                        self.thumbnailImageView.image = thumbnail
                        self.channel.invokeMethod("onThumbnailReady", arguments: nil)
                    }
                }
            } catch {
                // Thumbnail extraction failed, ignore
            }
        }
    }

    private func handleMethod(call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "play":
            isPlayingVideo = true
            thumbnailImageView.isHidden = true
            player?.play()
            result(nil)
        case "pause":
            player?.pause()
            result(nil)
        case "seekTo":
            if let args = call.arguments as? [String: Any],
               let ms = args["position"] as? Int {
                let time = CMTime(value: Int64(ms), timescale: 1000)
                player?.seek(to: time)
            }
            result(nil)
        case "isPlaying":
            result(player?.rate ?? 0 > 0)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func releasePlayer() {
        statusObserver?.invalidate()
        statusObserver = nil
        if let obs = completionObserver {
            NotificationCenter.default.removeObserver(obs)
            completionObserver = nil
        }
        player?.pause()
        playerUIView.setPlayer(nil)
        player = nil
        isPlayingVideo = false
    }

    deinit {
        releasePlayer()
        channel.setMethodCallHandler(nil)
    }
}

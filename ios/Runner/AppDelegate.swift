import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Register native video player for video notes
    let registrar = self.registrar(forPlugin: "NativeVideoPlayer")!
    let factory = NativeVideoPlayerFactory(messenger: registrar.messenger())
    registrar.register(factory, withId: "native_video_player")

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

import UIKit
import MediaPlayer

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        print("📱 [AppDelegate] 应用启动中，配置控制中心功能")
        
        // 配置远程控制
        setupRemoteCommandCenter()
        
        return true
    }
    
    // 配置远程控制命令中心
    private func setupRemoteCommandCenter() {
        print("📱 [AppDelegate] 设置MPRemoteCommandCenter")
        
        let commandCenter = MPRemoteCommandCenter.shared()
        
        // 播放/暂停命令
        commandCenter.playCommand.addTarget { [weak self] event in
            print("📱 [AppDelegate] 收到控制中心播放命令")
            MusicPlayer.shared.resume()
            // 发送播放器状态变化通知，确保UI更新
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: NSNotification.Name("PlayerStateChanged"), object: nil)
                NotificationCenter.default.post(name: .musicPlayerPlaybackStateChanged, object: nil)
            }
            return .success
        }
        
        commandCenter.pauseCommand.addTarget { [weak self] event in
            print("📱 [AppDelegate] 收到控制中心暂停命令")
            MusicPlayer.shared.pause()
            // 发送播放器状态变化通知，确保UI更新
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: NSNotification.Name("PlayerStateChanged"), object: nil)
                NotificationCenter.default.post(name: .musicPlayerPlaybackStateChanged, object: nil)
            }
            return .success
        }
        
        // 上一首/下一首命令
        commandCenter.previousTrackCommand.addTarget { [weak self] event in
            print("📱 [AppDelegate] 收到控制中心上一首命令")
            MusicPlayer.shared.playPrevious()
            return .success
        }
        
        commandCenter.nextTrackCommand.addTarget { [weak self] event in
            print("📱 [AppDelegate] 收到控制中心下一首命令")
            MusicPlayer.shared.playNext()
            return .success
        }
        
        // 快进/快退命令
        commandCenter.seekForwardCommand.addTarget { [weak self] event in
            print("📱 [AppDelegate] 收到控制中心快进命令")
            // 这里可以实现快进逻辑
            return .success
        }
        
        commandCenter.seekBackwardCommand.addTarget { [weak self] event in
            print("📱 [AppDelegate] 收到控制中心快退命令")
            // 这里可以实现快退逻辑
            return .success
        }
        
        // 设置命令可用状态
        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.isEnabled = true
        
        print("📱 [AppDelegate] MPRemoteCommandCenter配置完成")
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }

}
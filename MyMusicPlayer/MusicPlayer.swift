import Foundation
import AVFoundation
import MediaPlayer
import UIKit

class DirectoryItem: Equatable {
    let url: URL?
    let name: String
    weak var parentDirectory: DirectoryItem?
    var subdirectories: [DirectoryItem] = []
    var musicFiles: [MusicItem] = []
    var isExpanded: Bool = false
    
    init(name: String, url: URL) {
        self.name = name
        self.url = url
    }
    
    init(url: URL, name: String) {
        self.url = url
        self.name = name
    }
    
    static func == (lhs: DirectoryItem, rhs: DirectoryItem) -> Bool {
        return lhs.url == rhs.url
    }
}

class MusicItem {
    let url: URL
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval
    weak var parentDirectory: DirectoryItem?
    var lyricsURL: URL?
    var lyrics: [LyricsLine] = []
    
    init(url: URL) {
        self.url = url
        self.title = url.lastPathComponent
        self.artist = "Unknown Artist"
        self.album = "Unknown Album"
        self.duration = 0
    }
    
    init(title: String, artist: String, album: String, duration: TimeInterval, filePath: String) {
        self.url = URL(fileURLWithPath: filePath)
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
    }
}

// 播放模式枚举
enum PlayMode: Int, CaseIterable {
    case sequence // 顺序播放
    case repeatOne // 单曲循环
    case shuffle // 随机播放
    
    // 持久化相关键名
    private static let userDefaultsKey = "MusicPlayer_PlayMode"
    static let rangeLockKey = "MusicPlayer_RangeLock"
    
    // 保存播放模式到用户数据
    func save() {
        UserDefaults.standard.set(self.rawValue, forKey: Self.userDefaultsKey)
        print("[MusicPlayer] 播放模式已保存: \(self)")
    }
    
    // 从用户数据加载播放模式
    static func load() -> PlayMode {
        let savedValue = UserDefaults.standard.integer(forKey: Self.userDefaultsKey)
        return PlayMode(rawValue: savedValue) ?? .sequence // 默认顺序播放
    }
}

class MusicPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    // 单例模式
    static let shared = MusicPlayer()
    
    // 移除不再使用的AVAudioPlayer
    
    // 播放列表和当前状态
    @Published var currentMusic: MusicItem?
    @Published var isPlaying: Bool = false
    @Published var currentTime: TimeInterval = 0
    @Published var totalTime: TimeInterval = 0
    @Published var playMode: PlayMode = PlayMode.load() // 从用户数据加载播放模式
    @Published var isRangeLocked: Bool = false // 初始化为false，在init中加载
    
    // 完整播放列表和当前目录播放列表
    private var fullPlaylist: [MusicItem] = []
    private var currentDirectoryPlaylist: [MusicItem] = []
    private var currentIndex: Int = -1
    private var shuffleIndices: [Int] = []
    
    // 计时器用于更新播放进度
    private var progressTimer: Timer?
    
    // 音频播放器组件
    private var audioPlayer: AVAudioPlayer? = nil
    
    override init() {
        // 从用户数据加载播放范围锁定状态
        isRangeLocked = UserDefaults.standard.bool(forKey: PlayMode.rangeLockKey)
        super.init()
        setupAudioSession()
        setupAudioPlayer()
        print("[MusicPlayer] 从用户数据加载播放范围锁定状态: \(isRangeLocked)")
    }
    
    // 初始化音频播放器组件
    private func setupAudioPlayer() {
        print("[MusicPlayer] 音频播放器初始化成功")
    }
    
    // 设置远程控制命令中心
    // 远程控制命令中心的配置已移至AppDelegate.swift中实现
    // 避免重复设置导致的冲突问题
    
    // 设置音频会话
    private func setupAudioSession() {
        do {
            print("[MusicPlayer] 开始配置音频会话")
            let session = AVAudioSession.sharedInstance()
            
            // 先尝试停用现有的音频会话
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            
            // 为控制中心显示和后台播放配置音频会话
            // 移除.mixWithOthers选项，使用更标准的配置
            try session.setCategory(.playback, mode: .default, options: [])
            
            // 立即激活会话，确保控制中心能正确识别
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            print("[MusicPlayer] 音频会话成功激活")
            
        } catch {
            print("[MusicPlayer] 音频会话设置失败: \(error)")
            // 错误2003332927通常表示Core Audio设备属性访问问题，记录详细信息便于调试
            let nserror = error as NSError
            if nserror.domain == NSOSStatusErrorDomain {
                print("[MusicPlayer] Core Audio错误代码: \(nserror.code)，这通常是系统音频设备问题")
            }
        }
    }
    
    // 确保应用成为活动的媒体播放器
    private func becomeActiveMediaPlayer() {
        do {
            print("[MusicPlayer] 尝试成为活动媒体播放器")
            let session = AVAudioSession.sharedInstance()
            
            // 直接尝试激活会话，不再检查isActive属性
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            print("[MusicPlayer] 音频会话已激活")
            
            // 远程控制接收者设置已移至AppDelegate
            
            // 强制更新一次Now Playing信息
            DispatchQueue.main.async {
                self.updateNowPlayingInfo()
            }
            
        } catch {
            print("[MusicPlayer] 无法激活音频会话: \(error)")
            // 记录AQMEIO_HAL相关错误信息
            let nserror = error as NSError
            if nserror.domain == NSOSStatusErrorDomain {
                print("[MusicPlayer] Core Audio错误代码: \(nserror.code)，这通常是系统音频设备问题")
            }
        }
    }
    
    // 设置播放列表
    func setPlaylist(_ playlist: [MusicItem]) {
        fullPlaylist = playlist
        if isRangeLocked && currentMusic != nil {
            updateCurrentDirectoryPlaylist()
        } else {
            currentDirectoryPlaylist = fullPlaylist
        }
        resetShuffleIndices()
    }
    
    // 播放指定的音乐
    func playMusic(_ music: MusicItem, at index: Int) {
        // 防御性检查：确保传入的music不为nil
        let musicURL = music.url
        
        currentMusic = music
        
        // 确保索引在有效范围内
        self.currentIndex = (index >= 0 && (!currentDirectoryPlaylist.isEmpty || index == 0)) ? index : 0
        
        // 更新当前目录播放列表
        if isRangeLocked {
            updateCurrentDirectoryPlaylist()
        }
        
        // 加载歌词
        if let lyricsURL = music.lyricsURL {
            if let lyrics = LyricsParser.parseLyrics(from: lyricsURL) {
                music.lyrics = lyrics
            }
        }
        
        // 播放音乐
        playAudio(musicURL)
        
        // 发送播放器状态改变通知，让所有监听的视图控制器更新UI
        NotificationCenter.default.post(name: NSNotification.Name("PlayerStateChanged"), object: nil)
    }
    
    // 更新当前目录播放列表
    private func updateCurrentDirectoryPlaylist() {
        // 临时变量存储新的播放列表
        var newPlaylist: [MusicItem] = []
        
        if let currentMusic = currentMusic {
            // 如果锁定范围，播放列表只包含当前目录的音乐
            if isRangeLocked {
                newPlaylist = fullPlaylist.filter { $0.parentDirectory == currentMusic.parentDirectory }
            } else {
                // 否则使用完整播放列表
                newPlaylist = fullPlaylist
            }
        } else {
            // 当前音乐为nil，使用完整播放列表
            print("[MusicPlayer] 当前播放音乐为nil，使用完整播放列表")
            newPlaylist = fullPlaylist
        }
        
        // 确保播放列表有效，避免空数组问题
        if newPlaylist.isEmpty {
            print("[MusicPlayer] 播放列表为空，重置索引")
            currentDirectoryPlaylist = []
            currentIndex = -1
            return
        }
        
        // 更新播放列表
        currentDirectoryPlaylist = newPlaylist
        
        // 尝试更新当前索引，确保它在有效范围内
        if let currentMusic = currentMusic {
            if let newIndex = currentDirectoryPlaylist.firstIndex(where: { $0.url == currentMusic.url }) {
                currentIndex = newIndex
            } else {
                // 如果找不到当前音乐，设置索引为0
                print("[MusicPlayer] 在新播放列表中找不到当前音乐，重置为第一首")
                currentIndex = 0
            }
        } else {
            // 当前音乐为nil，设置索引为0
            currentIndex = 0
        }
        
        // 如果是随机播放模式，重置随机索引列表
        if playMode == .shuffle {
            resetShuffleIndices()
        }
    }
    
    // 用于跟踪需要保持访问权限的资源
    private var securityScopedResources: [URL] = []
    
    // 播放音频文件
    private func playAudio(_ url: URL) {
        // 防御性检查
        if !FileManager.default.fileExists(atPath: url.path) {
            print("[MusicPlayer] 警告: 文件不存在: \(url.path)")
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        
        // 尝试获取文件访问权限
        var shouldStopAccess = false
        if url.startAccessingSecurityScopedResource() {
            shouldStopAccess = true
            securityScopedResources.append(url)
            print("[MusicPlayer] 成功获取音频文件访问权限: \(url.lastPathComponent)")
        }

        do {
            // 音频会话仅在需要时激活
            becomeActiveMediaPlayer()
            
            // 创建并配置AVAudioPlayer
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            
            // 尝试播放
            if let audioPlayer = audioPlayer, audioPlayer.prepareToPlay() {
                // 确保在播放前激活音频会话
                becomeActiveMediaPlayer()
                
                // 实际播放音频
                audioPlayer.play()
                isPlaying = true
                totalTime = audioPlayer.duration
                currentTime = 0
                
                // 启动进度更新计时器
                startProgressTimer()
                
                // 立即更新控制中心信息
                updateNowPlayingInfo()
                
                // 记录成功播放的日志
                print("[MusicPlayer] 开始播放: \(currentMusic?.title ?? "未知歌曲")")
            } else {
                // 准备播放失败的处理
                print("[MusicPlayer] 准备播放失败: \(url.lastPathComponent)")
                isPlaying = false
                // 播放失败时清除控制中心信息
                MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            }
        } catch {
            // 错误处理
            print("[MusicPlayer] 播放音乐失败: \(error)")
            isPlaying = false
            
            // 播放失败时清除控制中心信息
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            
            // 如果播放失败，释放访问权限
            if shouldStopAccess {
                url.stopAccessingSecurityScopedResource()
                // 从跟踪列表中移除
                securityScopedResources.removeAll { $0 == url }
            }
            
            // 尝试清除播放器并准备重新创建
            audioPlayer = nil
            
            // 针对某些特定错误进行重试逻辑
            if (error as NSError).domain == NSOSStatusErrorDomain {
                print("[MusicPlayer] Core Audio错误: \((error as NSError).code)")
            }
        }
    }
    
    // 启动进度更新计时器
    private func startProgressTimer() {
        // 先停止之前的计时器
        stopProgressTimer()
        
        // 创建新的计时器
        progressTimer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(updatePlayProgress), userInfo: nil, repeats: true)
    }
    
    // 停止进度更新计时器
    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }
    
    // 连续检测到播放停滞的次数
    private var playbackStallCount: Int = 0
    
    // 更新播放进度
    @objc private func updatePlayProgress() {
        // 更新当前播放时间
        currentTime = audioPlayer?.currentTime ?? 0
        
        // 检查播放是否完成
        if isPlaying && currentTime >= totalTime && totalTime > 0 {
            audioPlayerDidFinishPlaying(audioPlayer!, successfully: true)
        }
        
        updateNowPlayingInfo()
    }
    
    // 更新控制中心显示信息
    func updateNowPlayingInfo() {
        // 检查是否有正在播放的音乐
        guard let currentMusic = currentMusic else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        
        // 创建完整的Now Playing信息字典，包含更多详细信息
        var info: [String: Any] = [
            // 基本信息
            MPMediaItemPropertyTitle: currentMusic.title.isEmpty ? "未知标题" : currentMusic.title,
            MPMediaItemPropertyArtist: currentMusic.artist.isEmpty ? "未知艺术家" : currentMusic.artist,
            MPMediaItemPropertyAlbumTitle: currentMusic.album.isEmpty ? "未知专辑" : currentMusic.album,
            
            // 播放状态信息
            MPMediaItemPropertyPlaybackDuration: totalTime,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            
            // 播放列表信息
            MPNowPlayingInfoPropertyIsLiveStream: false,
        ]
        
        // 添加播放列表位置信息
        let totalTracks = isRangeLocked ? currentDirectoryPlaylist.count : fullPlaylist.count
        if totalTracks > 0 && currentIndex >= 0 {
            info[MPMediaItemPropertyPersistentID] = currentIndex + 1
            info[MPMediaItemPropertyAlbumTrackNumber] = currentIndex + 1
            info[MPMediaItemPropertyAlbumTrackCount] = totalTracks
        }
        
        // 确保在主线程更新控制中心信息
        DispatchQueue.main.async {
            // 复制变量到闭包内部，避免作用域问题
            let localInfo = info
            
            // 直接更新Now Playing信息，不清除旧信息，避免闪烁
            MPNowPlayingInfoCenter.default().nowPlayingInfo = localInfo
            
            // 验证设置后的信息
            let updatedInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo
            if updatedInfo == nil {
                // 重试一次，这次先清除再设置
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        MPNowPlayingInfoCenter.default().nowPlayingInfo = localInfo
                    }
                }
            }
        }
        
        // 确保远程控制命令中心的状态与当前播放器状态一致
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.isEnabled = !isPlaying
        commandCenter.pauseCommand.isEnabled = isPlaying
    }
    
    // 清理安全范围资源的访问权限
    private func clearSecurityScopedResources() {
        for url in securityScopedResources {
            url.stopAccessingSecurityScopedResource()
        }
        securityScopedResources.removeAll()
    }
    
    // 播放/暂停
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            if currentMusic != nil {
                resume()
            } else if !currentDirectoryPlaylist.isEmpty {
                playMusic(currentDirectoryPlaylist[0], at: 0)
            }
        }
    }
    
    // 暂停播放
    func pause() {
        if audioPlayer?.isPlaying ?? false {
            audioPlayer?.pause()
            isPlaying = false
            stopProgressTimer()
            updateNowPlayingInfo()
        }
    }
    
    // 恢复播放
    func resume() {
        if !(audioPlayer?.isPlaying ?? false) && !currentDirectoryPlaylist.isEmpty {
            audioPlayer?.play()
            isPlaying = true
            startProgressTimer()
            updateNowPlayingInfo()
        }
    }
    
    // 播放上一首
    func playPrevious() {
        guard !currentDirectoryPlaylist.isEmpty else { return }
        
        var newIndex: Int
        
        switch playMode {
        case .sequence:
            newIndex = currentIndex - 1
            if newIndex < 0 {
                newIndex = currentDirectoryPlaylist.count - 1
            }
        case .repeatOne:
            newIndex = currentIndex // 单曲循环，索引不变
        case .shuffle:
            // 随机播放模式下，重新生成随机索引
            if shuffleIndices.isEmpty {
                resetShuffleIndices()
            }
            newIndex = shuffleIndices.removeFirst()
        }
        
        let music = currentDirectoryPlaylist[newIndex]
        playMusic(music, at: newIndex)
    }
    
    // 播放下一首
    func playNext() {
        guard !currentDirectoryPlaylist.isEmpty else { 
            print("[MusicPlayer] 播放队列为空，无法播放下一曲")
            return 
        }
        
        var newIndex: Int
        
        switch playMode {
        case .sequence:
            // 安全计算顺序播放的下一个索引
            newIndex = (currentIndex >= 0 ? currentIndex + 1 : 0)
            if newIndex >= currentDirectoryPlaylist.count {
                newIndex = 0
            }
        case .repeatOne:
            // 单曲循环，确保索引有效
            if currentIndex >= 0 && currentIndex < currentDirectoryPlaylist.count {
                newIndex = currentIndex
            } else {
                newIndex = 0 // 索引无效时默认为第一首
            }
        case .shuffle:
            // 随机播放模式下，重新生成随机索引
            if shuffleIndices.isEmpty || shuffleIndices.first == nil {
                resetShuffleIndices()
            }
            
            // 安全获取下一个随机索引
            if !shuffleIndices.isEmpty {
                newIndex = shuffleIndices.removeFirst()
                // 确保获取的索引在有效范围内
                if newIndex < 0 || newIndex >= currentDirectoryPlaylist.count {
                    print("[MusicPlayer] 随机索引无效，重置为第一首")
                    newIndex = 0
                }
            } else {
                newIndex = 0 // 安全兜底
            }
        }
        
        // 最终安全检查，确保索引有效后再访问数组
        if newIndex >= 0 && newIndex < currentDirectoryPlaylist.count {
            let music = currentDirectoryPlaylist[newIndex]
            playMusic(music, at: newIndex)
        } else {
            print("[MusicPlayer] 索引超出范围，无法播放下一曲")
            // 重置为第一首
            if !currentDirectoryPlaylist.isEmpty {
                let music = currentDirectoryPlaylist[0]
                playMusic(music, at: 0)
            }
        }
    }
    
    // 切换播放模式
    func togglePlayMode() {
        switch playMode {
        case .sequence:
            playMode = .repeatOne
        case .repeatOne:
            playMode = .shuffle
            resetShuffleIndices()
        case .shuffle:
            playMode = .sequence
        }
        
        // 保存切换后的播放模式
        playMode.save()
        print("[MusicPlayer] 播放模式已切换为: \(playMode)")
    }
    
    // 切换播放范围锁定
    func toggleRangeLock() {
        isRangeLocked.toggle()
        
        // 保存切换后的播放范围锁定状态
        UserDefaults.standard.set(isRangeLocked, forKey: PlayMode.rangeLockKey)
        print("[MusicPlayer] 播放范围锁定状态已保存: \(isRangeLocked)")
        
        // 更新当前目录播放列表
        if isRangeLocked && currentMusic != nil {
            updateCurrentDirectoryPlaylist()
        } else {
            currentDirectoryPlaylist = fullPlaylist
            // 重新计算当前索引
            if let music = currentMusic, let index = fullPlaylist.firstIndex(where: { $0.url == music.url }) {
                currentIndex = index
            }
        }
        
        // 重置随机索引
        resetShuffleIndices()
        
        print("[MusicPlayer] 播放范围锁定状态已切换为: \(isRangeLocked)")
    }
    
    // 重置随机播放索引
    private func resetShuffleIndices() {
        // 安全检查播放列表是否为空
        guard !currentDirectoryPlaylist.isEmpty else {
            print("[MusicPlayer] 播放队列为空，无法重置随机索引")
            shuffleIndices = []
            return
        }
        
        // 生成0到count-1的序列
        shuffleIndices = Array(0..<currentDirectoryPlaylist.count)
        
        // 打乱顺序
        shuffleIndices.shuffle()
        
        // 如果当前有播放的音乐，确保它不在随机列表的第一个位置
        if currentIndex >= 0 && currentIndex < currentDirectoryPlaylist.count && !shuffleIndices.isEmpty {
            // 安全地查找当前索引在shuffleIndices中的位置
            if let currentIndexInShuffle = shuffleIndices.firstIndex(of: currentIndex) {
                // 确保找到的索引有效且不是唯一的元素
                if shuffleIndices.count > 1 {
                    shuffleIndices.remove(at: currentIndexInShuffle)
                }
            }
        }
    }
    
    // 处理播放完成
    // AVAudioPlayerDelegate方法：播放完成时的处理
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if flag {
            // 检查是否启用了范围锁定
            if isRangeLocked {
                // 如果启用了范围锁定，重新播放当前曲目
                if let currentMusicURL = currentMusic?.url {
                    playAudio(currentMusicURL)
                }
            } else {
                // 根据播放模式决定下一首
                switch playMode {
                case .sequence:
                    playNext()
                case .repeatOne:
                    if let currentMusicURL = currentMusic?.url {
                        playAudio(currentMusicURL)
                    }
                case .shuffle:
                    playNext()
                }
            }
        }
    }
    
    // 跳转到指定时间
    func seek(to time: TimeInterval) {
        if !currentDirectoryPlaylist.isEmpty {
            let normalizedTime = max(0, min(time, totalTime))
            audioPlayer?.currentTime = normalizedTime
            currentTime = normalizedTime
            
            // 更新播放进度
            updateNowPlayingInfo()
        }
    }
    
    // 停止播放
    func stop() {
        // 停止播放的实现
        stopAudioComponents()
        
        audioPlayer?.stop()
        
        // 重置状态
        isPlaying = false
        currentTime = 0
        
        // 停止进度更新计时器
        stopProgressTimer()
        
        // 清除现在播放信息
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        
        // 释放安全作用域资源
        clearSecurityScopedResources()
    }
    
    // 停止相关音频组件
    func stopAudioComponents() {
        // 释放AVAudioPlayer
        audioPlayer = nil
        print("[MusicPlayer] 音频播放器已停止")
        
        // 释放访问权限
        clearSecurityScopedResources()
    }
    
    // 清理资源
    deinit {
        print("[MusicPlayer] 开始清理资源")
        
        // 停止进度更新计时器
        stopProgressTimer()
        
        // 释放音频播放器
        audioPlayer = nil
        
        // 尝试停用音频会话
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        print("[MusicPlayer] 音频会话已尝试停用")
        
        // 清除安全作用域资源
        clearSecurityScopedResources()
        
        // 移除所有通知监听
        NotificationCenter.default.removeObserver(self)
        
        print("[MusicPlayer] 资源清理完成")
    }
}

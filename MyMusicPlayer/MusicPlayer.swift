import Foundation
import AVFoundation
import MediaPlayer
import AudioKit

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

class MusicPlayer: NSObject, ObservableObject {
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
    
    // AudioKit相关组件
    private let engine = AudioEngine()
    private let player = AudioPlayer()
    private var fftTap: FFTTap?
   
    
    // 频谱数据回调闭包
    public var spectrumDataCallback: (([Float]) -> Void)? = nil
    
    // 控制是否启用频谱分析计算
    public var isSpectrumAnalysisEnabled: Bool = false
    
    override init() {
        // 从用户数据加载播放范围锁定状态
        isRangeLocked = UserDefaults.standard.bool(forKey: PlayMode.rangeLockKey)
        super.init()
        setupAudioSession()
        setupAudioKit()
        print("[MusicPlayer] 从用户数据加载播放范围锁定状态: \(isRangeLocked)")
    }
    
    // 设置AudioKit
    private func setupAudioKit() {
        // 配置AudioKit引擎和播放器
        engine.output = player
        
        // 设置FFT分析
        setupFFTAnalysis()

        print("[MusicPlayer] AudioKit 初始化成功")
    }
    
    // 设置FFT分析
    internal func setupFFTAnalysis() {
        // 先停止之前可能存在的FFT分析器
        fftTap?.stop()
        fftTap = nil
        
        // 只有在频谱分析已启用时才创建FFT分析器
        if isSpectrumAnalysisEnabled {
            print("[MusicPlayer] 频谱分析已启用，创建FFT分析器")
            
            // 创建FFT分析器
            fftTap = FFTTap(player) { [weak self] fftData in
                guard let self = self else { return }
                
                // 过滤掉NaN和无效值，只保留有效的FFT数据
                let validFFTData = fftData.filter { !$0.isNaN && !$0.isInfinite && $0 >= 0 }
                
                // 只有在频谱分析已启用、有效数据足够多且播放状态为true时才处理和传递数据
                if self.isPlaying && isSpectrumAnalysisEnabled && validFFTData.count > Int(Double(fftData.count) * 0.5) { // 至少80%的数据有效
                    // 限制FFT数据处理和回调频率为每秒1次，降低CPU占用
                    let currentTime = Date().timeIntervalSince1970
                    // 重要！！ 调整为刷新频率，提高视觉流畅度同时保持较低CPU占用
                    if currentTime - self.lastFFTLogTime > 0.06 {
                        // 添加调试信息，检查FFT数据
                        print("[MusicPlayer] FFT数据 - 数量: \(validFFTData.count), 播放状态: \(self.isPlaying)")
                        self.lastFFTLogTime = currentTime
                    
                        // 通过回调传递频谱数据
                        if let callback = self.spectrumDataCallback {
                            DispatchQueue.main.async {
                                callback(validFFTData)
                            }
                        }
                    }
                } else if !self.isPlaying {
                    // 在暂停状态下，如果数据质量差，减少日志输出频率
                    if Date().timeIntervalSince1970 - self.lastFFTLogTime > 2.0 {
                        print("[MusicPlayer] 暂停状态下FFT数据质量差，跳过处理 - 有效数据: \(validFFTData.count)/\(fftData.count)")
                        self.lastFFTLogTime = Date().timeIntervalSince1970
                    }
                }
            }
            
            // 启动FFT分析
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.fftTap?.start()
            }
            print("[MusicPlayer] FFT分析器初始化成功")
        } else {
            print("[MusicPlayer] 频谱分析已禁用，不创建FFT分析器")
        }
    }
    
    // 设置音频会话
    private func setupAudioSession() {
        do {
            // 简化音频会话配置，避免参数错误
            let session = AVAudioSession.sharedInstance()
            
            // 先尝试停用现有的音频会话
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            
            // 确保正确设置类别和模式
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])

            // 延迟激活会话，在实际需要播放时再激活
            // 这样可以避免在应用启动时就占用音频设备
            
            print("[MusicPlayer] 音频会话配置成功")
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
            // 使用相同的安全参数激活音频会话
            let session = AVAudioSession.sharedInstance()
            
            // 直接尝试激活会话，系统会自动处理重复激活的情况
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            print("[MusicPlayer] 音频会话已激活")
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
            
            // 确保引擎已准备好并正确启动
            if !engine.avEngine.isRunning {
                print("[MusicPlayer] 尝试启动AudioEngine")
                try engine.start()
                print("[MusicPlayer] AudioEngine启动成功")
            }
            
            // 使用AudioKit播放器
            try player.load(url: url)
            
            // 再次确认引擎正在运行后再播放
            if engine.avEngine.isRunning {
                player.play()
                isPlaying = true
                totalTime = player.duration
                
                // 重新建立 FFTTap
                fftTap?.stop()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self.fftTap?.start()
                }
                
                // 启动进度更新计时器
                startProgressTimer()
                
                // 立即更新Now Playing信息
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.updateNowPlayingInfo()
                }
            } else {
                throw NSError(domain: "MusicPlayerError", code: -1, userInfo: [NSLocalizedDescriptionKey: "AudioEngine未能启动"])            }
        } catch {
            print("[MusicPlayer] 播放音乐失败: \(error)")
            isPlaying = false
            
            // 如果播放失败，释放访问权限
            if shouldStopAccess {
                url.stopAccessingSecurityScopedResource()
                // 从跟踪列表中移除
                securityScopedResources.removeAll { $0 == url }
            }
        }
    }
    
    // 启动进度更新计时器
    private func startProgressTimer() {
        // 先停止之前的计时器
        stopProgressTimer()
        
        // 创建新的计时器
        progressTimer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(updateProgress), userInfo: nil, repeats: true)
    }
    
    // 停止进度更新计时器
    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }
    
    // 用于限制FFT日志输出频率
    private var lastFFTLogTime: TimeInterval = 0
    
    // 上一次播放时间，用于检测播放是否实际在前进
    private var lastPlayerTime: TimeInterval = -1
    // 连续检测到播放停滞的次数
    private var playbackStallCount: Int = 0
    
    // 更新播放进度
    @objc private func updateProgress() {
        // 获取当前状态
        let engineRunning = engine.avEngine.isRunning
        let playerPlaying = player.isPlaying
        let currentPlayerTime = player.currentTime
        
        // 检测播放是否实际在前进（时间是否更新）
        let isActuallyPlaying = isPlaying && playerPlaying && currentPlayerTime > lastPlayerTime + 0.01
        
        // 播放停滞检测
        if isPlaying && playerPlaying && !isActuallyPlaying {
            playbackStallCount += 1
            print("[播放状态监控] 警告: 检测到播放停滞! 状态显示播放中但时间未前进, 停滞次数: \(playbackStallCount)")
        } else {
            playbackStallCount = 0
        }
        
        print("[播放状态监控] isPlaying: \(isPlaying), player状态: \(playerPlaying ? "播放中" : "已停止"), 引擎状态: \(engineRunning ? "运行中" : "已停止"), 当前时间: \(String(format: "%.2f", currentPlayerTime)), 实际播放: \(isActuallyPlaying ? "是" : "否")")
        
        // 更新时间记录
        lastPlayerTime = currentPlayerTime
        
        // 使用AudioKit播放器的当前时间
        currentTime = currentPlayerTime
        
        updateNowPlayingInfo()
        
        // 检查播放是否完成（当AudioKit播放器到达结尾时）
        if isPlaying && currentPlayerTime >= player.duration && player.duration > 0 {
            handlePlaybackFinished()
        }
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
            MPMediaItemPropertyPlaybackDuration: player.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: player.currentTime,
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
        
        // 可以根据需要添加更多信息，如：
        // - 音频格式信息
        // - 歌词可用性信息
        // - 自定义信息
        
        // 确保在主线程更新控制中心信息
        DispatchQueue.main.async {
            // 复制变量到闭包内部，避免作用域问题
            let localInfo = info
            
            // 直接更新Now Playing信息，不清除旧信息，避免闪烁
            MPNowPlayingInfoCenter.default().nowPlayingInfo = localInfo
            
            // 验证设置后的信息，如有失败则重试
            if MPNowPlayingInfoCenter.default().nowPlayingInfo == nil {
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
            resume()
        }
    }
    
    // 暂停播放
    func pause() {
        // 确保在主线程执行
        DispatchQueue.main.async {
            // 确保音频会话激活
            self.becomeActiveMediaPlayer()
            
            // 暂停播放
            self.player.pause()
            self.isPlaying = false
            
            // 立即更新Now Playing信息
            self.updateNowPlayingInfo()
            
            // 0.5秒后再次更新，确保状态正确同步
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                // 使用weak self避免循环引用
                [weak self] in
                self?.updateNowPlayingInfo()
            }
            
            // 停止进度更新计时器
            self.stopProgressTimer()
            
            // 停止FFT分析，避免暂停后波形图仍在动
            self.fftTap?.stop()
            
            // 发送播放状态变化通知
            NotificationCenter.default.post(name: NSNotification.Name("PlayerStateChanged"), object: nil)
        }
    }
    
    // 恢复播放
    func resume() {
        // 确保在主线程执行
        DispatchQueue.main.async {
            // 使用weak self避免内存泄漏
            [weak self] in
            guard let self = self else { return }
            
            // 确保音频会话激活
            self.becomeActiveMediaPlayer()
            
            // 确保引擎已启动
            do {
                if !self.engine.avEngine.isRunning {
                    print("[MusicPlayer] 恢复播放时尝试启动AudioEngine")
                    try self.engine.start()
                    print("[MusicPlayer] 恢复播放时AudioEngine启动成功")
                }
                
                // 再次确认引擎正在运行后再播放
                if self.engine.avEngine.isRunning {
                    // 开始播放
                    self.player.play()
                    self.isPlaying = true
                    
                    // 立即更新Now Playing信息
                    self.updateNowPlayingInfo()
                    
                    // 0.5秒后再次更新，确保状态正确同步
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        // 使用weak self避免循环引用
                        [weak self] in
                        self?.updateNowPlayingInfo()
                    }
                    
                    // 开始进度更新计时器
                    self.startProgressTimer()
                    
                    // 重新设置并启动FFT分析器
                    if self.isSpectrumAnalysisEnabled {
                        print("[MusicPlayer] 恢复播放时重新设置FFT分析器")
                        self.setupFFTAnalysis()
                    } else {
                        // 如果频谱分析未启用，至少尝试启动现有的FFT分析器
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            self.fftTap?.start()
                        }
                    }
                    
                    // 发送播放状态变化通知
                    NotificationCenter.default.post(name: NSNotification.Name("PlayerStateChanged"), object: nil)
                } else {
                    print("[MusicPlayer] 恢复播放失败: AudioEngine未能启动")
                    self.isPlaying = false
                }
            } catch {
                print("[MusicPlayer] 恢复播放失败: \(error)")
                self.isPlaying = false
            }
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
    private func handlePlaybackFinished() {
        // 当前歌曲播放完成，根据播放模式决定下一首
        if playMode == .repeatOne {
            // 单曲循环，重新播放当前歌曲
            if let currentMusicURL = currentMusic?.url {
                playAudio(currentMusicURL)
            }
        } else {
            // 其他模式，播放下一首
            playNext()
        }
    }
    
    // 跳转到指定时间
    func seek(to time: TimeInterval) {
        // 保存当前播放状态
        let wasPlaying = isPlaying

        // 先停止进度更新计时器，避免在seek过程中更新currentTime
        stopProgressTimer()
        
        // 在执行seek操作前暂时停止FFT分析器，确保状态一致性
        fftTap?.stop()

        // 计算相对偏移量而不是使用绝对时间
        let offset = time - currentTime

        // 使用seek方法跳转位置，传入相对偏移量
        player.seek(time: offset)

        // 明确设置currentTime，确保UI能够立即更新到正确位置
        currentTime = time

        // 如果之前是暂停状态，确保在seek后仍然保持暂停
        if !wasPlaying {
            player.pause()
            isPlaying = false
        } else {
            // 如果正在播放，重新启动进度更新计时器
            startProgressTimer()
        }
        
        // 延迟重新设置FFT分析器，避免频繁操作
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            [weak self] in
            guard let self = self else { return }
            if self.isSpectrumAnalysisEnabled && self.engine.avEngine.isRunning {
                // 只在频谱分析启用且引擎运行时重新设置
                self.setupFFTAnalysis()
            } else {
                // 否则只恢复FFT分析器
                fftTap?.start()
            }
        }
    }
    
    // 停止播放
    func stop() {
        // 停止FFT分析器
        fftTap?.stop()
        
        // 停止播放器
        player.stop()
        
        // 先停止再seek到开始位置
        player.seek(time: -currentTime) // 重置到开始位置
        
        isPlaying = false
        
        // 停止进度更新计时器
        stopProgressTimer()
        
        // 延迟停用音频会话，避免快速操作导致的冲突
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            [weak self] in
            guard let self = self else { return }
            // 尝试停用音频会话，系统会自动处理未激活的情况
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            print("[MusicPlayer] 音频会话已尝试停用")
        }
        
        // 清除当前播放音乐，使播放横幅完全消失
        currentMusic = nil
        currentIndex = -1
        
        // 清空播放信息
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        
        // 发送播放器状态改变通知
        NotificationCenter.default.post(name: NSNotification.Name("PlayerStateChanged"), object: nil)
    }
    
    // 清理资源
    deinit {
        print("[MusicPlayer] 开始清理资源")
        
        // 停止计时器
        stopProgressTimer()
        
        // 清理FFT分析器
        fftTap?.stop()
        fftTap = nil
        
        // 停止播放器和引擎
        player.stop()
        engine.stop()
        
        // 尝试停用音频会话
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        print("[MusicPlayer] 音频会话已尝试停用")
        
        // 清除安全范围资源
        clearSecurityScopedResources()
        
        // 清空播放信息
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        
        print("[MusicPlayer] 资源清理完成")
    }
}

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
            
            // 创建FFT分析器，使用固定的bufferSize以获得更稳定的频谱数据
            fftTap = FFTTap(player, bufferSize: 1024) { [weak self] fftData in
                guard let self = self else { return }
                
                // 过滤掉NaN和无效值，只保留有效的FFT数据
                let validFFTData = fftData.filter { !$0.isNaN && !$0.isInfinite && $0 >= 0 }
                
                // 只有在频谱分析已启用、有效数据足够多且播放状态为true时才处理和传递数据
                if isSpectrumAnalysisEnabled && validFFTData.count > Int(Double(fftData.count) * 0.8) { // 至少80%的数据有效
                    // 添加调试信息，检查FFT数据
                    let maxValue = validFFTData.max() ?? 0
                    let avgValue = validFFTData.reduce(0, +) / Float(validFFTData.count)
                    print("[MusicPlayer] FFT数据 - 数量: \(validFFTData.count), 最大值: \(maxValue), 平均值: \(avgValue), 播放状态: \(self.isPlaying)")
                    
                    // 通过回调传递频谱数据
                    if let callback = self.spectrumDataCallback {
                        DispatchQueue.main.async {
                            callback(validFFTData)
                        }
                    }
                } else if !self.isPlaying {
                    // 在暂停状态下，如果数据质量差，减少日志输出频率
                    if Date().timeIntervalSince1970 - self.lastFFTLogTime > 1.0 {
                        print("[MusicPlayer] 暂停状态下FFT数据质量差，跳过处理 - 有效数据: \(validFFTData.count)/\(fftData.count)")
                        self.lastFFTLogTime = Date().timeIntervalSince1970
                    }
                }
            }
            
            // 启动FFT分析
            fftTap?.start()
            print("[MusicPlayer] FFT分析器初始化成功，使用bufferSize: 1024")
        } else {
            print("[MusicPlayer] 频谱分析已禁用，不创建FFT分析器")
        }
    }
    
    // 设置音频会话
    private func setupAudioSession() {
        do {
            // 简化音频会话配置，避免参数错误
            let session = AVAudioSession.sharedInstance()
            
            // 确保正确设置类别和模式
            try session.setCategory(.playback, mode: .default, options: [])

            // // 设置目标刷新速率 ≈ 60Hz
            // try? AVAudioSession.sharedInstance().setPreferredIOBufferDuration(1.0 / 60.0)
            
            // 使用options参数安全激活会话，避免系统音频设备冲突
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            
            print("[MusicPlayer] 音频会话设置成功")
        } catch {
            print("[MusicPlayer] 音频会话设置失败: \(error)")
            // 错误2003332927通常表示Core Audio设备属性访问问题，记录详细信息便于调试
            print("[MusicPlayer] 注意：如出现AQMEIO_HAL相关错误，通常是系统音频设备问题而非应用代码错误")
        }
    }
    
    // 确保应用成为活动的媒体播放器
    private func becomeActiveMediaPlayer() {
        do {
            // 使用相同的安全参数激活音频会话
            let session = AVAudioSession.sharedInstance()
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            print("[MusicPlayer] 尝试让应用成为活动媒体播放器")
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
            // 统一使用安全的音频会话配置参数
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            
            // 停止AudioKit播放器
            player.stop()
            
            // 先停止FFT分析器，确保干净的状态切换
            fftTap?.stop()
            
            // 使用AudioKit播放器
            try engine.start()
            try player.load(url: url)
            player.play()
            
            isPlaying = true
            totalTime = player.duration
            
            // 确保应用成为活动的媒体播放器
            becomeActiveMediaPlayer()
            
            // 启动进度更新计时器
            startProgressTimer()
            
            // 在加载新音频后重新启动FFT分析器，确保正确连接到新的音频源
            fftTap?.start()
            
            // 立即更新Now Playing信息
            DispatchQueue.main.async { [weak self] in
                self?.updateNowPlayingInfo()
                // 更新最后更新时间，避免短时间内重复更新
                self?.lastNowPlayingUpdateTime = Date().timeIntervalSince1970
            }
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
        progressTimer = Timer.scheduledTimer(timeInterval: 0.1, target: self, selector: #selector(updateProgress), userInfo: nil, repeats: true)
    }
    
    // 停止进度更新计时器
    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }
    
    // 用于跟踪上一次更新Now Playing信息的时间
    private var lastNowPlayingUpdateTime: TimeInterval = 0
    
    // 用于限制FFT日志输出频率
    private var lastFFTLogTime: TimeInterval = 0
    
    // 更新播放进度
    @objc private func updateProgress() {
        // 添加调试打印

        
        // 使用AudioKit播放器的当前时间
        currentTime = player.currentTime

        
        // 降低Now Playing信息更新频率，每3秒更新一次
        let currentTime = Date().timeIntervalSince1970
        if currentTime - lastNowPlayingUpdateTime >= 3.0 {
            updateNowPlayingInfo()
            lastNowPlayingUpdateTime = currentTime
        }
        
        // 检查播放是否完成（当AudioKit播放器到达结尾时）
        if isPlaying && player.currentTime >= player.duration && player.duration > 0 {
            handlePlaybackFinished()
        }
    }
    
    // 更新控制中心显示信息
    func updateNowPlayingInfo() {
        // 先检查是否有正在播放的音乐
        guard let currentMusic = currentMusic else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        
        // 创建基本的Now Playing信息字典（只包含必需字段）
        let info: [String: Any] = [
            MPMediaItemPropertyTitle: currentMusic.title.isEmpty ? "未知标题" : currentMusic.title,
            MPMediaItemPropertyArtist: currentMusic.artist.isEmpty ? "未知艺术家" : currentMusic.artist,
            MPMediaItemPropertyPlaybackDuration: player.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: player.currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        
        // 直接设置Now Playing信息
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        
        // 简化的诊断日志
//        print("🔊 [MusicPlayer] Now Playing信息已更新: 标题='\(info[MPMediaItemPropertyTitle]!)', 艺术家='\(info[MPMediaItemPropertyArtist]!)'")
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
        player.pause() // 使用pause()而不是stop()来保留播放位置
        isPlaying = false
        stopProgressTimer()
        
        // 停止FFT分析，避免暂停后波形图仍在动
        fftTap?.stop()
        print("[MusicPlayer] 已停止FFT分析")
        
        // 在主线程上更新Now Playing信息和发送状态改变通知
        DispatchQueue.main.async { [weak self] in
            self?.updateNowPlayingInfo()
            print("[MusicPlayer] 已暂停播放并更新Now Playing信息")
            
            // 发送播放器状态改变通知，确保UI组件能响应状态变化
            NotificationCenter.default.post(name: NSNotification.Name("PlayerStateChanged"), object: nil)
        }
    }
    
    // 恢复播放
    func resume() {
        // 确保音频会话处于活动状态
        becomeActiveMediaPlayer()
        
        player.play() // 只使用AudioKit播放器恢复播放
        isPlaying = true
        startProgressTimer()
        
        // 重新启动FFT分析
        fftTap?.start()
        print("[MusicPlayer] 已重新启动FFT分析")
        
        // 在主线程上更新Now Playing信息和发送状态改变通知
        DispatchQueue.main.async { [weak self] in
            self?.updateNowPlayingInfo()
            
            // 添加延迟再次更新，确保信息正确显示
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { 
                self?.updateNowPlayingInfo()
            }
            
            print("[MusicPlayer] 已恢复播放并更新Now Playing信息")
            
            // 发送播放器状态改变通知，确保UI组件能响应状态变化
            NotificationCenter.default.post(name: NSNotification.Name("PlayerStateChanged"), object: nil)
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
        // 添加调试打印

        
        // 保存当前播放状态
        let wasPlaying = isPlaying


        // 先停止进度更新计时器，避免在seek过程中更新currentTime
        stopProgressTimer()
        
        // 在执行seek操作前暂时停止FFT分析器，确保状态一致性
        fftTap?.stop()

        // 计算相对偏移量而不是使用绝对时间
        // 从调试日志中发现，player.seek(time: time)实际上是添加偏移量而不是设置绝对位置
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
        
        // 无论原状态如何，都完全重新设置FFT分析器
    // 这样在暂停状态下拖动进度条后再播放时，FFT分析器能够正确连接到新的音频位置
    DispatchQueue.main.async {
        print("[MusicPlayer] 在seek后立即重新设置FFT分析器")
        self.setupFFTAnalysis() // 完全重新设置FFT分析器
    }
    }
    
    // 停止播放
    func stop() {
        player.stop()
        // 先停止再seek到开始位置
        player.seek(time: 0)
        isPlaying = false
        
        // 清除当前播放音乐，使播放横幅完全消失
        currentMusic = nil
        currentIndex = -1
        
        stopProgressTimer()
        
        // 清空播放信息
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        
        // 发送播放器状态改变通知
        NotificationCenter.default.post(name: NSNotification.Name("PlayerStateChanged"), object: nil)
    }
    
    // 清理资源
    deinit {
        stopProgressTimer()
        clearSecurityScopedResources()
        
        // 清理AudioKit资源
        fftTap?.stop()
        fftTap = nil
        player.stop()
        engine.stop()
        
        // 清空播放信息
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
}

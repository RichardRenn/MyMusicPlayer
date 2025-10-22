import Foundation
import AVFoundation

// 基础类型定义
struct LyricsLine {
    let time: TimeInterval
    let text: String
    
    init(time: TimeInterval, text: String) {
        self.time = time
        self.text = text
    }
}

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
enum PlayMode {
    case sequence // 顺序播放
    case repeatOne // 单曲循环
    case shuffle // 随机播放
}

class MusicPlayer: NSObject, AVAudioPlayerDelegate, ObservableObject {
    // 单例模式
    static let shared = MusicPlayer()
    
    // 当前播放的音频播放器
    private var audioPlayer: AVAudioPlayer?
    
    // 播放列表和当前状态
    @Published var currentMusic: MusicItem?
    @Published var isPlaying: Bool = false
    @Published var currentTime: TimeInterval = 0
    @Published var totalTime: TimeInterval = 0
    @Published var playMode: PlayMode = .sequence
    @Published var isRangeLocked: Bool = false // 是否锁定播放范围在当前目录
    
    // 完整播放列表和当前目录播放列表
    private var fullPlaylist: [MusicItem] = []
    private var currentDirectoryPlaylist: [MusicItem] = []
    private var currentIndex: Int = -1
    private var shuffleIndices: [Int] = []
    
    // 计时器用于更新播放进度
    private var progressTimer: Timer?
    
    override init() {
        super.init()
        setupAudioSession()
    }
    
    // 设置音频会话
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("设置音频会话失败: \(error)")
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
        currentMusic = music
        currentIndex = index
        
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
        playAudio(music.url)
        
        // 发送播放器状态改变通知，让所有监听的视图控制器更新UI
        NotificationCenter.default.post(name: NSNotification.Name("PlayerStateChanged"), object: nil)
    }
    
    // 更新当前目录播放列表
    private func updateCurrentDirectoryPlaylist() {
        guard let currentMusic = currentMusic else { return }
        currentDirectoryPlaylist = fullPlaylist.filter { $0.parentDirectory == currentMusic.parentDirectory }
        
        // 重新计算当前索引
        if let newIndex = currentDirectoryPlaylist.firstIndex(where: { $0.url == currentMusic.url }) {
            currentIndex = newIndex
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
            print("成功获取音频文件访问权限: \(url.lastPathComponent)")
        }
        
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            
            isPlaying = true
            totalTime = audioPlayer?.duration ?? 0
            
            // 启动进度更新计时器
            startProgressTimer()
        } catch {
            print("播放音乐失败: \(error)")
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
    
    // 更新播放进度
    @objc private func updateProgress() {
        currentTime = audioPlayer?.currentTime ?? 0
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
        audioPlayer?.pause()
        isPlaying = false
        stopProgressTimer()
    }
    
    // 恢复播放
    func resume() {
        audioPlayer?.play()
        isPlaying = true
        startProgressTimer()
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
        guard !currentDirectoryPlaylist.isEmpty else { return }
        
        var newIndex: Int
        
        switch playMode {
        case .sequence:
            newIndex = currentIndex + 1
            if newIndex >= currentDirectoryPlaylist.count {
                newIndex = 0
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
    }
    
    // 切换播放范围锁定
    func toggleRangeLock() {
        isRangeLocked.toggle()
        
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
    }
    
    // 重置随机播放索引
    private func resetShuffleIndices() {
        shuffleIndices = Array(0..<currentDirectoryPlaylist.count)
        shuffleIndices.shuffle()
        
        // 如果当前有播放的音乐，确保它不在随机列表的第一个位置
        if currentIndex >= 0 && !shuffleIndices.isEmpty {
            if let currentIndexInShuffle = shuffleIndices.firstIndex(of: currentIndex) {
                shuffleIndices.remove(at: currentIndexInShuffle)
            }
        }
    }
    
    // AVAudioPlayerDelegate 方法
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if flag {
            // 当前歌曲播放完成，根据播放模式决定下一首
            if playMode == .repeatOne {
                // 单曲循环，重新播放当前歌曲
                playAudio(currentMusic!.url)
            } else {
                // 其他模式，播放下一首
                playNext()
            }
        }
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        if let err = error {
            print("音频解码错误: \(err.localizedDescription)")
        } else {
            print("音频解码错误: 未知错误")
        }
        isPlaying = false
    }
    
    // 跳转到指定时间
    func seek(to time: TimeInterval) {
        audioPlayer?.currentTime = time
        currentTime = time
    }
    
    // 清理资源
    deinit {
        stopProgressTimer()
        clearSecurityScopedResources()
        audioPlayer?.stop()
        audioPlayer = nil
    }
}
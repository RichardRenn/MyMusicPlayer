import Foundation

// 音乐文件模型
class MusicItem {
    let url: URL
    let title: String
    let artist: String?
    let album: String?
    let duration: TimeInterval
    let parentDirectory: URL
    let lyricsURL: URL?
    var lyrics: [LyricsLine]?
    
    init(url: URL, title: String, artist: String? = nil, album: String? = nil, duration: TimeInterval = 0, parentDirectory: URL, lyricsURL: URL? = nil) {
        self.url = url
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.parentDirectory = parentDirectory
        self.lyricsURL = lyricsURL
    }
    
    // 从文件名中提取标题
    convenience init(url: URL, parentDirectory: URL) {
        let fileName = url.deletingPathExtension().lastPathComponent
        self.init(url: url, title: fileName, parentDirectory: parentDirectory)
        
        // 检查是否有对应的lrc文件
        let lyricsURL = url.deletingPathExtension().appendingPathExtension("lrc")
        if FileManager.default.fileExists(atPath: lyricsURL.path) {
            self.lyricsURL = lyricsURL
        }
    }
}

// 歌词行模型
struct LyricsLine {
    let time: TimeInterval
    let text: String
    
    init(time: TimeInterval, text: String) {
        self.time = time
        self.text = text
    }
}

// 目录项模型（用于树状结构显示）
class DirectoryItem {
    let url: URL
    let name: String
    var subdirectories: [DirectoryItem] = []
    var musicFiles: [MusicItem] = []
    var isExpanded: Bool = false
    
    init(url: URL, name: String) {
        self.url = url
        self.name = name
    }
    
    // 添加子目录
    func addSubdirectory(_ directory: DirectoryItem) {
        subdirectories.append(directory)
    }
    
    // 添加音乐文件
    func addMusicFile(_ musicFile: MusicItem) {
        musicFiles.append(musicFile)
    }
}
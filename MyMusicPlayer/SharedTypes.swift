import Foundation
import AVFoundation

// 歌词行结构体
struct LyricsLine {
    let time: TimeInterval
    let text: String
    
    init(time: TimeInterval, text: String) {
        self.time = time
        self.text = text
    }
}

// 目录项类
class DirectoryItem {
    let url: URL
    let name: String
    weak var parentDirectory: DirectoryItem?
    var subdirectories: [DirectoryItem] = []
    var musicFiles: [MusicItem] = []
    
    init(url: URL, name: String) {
        self.url = url
        self.name = name
    }
    
    func addSubdirectory(_ directory: DirectoryItem) {
        directory.parentDirectory = self
        subdirectories.append(directory)
    }
    
    func addMusicFile(_ musicFile: MusicItem) {
        musicFile.parentDirectory = self
        musicFiles.append(musicFile)
    }
}

// 音乐项类
class MusicItem {
    let url: URL
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval
    weak var parentDirectory: DirectoryItem?
    var lyricsURL: URL?
    var lyrics: [LyricsLine] = []
    
    // 适配MusicScanner的初始化方法
    init(url: URL, parentDirectory: URL) {
        self.url = url
        self.title = url.lastPathComponent
        self.artist = "Unknown Artist"
        self.album = "Unknown Album"
        self.duration = 0
    }
    
    // 适配MusicPlayer的初始化方法
    init(title: String, artist: String, album: String, duration: TimeInterval, filePath: String) {
        self.url = URL(fileURLWithPath: filePath)
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
    }
    
    // 简化的初始化方法
    init(url: URL) {
        self.url = url
        self.title = url.lastPathComponent
        self.artist = "Unknown Artist"
        self.album = "Unknown Album"
        self.duration = 0
    }
}
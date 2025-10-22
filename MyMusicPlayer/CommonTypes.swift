import Foundation
import AVFoundation

// 歌词行结构体
struct LyricsLine {
    var time: TimeInterval
    var text: String
    
    init(time: TimeInterval, text: String) {
        self.time = time
        self.text = text
    }
}

// 目录项目类
class DirectoryItem {
    var url: URL
    var name: String
    weak var parentDirectory: DirectoryItem?
    var subdirectories: [DirectoryItem] = []
    var musicFiles: [MusicItem] = []
    
    // 适配MusicScanner使用的初始化方法
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

// 音乐项目类
class MusicItem {
    var url: URL
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval
    weak var parentDirectory: DirectoryItem?
    var lyricsURL: URL?
    var lyrics: [LyricsLine] = []
    
    // 适配MusicScanner使用的初始化方法
    init(url: URL, parentDirectory: URL) {
        self.url = url
        self.title = url.lastPathComponent
        self.artist = "Unknown Artist"
        self.album = "Unknown Album"
        self.duration = 0
    }
    
    init(url: URL, title: String, artist: String, album: String, duration: TimeInterval) {
        self.url = url
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
    }
}
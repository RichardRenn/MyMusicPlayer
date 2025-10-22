import Foundation
import AVFoundation

// 基础类型定义
public struct LyricsLine {
    public let time: TimeInterval
    public let text: String
    
    public init(time: TimeInterval, text: String) {
        self.time = time
        self.text = text
    }
}

public class DirectoryItem {
    public let url: URL
    public let name: String
    public weak var parentDirectory: DirectoryItem?
    public var subdirectories: [DirectoryItem] = []
    public var musicFiles: [MusicItem] = []
    
    public init(url: URL, name: String) {
        self.url = url
        self.name = name
    }
}

public class MusicItem {
    public let url: URL
    public var title: String
    public var artist: String
    public var album: String
    public var duration: TimeInterval
    public weak var parentDirectory: DirectoryItem?
    public var lyricsURL: URL?
    public var lyrics: [LyricsLine] = []
    
    public init(url: URL) {
        self.url = url
        self.title = url.lastPathComponent
        self.artist = "Unknown Artist"
        self.album = "Unknown Album"
        self.duration = 0
    }
    
    public init(title: String, artist: String, album: String, duration: TimeInterval, filePath: String) {
        self.url = URL(fileURLWithPath: filePath)
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
    }
}
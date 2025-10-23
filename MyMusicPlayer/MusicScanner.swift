import Foundation
import AVFoundation

class MusicScanner {
    let fileManager = FileManager.default
    
    // 扫描目录
    func scanDirectory(_ url: URL, progressHandler: @escaping (Double) -> Void, completionHandler: @escaping (DirectoryItem?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            // 检查URL是否需要访问权限
            var hasAccess = true
            var shouldStopAccess = false
            
            // 如果URL是安全范围的资源，尝试请求访问权限
            if url.startAccessingSecurityScopedResource() {
                shouldStopAccess = true
                hasAccess = true
                print("成功获取目录访问权限: \(url.lastPathComponent)")
            }
            
            let directoryName = url.lastPathComponent
            let directoryItem = DirectoryItem(name: directoryName, url: url)
            
            // 先发送初始进度
            DispatchQueue.main.async {
                progressHandler(0.0)
            }
            
            // 只有在有权限的情况下才扫描
            if hasAccess {
                // 首先预扫描计算文件总数
                var totalFilesCount = 0
                var processedFilesCount = 0
                
                // 预扫描函数
                func countFilesInDirectory(_ directoryURL: URL) -> Int {
                    var count = 0
                    
                    do {
                        var shouldStopItemAccess = false
                        if directoryURL.startAccessingSecurityScopedResource() {
                            shouldStopItemAccess = true
                        }
                        
                        defer {
                            if shouldStopItemAccess {
                                directoryURL.stopAccessingSecurityScopedResource()
                            }
                        }
                        
                        let contents = try self.fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
                        
                        for itemURL in contents {
                            var isDir: ObjCBool = false
                            if self.fileManager.fileExists(atPath: itemURL.path, isDirectory: &isDir) {
                                if isDir.boolValue {
                                    count += countFilesInDirectory(itemURL)
                                } else {
                                    count += 1
                                }
                            }
                        }
                    } catch {
                        print("预扫描目录失败: \(directoryURL.lastPathComponent), 原因: \(error.localizedDescription)")
                    }
                    
                    return count
                }
                
                // 计算总文件数
                totalFilesCount = countFilesInDirectory(url)
                
                // 实际扫描并更新进度
                func scanWithProgress(_ url: URL, parentItem: DirectoryItem) {
                    var shouldStopItemAccess = false
                    if url.startAccessingSecurityScopedResource() {
                        shouldStopItemAccess = true
                    }
                    
                    do {
                        let contents = try self.fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
                        
                        for itemURL in contents {
                            do {
                                var itemShouldStopAccess = false
                                if itemURL.startAccessingSecurityScopedResource() {
                                    itemShouldStopAccess = true
                                }
                                
                                var isDirectory: ObjCBool = false
                                if self.fileManager.fileExists(atPath: itemURL.path, isDirectory: &isDirectory) {
                                    if isDirectory.boolValue {
                                        // 是目录，创建DirectoryItem并递归扫描
                                        let subdirectoryItem = DirectoryItem(name: itemURL.lastPathComponent, url: itemURL)
                                        subdirectoryItem.parentDirectory = parentItem
                                        parentItem.subdirectories.append(subdirectoryItem)
                                        scanWithProgress(itemURL, parentItem: subdirectoryItem)
                                    } else if self.isAudioFile(itemURL) {
                                        // 是音频文件，创建MusicItem并读取元数据
                                        let musicItem = MusicItem(url: itemURL)
                                        musicItem.parentDirectory = parentItem
                                        
                                        // 读取音频文件元数据
                                        self.readAudioMetadata(for: itemURL, into: musicItem)
                                        
                                        // 查找同名歌词文件
                                        if let lyricsURL = self.findLyricsFile(for: itemURL) {
                                            musicItem.lyricsURL = lyricsURL
                                        }
                                        
                                        parentItem.musicFiles.append(musicItem)
                                    }
                                }
                                
                                // 释放项目的访问权限
                                if itemShouldStopAccess {
                                    itemURL.stopAccessingSecurityScopedResource()
                                }
                                
                                // 更新处理的文件数和进度
                                processedFilesCount += 1
                                if totalFilesCount > 0 {
                                    // 确保进度不会超过1.0 (100%)
                                    let progress = min(Double(processedFilesCount) / Double(totalFilesCount), 1.0)
                                    DispatchQueue.main.async {
                                        progressHandler(progress)
                                    }
                                }
                            } catch {
                                // 跳过无法访问的文件或目录，但继续处理其他项目
                                print("无法访问项目: \(itemURL.lastPathComponent), 原因: \(error.localizedDescription)")
                                
                                // 即使出错也计数，避免进度卡住
                                processedFilesCount += 1
                                if totalFilesCount > 0 {
                                    // 确保进度不会超过1.0 (100%)
                                    let progress = min(Double(processedFilesCount) / Double(totalFilesCount), 1.0)
                                    DispatchQueue.main.async {
                                        progressHandler(progress)
                                    }
                                }
                            }
                        }
                    } catch {
                        // 记录错误但不抛出，允许扫描继续处理已访问的部分
                        print("扫描子目录失败: \(url.lastPathComponent), 原因: \(error.localizedDescription)")
                    }
                    
                    // 释放目录的访问权限
                    if shouldStopItemAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                
                // 执行带进度的扫描
                scanWithProgress(url, parentItem: directoryItem)
            } else {
                print("无法获取目录访问权限: \(url.lastPathComponent)")
            }
            
            // 释放安全范围资源的访问权限
            if shouldStopAccess {
                url.stopAccessingSecurityScopedResource()
            }
            
            // 确保最终进度为100%
            DispatchQueue.main.async {
                progressHandler(1.0)
                // 检查是否找到任何音乐文件或子目录，如果没有，则返回nil表示扫描无效
                if directoryItem.musicFiles.isEmpty && directoryItem.subdirectories.isEmpty {
                    print("未在目录中找到任何音乐文件或子目录")
                    completionHandler(nil)
                } else {
                    completionHandler(directoryItem)
                }
            }
        }
    }
    
    // 递归扫描子目录
    private func scanSubdirectory(_ url: URL, parentItem: DirectoryItem) {
        // 尝试获取子目录的访问权限
        var shouldStopAccess = false
        
        // 如果URL是安全范围的资源，尝试请求访问权限
        if url.startAccessingSecurityScopedResource() {
            shouldStopAccess = true
            print("成功获取子目录访问权限: \(url.lastPathComponent)")
        }
        
        do {
            let contents = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            
            for itemURL in contents {
                do {
                    // 尝试对每个项目单独请求访问权限
                    var itemShouldStopAccess = false
                    if itemURL.startAccessingSecurityScopedResource() {
                        itemShouldStopAccess = true
                    }
                    
                    var isDirectory: ObjCBool = false
                    if fileManager.fileExists(atPath: itemURL.path, isDirectory: &isDirectory) {
                        if isDirectory.boolValue {
                            // 是目录，创建DirectoryItem并递归扫描
                            let directoryItem = DirectoryItem(name: itemURL.lastPathComponent, url: itemURL)
                            directoryItem.parentDirectory = parentItem
                            parentItem.subdirectories.append(directoryItem)
                            // 递归扫描子目录，但不抛出错误，而是继续处理其他目录
                            scanSubdirectory(itemURL, parentItem: directoryItem)
                        } else if isAudioFile(itemURL) {
                            // 是音频文件，创建MusicItem并读取元数据
                            let musicItem = MusicItem(url: itemURL)
                            musicItem.parentDirectory = parentItem
                            
                            // 读取音频文件元数据
                            readAudioMetadata(for: itemURL, into: musicItem)
                            
                            // 查找同名歌词文件
                            if let lyricsURL = findLyricsFile(for: itemURL) {
                                musicItem.lyricsURL = lyricsURL
                                print("找到歌词文件: \(lyricsURL.lastPathComponent)")
                            }
                            
                            parentItem.musicFiles.append(musicItem)
                        }
                    }
                    
                    // 释放项目的访问权限
                    if itemShouldStopAccess {
                        itemURL.stopAccessingSecurityScopedResource()
                    }
                } catch {
                    // 跳过无法访问的文件或目录，但继续处理其他项目
                    print("无法访问项目: \(itemURL.lastPathComponent), 原因: \(error.localizedDescription)")
                }
            }
        } catch {
            // 记录错误但不抛出，允许扫描继续处理已访问的部分
            print("扫描子目录失败: \(url.lastPathComponent), 原因: \(error.localizedDescription)")
        }
        
        // 释放目录的访问权限
        if shouldStopAccess {
            url.stopAccessingSecurityScopedResource()
        }
    }
    
    // 检查是否为音频文件
    private func isAudioFile(_ url: URL) -> Bool {
        let audioExtensions = ["mp3", "m4a", "wav", "aac"]
        let fileExtension = url.pathExtension.lowercased()
        return audioExtensions.contains(fileExtension)
    }
    
    // 检查是否为歌词文件
    private func isLyricsFile(_ url: URL) -> Bool {
        let fileExtension = url.pathExtension.lowercased()
        return fileExtension == "lrc"
    }
    
    // 查找同名歌词文件
    private func findLyricsFile(for audioURL: URL) -> URL? {
        let directory = audioURL.deletingLastPathComponent()
        let filenameWithoutExtension = audioURL.deletingPathExtension().lastPathComponent
        let lyricsURL = directory.appendingPathComponent(filenameWithoutExtension + ".lrc")
        
        // 尝试多种可能的文件名格式（处理可能的空格、连字符等差异）
        let possibleLyricsFilenames = [
            filenameWithoutExtension + ".lrc",
            filenameWithoutExtension.trimmingCharacters(in: .whitespaces) + ".lrc"
        ]
        
        for filename in possibleLyricsFilenames {
            let possibleURL = directory.appendingPathComponent(filename)
            
            // 尝试获取访问权限
            var shouldStopAccess = false
            let hasAccess = possibleURL.startAccessingSecurityScopedResource()
            
            if hasAccess {
                shouldStopAccess = true
            }
            
            let fileExists = fileManager.fileExists(atPath: possibleURL.path)
            
            // 释放访问权限
            if shouldStopAccess {
                possibleURL.stopAccessingSecurityScopedResource()
            }
            
            if fileExists {
                print("找到歌词文件: \(possibleURL.lastPathComponent)")
                return possibleURL
            }
        }
        
        // 尝试使用文件管理器的目录内容方法查找
        do {
            // 尝试获取目录访问权限
            var shouldStopAccess = false
            if directory.startAccessingSecurityScopedResource() {
                shouldStopAccess = true
            }
            
            defer { // 确保在退出作用域时释放权限
                if shouldStopAccess {
                    directory.stopAccessingSecurityScopedResource()
                }
            }
            
            // 获取目录内容
            let contents = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            
            // 查找匹配的lrc文件（忽略大小写和扩展名差异）
            let baseName = filenameWithoutExtension.lowercased()
            for fileURL in contents where fileURL.pathExtension.lowercased() == "lrc" {
                let fileBaseName = fileURL.deletingPathExtension().lastPathComponent.lowercased()
                
                // 如果文件名（不包括扩展名）相同或包含歌曲名，认为是匹配的歌词文件
                if fileBaseName == baseName || fileBaseName.contains(baseName) {
                    print("通过模糊匹配找到歌词文件: \(fileURL.lastPathComponent) 对应歌曲: \(filenameWithoutExtension)")
                    return fileURL
                }
            }
        } catch {
            print("扫描目录查找歌词文件时出错: \(error.localizedDescription)")
        }
        
        return nil
    }
    
    // 读取音频文件元数据
    private func readAudioMetadata(for url: URL, into musicItem: MusicItem) {
        do {
            // 使用AVURLAsset读取音频文件元数据
            let asset = AVURLAsset(url: url)
            
            // 等待元数据加载完成
            let keys = ["commonMetadata", "duration"]
            let semaphore = DispatchSemaphore(value: 0)
            var metadataLoaded = false
            
            asset.loadValuesAsynchronously(forKeys: keys) { [weak self] in
                defer {
                    semaphore.signal()
                }
                
                do {
                    // 获取持续时间
                    try asset.statusOfValue(forKey: "duration", error: nil)
                    musicItem.duration = asset.duration.seconds
                    
                    // 读取元数据
                    for metadataItem in asset.commonMetadata {
                        if let key = metadataItem.commonKey {
                            switch key {
                            case AVMetadataKey.commonKeyTitle:
                                if let title = metadataItem.value as? String,
                                   !title.isEmpty {
                                    musicItem.title = title
                                }
                            case AVMetadataKey.commonKeyArtist:
                                if let artist = metadataItem.value as? String,
                                   !artist.isEmpty {
                                    musicItem.artist = artist
                                }
                            case AVMetadataKey.commonKeyAlbumName:
                                if let album = metadataItem.value as? String,
                                   !album.isEmpty {
                                    musicItem.album = album
                                }
                            default:
                                break
                            }
                        }
                    }
                    
                    metadataLoaded = true
                } catch {
                    print("读取音频元数据失败: \(error.localizedDescription)")
                }
            }
            
            // 最多等待1秒获取元数据
            _ = semaphore.wait(timeout: .now() + 1)
            
            if metadataLoaded {
                print("成功读取音频元数据: 标题='\(musicItem.title)', 艺术家='\(musicItem.artist)', 专辑='\(musicItem.album)'")
            } else {
                // 如果无法获取元数据，尝试从文件名解析标题和艺术家
                parseTitleArtistFromFilename(url.lastPathComponent, into: musicItem)
            }
        } catch {
            print("创建音频资产失败: \(error.localizedDescription)")
            // 尝试从文件名解析
            parseTitleArtistFromFilename(url.lastPathComponent, into: musicItem)
        }
    }
    
    // 从文件名解析标题和艺术家
    private func parseTitleArtistFromFilename(_ filename: String, into musicItem: MusicItem) {
        // 移除文件扩展名
        let nameWithoutExtension = filename.components(separatedBy: ".").dropLast().joined(separator: ".")
        
        // 尝试多种常见格式解析："艺术家 - 标题" 或 "标题 - 艺术家"
        let patterns = [
            #"(.+?)\s*[-\u{2013}\u{2014}]\s*(.+?)"#,
            #"(.+?)\s*[‐‑‒–—―]\s*(.+?)"#
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: nameWithoutExtension, options: [], range: NSRange(location: 0, length: nameWithoutExtension.utf16.count)) {
                
                // 提取匹配的两个部分
                let part1Range = Range(match.range(at: 1), in: nameWithoutExtension)!
                let part2Range = Range(match.range(at: 2), in: nameWithoutExtension)!
                
                let part1 = String(nameWithoutExtension[part1Range]).trimmingCharacters(in: .whitespaces)
                let part2 = String(nameWithoutExtension[part2Range]).trimmingCharacters(in: .whitespaces)
                
                // 通常较短的字符串更可能是艺术家名
                if part1.count <= part2.count {
                    musicItem.artist = part1
                    musicItem.title = part2
                } else {
                    musicItem.artist = part2
                    musicItem.title = part1
                }
                
                print("从文件名解析元数据: 标题='\(musicItem.title)', 艺术家='\(musicItem.artist)'")
                return
            }
        }
        
        // 如果没有匹配任何格式，就使用整个文件名作为标题
        musicItem.title = nameWithoutExtension
        print("使用默认文件名作为标题: '\(musicItem.title)'")
    }
    
    // 获取所有音乐文件（递归）
    func getAllMusicFiles(from directoryItem: DirectoryItem) -> [MusicItem] {
        var allMusicFiles: [MusicItem] = []
        
        // 添加当前目录的音乐文件
        allMusicFiles.append(contentsOf: directoryItem.musicFiles)
        
        // 递归获取子目录的音乐文件
        for subdirectory in directoryItem.subdirectories {
            allMusicFiles.append(contentsOf: getAllMusicFiles(from: subdirectory))
        }
        
        return allMusicFiles
    }
}
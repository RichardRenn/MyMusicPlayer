import Foundation

class MusicScanner {
    let fileManager = FileManager.default
    var rootDirectoryItem: DirectoryItem?
    var progressHandler: ((Double) -> Void)?
    var completionHandler: ((DirectoryItem?) -> Void)?
    
    // 开始扫描指定目录
    func scanDirectory(_ url: URL, progressHandler: @escaping (Double) -> Void, completionHandler: @escaping (DirectoryItem?) -> Void) {
        self.progressHandler = progressHandler
        self.completionHandler = completionHandler
        
        // 创建根目录项
        rootDirectoryItem = DirectoryItem(url: url, name: url.lastPathComponent)
        
        // 异步执行扫描
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try self.scanSubdirectory(url, parentItem: self.rootDirectoryItem!)
                
                DispatchQueue.main.async {
                    progressHandler(1.0) // 扫描完成，进度100%
                    completionHandler(self.rootDirectoryItem)
                }
            } catch {
                DispatchQueue.main.async {
                    completionHandler(nil)
                }
            }
        }
    }
    
    // 递归扫描子目录
    private func scanSubdirectory(_ url: URL, parentItem: DirectoryItem) throws {
        let contents = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)
        
        for itemURL in contents {
            let resourceValues = try itemURL.resourceValues(forKeys: [.isDirectoryKey])
            let isDirectory = resourceValues.isDirectory ?? false
            
            if isDirectory {
                // 是目录，创建DirectoryItem并递归扫描
                let directoryItem = DirectoryItem(url: itemURL, name: itemURL.lastPathComponent)
                parentItem.addSubdirectory(directoryItem)
                try scanSubdirectory(itemURL, parentItem: directoryItem)
            } else if itemURL.pathExtension.lowercased() == "mp3" {
                // 是MP3文件，创建MusicItem
                let musicItem = MusicItem(url: itemURL, parentDirectory: url)
                parentItem.addMusicFile(musicItem)
            }
            
            // 更新进度
            DispatchQueue.main.async {
                // 这里简化处理，实际应该计算更精确的进度
                self.progressHandler?(0.5) // 示例进度值
            }
        }
    }
    
    // 获取目录中所有音乐文件的扁平列表
    func getAllMusicFiles(from directoryItem: DirectoryItem) -> [MusicItem] {
        var allFiles: [MusicItem] = []
        
        // 添加当前目录的音乐文件
        allFiles.append(contentsOf: directoryItem.musicFiles)
        
        // 递归获取子目录的音乐文件
        for subdirectory in directoryItem.subdirectories {
            allFiles.append(contentsOf: getAllMusicFiles(from: subdirectory))
        }
        
        return allFiles
    }
    
    // 获取指定目录内的音乐文件列表
    func getMusicFilesInDirectory(_ directoryURL: URL, from rootItem: DirectoryItem) -> [MusicItem] {
        var result: [MusicItem] = []
        
        // 检查是否是根目录
        if rootItem.url == directoryURL {
            return rootItem.musicFiles
        }
        
        // 递归查找匹配的目录
        for subdirectory in rootItem.subdirectories {
            if subdirectory.url == directoryURL {
                result = subdirectory.musicFiles
                break
            }
            
            let subResult = getMusicFilesInDirectory(directoryURL, from: subdirectory)
            if !subResult.isEmpty {
                result = subResult
                break
            }
        }
        
        return result
    }
}
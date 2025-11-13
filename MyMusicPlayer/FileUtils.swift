import Foundation

/// 文件操作工具类，提供常用的文件操作辅助方法
enum FileUtils {
    
    /// 检查URL是否位于应用程序的沙盒目录内
    /// - Parameter url: 要检查的文件URL
    /// - Returns: 如果URL位于应用程序的沙盒目录内（Documents、Library、Application Support或临时目录），则返回true，否则返回false
    static func isURLInAppSandbox(_ url: URL) -> Bool {
        // 获取应用程序的Documents目录
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first, 
              let libraryDirectory = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first, 
              let applicationSupportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first, 
              let tempDirectory = FileManager.default.temporaryDirectory as URL? else {
            return false
        }
        
        let standardizedURL = url.standardizedFileURL.path
        let standardizedDocs = documentsDirectory.standardizedFileURL.path
        let standardizedLib = libraryDirectory.standardizedFileURL.path
        let standardizedAppSupport = applicationSupportDirectory.standardizedFileURL.path
        let standardizedTemp = tempDirectory.standardizedFileURL.path
        
        // 检查URL是否为任何APP沙盒目录的子目录
        return (standardizedURL.hasPrefix(standardizedDocs) && standardizedURL != standardizedDocs) || 
               (standardizedURL.hasPrefix(standardizedLib) && standardizedURL != standardizedLib) || 
               (standardizedURL.hasPrefix(standardizedAppSupport) && standardizedURL != standardizedAppSupport) || 
               (standardizedURL.hasPrefix(standardizedTemp) && standardizedURL != standardizedTemp)
    }
}

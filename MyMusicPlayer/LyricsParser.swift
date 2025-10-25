import Foundation

// 临时定义，确保编译通过
struct LyricsLine {
    let time: TimeInterval
    let text: String
    
    init(time: TimeInterval, text: String) {
        self.time = time
        self.text = text
    }
}

class LyricsParser {
    
    // 解析LRC歌词文件
    static func parseLyrics(from url: URL) -> [LyricsLine]? {
        print("[LyricsParser] 开始解析歌词文件: \(url.lastPathComponent)")
        
        var shouldStopAccess = false
        let hasAccess = url.startAccessingSecurityScopedResource()
        if hasAccess {
            shouldStopAccess = true
            print("[LyricsParser] 成功获取歌词文件访问权限: \(url.lastPathComponent)")
        } else {
            print("[LyricsParser] 无法获取歌词文件访问权限: \(url.lastPathComponent)，尝试使用备用方式访问")
        }
        
        var result: [LyricsLine]?
        // 使用defer语句确保无论如何都会释放访问权限
        defer {
            if shouldStopAccess {
                url.stopAccessingSecurityScopedResource()
                print("[LyricsParser] 已释放歌词文件访问权限: \(url.lastPathComponent)")
            }
        }
        
        // 尝试不同的编码方式读取文件
        let encodings: [String.Encoding] = [.utf8, .utf16, .ascii]
        var content: String? = nil
        
        for encoding in encodings {
            do {
                content = try String(contentsOf: url, encoding: encoding)
                print("[LyricsParser] 使用编码 \(encoding) 成功读取歌词文件")
                break // 成功读取后跳出循环
            } catch {
                print("[LyricsParser] 使用编码 \(encoding) 读取歌词文件失败: \(error.localizedDescription)")
                continue
            }
        }
        
        if let content = content {
            result = parseLyrics(content: content)
        } else {
            print("[LyricsParser] 尝试所有编码方式后仍无法读取歌词文件: \(url.lastPathComponent)")
        }
        
        return result
    }
    
    // 解析歌词内容
    static func parseLyrics(content: String) -> [LyricsLine] {
        // 打印原始歌词内容前100个字符用于调试
        // print("原始歌词文件内容开始 (前100字符): \(content.prefix(100))...")
        
        var lyrics: [LyricsLine] = []
        
        // 按行分割歌词
        let lines = content.components(separatedBy: .newlines)
        print("[LyricsParser] 歌词文件共有 \(lines.count) 行")
        
        // 正则表达式匹配时间标签，支持两位数或三位数的毫秒部分
        let timeRegex = try! NSRegularExpression(pattern: "\\[(\\d{2}):(\\d{2})\\.(\\d{2,3})\\]")
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedLine.isEmpty {
                // print("跳过空行")
                continue
            }
            
            // 查找所有时间标签
            let matches = timeRegex.matches(in: trimmedLine, range: NSRange(trimmedLine.startIndex..., in: trimmedLine))
            
            if matches.isEmpty {
                // print("跳过没有时间标签的行: \(trimmedLine)")
                continue
            }
            
            // 提取歌词文本（去除所有时间标签后的内容）
            // 使用更可靠的方式提取文本：移除所有匹配的时间标签
            var text = trimmedLine
            for match in matches {
                if let range = Range(match.range, in: text) {
                    text.replaceSubrange(range, with: "")
                }
            }
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // print("提取到文本: \(text.isEmpty ? "[空]" : text)")
            
            // // 检查是否是元数据行（如作词、作曲、编曲等），如果是则跳过
            // let metadataKeywords = ["作词", "作曲", "编曲", "制作人", "演唱", "歌手"]
            // if metadataKeywords.contains(where: { text.contains($0) }) {
            //     print("跳过元数据行: \(trimmedLine)")
            //     continue
            // }
            
            // 如果文本为空，跳过这行
            if text.isEmpty {
                // print("跳过空歌词行")
                continue
            }
            
            // 为每个时间标签创建歌词行
            for match in matches {
                if match.numberOfRanges >= 4 {
                    // 提取分钟、秒、毫秒
                    let minuteRange = Range(match.range(at: 1), in: trimmedLine)!
                    let secondRange = Range(match.range(at: 2), in: trimmedLine)!
                    let millisecondRange = Range(match.range(at: 3), in: trimmedLine)!
                    
                    let minute = Double(trimmedLine[minuteRange]) ?? 0
                    let second = Double(trimmedLine[secondRange]) ?? 0
                    let millisecond = Double(trimmedLine[millisecondRange]) ?? 0
                    
                    // 转换为总秒数，根据毫秒位数进行不同处理
                    let totalSeconds = minute * 60 + second + millisecond / (millisecond > 99 ? 1000 : 100)
                    
                    lyrics.append(LyricsLine(time: totalSeconds, text: text))
                    // print("添加歌词行: [\(String(format: "%.3f", totalSeconds))] \(text)")
                }
            }
        }
        
        // 按时间排序
        lyrics.sort { $0.time < $1.time }
        
        // 打印解析结果
        print("[LyricsParser] 歌词解析完成，共解析出 \(lyrics.count) 行歌词")
        if !lyrics.isEmpty {
            // 打印前3行歌词作为示例
            let sampleLines = lyrics.prefix(3).map { "[\($0.time)] \($0.text)" }
            // print("歌词示例:\n\(sampleLines.joined(separator: "\n"))")
        }
        
        return lyrics
    }
    
    // 根据当前播放时间获取应该显示的歌词行索引
    static func getCurrentLyricIndex(time: TimeInterval, lyrics: [LyricsLine]) -> Int {
        for (index, lyric) in lyrics.enumerated() {
            if time < lyric.time {
                // 当前时间小于下一行歌词的时间，返回上一行的索引
                return max(0, index - 1)
            }
        }
        
        // 如果没有找到合适的索引，返回最后一行
        return lyrics.count - 1
    }
}
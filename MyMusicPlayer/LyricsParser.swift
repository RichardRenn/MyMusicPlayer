import Foundation

class LyricsParser {
    
    // 解析LRC歌词文件
    static func parseLyrics(from url: URL) -> [LyricsLine]? {
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            return parseLyrics(content: content)
        } catch {
            print("解析歌词文件失败: \(error)")
            return nil
        }
    }
    
    // 解析歌词内容
    static func parseLyrics(content: String) -> [LyricsLine] {
        var lyrics: [LyricsLine] = []
        
        // 按行分割歌词
        let lines = content.components(separatedBy: .newlines)
        
        // 正则表达式匹配时间标签
        let timeRegex = try! NSRegularExpression(pattern: \[(\d{2}):(\d{2})\.(\d{2})\])
        
        for line in lines {
            // 查找所有时间标签
            let matches = timeRegex.matches(in: line, range: NSRange(line.startIndex..., in: line))
            
            // 提取歌词文本（去除时间标签后的内容）
            let textRange = line.range(of: "\].*", options: .regularExpression)
            let text: String
            
            if let range = textRange {
                text = String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                text = ""
            }
            
            // 为每个时间标签创建歌词行
            for match in matches {
                if match.numberOfRanges >= 4 {
                    // 提取分钟、秒、毫秒
                    let minuteRange = Range(match.range(at: 1), in: line)!
                    let secondRange = Range(match.range(at: 2), in: line)!
                    let millisecondRange = Range(match.range(at: 3), in: line)!
                    
                    let minute = Double(line[minuteRange]) ?? 0
                    let second = Double(line[secondRange]) ?? 0
                    let millisecond = Double(line[millisecondRange]) ?? 0
                    
                    // 转换为总秒数
                    let totalSeconds = minute * 60 + second + millisecond / 100
                    
                    lyrics.append(LyricsLine(time: totalSeconds, text: text))
                }
            }
        }
        
        // 按时间排序
        lyrics.sort { $0.time < $1.time }
        
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
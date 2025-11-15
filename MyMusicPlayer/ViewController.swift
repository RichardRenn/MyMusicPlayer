import UIKit
import Foundation
import UniformTypeIdentifiers
import AVFoundation

#if canImport(Foundation)
// 尝试使用Foundation框架来模拟持久化功能
#endif


class ViewController: UIViewController, UIDocumentPickerDelegate {
    
    private let musicScanner = MusicScanner()
    private var selectedDirectoryURL: URL?
    private var securityScopedResources: [URL] = [] // 用于跟踪需要保持访问权限的资源
    private var hasSelectedDirectory = false // 跟踪是否已选择过文件夹
    
    // UI元素
    // 主题颜色，默认为.systemBlue，在viewDidLoad中加载保存的设置
    private var themeColor: UIColor = .systemBlue
    
    // 主题模式
    private var currentThemeMode: ThemeMode = .light
    
    // 毛玻璃效果背景视图
    private var blurEffectView: UIVisualEffectView?
    
    private var scanningAppFolder = false
    
    private var helpButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("?", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 20, weight: .bold)
        button.layer.cornerRadius = 20
        button.clipsToBounds = true
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "欢迎使用本地音乐播放器"
        label.font = UIFont.systemFont(ofSize: 24, weight: .bold)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let subtitleLabel: UILabel = {
        let label = UILabel()
        // label.text = "将音乐文件夹放至【本地音乐】目录下可自动加载"
        label.text = ""
        label.font = UIFont.systemFont(ofSize: 16)
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0 // 允许显示多行文本
        return label
    }()
    
    private let selectButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("打开文件夹", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .medium)
        button.backgroundColor = .systemBlue
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 10
        button.clipsToBounds = true
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let scanProgressView: UIProgressView = {
        let scanProgressView = UIProgressView(progressViewStyle: .default)
        scanProgressView.progress = 0
        scanProgressView.isHidden = true
        scanProgressView.translatesAutoresizingMaskIntoConstraints = false
        return scanProgressView
    }()
    
    private let scanProgressLabel: UILabel = {
        let label = UILabel()
        label.text = "0%"
        label.font = UIFont.systemFont(ofSize: 14)
        label.textAlignment = .center
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let scanningTipsLabel: UILabel = {
        let label = UILabel()
        // label.text = "正在很努力的打开歌曲库 请稍等下下～"
        label.text = ""
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let tipsLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // 提示文本数组
    private let tipsArray = [
        "将音乐文件夹放入【本地音乐】目录下可自动加载",
        "文件夹左滑可以删除哦",
        "歌曲较多时加载可能较慢，请稍等下下",
        "锁定可以控制只在歌曲所在目录循环播放",
        "左上角编辑面板可以添加或者刷新音乐目录",
        "右上角设置面板可以按个人喜好调整外观",
        "轻点下方的歌曲名来快速定位到歌曲位置",
        "点击播放控制空白处可以进入歌词详情页"
    ]
    
    // 当前提示索引
    private var currentTipIndex: Int = 0
    
    // 提示切换定时器
    private var tipsTimer: Timer?
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        // 添加按钮点击事件
        selectButton.addTarget(self, action: #selector(selectButtonTapped), for: .touchUpInside)
        
        // 加载并应用保存的主题设置
        loadSavedTheme()
        // 先加载主题颜色，再应用到按钮和进度条
        themeColor = loadThemeColorSetting()
        selectButton.backgroundColor = themeColor
        scanProgressView.progressTintColor = themeColor
        helpButton.setTitleColor(themeColor, for: .normal)
        
        // 更新毛玻璃背景颜色
        updateBlurBackground()
        
        // 设置初始提示文本
        tipsLabel.text = tipsArray[0]
        
        // 启动提示滚动效果
        startTipsScrolling()
        
        // 注册应用从后台返回前台的通知
        NotificationCenter.default.addObserver(self, selector: #selector(handleAppWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // 检查音乐文件加并显示操作对话框
        checkAndShowDialogs()
    }
    
    // 处理应用从后台返回前台的通知
    @objc private func handleAppWillEnterForeground() {
        // 检查是否是首页（通过hasSelectedDirectory标志判断）
        if !hasSelectedDirectory {
            // 如果当前是首页，调用checkAndShowDialogs方法
            checkAndShowDialogs()
        }
    }
    
    // 启动提示文本滚动效果
    private func startTipsScrolling() {
        // 先停止已有的定时器
        stopTipsScrolling()
        
        // 创建新的定时器，每3秒切换一次提示
        tipsTimer = Timer.scheduledTimer(timeInterval: 3, target: self, selector: #selector(showNextTip), userInfo: nil, repeats: true)
    }
    
    // 停止提示文本滚动
    private func stopTipsScrolling() {
        tipsTimer?.invalidate()
        tipsTimer = nil
    }
    
    // 显示下一条提示
    @objc private func showNextTip() {
        // 当前提示向上滑出并淡出
        UIView.animate(withDuration: 0.5) {
            self.tipsLabel.transform = CGAffineTransform(translationX: 0, y: -20)
            self.tipsLabel.alpha = 0.0
        } completion: { [weak self] _ in
            guard let self = self else { return }
            
            // 更新索引
            self.currentTipIndex = (self.currentTipIndex + 1) % self.tipsArray.count
            
            // 设置新的提示文本
            self.tipsLabel.text = self.tipsArray[self.currentTipIndex]
            
            // 重置位置并设置为从下方进入的初始状态
            self.tipsLabel.transform = CGAffineTransform(translationX: 0, y: 20)
            self.tipsLabel.alpha = 0.0
            
            // 新提示从下方滑入并淡入
            UIView.animate(withDuration: 0.5) {
                self.tipsLabel.transform = .identity
                self.tipsLabel.alpha = 1.0
            }
        }
    }
    
    // 加载保存的主题设置
    // 从UserDefaults加载主题颜色设置
    private func loadThemeColorSetting() -> UIColor {
        let userDefaults = UserDefaults.standard
        if let colorData = userDefaults.data(forKey: "themeColor") {
            if let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: UIColor.self, from: colorData) {
                return color
            }
        }
        return .systemBlue
    }
    
    private func loadSavedTheme() {
        let defaults = UserDefaults.standard
        let themeKey = "themeMode"
        
        if let savedThemeValue = defaults.object(forKey: themeKey) as? Int {
            switch savedThemeValue {
            case 0: // light
                self.overrideUserInterfaceStyle = .light
            case 1: // dark
                self.overrideUserInterfaceStyle = .dark
            default: // 默认使用浅色模式
                self.overrideUserInterfaceStyle = .light
            }
            print("[ViewController] [主题设置] 已加载保存的主题模式：\(savedThemeValue)")
        } else {
            // 如果没有保存的设置，默认为浅色模式
            self.overrideUserInterfaceStyle = .light
        }
        
        // 加载主题模式设置
        loadThemeSetting()
    }
    
    // 加载主题设置
    private func loadThemeSetting() {
        let savedValue = UserDefaults.standard.integer(forKey: "themeMode")
        if let themeMode = ThemeMode(rawValue: savedValue) {
            currentThemeMode = themeMode
        } else {
            // 默认为浅色模式
            currentThemeMode = .light
        }
        print("[ViewController] [主题设置] 已加载保存的主题模式：\(currentThemeMode)")
    }
    
    // 设置毛玻璃背景效果
    private func setupBlurBackground() {
        // 先移除旧的毛玻璃视图
        blurEffectView?.removeFromSuperview()
        
        // 根据当前主题模式选择模糊效果风格
        let blurEffectStyle: UIBlurEffect.Style = currentThemeMode == .light ? .light : .dark
        let blurEffect = UIBlurEffect(style: blurEffectStyle)
        blurEffectView = UIVisualEffectView(effect: blurEffect)
        blurEffectView?.frame = view.bounds
        blurEffectView?.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        
        // 将毛玻璃视图添加到最底层
        view.insertSubview(blurEffectView!, at: 0)
        
        // 初始更新毛玻璃背景颜色
        updateBlurBackground()
    }
    
    // 更新毛玻璃背景颜色
    private func updateBlurBackground() {
        guard let blurEffectView = blurEffectView else { return }
        
        // 确保模糊视图有正确的尺寸
        blurEffectView.frame = view.bounds
        
        // 根据当前主题模式选择模糊效果风格
        let blurEffectStyle: UIBlurEffect.Style = currentThemeMode == .light ? .light : .dark
        let blurEffect = UIBlurEffect(style: blurEffectStyle)
        blurEffectView.effect = blurEffect
        
        // 根据当前主题模式选择对应的主题色 - 使用更明显的颜色差异来测试渐变效果
        let topColor: UIColor
        let bottomColor: UIColor
        if currentThemeMode == .light {
            // 浅色主题：顶部颜色更深，底部颜色更浅
            topColor = createLightThemeColor(baseColor: themeColor, alpha: 0.8)
            bottomColor = createLightThemeColor(baseColor: themeColor, alpha: 0.2)
        } else {
            // 深色主题：顶部颜色更深，底部颜色更浅
            topColor = createDarkThemeColor(baseColor: themeColor, alpha: 0.8)
            bottomColor = createDarkThemeColor(baseColor: themeColor, alpha: 0.2)
        }
        
        // 移除旧的颜色视图
        blurEffectView.contentView.subviews.forEach { $0.removeFromSuperview() }
        
        // 直接在contentView上创建渐变色层
        let gradientLayer = CAGradientLayer()
        gradientLayer.frame = blurEffectView.contentView.bounds
        gradientLayer.colors = [topColor.cgColor, bottomColor.cgColor]
        gradientLayer.locations = [0.0, 1.0]
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.0)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 1.0)
        
        // 确保图层数组为空再添加
        blurEffectView.contentView.layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        blurEffectView.contentView.layer.addSublayer(gradientLayer)
        
        // 设置zPosition确保渐变层在正确的层级
        gradientLayer.zPosition = -1
    }
    
    // 根据基础颜色创建浅色主题色，并支持自定义透明度
    private func createLightThemeColor(baseColor: UIColor, alpha: CGFloat = 1.0) -> UIColor {
        // 获取基础颜色的RGB值
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        baseColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        
        // 创建浅色版本，降低饱和度，提高亮度
        // 混合白色和基础颜色，使用85%的白色和15%的基础颜色
        let lightR = 0.4 * 1.0 + 0.4 * r
        let lightG = 0.4 * 1.0 + 0.4 * g
        let lightB = 0.4 * 1.0 + 0.4 * b
        
        // 使用传入的透明度
        return UIColor(red: lightR, green: lightG, blue: lightB, alpha: alpha)
    }

    // 根据基础颜色创建深色主题色，并支持自定义透明度
    private func createDarkThemeColor(baseColor: UIColor, alpha: CGFloat = 1.0) -> UIColor {
        // 获取基础颜色的RGB值
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        baseColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        
        // 创建深色版本，降低亮度，增加饱和度
        // 混合黑色和基础颜色，使用85%的黑色和15%的基础颜色
        let darkR = 0.0 * 0.0 + 0.4 * r
        let darkG = 0.0 * 0.0 + 0.4 * g
        let darkB = 0.0 * 0.0 + 0.4 * b
        
        // 使用传入的透明度
        return UIColor(red: darkR, green: darkG, blue: darkB, alpha: alpha)
    }
    
    // 检查是否有已保存的音乐列表
    private func checkForSavedMusicList() {
        print("[ViewController] [持久化] 开始检查保存的音乐列表...")
        let defaults = UserDefaults.standard
        let bookmarkKey = "savedMusicDirectoriesBookmarks"
        
        // 检查UserDefaults中是否存在该键
        if defaults.object(forKey: bookmarkKey) != nil {
            print("[ViewController] [持久化] UserDefaults中存在键 \(bookmarkKey)")
            // 继续执行原有的持久化目录加载逻辑
        } else {
            print("[ViewController] [持久化] UserDefaults中不存在键 \(bookmarkKey)")
            // 如果没有持久化的目录，自动扫描专用文件夹
            scanAppMusicFolder()
            return
        }
        
        // 首先尝试从bookmark数据加载（新方法）
        if let savedBookmarksData = defaults.data(forKey: bookmarkKey) {
            print("[ViewController] [持久化] 找到保存的安全书签数据，数据大小: \(savedBookmarksData.count)字节，尝试解析...")
            do {
                // 尝试解析保存的bookmark数据
                let savedBookmarks = try JSONDecoder().decode([Data].self, from: savedBookmarksData)
                print("[ViewController] [持久化] 解析成功，书签数量: \(savedBookmarks.count)")
                
                // 如果书签数组为空，直接返回，不尝试加载
                if savedBookmarks.isEmpty {
                    print("[ViewController] [持久化] 书签数组为空，无需恢复，显示选择文件夹界面")
                    return
                }
                
                for (idx, bookmark) in savedBookmarks.enumerated() {
                    print("[ViewController] [持久化] 加载的书签\(idx+1) - 数据类型: \(type(of: bookmark)), 大小: \(bookmark.count)字节")
                    // 打印前几个字节的十六进制表示，用于验证数据一致性
                    let prefixSize = min(10, bookmark.count)
                    let prefixData = bookmark.subdata(in: 0..<prefixSize)
                    let hexDescription = prefixData.map { String(format: "%02x", $0) }.joined(separator: " ")
                    print("[ViewController] [持久化] 加载的书签\(idx+1) - 前10字节: \(hexDescription)")
                }
                
                if !savedBookmarks.isEmpty {
                    print("[ViewController] [持久化] 发现保存的音乐目录书签，准备恢复访问权限...")
                    
                    // 创建一个数组来存储所有恢复的URL
                    var recoveredURLs: [URL] = []
                    var updatedBookmarks: [Data] = []
                    var hasError = false
                    
                    // 遍历所有bookmark数据，恢复URL和访问权限
                    for (index, bookmarkData) in savedBookmarks.enumerated() {
                        var isStale = false
                        
                        do {
                            // 使用基本选项恢复URL
                            let bookmarkOptions: URL.BookmarkResolutionOptions = [
                                .withoutUI
                            ]
                            
                            print("[ViewController] [持久化] 尝试从书签\(index+1) 恢复URL...")
                            let recoveredURL = try URL(resolvingBookmarkData: bookmarkData, options: bookmarkOptions, relativeTo: nil, bookmarkDataIsStale: &isStale)
                            print("[ViewController] [持久化] 成功从书签\(index+1) 恢复URL: \(recoveredURL.lastPathComponent)")
                            
                            // 检查是否是目录
                            var isDir: ObjCBool = false
                            if FileManager.default.fileExists(atPath: recoveredURL.path, isDirectory: &isDir) && isDir.boolValue {
                                // 检查是否是APP专用文件夹
                                let isAppFolder = FileUtils.isURLInAppSandbox(recoveredURL)
                                
                                // 获取安全访问权限 - APP专用文件夹无需获取权限
                                if isAppFolder || recoveredURL.startAccessingSecurityScopedResource() {
                                    if !isAppFolder {
                                        // 只有非APP专用文件夹才需要跟踪以便释放权限
                                        self.securityScopedResources.append(recoveredURL)
                                    }
                                    
                                    recoveredURLs.append(recoveredURL)
                                    print("[ViewController] [持久化] \(isAppFolder ? "APP专用文件夹" : "成功恢复文件夹")\(index+1)访问权限: \(recoveredURL.lastPathComponent)")
                                    
                                    // 无论是否是APP专用文件夹，都需要处理书签更新
                                    if isStale {
                                        do {
                                            // 在iOS中使用基本选项创建书签
                                            let updateOptions: URL.BookmarkCreationOptions = []
                                            let newBookmarkData = try recoveredURL.bookmarkData(options: updateOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
                                            updatedBookmarks.append(newBookmarkData)
                                            print("[ViewController] [持久化] 已更新过时的安全书签\(index+1)")
                                        } catch {
                                            print("[ViewController] [持久化] 更新过时书签\(index+1)失败: \(error.localizedDescription)")
                                            updatedBookmarks.append(bookmarkData) // 保留原数据
                                        }
                                    } else {
                                        updatedBookmarks.append(bookmarkData)
                                    }
                                } else {
                                    print("[ViewController] [持久化] 无法获取文件夹\(index+1)的安全访问权限")
                                    hasError = true
                                    updatedBookmarks.append(bookmarkData) // 保留原数据以便后续重试
                                }
                            } else {
                                print("[ViewController] [持久化] 恢复的URL不是有效的目录: \(recoveredURL.lastPathComponent)")
                                hasError = true
                                updatedBookmarks.append(bookmarkData)
                            }
                        } catch {
                            print("[ViewController] [持久化] 从书签\(index+1)恢复URL失败: \(error.localizedDescription)")
                            hasError = true
                            updatedBookmarks.append(bookmarkData) // 即使失败也保留原数据
                        }
                    }
                    
                    // 如果有更新的书签数据，保存回UserDefaults
                    if updatedBookmarks.count == savedBookmarks.count {
                        do {
                            let encodedData = try JSONEncoder().encode(updatedBookmarks)
                            UserDefaults.standard.set(encodedData, forKey: bookmarkKey)
                        } catch {
                            print("[ViewController] [持久化] 保存更新的书签失败: \(error.localizedDescription)")
                        }
                    }
                    
                    // 如果有错误且没有成功恢复的URL，显示错误
                    if hasError && recoveredURLs.isEmpty {
                        self.showPermissionErrorAndClearData()
                    } else if !recoveredURLs.isEmpty {
                        // 逐个扫描所有恢复的URL并收集结果
                        var rootDirectoryItems: [DirectoryItem] = []
                        var completedScans = 0
                        let totalScans = recoveredURLs.count
                        
                        // 显示进度条并隐藏选择按钮，与手动选择文件夹时保持一致
                        DispatchQueue.main.async {
                            self.scanProgressView.isHidden = false
                            self.scanProgressLabel.isHidden = false
                            self.scanningTipsLabel.isHidden = false
                            self.selectButton.isHidden = true
                            // self.subtitleLabel.isHidden = true
                        }
                        
                        // 逐个扫描每个URL
                        for (index, url) in recoveredURLs.enumerated() {
                            self.musicScanner.scanDirectory(url, scanProgressHandler: { progress in
                                print("[ViewController] [持久化] 扫描文件夹\(index+1)/\(totalScans) 进度: \(Int(progress * 100))%")
                                
                                // 更新进度条UI
                                DispatchQueue.main.async {
                                    // 计算总体进度
                                    let overallProgress = (Float(completedScans) + Float(progress)) / Float(totalScans)
                                    self.scanProgressView.progress = overallProgress
                                    self.scanProgressLabel.text = "\(Int(overallProgress * 100))%"
                                }
                            }) { [weak self] (rootDirectoryItem) in
                                guard let self = self else { return }
                                
                                DispatchQueue.main.async {
                                    // 如果成功扫描到目录，添加到结果数组
                                    if let rootItem = rootDirectoryItem {
                                        rootDirectoryItems.append(rootItem)
                                        print("[ViewController] [持久化] 成功扫描文件夹\(index+1)/\(totalScans): \(rootItem.name)")
                                    } else {
                                        print("[ViewController] [持久化] 扫描文件夹\(index+1)/\(totalScans)失败")
                                    }
                                    
                                    // 检查是否所有扫描都已完成
                                    completedScans += 1
                                    if completedScans == totalScans {
                                        if !rootDirectoryItems.isEmpty {
                                            print("[ViewController] [持久化] 所有文件夹扫描完成，成功扫描到\(rootDirectoryItems.count)个文件夹")
                                            
                                            // 隐藏进度条
                                            self.scanProgressView.isHidden = true
                                            self.scanProgressLabel.isHidden = true
                                            
                                            // 跳转到音乐列表页面，传入所有根目录项
                                            let musicListVC = MusicListViewController(rootDirectoryItems: rootDirectoryItems, scanner: self.musicScanner)
                                            let navigationController = UINavigationController(rootViewController: musicListVC)
                                            navigationController.modalPresentationStyle = .fullScreen
                                            self.present(navigationController, animated: true, completion: nil)
                                        } else {
                                            // 隐藏进度条
                                            self.scanProgressView.isHidden = true
                                            self.scanProgressLabel.isHidden = true
                                            
                                            print("[ViewController] [持久化] 所有文件夹都无法扫描到有效内容")
                                            self.showPermissionErrorAndClearData()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            } catch {
                print("[ViewController] [持久化] 解析书签数据失败: \(error.localizedDescription)")
                self.tryLoadingFromLegacyFormat()
            }
        } else {
            // 如果没有找到bookmark数据，尝试从旧的URL字符串格式加载
            self.tryLoadingFromLegacyFormat()
        }
    }
    
    // 显示权限错误并清除保存的数据
    private func showPermissionErrorAndClearData() {
        DispatchQueue.main.async {
            let alert = UIAlertController(title: "权限已过期", message: "保存的音乐文件夹访问权限已过期，请重新选择文件夹", preferredStyle: .alert)
            
            // 添加取消按钮
            let cancelAction = UIAlertAction(title: "取消", style: .cancel) { _ in
                print("[ViewController] [持久化] 用户取消了重新选择文件夹")
            }
            
            // 添加重新选择按钮，点击后直接打开文件夹选择器
            let reselectAction = UIAlertAction(title: "重新选择", style: .default) { [weak self] _ in
                guard let self = self else { return }
                print("[ViewController] [持久化] 用户选择重新选择文件夹")
                
                // 清理所有保存的数据，包括新格式和旧格式
                let defaults = UserDefaults.standard
                defaults.removeObject(forKey: "savedMusicDirectoriesBookmarks")
                defaults.removeObject(forKey: "savedMusicDirectories")
                print("[ViewController] [持久化] 已清理所有过期的保存数据")
                
                // 打开文件夹选择器
                self.selectButtonTapped()
            }
            
            alert.addAction(cancelAction)
            alert.addAction(reselectAction)
            self.present(alert, animated: true) { 
                print("[ViewController] [持久化] 权限过期提示已显示")
            }
        }
    }
    
    // 尝试从旧的URL字符串格式加载（向后兼容）
    private func tryLoadingFromLegacyFormat() {
        print("[ViewController] [持久化] 尝试从旧格式加载保存的音乐列表...")
        let defaults = UserDefaults.standard
        let legacyKey = "savedMusicDirectories"
        
        if let savedDirectoriesData = defaults.data(forKey: legacyKey) {
            print("[ViewController] [持久化] 找到旧格式保存的数据，尝试解析...")
            if let savedDirectories = try? JSONDecoder().decode([String].self, from: savedDirectoriesData) {
                print("[ViewController] [持久化] 解析成功，目录数量: \(savedDirectories.count)")
                if !savedDirectories.isEmpty {
                    print("[ViewController] [持久化] 发现保存的音乐目录，准备加载...")
                    
                    // 获取保存的文件夹URL
                    if let firstURLString = savedDirectories.first, let savedURL = URL(string: firstURLString) {
                        print("[ViewController] [持久化] 使用保存的路径: \(firstURLString)")
                        
                        // 尝试获取文件夹访问权限
                        print("[ViewController] [持久化] 尝试获取文件夹访问权限...")
                        if savedURL.startAccessingSecurityScopedResource() {
                            self.securityScopedResources.append(savedURL)
                            print("[ViewController] [持久化] 成功获取文件夹访问权限")
                            
                            // 显示进度条并隐藏选择按钮
                                DispatchQueue.main.async {
                                    self.scanProgressView.isHidden = false
                                    self.scanProgressLabel.isHidden = false
                                    self.scanningTipsLabel.isHidden = false
                                    self.selectButton.isHidden = true
                                    // self.subtitleLabel.isHidden = true
                                }
                            
                            // 立即开始扫描
                            self.musicScanner.scanDirectory(savedURL, scanProgressHandler: { progress in
                                print("[ViewController] [持久化] 扫描进度: \(Int(progress * 100))%")
                                
                                // 更新进度条UI
                                DispatchQueue.main.async {
                                    self.scanProgressView.progress = Float(progress)
                                    self.scanProgressLabel.text = "\(Int(progress * 100))%"
                                }
                            }) { [weak self] (rootDirectoryItem) in
                                guard let self = self else { return }
                                
                                DispatchQueue.main.async {
                                    // 隐藏进度条
                                    self.scanProgressView.isHidden = true
                                    self.scanProgressLabel.isHidden = true
                                    self.scanningTipsLabel.isHidden = true
                                    self.scanningTipsLabel.isHidden = true
                                    
                                    if let rootItem = rootDirectoryItem {
                                        print("[ViewController] [持久化] 扫描完成，找到文件夹: \(rootItem.name)")
                                        
                                        // 跳转到音乐列表页面
                                        let musicListVC = MusicListViewController(rootDirectoryItem: rootItem, scanner: self.musicScanner)
                                        let navigationController = UINavigationController(rootViewController: musicListVC)
                                        navigationController.modalPresentationStyle = .fullScreen
                                        self.present(navigationController, animated: true, completion: nil)
                                    }
                                }
                            }
                        } else {
                            print("[ViewController] [持久化] 无法获取文件夹访问权限")
                            self.showPermissionErrorAndClearData()
                        }
                    }
                }
            } else {
                print("[ViewController] [持久化] 解析数据失败")
            }
        } else {
            print("[ViewController] [持久化] 未找到保存的音乐目录数据")
        }
        print("[ViewController] [持久化] 检查保存的音乐列表完成")
    }
    
    // 设置UI
    private func setupUI() {
        
        // 设置毛玻璃背景效果
        setupBlurBackground()
        
        // 添加UI元素
        view.addSubview(titleLabel)
        view.addSubview(subtitleLabel)
        view.addSubview(selectButton)
        view.addSubview(scanProgressView)
        view.addSubview(scanProgressLabel)
        view.addSubview(scanningTipsLabel)
        view.addSubview(tipsLabel)
        view.addSubview(helpButton)
        
        // 添加帮助按钮点击事件
        helpButton.addTarget(self, action: #selector(helpButtonTapped), for: .touchUpInside)
        
        // 设置约束
        NSLayoutConstraint.activate([
            // 帮助按钮
            helpButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            helpButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            helpButton.widthAnchor.constraint(equalToConstant: 40),
            helpButton.heightAnchor.constraint(equalToConstant: 40),

            // 标题
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 100),
            
            // 副标题
            subtitleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            
            // 选择按钮
            selectButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            selectButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            selectButton.widthAnchor.constraint(equalToConstant: 200),
            selectButton.heightAnchor.constraint(equalToConstant: 50),
            
            // 进度条
            scanProgressView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            scanProgressView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            // scanProgressView.topAnchor.constraint(equalTo: selectButton.bottomAnchor, constant: 50),
            scanProgressView.widthAnchor.constraint(equalTo: view.widthAnchor, constant: -40),
            
            // 进度标签
            scanProgressLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            scanProgressLabel.topAnchor.constraint(equalTo: scanProgressView.bottomAnchor, constant: 8),
            
            // 扫描提示标签
            scanningTipsLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            scanningTipsLabel.topAnchor.constraint(equalTo: scanProgressLabel.bottomAnchor, constant: 8),
            
            // 布局约束
            tipsLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            tipsLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            tipsLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -100),
            tipsLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 30) // 确保有足够高度显示文本
        ])
        
        // 应用主题颜色到按钮
        selectButton.backgroundColor = themeColor
    }
    
    // 选择文件夹按钮点击事件
    @objc private func selectButtonTapped() {
        let documentPicker: UIDocumentPickerViewController
        
        // 使用iOS 14.0及以上推荐的API，回退到旧API以支持较早版本
        if #available(iOS 14, *) {
            documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        } else {
            documentPicker = UIDocumentPickerViewController(documentTypes: ["public.folder"], in: .open)
        }
        
        documentPicker.delegate = self
        documentPicker.allowsMultipleSelection = true
        
        // iOS 14及以上支持文件夹选择
        if #available(iOS 14, *) {
            documentPicker.directoryURL = nil
        }
        
        present(documentPicker, animated: true, completion: nil)
    }
    
    // UIDocumentPickerDelegate 方法
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard !urls.isEmpty else { return }
        
        // 清除之前的权限记录
        clearSecurityScopedResources()
        
        // 获取并保持所有文件夹访问权限
        var grantedURLs: [URL] = []
        
        for url in urls {
            if url.startAccessingSecurityScopedResource() {
                securityScopedResources.append(url)
                grantedURLs.append(url)
                print("[ViewController] [持久化] 成功获取文件夹访问权限: \(url.lastPathComponent)")
            } else {
                print("[ViewController] [持久化] 无法获取文件夹访问权限: \(url.lastPathComponent)")
            }
        }
        
        guard !grantedURLs.isEmpty else {
            return
        }
        
        // 设置多选模式下的选中状态
        hasSelectedDirectory = true
        
        // 显示进度条并隐藏选择按钮
        scanProgressView.isHidden = false
        scanProgressLabel.isHidden = false
        scanningTipsLabel.isHidden = false
        selectButton.isHidden = true
        // subtitleLabel.isHidden = true
        
        // 逐个扫描所有选中的URL并收集结果
        var rootDirectoryItems: [DirectoryItem] = []
        var completedScans = 0
        let totalScans = grantedURLs.count
        var lastUIUpdateTime: Date?
        let minUIUpdateInterval: TimeInterval = 0.02 // 控制扫描进度更新频率
        
        // 逐个扫描每个URL
        for (index, url) in grantedURLs.enumerated() {
            self.musicScanner.scanDirectory(url, scanProgressHandler: { progress in
                DispatchQueue.main.async {
                    let currentTime = Date()
                    // 只有在距离上次更新至少1秒时才更新UI
                    if lastUIUpdateTime == nil || currentTime.timeIntervalSince(lastUIUpdateTime!) >= minUIUpdateInterval {
                        // 计算总体进度
                        let overallProgress = (Float(completedScans) + Float(progress)) / Float(totalScans)
                        self.scanProgressView.progress = overallProgress
                        self.scanProgressLabel.text = "\(Int(overallProgress * 100))%"
                        lastUIUpdateTime = currentTime
                    }
                }
            }) { [weak self] (rootDirectoryItem) in
                guard let self = self else { return }
                
                DispatchQueue.main.async {
                    // 如果成功扫描到目录，添加到结果数组
                    if let rootItem = rootDirectoryItem {
                        rootDirectoryItems.append(rootItem)
                        print("[ViewController] [选择器] 成功扫描文件夹\(index+1)/\(totalScans): \(rootItem.name)")
                    } else {
                        print("[ViewController] [选择器] 扫描文件夹\(index+1)/\(totalScans)失败")
                    }
                    
                    // 检查是否所有扫描都已完成
                    completedScans += 1
                    if completedScans == totalScans {
                        // 隐藏进度条
                        self.scanProgressView.isHidden = true
                        self.scanProgressLabel.isHidden = true
                        self.scanningTipsLabel.isHidden = true
                        
                        // 扫描完成
                        if !rootDirectoryItems.isEmpty {
                            // 使用Security-Scoped Bookmarks保存所有文件夹访问权限
                            do {
                                let key = "savedMusicDirectoriesBookmarks"
                                
                                // 创建安全范围的书签数组
                                var bookmarksToSave: [Data] = []
                                print("[ViewController] [持久化] 开始为\(grantedURLs.count)个目录创建书签...")
                                
                                for (index, url) in grantedURLs.enumerated() {
                                    print("[ViewController] [持久化] 正在处理目录\(index+1): \(url.lastPathComponent) (URL: \(url.path))")
                                    
                                    // 在iOS中使用基本选项创建书签
                                    let bookmarkOptions: URL.BookmarkCreationOptions = []
                                    
                                    do {
                                        // 验证URL是否可访问
                                        var isDir: ObjCBool = false
                                        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue {
                                            print("[ViewController] [持久化] URL验证: 是有效的目录")
                                        } else {
                                            print("[ViewController] [持久化] URL验证: 不是有效目录或无法访问")
                                        }
                                        
                                        let bookmarkData = try url.bookmarkData(
                                            options: bookmarkOptions,
                                            includingResourceValuesForKeys: nil,
                                            relativeTo: nil
                                        )
                                        
                                        // 验证书签数据
                                        if !bookmarkData.isEmpty {
                                            bookmarksToSave.append(bookmarkData)
                                            print("[ViewController] [持久化] 成功创建文件夹\(index+1) 的书签，大小: \(bookmarkData.count)字节")
                                        } else {
                                            print("[ViewController] [持久化] 创建文件夹\(index+1) 的书签为空数据")
                                        }
                                    } catch {
                                        print("[ViewController] [持久化] 创建文件夹\(index+1) 的书签失败: \(error.localizedDescription)")
                                        print("[ViewController] [持久化] 错误详情: \(error)")
                                    }
                                }
                                
                                // 创建后的状态确认
                                print("[ViewController] [持久化] 书签创建过程完成，总共创建\(bookmarksToSave.count)/\(grantedURLs.count)个书签")
                                
                                for (idx, bookmark) in bookmarksToSave.enumerated() {
                                    print("[ViewController] [持久化] 待保存书签\(idx+1) - 数据类型: \(type(of: bookmark)), 大小: \(bookmark.count)字节")
                                    // 打印前几个字节的十六进制表示，用于验证数据一致性
                                    let prefixSize = min(10, bookmark.count)
                                    let prefixData = bookmark.subdata(in: 0..<prefixSize)
                                    let hexDescription = prefixData.map { String(format: "%02x", $0) }.joined(separator: " ")
                                    print("[ViewController] [持久化] 待保存书签\(idx+1) - 前10字节: \(hexDescription)")
                                }
                                
                                // 将bookmarkData数组保存到UserDefaults
                                let encodedData = try JSONEncoder().encode(bookmarksToSave)
                                print("[ViewController] [持久化] JSON编码后数据大小: \(encodedData.count)字节")
                                
                                UserDefaults.standard.set(encodedData, forKey: key)
                                UserDefaults.standard.synchronize() // 确保立即保存
                                print("[ViewController] [持久化] 已保存\(bookmarksToSave.count)个音乐目录安全书签到UserDefaults")
                                
                                // 立即验证保存是否成功
                                if let savedData = UserDefaults.standard.data(forKey: key) {
                                    do {
                                        let decodedTest = try JSONDecoder().decode([Data].self, from: savedData)
                                        print("[ViewController] [持久化] 立即验证: 成功读取到\(decodedTest.count)个书签")
                                    } catch {
                                        print("[ViewController] [持久化] 立即验证失败: \(error.localizedDescription)")
                                    }
                                } else {
                                    print("[ViewController] [持久化] 立即验证失败: 无法读取保存的数据")
                                }
                            } catch {
                                print("[ViewController] [持久化] 创建安全书签失败: \(error.localizedDescription)")
                            }
                            
                            // 跳转到音乐列表页面，传入所有根目录项
                            let musicListVC = MusicListViewController(rootDirectoryItems: rootDirectoryItems, scanner: self.musicScanner)
                            let navigationController = UINavigationController(rootViewController: musicListVC)
                            navigationController.modalPresentationStyle = .fullScreen
                            self.present(navigationController, animated: true, completion: nil)
                        } else {
                            // 扫描失败，显示错误提示并恢复选择按钮和副标题，隐藏扫描提示
                            let alert = UIAlertController(title: "扫描失败", message: "无法扫描所选文件夹，请重试", preferredStyle: .alert)
                            alert.addAction(UIAlertAction(title: "确定", style: .default) { [weak self] _ in
                                self?.selectButton.isHidden = false
                                // self?.subtitleLabel.isHidden = false
                                self?.scanningTipsLabel.isHidden = true
                            })
                            self.present(alert, animated: true)
                        }
                    }
                }
            }
        }
    }
    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        // 用户取消了选择
        clearSecurityScopedResources()
        // 确保选择按钮可见，隐藏扫描提示
        selectButton.isHidden = false
        // subtitleLabel.isHidden = false
        scanningTipsLabel.isHidden = true
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // 重新加载主题设置，确保从其他页面返回时主题正确更新
        loadThemeSetting()
        loadSavedTheme()
        themeColor = loadThemeColorSetting()
        selectButton.backgroundColor = themeColor
        scanProgressView.progressTintColor = themeColor
        helpButton.setTitleColor(themeColor, for: .normal)
        updateBlurBackground()
        
        // 根据是否已选择过文件夹控制按钮和扫描提示的可见性
        selectButton.isHidden = hasSelectedDirectory
        // subtitleLabel.isHidden = hasSelectedDirectory
        scanningTipsLabel.isHidden = !hasSelectedDirectory
    }
    
    // 检查并显示相应的对话框
    private func checkAndShowDialogs() {
        // 首先检查是否有保存的书签
        checkSavedBookmarkForMusicFiles { [weak self] hasBookmarkMusicFiles in
            guard let self = self else { return }
            
            if hasBookmarkMusicFiles {
                // 如果有保存的书签且目录下有音乐文件，显示使用上次目录的对话框
                self.showBookmarkDialog()
            } else {
                // 如果没有保存的书签，检查APP专用目录是否有音乐文件
                if self.checkAppMusicFolderForMusicFiles() {
                    // 如果APP专用目录有音乐文件，显示使用本地音乐文件夹的对话框
                    self.showLocalMusicFolderDialog()
                }
                // 如果两者都没有，保持默认显示首页
            }
        }
    }
    
    // 显示使用上次目录的对话框
    private func showBookmarkDialog() {
        let alert = UIAlertController(title: "发现歌曲文件", message: "是否使用上次的目录？", preferredStyle: .alert)
        
        // 确定按钮
        alert.addAction(UIAlertAction(title: "确定", style: .default) { [weak self] _ in
            guard let self = self else { return }
            print("[ViewController] 用户确认使用上次的目录")
            // 直接调用checkForSavedMusicList方法，该方法会自动扫描保存的书签目录
            self.checkForSavedMusicList()
        })
        
        // 取消按钮
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { [weak self] _ in
            guard let self = self else { return }
            print("[ViewController] 用户取消使用上次的目录")
            // 保持在首页，不执行任何操作
        })
        
        // 显示对话框
        self.present(alert, animated: true, completion: nil)
    }
    
    // 显示使用本地音乐文件夹的对话框
    private func showLocalMusicFolderDialog() {
        let alert = UIAlertController(title: "发现歌曲文件", message: "是否使用【本地音乐】目录？", preferredStyle: .alert)
        
        // 确定按钮
        alert.addAction(UIAlertAction(title: "确定", style: .default) { [weak self] _ in
            guard let self = self else { return }
            print("[ViewController] 用户确认使用【本地音乐】文件夹")
            // 调用scanAppMusicFolder方法扫描APP专用目录
            self.scanAppMusicFolder()
        })
        
        // 取消按钮
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { [weak self] _ in
            guard let self = self else { return }
            print("[ViewController] 用户取消使用【本地音乐】文件夹")
            // 保持在首页，不执行任何操作
        })
        
        // 显示对话框
        self.present(alert, animated: true, completion: nil)
    }
    
    // 清理安全范围资源的访问权限
    private func clearSecurityScopedResources() {
        for url in securityScopedResources {
            url.stopAccessingSecurityScopedResource()
        }
        securityScopedResources.removeAll()
    }
    
    // 重置文件夹选择状态（供其他控制器调用）
    public func resetSelectionState() {
        hasSelectedDirectory = false
        clearSecurityScopedResources()
        selectedDirectoryURL = nil
        DispatchQueue.main.async {
            self.selectButton.isHidden = false
            // self.subtitleLabel.isHidden = false
            self.scanningTipsLabel.isHidden = true
        }
    }
    
    // 获取应用程序的Documents目录
    private func getDocumentsDirectory() -> URL {
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
    
    // 获取Documents目录下的所有子目录
    private func getMusicFolders() -> [URL] {
        let documentsDirectory = getDocumentsDirectory()
        var musicFolders: [URL] = []
        
        // 创建说明文件
        createReadmeFileIfNeeded(in: documentsDirectory)
        
        // 获取Documents目录下的所有子目录
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: documentsDirectory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants])
            
            // 筛选出所有目录（跳过文件和说明文件）
            for url in contents {
                let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey])
                if resourceValues.isDirectory == true && url.lastPathComponent != "请将您的音乐文件夹放到这里" {
                    musicFolders.append(url)
                    print("[ViewController] 发现音乐文件夹: \(url.path)")
                }
            }
            
            print("[ViewController] 总共发现 \(musicFolders.count) 个音乐文件夹")
        } catch {
            print("[ViewController] 获取Documents目录内容失败: \(error.localizedDescription)")
        }
        
        return musicFolders
    }
    
    // 创建说明文件
    private func createReadmeFileIfNeeded(in directory: URL) {
        let instructionURL = directory.appendingPathComponent("请将您的音乐文件夹放到这里")
        let fileManager = FileManager.default
        
        if !fileManager.fileExists(atPath: instructionURL.path) {
            do {
                // 创建空白文件
                try Data().write(to: instructionURL)
                print("[ViewController] 创建说明文件: \(instructionURL.path)")
            } catch {
                print("[ViewController] 创建说明文件失败: \(error.localizedDescription)")
            }
        }
    }
    
    // 扫描APP专用文件夹
    private func scanAppMusicFolder() {
        print("[ViewController] [专用文件夹] 开始扫描Documents目录下的所有音乐文件夹...")
        scanningAppFolder = true
        
        // 获取所有音乐文件夹
        let musicFolders = getMusicFolders()
        
        // 如果没有找到音乐文件夹
        if musicFolders.isEmpty {
            print("[ViewController] [专用文件夹] 未发现任何音乐文件夹")
            DispatchQueue.main.async {
                self.scanningAppFolder = false
                // 保持在首页，显示选择按钮
                self.selectButton.isHidden = false
            }
            return
        }
        
        // 显示进度条并隐藏选择按钮
        DispatchQueue.main.async {
            self.scanProgressView.isHidden = false
            self.scanProgressLabel.isHidden = false
            self.scanningTipsLabel.isHidden = false
            self.selectButton.isHidden = true
        }
        
        var scannedItems: [DirectoryItem] = []
        var completedScans = 0
        let totalFolders = musicFolders.count
        
        // 扫描每个音乐文件夹
        for folderURL in musicFolders {
            musicScanner.scanDirectory(folderURL, scanProgressHandler: { [weak self] progress in
                // 计算整体进度
                let folderProgress = Float(completedScans) / Float(totalFolders)
                let currentFolderProgress = Float(progress) / Float(totalFolders)
                let overallProgress = folderProgress + currentFolderProgress
                
                print("[ViewController] [专用文件夹] 扫描进度: \(Int(overallProgress * 100))%")
                
                // 更新进度条UI
                DispatchQueue.main.async {
                    self?.scanProgressView.progress = Float(overallProgress)
                    self?.scanProgressLabel.text = "\(Int(overallProgress * 100))%"
                }
            }) { [weak self] (directoryItem) in
                guard let self = self else { return }
                
                // 将扫描结果添加到数组
                if let item = directoryItem {
                    scannedItems.append(item)
                    print("[ViewController] [专用文件夹] 扫描完成，找到文件夹: \(item.name)，音乐文件数: \(item.musicFiles.count)")
                }
                
                // 增加完成计数
                completedScans += 1
                
                // 检查是否所有文件夹都已扫描完成
                if completedScans == totalFolders {
                    DispatchQueue.main.async {
                        // 隐藏进度条
                        self.scanProgressView.isHidden = true
                        self.scanProgressLabel.isHidden = true
                        self.scanningTipsLabel.isHidden = true
                        self.scanningAppFolder = false
                        
                        // 过滤掉空文件夹
                        let nonEmptyItems = scannedItems.filter { !$0.musicFiles.isEmpty || !$0.subdirectories.isEmpty }
                        
                        if !nonEmptyItems.isEmpty {
                            // 跳转到音乐列表页面，传递所有找到的文件夹
                            let musicListVC = MusicListViewController(rootDirectoryItems: nonEmptyItems, scanner: self.musicScanner)
                            let navigationController = UINavigationController(rootViewController: musicListVC)
                            navigationController.modalPresentationStyle = .fullScreen
                            self.present(navigationController, animated: true, completion: nil)
                        } else {
                            print("[ViewController] [专用文件夹] 所有文件夹都为空，未找到音乐文件")
                            // 保持在首页，显示选择按钮
                            self.selectButton.isHidden = false
                        }
                    }
                }
            }
        }
    }
    
    // 检查URL是否在APP的沙盒目录中

    
    // 检查APP专用目录下是否有音乐文件
    private func checkAppMusicFolderForMusicFiles() -> Bool {
        print("[ViewController] 检查APP专用目录下是否有音乐文件...")
        
        // 获取Documents目录下的所有音乐文件夹
        let musicFolders = getMusicFolders()
        
        // 如果没有音乐文件夹，返回false
        if musicFolders.isEmpty {
            print("[ViewController] APP专用目录下没有音乐文件夹")
            return false
        }
        
        // 遍历所有音乐文件夹，检查是否有音乐文件
        for folderURL in musicFolders {
            do {
                // 获取文件夹内容
                let contents = try FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants])
                
                // 检查是否有音频文件
                for fileURL in contents {
                    // 检查是否为音频文件
                    if musicScanner.isAudioFile(fileURL) {
                        print("[ViewController] 在APP专用目录下发现音乐文件: \(fileURL.lastPathComponent)")
                        return true
                    }
                    
                    // 如果是子目录，递归检查
                    var isDir: ObjCBool = false
                    if FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDir) && isDir.boolValue {
                        // 递归检查子目录
                        if hasAudioFilesInDirectory(fileURL) {
                            return true
                        }
                    }
                }
            } catch {
                print("[ViewController] 检查文件夹内容失败: \(error.localizedDescription)")
            }
        }
        
        print("[ViewController] APP专用目录下没有发现音乐文件")
        return false
    }
    
    // 递归检查目录下是否有音频文件
    private func hasAudioFilesInDirectory(_ directoryURL: URL) -> Bool {
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants])
            
            for fileURL in contents {
                // 检查是否为音频文件
                if musicScanner.isAudioFile(fileURL) {
                    return true
                }
                
                // 如果是子目录，继续递归检查
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDir) && isDir.boolValue {
                    if hasAudioFilesInDirectory(fileURL) {
                        return true
                    }
                }
            }
        } catch {
            print("[ViewController] 递归检查文件夹内容失败: \(error.localizedDescription)")
        }
        
        return false
    }
    
    // 检查保存的书签目录下是否有音乐文件
    private func checkSavedBookmarkForMusicFiles(completion: @escaping (Bool) -> Void) {
        print("[ViewController] 检查保存的书签目录下是否有音乐文件...")
        
        // 从UserDefaults获取保存的书签数据
        let key = "savedMusicDirectoriesBookmarks"
        guard let bookmarkData = UserDefaults.standard.data(forKey: key) else {
            print("[ViewController] 没有找到保存的书签数据")
            completion(false)
            return
        }
        
        do {
            // 解码书签数据
            let bookmarks = try JSONDecoder().decode([Data].self, from: bookmarkData)
            
            // 如果没有书签，返回false
            if bookmarks.isEmpty {
                print("[ViewController] 书签数组为空")
                completion(false)
                return
            }
            
            // 恢复书签并检查每个目录
            var securityScopedResourcesToRelease: [URL] = []
            var hasMusicFiles = false
            
            // 使用DispatchGroup来处理异步操作
            let group = DispatchGroup()
            
            for bookmark in bookmarks {
                group.enter()
                
                // 恢复书签
                do {
                    var isStale = false
                    let url = try URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &isStale)
                    
                    // 检查URL是否需要安全作用域访问
                    if url.startAccessingSecurityScopedResource() {
                        securityScopedResourcesToRelease.append(url)
                    }
                    
                    // 检查目录是否有音频文件
                    if hasAudioFilesInDirectory(url) {
                        hasMusicFiles = true
                        print("[ViewController] 在保存的书签目录中发现音乐文件: \(url.lastPathComponent)")
                    }
                    
                } catch {
                    print("[ViewController] 恢复书签失败: \(error.localizedDescription)")
                }
                
                // 确保group.leave()总是会被调用
                group.leave()
            }
            
            // 当所有书签都检查完成后
            group.notify(queue: .main) {
                // 释放所有安全作用域资源
                for url in securityScopedResourcesToRelease {
                    url.stopAccessingSecurityScopedResource()
                }
                
                print("[ViewController] 书签目录检查完成，是否有音乐文件: \(hasMusicFiles)")
                completion(hasMusicFiles)
            }
        } catch {
            print("[ViewController] 解码书签数据失败: \(error.localizedDescription)")
            completion(false)
        }
    }
    
    // 确保在视图控制器销毁时释放所有权限
    deinit {
        clearSecurityScopedResources()
    }
    
    // 帮助按钮点击事件
    @objc private func helpButtonTapped() {
        showDetailedGuide()
    }
    
    // 显示详细使用说明弹窗
    private func showDetailedGuide() {
        let detailedAlert = UIAlertController(title: "使用说明", message: "如何找到iPhone【本地音乐】的位置：\n\n1. 打开系统的【文件】应用\n2. 点击底部的【浏览】标签\n3. 找到并点击【我的iPhone】\n4. 找到并点击【本地音乐】文件夹\n5. 将音乐文件夹放到此目录下即可自动加载\n*6. 当然您也可以直接打开任意文件夹\n\n注意事项：\n- 卸载APP后若选择清理数据此文件夹将被删除\n- 在您卸载APP前请备份【本地音乐】文件夹", preferredStyle: .alert)
        
        // 设置文字靠左对齐
        detailedAlert.view.tintColor = UIColor.label
        
        // 延迟执行以确保UI元素已加载
        DispatchQueue.main.async {
            // 获取消息标签并设置对齐方式
            let messageLabel = detailedAlert.view.value(forKey: "_messageLabel") as? UILabel
            messageLabel?.textAlignment = .left
        }
        
        detailedAlert.addAction(UIAlertAction(title: "确定", style: .default))
        present(detailedAlert, animated: true, completion: nil)
    }
}

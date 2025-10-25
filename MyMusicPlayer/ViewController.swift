import UIKit
import Foundation

#if canImport(Foundation)
// 尝试使用Foundation框架来模拟持久化功能
#endif


class ViewController: UIViewController, UIDocumentPickerDelegate {
    
    private let musicScanner = MusicScanner()
    private var selectedDirectoryURL: URL?
    private var securityScopedResources: [URL] = [] // 用于跟踪需要保持访问权限的资源
    private var hasSelectedDirectory = false // 跟踪是否已选择过文件夹
    
    // UI元素
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "欢迎使用音乐播放器"
        label.font = UIFont.systemFont(ofSize: 24, weight: .bold)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.text = "请选择一个包含音乐文件的文件夹"
        label.font = UIFont.systemFont(ofSize: 16)
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let selectButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("选择文件夹", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .medium)
        button.backgroundColor = .systemBlue
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 10
        button.clipsToBounds = true
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let progressView: UIProgressView = {
        let progressView = UIProgressView(progressViewStyle: .default)
        progressView.progress = 0
        progressView.isHidden = true
        progressView.translatesAutoresizingMaskIntoConstraints = false
        return progressView
    }()
    
    private let progressLabel: UILabel = {
        let label = UILabel()
        label.text = "0%"
        label.font = UIFont.systemFont(ofSize: 14)
        label.textAlignment = .center
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        // 添加按钮点击事件
        selectButton.addTarget(self, action: #selector(selectButtonTapped), for: .touchUpInside)
        checkForSavedMusicList() // 启用自动检查保存的音乐列表
    }
    
    // 检查是否有已保存的音乐列表
    private func checkForSavedMusicList() {
        print("[持久化] 开始检查保存的音乐列表...")
        let defaults = UserDefaults.standard
        let bookmarkKey = "savedMusicDirectoriesBookmarks"
        
        // 检查UserDefaults中是否存在该键
        if defaults.object(forKey: bookmarkKey) != nil {
            print("[持久化] UserDefaults中存在键 \(bookmarkKey)")
        } else {
            print("[持久化] UserDefaults中不存在键 \(bookmarkKey)")
            return
        }
        
        // 首先尝试从bookmark数据加载（新方法）
        if let savedBookmarksData = defaults.data(forKey: bookmarkKey) {
            print("[持久化] 找到保存的安全书签数据，数据大小: \(savedBookmarksData.count)字节，尝试解析...")
            do {
                // 尝试解析保存的bookmark数据
                let savedBookmarks = try JSONDecoder().decode([Data].self, from: savedBookmarksData)
                print("[持久化] 解析成功，书签数量: \(savedBookmarks.count)")
                
                // 如果书签数组为空，直接返回，不尝试加载
                if savedBookmarks.isEmpty {
                    print("[持久化] 书签数组为空，无需恢复，显示选择文件夹界面")
                    return
                }
                
                for (idx, bookmark) in savedBookmarks.enumerated() {
                    print("[持久化] 加载的书签\(idx+1) - 数据类型: \(type(of: bookmark)), 大小: \(bookmark.count)字节")
                    // 打印前几个字节的十六进制表示，用于验证数据一致性
                    let prefixSize = min(10, bookmark.count)
                    let prefixData = bookmark.subdata(in: 0..<prefixSize)
                    let hexDescription = prefixData.map { String(format: "%02x", $0) }.joined(separator: " ")
                    print("[持久化] 加载的书签\(idx+1) - 前10字节: \(hexDescription)")
                }
                
                if !savedBookmarks.isEmpty {
                    print("[持久化] 发现保存的音乐目录书签，准备恢复访问权限...")
                    
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
                            
                            print("[持久化] 尝试从书签\(index+1) 恢复URL...")
                            let recoveredURL = try URL(resolvingBookmarkData: bookmarkData, options: bookmarkOptions, relativeTo: nil, bookmarkDataIsStale: &isStale)
                            print("[持久化] 成功从书签\(index+1) 恢复URL: \(recoveredURL.lastPathComponent)")
                            
                            // 检查是否是目录
                            var isDir: ObjCBool = false
                            if FileManager.default.fileExists(atPath: recoveredURL.path, isDirectory: &isDir) && isDir.boolValue {
                                // 获取安全访问权限
                                if recoveredURL.startAccessingSecurityScopedResource() {
                                    self.securityScopedResources.append(recoveredURL)
                                    recoveredURLs.append(recoveredURL)
                                    print("[持久化] 成功恢复文件夹\(index+1)访问权限")
                                    
                                    // 如果书签已过时，重新创建它
                                    if isStale {
                                        do {
                                            // 在iOS中使用基本选项创建书签
                                            let updateOptions: URL.BookmarkCreationOptions = []
                                            let newBookmarkData = try recoveredURL.bookmarkData(options: updateOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
                                            updatedBookmarks.append(newBookmarkData)
                                            print("[持久化] 已更新过时的安全书签\(index+1)")
                                        } catch {
                                            print("[持久化] 更新过时书签\(index+1)失败: \(error.localizedDescription)")
                                            updatedBookmarks.append(bookmarkData) // 保留原数据
                                        }
                                    } else {
                                        updatedBookmarks.append(bookmarkData)
                                    }
                                } else {
                                    print("[持久化] 无法获取文件夹\(index+1)的安全访问权限")
                                    hasError = true
                                    updatedBookmarks.append(bookmarkData) // 保留原数据以便后续重试
                                }
                            } else {
                                print("[持久化] 恢复的URL不是有效的目录: \(recoveredURL.lastPathComponent)")
                                hasError = true
                                updatedBookmarks.append(bookmarkData)
                            }
                        } catch {
                            print("[持久化] 从书签\(index+1)恢复URL失败: \(error.localizedDescription)")
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
                            print("[持久化] 保存更新的书签失败: \(error.localizedDescription)")
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
                            self.progressView.isHidden = false
                            self.progressLabel.isHidden = false
                            self.selectButton.isHidden = true
                        }
                        
                        // 逐个扫描每个URL
                        for (index, url) in recoveredURLs.enumerated() {
                            self.musicScanner.scanDirectory(url, progressHandler: { progress in
                                print("[持久化] 扫描文件夹\(index+1)/\(totalScans) 进度: \(Int(progress * 100))%")
                                
                                // 更新进度条UI
                                DispatchQueue.main.async {
                                    // 计算总体进度
                                    let overallProgress = (Float(completedScans) + Float(progress)) / Float(totalScans)
                                    self.progressView.progress = overallProgress
                                    self.progressLabel.text = "\(Int(overallProgress * 100))%"
                                }
                            }) { [weak self] (rootDirectoryItem) in
                                guard let self = self else { return }
                                
                                DispatchQueue.main.async {
                                    // 如果成功扫描到目录，添加到结果数组
                                    if let rootItem = rootDirectoryItem {
                                        rootDirectoryItems.append(rootItem)
                                        print("[持久化] 成功扫描文件夹\(index+1)/\(totalScans): \(rootItem.name)")
                                    } else {
                                        print("[持久化] 扫描文件夹\(index+1)/\(totalScans)失败")
                                    }
                                    
                                    // 检查是否所有扫描都已完成
                                    completedScans += 1
                                    if completedScans == totalScans {
                                        if !rootDirectoryItems.isEmpty {
                                            print("[持久化] 所有文件夹扫描完成，成功扫描到\(rootDirectoryItems.count)个文件夹")
                                            
                                            // 隐藏进度条
                                            self.progressView.isHidden = true
                                            self.progressLabel.isHidden = true
                                            
                                            // 跳转到音乐列表页面，传入所有根目录项
                                            let musicListVC = MusicListViewController(rootDirectoryItems: rootDirectoryItems, scanner: self.musicScanner)
                                            let navigationController = UINavigationController(rootViewController: musicListVC)
                                            navigationController.modalPresentationStyle = .fullScreen
                                            self.present(navigationController, animated: true, completion: nil)
                                        } else {
                                            // 隐藏进度条
                                            self.progressView.isHidden = true
                                            self.progressLabel.isHidden = true
                                            
                                            print("[持久化] 所有文件夹都无法扫描到有效内容")
                                            self.showPermissionErrorAndClearData()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            } catch {
                print("[持久化] 解析书签数据失败: \(error.localizedDescription)")
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
                print("[持久化] 用户取消了重新选择文件夹")
            }
            
            // 添加重新选择按钮，点击后直接打开文件夹选择器
            let reselectAction = UIAlertAction(title: "重新选择", style: .default) { [weak self] _ in
                guard let self = self else { return }
                print("[持久化] 用户选择重新选择文件夹")
                
                // 清理所有保存的数据，包括新格式和旧格式
                let defaults = UserDefaults.standard
                defaults.removeObject(forKey: "savedMusicDirectoriesBookmarks")
                defaults.removeObject(forKey: "savedMusicDirectories")
                print("[持久化] 已清理所有过期的保存数据")
                
                // 打开文件夹选择器
                self.selectButtonTapped()
            }
            
            alert.addAction(cancelAction)
            alert.addAction(reselectAction)
            self.present(alert, animated: true) { 
                print("[持久化] 权限过期提示已显示")
            }
        }
    }
    
    // 尝试从旧的URL字符串格式加载（向后兼容）
    private func tryLoadingFromLegacyFormat() {
        print("[持久化] 尝试从旧格式加载保存的音乐列表...")
        let defaults = UserDefaults.standard
        let legacyKey = "savedMusicDirectories"
        
        if let savedDirectoriesData = defaults.data(forKey: legacyKey) {
            print("[持久化] 找到旧格式保存的数据，尝试解析...")
            if let savedDirectories = try? JSONDecoder().decode([String].self, from: savedDirectoriesData) {
                print("[持久化] 解析成功，目录数量: \(savedDirectories.count)")
                if !savedDirectories.isEmpty {
                    print("[持久化] 发现保存的音乐目录，准备加载...")
                    
                    // 获取保存的文件夹URL
                    if let firstURLString = savedDirectories.first, let savedURL = URL(string: firstURLString) {
                        print("[持久化] 使用保存的路径: \(firstURLString)")
                        
                        // 尝试获取文件夹访问权限
                        print("[持久化] 尝试获取文件夹访问权限...")
                        if savedURL.startAccessingSecurityScopedResource() {
                            self.securityScopedResources.append(savedURL)
                            print("[持久化] 成功获取文件夹访问权限")
                            
                            // 显示进度条并隐藏选择按钮
                            DispatchQueue.main.async {
                                self.progressView.isHidden = false
                                self.progressLabel.isHidden = false
                                self.selectButton.isHidden = true
                            }
                            
                            // 立即开始扫描
                            self.musicScanner.scanDirectory(savedURL, progressHandler: { progress in
                                print("[持久化] 扫描进度: \(Int(progress * 100))%")
                                
                                // 更新进度条UI
                                DispatchQueue.main.async {
                                    self.progressView.progress = Float(progress)
                                    self.progressLabel.text = "\(Int(progress * 100))%"
                                }
                            }) { [weak self] (rootDirectoryItem) in
                                guard let self = self else { return }
                                
                                DispatchQueue.main.async {
                                    // 隐藏进度条
                                    self.progressView.isHidden = true
                                    self.progressLabel.isHidden = true
                                    
                                    if let rootItem = rootDirectoryItem {
                                        print("[持久化] 扫描完成，找到文件夹: \(rootItem.name)")
                                        
                                        // 跳转到音乐列表页面
                                        let musicListVC = MusicListViewController(rootDirectoryItem: rootItem, scanner: self.musicScanner)
                                        let navigationController = UINavigationController(rootViewController: musicListVC)
                                        navigationController.modalPresentationStyle = .fullScreen
                                        self.present(navigationController, animated: true, completion: nil)
                                    }
                                }
                            }
                        } else {
                            print("[持久化] 无法获取文件夹访问权限")
                            self.showPermissionErrorAndClearData()
                        }
                    }
                }
            } else {
                print("[持久化] 解析数据失败")
            }
        } else {
            print("[持久化] 未找到保存的音乐目录数据")
        }
        print("[持久化] 检查保存的音乐列表完成")
    }
    
    // 设置UI
    private func setupUI() {
        view.backgroundColor = .systemBackground
        
        // 添加UI元素
        view.addSubview(titleLabel)
        view.addSubview(subtitleLabel)
        view.addSubview(selectButton)
        view.addSubview(progressView)
        view.addSubview(progressLabel)
        
        // 设置约束
        NSLayoutConstraint.activate([
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
            progressView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            progressView.topAnchor.constraint(equalTo: selectButton.bottomAnchor, constant: 50),
            progressView.widthAnchor.constraint(equalTo: view.widthAnchor, constant: -40),
            
            // 进度标签
            progressLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            progressLabel.topAnchor.constraint(equalTo: progressView.bottomAnchor, constant: 8)
        ])
    }
    
    // 选择文件夹按钮点击事件
    @objc private func selectButtonTapped() {
        let documentPicker = UIDocumentPickerViewController(documentTypes: ["public.folder"], in: .open)
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
                print("[持久化] 成功获取文件夹访问权限: \(url.lastPathComponent)")
            } else {
                print("[持久化] 无法获取文件夹访问权限: \(url.lastPathComponent)")
            }
        }
        
        guard !grantedURLs.isEmpty else {
            return
        }
        
        // 设置多选模式下的选中状态
        hasSelectedDirectory = true
        
        // 显示进度条并隐藏选择按钮
        progressView.isHidden = false
        progressLabel.isHidden = false
        selectButton.isHidden = true
        
        // 逐个扫描所有选中的URL并收集结果
        var rootDirectoryItems: [DirectoryItem] = []
        var completedScans = 0
        let totalScans = grantedURLs.count
        
        // 逐个扫描每个URL
        for (index, url) in grantedURLs.enumerated() {
            self.musicScanner.scanDirectory(url, progressHandler: { progress in
                DispatchQueue.main.async {
                    // 计算总体进度
                    let overallProgress = (Float(completedScans) + Float(progress)) / Float(totalScans)
                    self.progressView.progress = overallProgress
                    self.progressLabel.text = "\(Int(overallProgress * 100))%"
                }
            }) { [weak self] (rootDirectoryItem) in
                guard let self = self else { return }
                
                DispatchQueue.main.async {
                    // 如果成功扫描到目录，添加到结果数组
                    if let rootItem = rootDirectoryItem {
                        rootDirectoryItems.append(rootItem)
                        print("[选择器] 成功扫描文件夹\(index+1)/\(totalScans): \(rootItem.name)")
                    } else {
                        print("[选择器] 扫描文件夹\(index+1)/\(totalScans)失败")
                    }
                    
                    // 检查是否所有扫描都已完成
                    completedScans += 1
                    if completedScans == totalScans {
                        // 隐藏进度条
                        self.progressView.isHidden = true
                        self.progressLabel.isHidden = true
                        
                        // 扫描完成
                        if !rootDirectoryItems.isEmpty {
                            // 使用Security-Scoped Bookmarks保存所有文件夹访问权限
                            do {
                                let key = "savedMusicDirectoriesBookmarks"
                                
                                // 创建安全范围的书签数组
                                var bookmarksToSave: [Data] = []
                                print("[持久化] 开始为\(grantedURLs.count)个目录创建书签...")
                                
                                for (index, url) in grantedURLs.enumerated() {
                                    print("[持久化] 正在处理目录\(index+1): \(url.lastPathComponent) (URL: \(url.path))")
                                    
                                    // 在iOS中使用基本选项创建书签
                                    let bookmarkOptions: URL.BookmarkCreationOptions = []
                                    
                                    do {
                                        // 验证URL是否可访问
                                        var isDir: ObjCBool = false
                                        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue {
                                            print("[持久化] URL验证: 是有效的目录")
                                        } else {
                                            print("[持久化] URL验证: 不是有效目录或无法访问")
                                        }
                                        
                                        let bookmarkData = try url.bookmarkData(
                                            options: bookmarkOptions,
                                            includingResourceValuesForKeys: nil,
                                            relativeTo: nil
                                        )
                                        
                                        // 验证书签数据
                                        if !bookmarkData.isEmpty {
                                            bookmarksToSave.append(bookmarkData)
                                            print("[持久化] 成功创建文件夹\(index+1) 的书签，大小: \(bookmarkData.count)字节")
                                        } else {
                                            print("[持久化] 创建文件夹\(index+1) 的书签为空数据")
                                        }
                                    } catch {
                                        print("[持久化] 创建文件夹\(index+1) 的书签失败: \(error.localizedDescription)")
                                        print("[持久化] 错误详情: \(error)")
                                    }
                                }
                                
                                // 创建后的状态确认
                                print("[持久化] 书签创建过程完成，总共创建\(bookmarksToSave.count)/\(grantedURLs.count)个书签")
                                
                                for (idx, bookmark) in bookmarksToSave.enumerated() {
                                    print("[持久化] 待保存书签\(idx+1) - 数据类型: \(type(of: bookmark)), 大小: \(bookmark.count)字节")
                                    // 打印前几个字节的十六进制表示，用于验证数据一致性
                                    let prefixSize = min(10, bookmark.count)
                                    let prefixData = bookmark.subdata(in: 0..<prefixSize)
                                    let hexDescription = prefixData.map { String(format: "%02x", $0) }.joined(separator: " ")
                                    print("[持久化] 待保存书签\(idx+1) - 前10字节: \(hexDescription)")
                                }
                                
                                // 将bookmarkData数组保存到UserDefaults
                                let encodedData = try JSONEncoder().encode(bookmarksToSave)
                                print("[持久化] JSON编码后数据大小: \(encodedData.count)字节")
                                
                                UserDefaults.standard.set(encodedData, forKey: key)
                                UserDefaults.standard.synchronize() // 确保立即保存
                                print("[持久化] 已保存\(bookmarksToSave.count)个音乐目录安全书签到UserDefaults")
                                
                                // 立即验证保存是否成功
                                if let savedData = UserDefaults.standard.data(forKey: key) {
                                    do {
                                        let decodedTest = try JSONDecoder().decode([Data].self, from: savedData)
                                        print("[持久化] 立即验证: 成功读取到\(decodedTest.count)个书签")
                                    } catch {
                                        print("[持久化] 立即验证失败: \(error.localizedDescription)")
                                    }
                                } else {
                                    print("[持久化] 立即验证失败: 无法读取保存的数据")
                                }
                            } catch {
                                print("[持久化] 创建安全书签失败: \(error.localizedDescription)")
                            }
                            
                            // 跳转到音乐列表页面，传入所有根目录项
                            let musicListVC = MusicListViewController(rootDirectoryItems: rootDirectoryItems, scanner: self.musicScanner)
                            let navigationController = UINavigationController(rootViewController: musicListVC)
                            navigationController.modalPresentationStyle = .fullScreen
                            self.present(navigationController, animated: true, completion: nil)
                        } else {
                            // 扫描失败，显示错误提示
                            let alert = UIAlertController(title: "扫描失败", message: "无法扫描所选文件夹，请重试", preferredStyle: .alert)
                            alert.addAction(UIAlertAction(title: "确定", style: .default))
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
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // 根据是否已选择过文件夹控制按钮可见性
        selectButton.isHidden = hasSelectedDirectory
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
        }
    }
    
    // 确保在视图控制器销毁时释放所有权限
    deinit {
        clearSecurityScopedResources()
    }
}

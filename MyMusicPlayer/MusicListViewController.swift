import UIKit
import AVFoundation

class MusicListViewController: UIViewController, UITableViewDelegate, UITableViewDataSource, UIDocumentPickerDelegate {
    
    private var rootDirectoryItems: [DirectoryItem] = [] // 修改为支持多个根目录
    private var scanner: MusicScanner
    private let musicPlayer = MusicPlayer.shared
    
    // 扁平化的显示列表（用于表格视图）
    private var displayItems: [Any] = []
    
    // UI元素
    private let tableView: UITableView = {
        let tableView = UITableView()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        return tableView
    }()
    
    private let bottomBanner: UIView = {
        let view = UIView()
        view.backgroundColor = .secondarySystemBackground
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()
    
    private let songTitleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let previousButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "backward.fill"), for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let playPauseButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "play.fill"), for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let nextButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "forward.fill"), for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let playModeButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "repeat"), for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let rangeLockButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "lock"), for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let progressSlider: UISlider = {
        let slider = UISlider()
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.minimumValue = 0.0
        slider.maximumValue = 1.0
        slider.minimumTrackTintColor = .systemBlue
        slider.maximumTrackTintColor = .systemGray3
        slider.thumbTintColor = .systemBlue
        
        // 自定义滑块外观为小方块
        let thumbImage = UIGraphicsImageRenderer(size: CGSize(width: 12, height: 12)).image { context in
            UIColor.systemBlue.setFill()
            let rect = CGRect(x: 0, y: 0, width: 12, height: 12)
            context.fill(rect)
        }
        slider.setThumbImage(thumbImage, for: .normal)
        slider.setThumbImage(thumbImage, for: .highlighted)
        
        return slider
    }()
    
    // 保留原来的进度视图作为背景指示器（可选，默认隐藏）
    private let progressView: UIProgressView = {
        let progressView = UIProgressView()
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.isHidden = true // 隐藏，因为我们将使用滑块
        return progressView
    }()
    
    private let timeLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let totalTimeLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private var updateTimer: Timer? = nil
    private var securityScopedResources: [URL] = [] // 用于跟踪需要保持访问权限的资源
    
    // 初始化方法 - 单目录版本
    init(rootDirectoryItem: DirectoryItem, scanner: MusicScanner) {
        self.rootDirectoryItems = [rootDirectoryItem] // 将单个目录添加到数组中
        self.scanner = scanner
        super.init(nibName: nil, bundle: nil)
    }
    
    // 初始化方法 - 多目录版本
    init(rootDirectoryItems: [DirectoryItem], scanner: MusicScanner) {
        self.rootDirectoryItems = rootDirectoryItems
        self.scanner = scanner
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        updateDisplayItems()
        
        // 设置导航栏
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "刷新", style: .plain, target: self, action: #selector(refreshButtonTapped))
        
        // 注册通知
        NotificationCenter.default.addObserver(self, selector: #selector(updatePlayerUI), name: .musicPlayerPlaybackStateChanged, object: nil)
        // 注册进度更新通知，用于同步播放页拖动后的进度
        NotificationCenter.default.addObserver(self, selector: #selector(handleProgressUpdateNotification), name: .musicPlayerProgressChanged, object: nil)
    }
    
    // 设置UI
    private func setupUI() {
        title = "音乐列表"
        view.backgroundColor = .systemBackground
        
        // 设置导航栏左侧加号按钮，用于添加新文件夹
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addFolderButtonTapped))
        
        // 设置导航栏右侧刷新按钮
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .refresh, target: self, action: #selector(refreshButtonTapped))
        
        // 添加表格视图
        view.addSubview(tableView)
        tableView.delegate = self
        tableView.dataSource = self
        
        // 添加底部横幅
        view.addSubview(bottomBanner)
        bottomBanner.addSubview(songTitleLabel)
        bottomBanner.addSubview(progressView) // 保留但隐藏
        bottomBanner.addSubview(progressSlider) // 添加滑块
        bottomBanner.addSubview(timeLabel)
        bottomBanner.addSubview(totalTimeLabel)
        
        // 创建合并的按钮容器StackView，实现居中显示
        let allButtonsStack = UIStackView(arrangedSubviews: [previousButton, playPauseButton, nextButton, playModeButton, rangeLockButton])
        allButtonsStack.translatesAutoresizingMaskIntoConstraints = false
        allButtonsStack.axis = .horizontal
        allButtonsStack.alignment = .center
        allButtonsStack.distribution = .equalSpacing
        allButtonsStack.spacing = 20
        
        // 设置歌曲标题文本靠左对齐
        songTitleLabel.textAlignment = .left
        
        bottomBanner.addSubview(allButtonsStack)
        
        // 设置约束 - 全部使用百分比实现自适应布局
        NSLayoutConstraint.activate([
            // 表格视图
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: bottomBanner.topAnchor),
            
            // 底部横幅 - 高度改为屏幕高度的15%
            bottomBanner.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBanner.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBanner.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            bottomBanner.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.15), // 改为15%
            
            // 歌曲标题 - 靠左显示
            songTitleLabel.leadingAnchor.constraint(equalTo: bottomBanner.leadingAnchor, constant: 16), // 固定16像素左侧边距
            songTitleLabel.widthAnchor.constraint(lessThanOrEqualTo: bottomBanner.widthAnchor, constant: -32), // 两侧各16像素边距
            songTitleLabel.topAnchor.constraint(equalTo: bottomBanner.topAnchor, constant: 12), // 固定12像素顶部边距
            
            // 进度条（隐藏）
            progressView.leadingAnchor.constraint(equalTo: bottomBanner.leadingAnchor, constant: 16), // 固定16像素左侧边距
            progressView.trailingAnchor.constraint(equalTo: bottomBanner.trailingAnchor, constant: -16), // 固定16像素右侧边距
            progressView.topAnchor.constraint(equalTo: songTitleLabel.bottomAnchor, constant: 8), // 固定8像素顶部边距
            
            // 进度滑块和时间 - 第二部分
            progressSlider.leadingAnchor.constraint(equalTo: bottomBanner.leadingAnchor, constant: 16), // 固定16像素左侧边距
            progressSlider.trailingAnchor.constraint(equalTo: bottomBanner.trailingAnchor, constant: -16), // 固定16像素右侧边距
            progressSlider.topAnchor.constraint(equalTo: songTitleLabel.bottomAnchor, constant: 8), // 固定8像素顶部边距
            
            // 时间标签
            timeLabel.leadingAnchor.constraint(equalTo: bottomBanner.leadingAnchor, constant: 16), // 固定16像素左侧边距
            timeLabel.topAnchor.constraint(equalTo: progressSlider.bottomAnchor, constant: 4), // 固定4像素顶部边距
            
            totalTimeLabel.trailingAnchor.constraint(equalTo: bottomBanner.trailingAnchor, constant: -16), // 固定16像素右侧边距
            totalTimeLabel.topAnchor.constraint(equalTo: progressSlider.bottomAnchor, constant: 4), // 固定4像素顶部边距
            
            // 合并的按钮组 - 居中显示
            allButtonsStack.centerXAnchor.constraint(equalTo: bottomBanner.centerXAnchor),
            allButtonsStack.bottomAnchor.constraint(equalTo: bottomBanner.bottomAnchor, constant: -8), // 固定8像素底部边距
            allButtonsStack.widthAnchor.constraint(lessThanOrEqualTo: bottomBanner.widthAnchor, constant: -32), // 两侧各16像素边距
            
            // 按钮大小约束 - 使用底部横幅高度的百分比
            previousButton.widthAnchor.constraint(equalTo: bottomBanner.heightAnchor, multiplier: 0.5),
            previousButton.heightAnchor.constraint(equalTo: bottomBanner.heightAnchor, multiplier: 0.5),
            
            playPauseButton.widthAnchor.constraint(equalTo: bottomBanner.heightAnchor, multiplier: 0.5),
            playPauseButton.heightAnchor.constraint(equalTo: bottomBanner.heightAnchor, multiplier: 0.5),
            
            nextButton.widthAnchor.constraint(equalTo: bottomBanner.heightAnchor, multiplier: 0.5),
            nextButton.heightAnchor.constraint(equalTo: bottomBanner.heightAnchor, multiplier: 0.5),
            
            playModeButton.widthAnchor.constraint(equalTo: bottomBanner.heightAnchor, multiplier: 0.5),
            playModeButton.heightAnchor.constraint(equalTo: bottomBanner.heightAnchor, multiplier: 0.5),
            
            rangeLockButton.widthAnchor.constraint(equalTo: bottomBanner.heightAnchor, multiplier: 0.5),
            rangeLockButton.heightAnchor.constraint(equalTo: bottomBanner.heightAnchor, multiplier: 0.5)
        ])
        
        // 添加底部横幅的点击手势
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(bottomBannerTapped))
        bottomBanner.addGestureRecognizer(tapGesture)
        bottomBanner.isUserInteractionEnabled = true
        
        setupPlayerObservers()
        setupButtonActions()
    }
    
    // 设置按钮点击事件
    private func setupButtonActions() {
        previousButton.addTarget(self, action: #selector(previousButtonTapped), for: .touchUpInside)
        playPauseButton.addTarget(self, action: #selector(playPauseButtonTapped), for: .touchUpInside)
        nextButton.addTarget(self, action: #selector(nextButtonTapped), for: .touchUpInside)
        playModeButton.addTarget(self, action: #selector(playModeButtonTapped), for: .touchUpInside)
        rangeLockButton.addTarget(self, action: #selector(rangeLockButtonTapped), for: .touchUpInside)
        progressSlider.addTarget(self, action: #selector(progressSliderValueChanged(_:)), for: .valueChanged)
        progressSlider.addTarget(self, action: #selector(progressSliderTouchBegan(_:)), for: .touchDown)
        progressSlider.addTarget(self, action: #selector(progressSliderTouchEnded(_:)), for: .touchUpInside)
        progressSlider.addTarget(self, action: #selector(progressSliderTouchEnded(_:)), for: .touchUpOutside)
    }
    
    // 设置播放器观察者
    private func setupPlayerObservers() {
        // 监听当前播放音乐的变化
        NotificationCenter.default.addObserver(self, selector: #selector(updatePlayerUI), name: NSNotification.Name("PlayerStateChanged"), object: nil)
        
        // 初始化进度条和时间标签
        progressView.progress = 0
        progressView.tintColor = .systemBlue
        progressView.trackTintColor = .systemGray3
        
        // 初始化进度滑块
        progressSlider.value = 0
        
        // 配置时间标签
        timeLabel.font = UIFont.systemFont(ofSize: 12)
        timeLabel.textColor = .secondaryLabel
        timeLabel.text = "00:00"
        
        totalTimeLabel.font = UIFont.systemFont(ofSize: 12)
        totalTimeLabel.textColor = .secondaryLabel
        totalTimeLabel.text = "00:00"
    }
    
    // 更新显示列表（扁平化树状结构）
    private func updateDisplayItems() {
        displayItems.removeAll()
        
        // 显示所有根目录项
        for rootDirectoryItem in rootDirectoryItems {
            addDirectoryToDisplayItems(rootDirectoryItem, level: 0)
        }
        
        tableView.reloadData()
    }
    
    // 递归添加目录到显示列表
    private func addDirectoryToDisplayItems(_ directory: DirectoryItem, level: Int) {
        // 添加目录项
        displayItems.append((directory, level))
        
        // 如果目录展开，添加其子项
        if directory.isExpanded {
            // 先添加子目录
            for subdirectory in directory.subdirectories {
                addDirectoryToDisplayItems(subdirectory, level: level + 1)
            }
            
            // 再添加音乐文件
            for musicFile in directory.musicFiles {
                displayItems.append((musicFile, level + 1))
            }
        }
    }
    
    // 刷新按钮点击事件
    @objc private func refreshButtonTapped() {
        if rootDirectoryItems.isEmpty {
            // 如果没有根目录，显示提示
            let alert = UIAlertController(title: "提示", message: "没有可刷新的文件夹", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "确定", style: .default))
            present(alert, animated: true)
            return
        }
        
        // 显示加载提示
        let alert = UIAlertController(title: "扫描中", message: "正在重新扫描所有文件夹...", preferredStyle: .alert)
        present(alert, animated: true)
        
        // 重新扫描所有根目录
        var totalDirectories = rootDirectoryItems.count
        var completedScans = 0
        
        for (index, rootItem) in rootDirectoryItems.enumerated() {
            guard let directoryURL = rootItem.url else { continue }
            
            scanner.scanDirectory(directoryURL, progressHandler: { _ in
                // 进度更新可以在这里处理
            }, completionHandler: { [weak self] newRootItem in
                guard let self = self else { return }
                
                DispatchQueue.main.async {
                    // 更新对应的根目录项
                    if let newRoot = newRootItem {
                        self.rootDirectoryItems[index].subdirectories = newRoot.subdirectories
                        self.rootDirectoryItems[index].musicFiles = newRoot.musicFiles
                    }
                    
                    completedScans += 1
                    
                    // 如果所有扫描都完成了
                    if completedScans == totalDirectories {
                        // 关闭加载提示
                        alert.dismiss(animated: true)
                        
                        // 更新显示
                        self.updateDisplayItems()
                        
                        // 更新播放列表 - 收集所有根目录的音乐文件
                        var allMusicFiles: [MusicItem] = []
                        for rootItem in self.rootDirectoryItems {
                            allMusicFiles.append(contentsOf: self.scanner.getAllMusicFiles(from: rootItem))
                        }
                        self.musicPlayer.setPlaylist(allMusicFiles)
                        
                        // 显示成功提示
                        let successAlert = UIAlertController(title: "成功", message: "所有文件夹已重新扫描", preferredStyle: .alert)
                        successAlert.addAction(UIAlertAction(title: "确定", style: .default))
                        self.present(successAlert, animated: true)
                    }
                }
            })
        }
    }
    
    // 底部横幅点击事件
    @objc private func bottomBannerTapped() {
        guard let currentMusic = musicPlayer.currentMusic else { return }
        
        // 跳转到播放详情页面
        let playerVC = MusicPlayerViewController(music: currentMusic)
        navigationController?.pushViewController(playerVC, animated: true)
    }
    
    // 底部控制按钮事件
    @objc private func previousButtonTapped() {
        musicPlayer.playPrevious()
        // 立即更新UI
        updatePlayerUI()
    }
    
    @objc private func playPauseButtonTapped() {
        musicPlayer.togglePlayPause()
        updatePlayerUI()
        
        // 根据播放状态启动或停止计时器
        if musicPlayer.isPlaying {
            startUpdateTimer()
        } else {
            stopUpdateTimer()
        }
    }
    
    @objc private func nextButtonTapped() {
        musicPlayer.playNext()
        // 立即更新UI
        updatePlayerUI()
    }
    
    @objc private func playModeButtonTapped() {
        musicPlayer.togglePlayMode()
        updatePlayModeButtonImage()
    }
    
    @objc private func rangeLockButtonTapped() {
        musicPlayer.toggleRangeLock()
        updateRangeLockButtonImage()
    }
    
    private var isSeeking = false // 标记是否正在手动拖动滑块
    
    // 更新播放器UI
    @objc private func updatePlayerUI() {
        if let currentMusic = musicPlayer.currentMusic {
            bottomBanner.isHidden = false
            songTitleLabel.text = currentMusic.title
            totalTimeLabel.text = formatTime(musicPlayer.totalTime)
            
            // 更新播放/暂停按钮
            let imageName = musicPlayer.isPlaying ? "pause.fill" : "play.fill"
            playPauseButton.setImage(UIImage(systemName: imageName), for: .normal)
            
            // 更新播放模式按钮
            updatePlayModeButtonImage()
            
            // 更新范围锁定按钮
            updateRangeLockButtonImage()
            
            // 只有当用户不在拖动滑块时才更新UI
            if !isSeeking {
                // 更新进度条和滑块
                let progress = Float(musicPlayer.currentTime / musicPlayer.totalTime)
                progressView.progress = progress
                progressSlider.value = progress
                timeLabel.text = formatTime(musicPlayer.currentTime)
            }
            
            // 根据播放状态启动或停止计时器
            if musicPlayer.isPlaying {
                startUpdateTimer()
            } else {
                stopUpdateTimer()
            }
        } else {
            bottomBanner.isHidden = true
            stopUpdateTimer()
        }
    }
    
    // 更新播放模式按钮图标
    private func updatePlayModeButtonImage() {
        var imageName: String
        
        switch musicPlayer.playMode {
        case .sequence:
            imageName = "repeat"
        case .repeatOne:
            imageName = "repeat.1"
        case .shuffle:
            imageName = "shuffle"
        }
        
        playModeButton.setImage(UIImage(systemName: imageName), for: .normal)
    }
    
    // 启动更新计时器
    private func startUpdateTimer() {
        stopUpdateTimer() // 先停止之前的计时器
        updateTimer = Timer.scheduledTimer(timeInterval: 0.1, target: self, selector: #selector(updateProgress), userInfo: nil, repeats: true)
    }
    
    // 停止更新计时器
    private func stopUpdateTimer() {
        updateTimer?.invalidate()
        updateTimer = nil
    }
    
    // 更新进度
    @objc private func updateProgress() {
        // 只有当用户不在拖动滑块时才更新UI
        if !isSeeking {
            let progress = musicPlayer.currentTime / musicPlayer.totalTime
            progressView.progress = Float(progress)
            progressSlider.value = Float(progress) // 同时更新滑块位置
            timeLabel.text = formatTime(musicPlayer.currentTime)
        }
    }
    
    // 格式化时间
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time / 60)
        let seconds = Int(time.truncatingRemainder(dividingBy: 60))
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    // 进度滑块值变化事件处理
    @objc private func progressSliderValueChanged(_ slider: UISlider) {
        // 更新时间标签显示
        let seekTime = TimeInterval(slider.value) * musicPlayer.totalTime
        timeLabel.text = formatTime(seekTime)
    }
    
    // 滑块触摸开始
    @objc private func progressSliderTouchBegan(_ slider: UISlider) {
        isSeeking = true
        // 暂停自动更新计时器
        stopUpdateTimer()
    }
    
    // 滑块触摸结束，执行跳转
    @objc private func progressSliderTouchEnded(_ slider: UISlider) {
        isSeeking = false
        // 执行跳转
        let seekTime = TimeInterval(slider.value) * musicPlayer.totalTime
        musicPlayer.seek(to: seekTime)
        
        // 立即更新UI并恢复计时器
        progressView.progress = slider.value
        timeLabel.text = formatTime(seekTime)
        
        // 发送通知，通知播放页更新滑块位置
        NotificationCenter.default.post(name: .musicPlayerProgressChanged, object: nil, userInfo: ["currentTime": seekTime, "totalTime": musicPlayer.totalTime])
        
        if musicPlayer.isPlaying {
            startUpdateTimer()
        }
    }
    
    // 更新范围锁定按钮图标
    private func updateRangeLockButtonImage() {
        let imageName = musicPlayer.isRangeLocked ? "lock.fill" : "lock.open.fill"
        rangeLockButton.setImage(UIImage(systemName: imageName), for: .normal)
    }
    
    // 添加文件夹按钮点击事件
    @objc private func addFolderButtonTapped() {
        let documentPicker = UIDocumentPickerViewController(documentTypes: ["public.folder"], in: .open)
        documentPicker.delegate = self
        documentPicker.allowsMultipleSelection = false
        
        // iOS 14及以上支持文件夹选择
        if #available(iOS 14, *) {
            documentPicker.directoryURL = nil
        }
        
        present(documentPicker, animated: true, completion: nil)
    }
    
    // UIDocumentPickerDelegate 方法
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        
        // 请求访问权限
        guard url.startAccessingSecurityScopedResource() else {
            let alert = UIAlertController(title: "错误", message: "无法获取文件夹访问权限", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "确定", style: .default))
            present(alert, animated: true)
            return
        }
        
        // 将权限记录添加到数组中以便稍后释放
        securityScopedResources.append(url)
        
        // 显示加载提示
        let alert = UIAlertController(title: "扫描中", message: "正在扫描文件夹...", preferredStyle: .alert)
        present(alert, animated: true)
        
        // 扫描文件夹内容
        scanner.scanDirectory(url, progressHandler: { _ in
            // 进度更新可以在这里处理
        }, completionHandler: { [weak self] newRootItem in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                // 关闭加载提示
                alert.dismiss(animated: true)
                
                // 检查是否已存在同名文件夹
                if let newRoot = newRootItem {
                    let isDuplicate = self.rootDirectoryItems.contains {
                        $0.name == newRoot.name && $0.url == newRoot.url
                    }
                    
                    if !isDuplicate {
                        // 添加到根目录列表
                        self.rootDirectoryItems.append(newRoot)
                        print("成功添加新的根目录: \(newRoot.name)")
                        
                        // 更新UI显示
                        self.updateDisplayItems()
                        
                        // 显示成功提示
                        let successAlert = UIAlertController(title: "成功", message: "文件夹已添加到列表", preferredStyle: .alert)
                        successAlert.addAction(UIAlertAction(title: "确定", style: .default))
                        self.present(successAlert, animated: true)
                    } else {
                        // 显示重复提示
                        let duplicateAlert = UIAlertController(title: "提示", message: "该文件夹已存在", preferredStyle: .alert)
                        duplicateAlert.addAction(UIAlertAction(title: "确定", style: .default))
                        self.present(duplicateAlert, animated: true)
                    }
                } else {
                    // 扫描失败
                    let errorAlert = UIAlertController(title: "错误", message: "无法扫描文件夹内容", preferredStyle: .alert)
                    errorAlert.addAction(UIAlertAction(title: "确定", style: .default))
                    self.present(errorAlert, animated: true)
                }
            }
        })
    }
    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        // 用户取消了选择
        // 不需要特殊处理
    }
    
    // 清理安全范围资源的访问权限
    private func clearSecurityScopedResources() {
        for url in securityScopedResources {
            url.stopAccessingSecurityScopedResource()
        }
        securityScopedResources.removeAll()
    }
    
    // 处理进度更新通知
    @objc private func handleProgressUpdateNotification(_ notification: Notification) {
        // 如果不是正在拖动滑块，则更新滑块位置
        if !isSeeking {
            if let userInfo = notification.userInfo,
               let currentTime = userInfo["currentTime"] as? TimeInterval,
               let totalTime = userInfo["totalTime"] as? TimeInterval,
               totalTime > 0 {
                
                let progress = currentTime / totalTime
                progressSlider.value = Float(progress)
                timeLabel.text = formatTime(currentTime)
                totalTimeLabel.text = formatTime(totalTime)
            }
        }
    }
    
    // 析构函数
    deinit {
        stopUpdateTimer()
        clearSecurityScopedResources()
        NotificationCenter.default.removeObserver(self)
    }
    
    // UITableViewDataSource 方法
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return displayItems.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        
        // 获取显示项
        let item = displayItems[indexPath.row]
        
        // 根据类型设置单元格内容
        if let (directory, level) = item as? (DirectoryItem, Int) {
            // 目录项
            var content = cell.defaultContentConfiguration()
            content.text = directory.name
            content.textProperties.font = UIFont.boldSystemFont(ofSize: 16)
            
            // 设置缩进
            cell.indentationLevel = level
            cell.indentationWidth = 20
            
            // 设置附件视图（展开/折叠指示器）
            if !directory.subdirectories.isEmpty || !directory.musicFiles.isEmpty {
                let imageName = directory.isExpanded ? "chevron.down" : "chevron.right"
                cell.accessoryType = .none
                cell.accessoryView = UIImageView(image: UIImage(systemName: imageName))
            } else {
                cell.accessoryView = nil
                cell.accessoryType = .none
            }
            
            cell.contentConfiguration = content
        } else if let (musicFile, level) = item as? (MusicItem, Int) {
            // 音乐文件项
            var content = cell.defaultContentConfiguration()
            content.text = musicFile.title
            
            // 如果是当前播放的歌曲，高亮显示
            if let currentMusic = musicPlayer.currentMusic, currentMusic.url == musicFile.url {
                content.textProperties.font = UIFont.boldSystemFont(ofSize: 16)
                content.textProperties.color = .systemBlue
            } else {
                content.textProperties.font = UIFont.systemFont(ofSize: 16)
                content.textProperties.color = .label
            }
            
            // 设置缩进
            cell.indentationLevel = level
            cell.indentationWidth = 20
            cell.accessoryView = nil
            cell.accessoryType = .none
            
            cell.contentConfiguration = content
        }
        
        return cell
    }
    
    // UITableViewDelegate 方法
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let item = displayItems[indexPath.row]
        
        if let (directory, _) = item as? (DirectoryItem, Int) {
            // 点击的是目录，切换展开/折叠状态
            directory.isExpanded.toggle()
            updateDisplayItems()
        } else if let (musicFile, _) = item as? (MusicItem, Int) {
            // 点击的是音乐文件，开始播放
            // 收集所有根目录的音乐文件
            var allMusicFiles: [MusicItem] = []
            for rootItem in rootDirectoryItems {
                allMusicFiles.append(contentsOf: scanner.getAllMusicFiles(from: rootItem))
            }
            musicPlayer.setPlaylist(allMusicFiles)
            
            if let index = allMusicFiles.firstIndex(where: { $0.url == musicFile.url }) {
                musicPlayer.playMusic(musicFile, at: index)
                updatePlayerUI()
            }
        }
    }
}

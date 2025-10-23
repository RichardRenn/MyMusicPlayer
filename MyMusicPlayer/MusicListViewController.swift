import UIKit
import AVFoundation

class MusicListViewController: UIViewController, UITableViewDelegate, UITableViewDataSource, UIDocumentPickerDelegate {
    
    private var rootDirectoryItems: [DirectoryItem] = [] // 修改为支持多个根目录
    private var scanner: MusicScanner
    private let musicPlayer = MusicPlayer.shared
    
    // 扁平化的显示列表（用于表格视图）
    private var displayItems: [Any] = []
    
    // 歌词相关
    private var isLyricsExpanded = false
    private var lyrics: [LyricsLine] = []
    private var currentLyricIndex = 0
    
    // UI元素
    // 展开/收起歌词按钮
    private let expandButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "chevron.up"), for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.backgroundColor = .secondarySystemBackground
        
        // 创建上窄下宽的梯形形状
        let shapeLayer = CAShapeLayer()
        button.layer.mask = shapeLayer
        
        return button
    }()
    
    // 歌词面板
    private let lyricsPanel: UIView = {
        let view = UIView()
        view.backgroundColor = .secondarySystemBackground
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()
    
    // 歌词表格视图
    private let lyricsTableView: UITableView = {
        let tableView = UITableView()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "lyricCell")
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        return tableView
    }()
    
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
        
        // 自定义滑块外观为圆角矩形
        let thumbImage = UIGraphicsImageRenderer(size: CGSize(width: 12, height: 12)).image { context in
            let ctx = context.cgContext
            ctx.setFillColor(UIColor.systemBlue.cgColor)
            let rect = CGRect(x: 0, y: 0, width: 12, height: 12)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 6)
            ctx.addPath(path.cgPath)
            ctx.fillPath()
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
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // 当视图布局更新时重新设置梯形形状
        updateButtonTrapezoidShape()
        
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
        
        // 添加歌词面板
        view.addSubview(lyricsPanel)
        lyricsPanel.addSubview(lyricsTableView)
        lyricsTableView.delegate = self
        lyricsTableView.dataSource = self
        lyricsTableView.register(UITableViewCell.self, forCellReuseIdentifier: "lyricCell")
        
        // 添加展开/收起按钮
        view.addSubview(expandButton)
        expandButton.isHidden = true // 初始状态隐藏展开按钮
        
        // 添加底部横幅
        view.addSubview(bottomBanner)
        bottomBanner.addSubview(songTitleLabel)
        bottomBanner.addSubview(progressView) // 保留但隐藏
        bottomBanner.addSubview(progressSlider) // 添加滑块
        bottomBanner.addSubview(timeLabel)
        bottomBanner.addSubview(totalTimeLabel)
        
        // 创建合并的按钮容器StackView，实现居中显示
        let allButtonsStack = UIStackView(arrangedSubviews: [playModeButton, previousButton, playPauseButton, nextButton, rangeLockButton])
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
            tableView.bottomAnchor.constraint(equalTo: expandButton.topAnchor),
            
            // 展开/收起按钮
            expandButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            expandButton.widthAnchor.constraint(equalToConstant: 80),
            expandButton.heightAnchor.constraint(equalToConstant: 20),
            expandButton.bottomAnchor.constraint(equalTo: bottomBanner.topAnchor),
            
            // 歌词面板
            lyricsPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            lyricsPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            lyricsPanel.bottomAnchor.constraint(equalTo: expandButton.topAnchor),
            lyricsPanel.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.3), // 歌词面板高度为屏幕的30%
            
            // 歌词表格视图
            lyricsTableView.topAnchor.constraint(equalTo: lyricsPanel.topAnchor),
            lyricsTableView.leadingAnchor.constraint(equalTo: lyricsPanel.leadingAnchor),
            lyricsTableView.trailingAnchor.constraint(equalTo: lyricsPanel.trailingAnchor),
            lyricsTableView.bottomAnchor.constraint(equalTo: lyricsPanel.bottomAnchor),
            
            // 底部横幅 - 高度改为屏幕高度的15%
            bottomBanner.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBanner.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBanner.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            bottomBanner.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.15), // 改为15%
            
            // 歌曲标题 - 靠左显示
            songTitleLabel.leadingAnchor.constraint(equalTo: bottomBanner.leadingAnchor, constant: 16), // 固定16像素左侧边距
            songTitleLabel.widthAnchor.constraint(lessThanOrEqualTo: bottomBanner.widthAnchor, constant: -32), // 两侧各16像素边距
            songTitleLabel.topAnchor.constraint(equalTo: bottomBanner.topAnchor, constant: 12), // 固定12像素顶部边距
            
            // 合并的按钮组 - 居中显示
            allButtonsStack.centerXAnchor.constraint(equalTo: bottomBanner.centerXAnchor),
            allButtonsStack.bottomAnchor.constraint(equalTo: bottomBanner.bottomAnchor, constant: -2), // 固定2像素底部边距
            
            // 进度条（隐藏）- 相对于按钮组上方定位
            progressView.leadingAnchor.constraint(equalTo: bottomBanner.leadingAnchor, constant: 16), // 固定16像素左侧边距
            progressView.trailingAnchor.constraint(equalTo: bottomBanner.trailingAnchor, constant: -16), // 固定16像素右侧边距
            progressView.bottomAnchor.constraint(equalTo: allButtonsStack.topAnchor, constant: -8), // 按钮组上方8像素
            
            // 进度滑块 - 相对于按钮组上方定位
            progressSlider.leadingAnchor.constraint(equalTo: bottomBanner.leadingAnchor, constant: 16), // 固定16像素左侧边距
            progressSlider.trailingAnchor.constraint(equalTo: bottomBanner.trailingAnchor, constant: -16), // 固定16像素右侧边距
            progressSlider.bottomAnchor.constraint(equalTo: allButtonsStack.topAnchor, constant: -8), // 按钮组上方8像素
            
            // 时间标签 - 相对于进度滑块下方定位
            timeLabel.leadingAnchor.constraint(equalTo: bottomBanner.leadingAnchor, constant: 16), // 固定16像素左侧边距
            timeLabel.topAnchor.constraint(equalTo: progressSlider.bottomAnchor, constant: 4), // 固定4像素顶部边距
            
            totalTimeLabel.trailingAnchor.constraint(equalTo: bottomBanner.trailingAnchor, constant: -16), // 固定16像素右侧边距
            totalTimeLabel.topAnchor.constraint(equalTo: progressSlider.bottomAnchor, constant: 4), // 固定4像素顶部边距
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
        
        // 设置展开/收起按钮的点击事件
        expandButton.addTarget(self, action: #selector(toggleLyricsPanel), for: .touchUpInside)
        
        // 初始化梯形形状
        updateButtonTrapezoidShape()
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
        
        // 重新扫描所有根目录
        let totalDirectories = rootDirectoryItems.count
        var completedScans = 0
        
        // 用于跟踪每个目录的扫描进度
        var directoryProgresses: [Int: Double] = [:]
        // 初始化所有目录的进度为0
        for index in 0..<totalDirectories {
            directoryProgresses[index] = 0.0
        }
        
        // 记录最后更新进度的目录索引
        var lastUpdatedDirectoryIndex = 0
        
        // 创建并显示加载提示 - 只创建一次
        let progressAlert = UIAlertController(
            title: "扫描中", 
            message: "正在扫描...", 
            preferredStyle: .alert
        )
        
        // 显示alert
        present(progressAlert, animated: true)
        
        // 更新进度的函数
        func updateProgress() {
            DispatchQueue.main.async {
                // 计算总进度（所有目录进度的平均值）
                let totalProgress = directoryProgresses.values.reduce(0, +) / Double(totalDirectories)
                let progressPercentage = Int(totalProgress * 100)
                
                // 获取最后更新的文件夹名称
                let currentFolderName = self.rootDirectoryItems[lastUpdatedDirectoryIndex].name
                
                // 动态更新alert的消息内容，不重新创建alert
                progressAlert.message = "正在扫描[\(currentFolderName)]\n进度: \(progressPercentage)%"
            }
        }
        
        for (index, rootItem) in rootDirectoryItems.enumerated() {
            guard let directoryURL = rootItem.url else { 
                // 如果URL为空，将其标记为完成
                        completedScans += 1
                        if completedScans == totalDirectories {
                            DispatchQueue.main.async {
                                // 关闭进度alert并更新数据
                                progressAlert.dismiss(animated: true, completion: {
                                    // 更新显示
                                    self.updateDisplayItems()
                                    
                                    // 更新播放列表
                                    var allMusicFiles: [MusicItem] = []
                                    for rootItem in self.rootDirectoryItems {
                                        allMusicFiles.append(contentsOf: self.scanner.getAllMusicFiles(from: rootItem))
                                    }
                                    self.musicPlayer.setPlaylist(allMusicFiles)
                                })
                            }
                        }
                continue 
            }
            
            scanner.scanDirectory(directoryURL, progressHandler: { [weak self] progress in
                guard let self = self else { return }
                
                // 更新当前目录的进度
                directoryProgresses[index] = progress
                // 更新最后活动的目录索引
                lastUpdatedDirectoryIndex = index
                
                // 更新进度显示
                updateProgress()
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
                        // 关闭进度alert并更新数据
                        progressAlert.dismiss(animated: true, completion: {
                            // 更新显示
                            self.updateDisplayItems()
                            
                            // 更新播放列表 - 收集所有根目录的音乐文件
                            var allMusicFiles: [MusicItem] = []
                            for rootItem in self.rootDirectoryItems {
                                allMusicFiles.append(contentsOf: self.scanner.getAllMusicFiles(from: rootItem))
                            }
                            self.musicPlayer.setPlaylist(allMusicFiles)
                        })
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
    
    // 切换歌词面板展开/收起状态
    @objc private func toggleLyricsPanel() {
        isLyricsExpanded.toggle()
        
        // 更新按钮图标
        let imageName = isLyricsExpanded ? "chevron.down" : "chevron.up"
        expandButton.setImage(UIImage(systemName: imageName), for: .normal)
        
        // 显示或隐藏歌词面板
        lyricsPanel.isHidden = !isLyricsExpanded
        
        // 更新梯形形状方向
        updateButtonTrapezoidShape()
        
        // 加载歌词
        if isLyricsExpanded {
            loadLyrics()
        }
    }
    
    // 更新按钮的梯形形状
    private func updateButtonTrapezoidShape() {
        guard let maskLayer = expandButton.layer.mask as? CAShapeLayer else { return }
        
        let bounds = expandButton.bounds
        let path = UIBezierPath()
        
        if isLyricsExpanded {
            // 上宽下窄的梯形
            let topWidth = bounds.width
            let bottomWidth = bounds.width * 0.5
            let offset = (topWidth - bottomWidth) / 2
            
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: topWidth, y: 0))
            path.addLine(to: CGPoint(x: topWidth - offset, y: bounds.height))
            path.addLine(to: CGPoint(x: offset, y: bounds.height))
            path.close()
        } else {
            // 上窄下宽的梯形
            let topWidth = bounds.width * 0.5
            let bottomWidth = bounds.width
            let offset = (bottomWidth - topWidth) / 2
            
            path.move(to: CGPoint(x: offset, y: 0))
            path.addLine(to: CGPoint(x: bottomWidth - offset, y: 0))
            path.addLine(to: CGPoint(x: bottomWidth, y: bounds.height))
            path.addLine(to: CGPoint(x: 0, y: bounds.height))
            path.close()
        }
        
        maskLayer.path = path.cgPath
    }
    
    // 加载歌词
    private func loadLyrics() {
        print("===== 开始加载歌词 =====")
        // 清空之前的歌词
        lyrics.removeAll()
        currentLyricIndex = 0
        
        if let currentMusic = musicPlayer.currentMusic {
            // 先尝试使用已有的歌词缓存
            if !currentMusic.lyrics.isEmpty {
                print("使用已缓存的歌词数据，共\(currentMusic.lyrics.count)行")
                lyrics = currentMusic.lyrics
            } 
            // 尝试从文件加载歌词
            else if let lyricsURL = currentMusic.lyricsURL {
                print("尝试从文件加载歌词: \(lyricsURL.lastPathComponent)")
                print("歌词文件路径: \(lyricsURL.path)")
                
                // 检查文件是否存在
                if FileManager.default.fileExists(atPath: lyricsURL.path) {
                    print("歌词文件存在")
                } else {
                    print("歌词文件不存在于路径: \(lyricsURL.path)")
                }
                
                // 为歌词加载添加访问权限处理
                var shouldStopAccess = false
                if lyricsURL.startAccessingSecurityScopedResource() {
                    shouldStopAccess = true
                    print("成功获取歌词文件临时访问权限")
                } else {
                    print("未能获取歌词文件临时访问权限")
                }
                
                // 尝试解析歌词
                if let parsedLyrics = LyricsParser.parseLyrics(from: lyricsURL) {
                    if !parsedLyrics.isEmpty {
                        lyrics = parsedLyrics
                        currentMusic.lyrics = parsedLyrics // 缓存解析结果
                        print("成功解析歌词，共\(lyrics.count)行")
                    } else {
                        print("歌词文件存在但内容为空或格式错误")
                    }
                } else {
                    print("解析歌词文件失败")
                }
                
                // 释放访问权限
                if shouldStopAccess {
                    lyricsURL.stopAccessingSecurityScopedResource()
                    print("已释放歌词文件访问权限")
                }
            } else {
                print("音乐项没有关联的歌词URL")
            }
            
            // 如果没有歌词，添加默认文本
            if lyrics.isEmpty {
                if currentMusic.lyricsURL != nil {
                    // 有歌词文件路径但未能成功加载
                    lyrics.append(LyricsLine(time: 0, text: "无法加载歌词文件"))
                    lyrics.append(LyricsLine(time: 1, text: "可能是文件格式不兼容或权限问题"))
                } else {
                    // 没有歌词文件
                    lyrics.append(LyricsLine(time: 0, text: "暂无歌词"))
                }
            }
        } else {
            // 默认歌词
            lyrics = [
                LyricsLine(time: 0, text: "暂无歌曲播放"),
                LyricsLine(time: 5, text: "请选择一首歌曲开始播放")
            ]
        }
        
        // 刷新表格显示
        print("准备刷新表格，当前歌词数量: \(lyrics.count)")
        DispatchQueue.main.async {
            print("在主线程执行表格刷新")
            self.lyricsTableView.reloadData()
            
            // 初始滚动到第一行歌词
            if !self.lyrics.isEmpty {
                self.lyricsTableView.scrollToRow(at: IndexPath(row: 0, section: 0), at: .middle, animated: false)
            }
            
            print("表格刷新完成")
        }
        
        print("===== 歌词加载结束 =====")
    }
    
    // 更新播放器UI
    @objc private func updatePlayerUI() {
        if let currentMusic = musicPlayer.currentMusic {
            bottomBanner.isHidden = false
            expandButton.isHidden = false // 有歌曲播放时显示展开按钮
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
            
            // 如果歌词面板是展开的，重新加载歌词
            if isLyricsExpanded {
                loadLyrics()
            }
            
            // 刷新表格视图，使当前播放的歌曲高亮显示
            tableView.reloadData()
        } else {
            bottomBanner.isHidden = true
            expandButton.isHidden = true // 没有歌曲播放时隐藏展开按钮
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
            
            // 更新歌词高亮显示
            updateCurrentLyricIndex()
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
        if tableView == lyricsTableView {
            return lyrics.count
        }
        return displayItems.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if tableView == lyricsTableView {
            // 处理歌词单元格
            let cell = tableView.dequeueReusableCell(withIdentifier: "lyricCell", for: indexPath)
            cell.backgroundColor = .clear
            
            let lyricLine = lyrics[indexPath.row]
            var content = cell.defaultContentConfiguration()
            content.text = lyricLine.text
            
            // 设置文本居中对齐
            content.textProperties.alignment = .center
            
            // 当前播放的歌词行高亮显示
            if indexPath.row == currentLyricIndex {
                content.textProperties.font = UIFont.systemFont(ofSize: 18, weight: .bold)
                content.textProperties.color = .systemBlue
            } else {
                content.textProperties.font = UIFont.systemFont(ofSize: 16)
                content.textProperties.color = .secondaryLabel
            }
            
            cell.contentConfiguration = content
            cell.textLabel?.textAlignment = .center
            cell.selectionStyle = .none
            
            return cell
        }
        
        // 处理音乐列表单元格
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
            
            // 检查是否有歌词，如果有则显示歌词图标
            if musicFile.lyricsURL != nil || !musicFile.lyrics.isEmpty {
                let lyricIcon = UIImageView(image: UIImage(systemName: "music.note"))
                lyricIcon.tintColor = .systemBlue
                lyricIcon.contentMode = .scaleAspectFit
                lyricIcon.frame = CGRect(x: 0, y: 0, width: 20, height: 20)
                cell.accessoryView = lyricIcon
            } else {
                cell.accessoryView = nil
            }
            
            cell.accessoryType = .none
            
            cell.contentConfiguration = content
        }
        
        return cell
    }
    
    // UITableViewDelegate 方法
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        // 检查是否是歌词表格
        if tableView == lyricsTableView {
            // 歌词表格不需要处理点击事件
            return
        }
        
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
                
                // 如果歌词面板是展开的，重新加载歌词
                if isLyricsExpanded {
                    loadLyrics()
                }
            }
        }
    }
    

    
    // 处理歌词滚动，高亮当前播放的歌词
    private func updateCurrentLyricIndex() {
        guard !lyrics.isEmpty, musicPlayer.isPlaying else { return }
        
        let newIndex = LyricsParser.getCurrentLyricIndex(time: musicPlayer.currentTime, lyrics: lyrics)
        
        if newIndex != currentLyricIndex {
            currentLyricIndex = newIndex
            
            // 如果歌词面板是展开的，更新UI
            if isLyricsExpanded {
                DispatchQueue.main.async {
                    self.lyricsTableView.reloadData()
                    
                    // 自动滚动到当前歌词
                    let indexPath = IndexPath(row: self.currentLyricIndex, section: 0)
                    self.lyricsTableView.scrollToRow(at: indexPath, at: .middle, animated: true)
                }
            }
        }
    }
    
    // 在updateProgress方法中调用updateCurrentLyricIndex来更新歌词显示
    
    // MARK: - 左滑删除功能实现
    
    // 允许编辑表格行
    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return tableView != lyricsTableView
    }
    
    // 设置编辑样式
    func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        if tableView == lyricsTableView {
            return .none
        }
        
        // 对于文件夹项允许删除
        if displayItems[indexPath.row] is (DirectoryItem, Int) {
            return .delete
        } else {
            return .none
        }
    }
    
    // 执行删除操作
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete && tableView != lyricsTableView {
            if let directoryItem = displayItems[indexPath.row] as? (DirectoryItem, Int) {
                let directory = directoryItem.0
                
                // 检查当前播放的歌曲是否在要删除的文件夹中
                if let currentMusic = musicPlayer.currentMusic {
                    // 递归检查歌曲的父目录链是否包含要删除的目录
                    var currentParent = currentMusic.parentDirectory
                    while let parent = currentParent {
                        if parent.url?.path == directory.url?.path {
                            // 当前播放的歌曲在要删除的文件夹中，停止播放
                            musicPlayer.stop()
                            break
                        }
                        currentParent = parent.parentDirectory
                    }
                }
                
                // 关闭安全范围资源访问
                directory.url?.stopAccessingSecurityScopedResource()
                
                var removed = false
                
                // 检查是否是根目录项
                if directory.parentDirectory == nil {
                    // 从根目录列表中找到并移除对应项
                    if let indexToRemove = rootDirectoryItems.firstIndex(where: { $0.url?.path == directory.url?.path }) {
                        rootDirectoryItems.remove(at: indexToRemove)
                        removed = true
                    }
                } else {
                    // 是子目录，从父目录的子目录列表中移除
                    if let parent = directory.parentDirectory {
                        if let indexToRemove = parent.subdirectories.firstIndex(where: { $0.url?.path == directory.url?.path }) {
                            parent.subdirectories.remove(at: indexToRemove)
                            removed = true
                        }
                    }
                }
                
                if removed {
                    // 使用安全的方式更新表格 - 直接调用updateDisplayItems刷新整个表格
                    updateDisplayItems()
                    
                    // 更新播放列表 - 收集所有根目录的音乐文件
                    var allMusicFiles: [MusicItem] = []
                    for rootItem in rootDirectoryItems {
                        allMusicFiles.append(contentsOf: scanner.getAllMusicFiles(from: rootItem))
                    }
                    musicPlayer.setPlaylist(allMusicFiles)
                    
                    // 检查是否所有文件夹都被删除，如果是则返回选择文件夹页面
                    if rootDirectoryItems.isEmpty {
                        // 停止播放
                        musicPlayer.stop()
                        
                        // 延迟一点时间确保界面更新后再返回
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            // 获取根视图控制器并调用重置方法
                            if let presentingVC = self.presentingViewController as? ViewController {
                                presentingVC.resetSelectionState()
                            }
                            // 关闭当前导航控制器，返回到选择文件夹页面
                            self.dismiss(animated: true, completion: nil)
                        }
                    }
                }
            }
        }
    }
    
    // 自定义删除按钮标题
    func tableView(_ tableView: UITableView, titleForDeleteConfirmationButtonForRowAt indexPath: IndexPath) -> String? {
        return "删除"
    }
}

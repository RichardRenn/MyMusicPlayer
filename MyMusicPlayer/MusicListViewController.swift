import UIKit

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
    
    private let progressView: UIProgressView = {
        let progressView = UIProgressView()
        progressView.translatesAutoresizingMaskIntoConstraints = false
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
        setupPlayerObservers()
        setupButtonActions()
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
        bottomBanner.addSubview(progressView)
        bottomBanner.addSubview(timeLabel)
        bottomBanner.addSubview(totalTimeLabel)
        bottomBanner.addSubview(previousButton)
        bottomBanner.addSubview(playPauseButton)
        bottomBanner.addSubview(nextButton)
        bottomBanner.addSubview(playModeButton)
        bottomBanner.addSubview(rangeLockButton)
        
        // 设置约束
        NSLayoutConstraint.activate([
            // 表格视图
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: bottomBanner.topAnchor),
            
            // 底部横幅
            bottomBanner.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBanner.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBanner.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            bottomBanner.heightAnchor.constraint(equalToConstant: 100),
            
            // 歌曲标题
            songTitleLabel.leadingAnchor.constraint(equalTo: bottomBanner.leadingAnchor, constant: 16),
            songTitleLabel.trailingAnchor.constraint(equalTo: bottomBanner.trailingAnchor, constant: -16),
            songTitleLabel.topAnchor.constraint(equalTo: bottomBanner.topAnchor, constant: 8),
            
            // 进度条
            progressView.leadingAnchor.constraint(equalTo: bottomBanner.leadingAnchor, constant: 16),
            progressView.trailingAnchor.constraint(equalTo: bottomBanner.trailingAnchor, constant: -16),
            progressView.topAnchor.constraint(equalTo: songTitleLabel.bottomAnchor, constant: 4),
            
            // 时间标签
            timeLabel.leadingAnchor.constraint(equalTo: bottomBanner.leadingAnchor, constant: 16),
            timeLabel.topAnchor.constraint(equalTo: progressView.bottomAnchor, constant: 2),
            
            totalTimeLabel.trailingAnchor.constraint(equalTo: bottomBanner.trailingAnchor, constant: -16),
            totalTimeLabel.topAnchor.constraint(equalTo: progressView.bottomAnchor, constant: 2),
            
            // 按钮容器
            previousButton.leadingAnchor.constraint(equalTo: bottomBanner.leadingAnchor, constant: 32),
            previousButton.centerYAnchor.constraint(equalTo: bottomBanner.centerYAnchor, constant: 10),
            previousButton.widthAnchor.constraint(equalToConstant: 40),
            previousButton.heightAnchor.constraint(equalToConstant: 40),
            
            playPauseButton.leadingAnchor.constraint(equalTo: previousButton.trailingAnchor, constant: 24),
            playPauseButton.centerYAnchor.constraint(equalTo: bottomBanner.centerYAnchor, constant: 10),
            playPauseButton.widthAnchor.constraint(equalToConstant: 50),
            playPauseButton.heightAnchor.constraint(equalToConstant: 50),
            
            nextButton.leadingAnchor.constraint(equalTo: playPauseButton.trailingAnchor, constant: 24),
            nextButton.centerYAnchor.constraint(equalTo: bottomBanner.centerYAnchor, constant: 10),
            nextButton.widthAnchor.constraint(equalToConstant: 40),
            nextButton.heightAnchor.constraint(equalToConstant: 40),
            
            playModeButton.trailingAnchor.constraint(equalTo: rangeLockButton.leadingAnchor, constant: -24),
            playModeButton.centerYAnchor.constraint(equalTo: bottomBanner.centerYAnchor, constant: 10),
            playModeButton.widthAnchor.constraint(equalToConstant: 40),
            playModeButton.heightAnchor.constraint(equalToConstant: 40),
            
            rangeLockButton.trailingAnchor.constraint(equalTo: bottomBanner.trailingAnchor, constant: -32),
            rangeLockButton.centerYAnchor.constraint(equalTo: bottomBanner.centerYAnchor, constant: 10),
            rangeLockButton.widthAnchor.constraint(equalToConstant: 40),
            rangeLockButton.heightAnchor.constraint(equalToConstant: 40)
        ])
        
        // 添加底部横幅的点击手势
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(bottomBannerTapped))
        bottomBanner.addGestureRecognizer(tapGesture)
        bottomBanner.isUserInteractionEnabled = true
    }
    
    // 设置按钮点击事件
    private func setupButtonActions() {
        previousButton.addTarget(self, action: #selector(previousButtonTapped), for: .touchUpInside)
        playPauseButton.addTarget(self, action: #selector(playPauseButtonTapped), for: .touchUpInside)
        nextButton.addTarget(self, action: #selector(nextButtonTapped), for: .touchUpInside)
        playModeButton.addTarget(self, action: #selector(playModeButtonTapped), for: .touchUpInside)
        rangeLockButton.addTarget(self, action: #selector(rangeLockButtonTapped), for: .touchUpInside)
    }
    
    // 设置播放器观察者
    private func setupPlayerObservers() {
        // 监听当前播放音乐的变化
        NotificationCenter.default.addObserver(self, selector: #selector(updatePlayerUI), name: NSNotification.Name("PlayerStateChanged"), object: nil)
        
        // 初始化进度条和时间标签
        progressView.progress = 0
        progressView.tintColor = .systemBlue
        progressView.trackTintColor = .systemGray3
        
        // 配置时间标签
        timeLabel.font = UIFont.systemFont(ofSize: 12)
        timeLabel.textColor = .secondaryLabel
        timeLabel.text = "00:00"
        
        totalTimeLabel.font = UIFont.systemFont(ofSize: 12)
        totalTimeLabel.textColor = .secondaryLabel
        totalTimeLabel.text = "00:00"
        
        // 添加进度条点击手势
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(progressViewTapped(_:)))
        progressView.addGestureRecognizer(tapGesture)
        progressView.isUserInteractionEnabled = true
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
            
            // 更新进度条
            progressView.progress = Float(musicPlayer.currentTime / musicPlayer.totalTime)
            timeLabel.text = formatTime(musicPlayer.currentTime)
            
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
        let progress = musicPlayer.currentTime / musicPlayer.totalTime
        progressView.progress = Float(progress)
        timeLabel.text = formatTime(musicPlayer.currentTime)
    }
    
    // 格式化时间
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time / 60)
        let seconds = Int(time.truncatingRemainder(dividingBy: 60))
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    // 进度条点击事件处理
    @objc private func progressViewTapped(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: progressView)
        let progress = location.x / progressView.bounds.width
        let seekTime = TimeInterval(progress) * musicPlayer.totalTime
        musicPlayer.seek(to: seekTime)
        
        // 立即更新UI
        progressView.progress = Float(progress)
        timeLabel.text = formatTime(seekTime)
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
    
    // 析构函数
    deinit {
        stopUpdateTimer()
        clearSecurityScopedResources()
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
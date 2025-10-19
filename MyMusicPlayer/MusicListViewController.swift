import UIKit

class MusicListViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {
    
    private let rootDirectoryItem: DirectoryItem
    private let scanner: MusicScanner
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
    
    // 初始化方法
    init(rootDirectoryItem: DirectoryItem, scanner: MusicScanner) {
        self.rootDirectoryItem = rootDirectoryItem
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
        
        // 设置导航栏右侧刷新按钮
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .refresh, target: self, action: #selector(refreshButtonTapped))
        
        // 添加表格视图
        view.addSubview(tableView)
        tableView.delegate = self
        tableView.dataSource = self
        
        // 添加底部横幅
        view.addSubview(bottomBanner)
        bottomBanner.addSubview(songTitleLabel)
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
            bottomBanner.heightAnchor.constraint(equalToConstant: 80),
            
            // 歌曲标题
            songTitleLabel.leadingAnchor.constraint(equalTo: bottomBanner.leadingAnchor, constant: 16),
            songTitleLabel.trailingAnchor.constraint(equalTo: bottomBanner.trailingAnchor, constant: -16),
            songTitleLabel.topAnchor.constraint(equalTo: bottomBanner.topAnchor, constant: 8),
            
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
    }
    
    // 更新显示列表（扁平化树状结构）
    private func updateDisplayItems() {
        displayItems.removeAll()
        addDirectoryToDisplayItems(rootDirectoryItem, level: 0)
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
        guard let directoryURL = rootDirectoryItem.url else { return }
        
        // 显示加载提示
        let alert = UIAlertController(title: "扫描中", message: "正在重新扫描文件夹...", preferredStyle: .alert)
        present(alert, animated: true)
        
        // 重新扫描
        scanner.scanDirectory(directoryURL, progressHandler: { _ in
            // 进度更新可以在这里处理
        }, completionHandler: { [weak self] newRootItem in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                // 关闭加载提示
                alert.dismiss(animated: true)
                
                // 更新显示
                if let newRoot = newRootItem {
                    // 更新根目录项
                    self.rootDirectoryItem.subdirectories = newRoot.subdirectories
                    self.rootDirectoryItem.musicFiles = newRoot.musicFiles
                    self.updateDisplayItems()
                    
                    // 更新播放列表
                    let allMusicFiles = self.scanner.getAllMusicFiles(from: newRoot)
                    self.musicPlayer.setPlaylist(allMusicFiles)
                }
            }
        })
    }
    
    // 底部横幅点击事件
    @objc private func bottomBannerTapped() {
        guard let currentMusic = musicPlayer.currentMusic else { return }
        
        // 跳转到播放详情页面
        let playerVC = MusicPlayerViewController(music: currentMusic)
        playerVC.modalPresentationStyle = .fullScreen
        present(playerVC, animated: true)
    }
    
    // 底部控制按钮事件
    @objc private func previousButtonTapped() {
        musicPlayer.playPrevious()
    }
    
    @objc private func playPauseButtonTapped() {
        musicPlayer.togglePlayPause()
        updatePlayerUI()
    }
    
    @objc private func nextButtonTapped() {
        musicPlayer.playNext()
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
            
            // 更新播放/暂停按钮
            let imageName = musicPlayer.isPlaying ? "pause.fill" : "play.fill"
            playPauseButton.setImage(UIImage(systemName: imageName), for: .normal)
            
            // 更新播放模式按钮
            updatePlayModeButtonImage()
            
            // 更新范围锁定按钮
            updateRangeLockButtonImage()
        } else {
            bottomBanner.isHidden = true
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
    
    // 更新范围锁定按钮图标
    private func updateRangeLockButtonImage() {
        let imageName = musicPlayer.isRangeLocked ? "lock.fill" : "lock.open.fill"
        rangeLockButton.setImage(UIImage(systemName: imageName), for: .normal)
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
            let allMusicFiles = scanner.getAllMusicFiles(from: rootDirectoryItem)
            musicPlayer.setPlaylist(allMusicFiles)
            
            if let index = allMusicFiles.firstIndex(where: { $0.url == musicFile.url }) {
                musicPlayer.playMusic(musicFile, at: index)
                updatePlayerUI()
            }
        }
    }
}
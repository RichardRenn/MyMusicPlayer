import UIKit
import AVFoundation

// 导入Foundation以支持持久化功能
import Foundation

// 主题模式枚举
enum ThemeMode: Int, Codable {
    case light = 0    // 浅色模式
    case dark = 1     // 深色模式
    case system = 2   // 跟随系统
    
    // 切换到下一个主题模式
    func next() -> ThemeMode {
        switch self {
        case .light:
            return .dark
        case .dark:
            return .system
        case .system:
            return .light
        }
    }
    
    // 获取对应的图标名称
    var iconName: String {
        switch self {
        case .light:
            return "sun.min.fill"      // 太阳图标
        case .dark:
            return "moon.stars.fill"   // 月亮
        case .system:
            return "a.circle"          // 跟随系统
        }
    }
}

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
    private var lyricsLoaded = false // 跟踪是否已经加载了歌词
    private var currentPlayingMusicURL: URL? // 跟踪当前播放的歌曲URL
    
    // 主题相关
    private var currentThemeMode: ThemeMode = .system
    
    // 文件夹图标显示控制
    private var showFolderIcons: Bool = true { 
        didSet {
            saveFolderIconSetting()
        }
    }
    
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
        view.backgroundColor = .secondarySystemBackground.withAlphaComponent(0.98) // 与底部横幅统一背景色
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        view.layer.cornerRadius = 12
        view.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner] // 只设置顶部两个角为圆角
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
        slider.minimumTrackTintColor = .tintColor
        slider.maximumTrackTintColor = .systemGray3
        slider.thumbTintColor = .tintColor
        
        // 自定义滑块外观为圆角矩形
        let thumbImage = UIGraphicsImageRenderer(size: CGSize(width: 12, height: 12)).image { context in
            let ctx = context.cgContext
            ctx.setFillColor(UIColor.tintColor.cgColor)
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
        
        // 启用应用生命周期通知
        registerAppLifeCycleNotifications()
        
        // 监听从歌词详情页返回的通知
        NotificationCenter.default.addObserver(self, selector: #selector(handleMusicPlayerReturn), name: NSNotification.Name("MusicPlayerReturned"), object: nil)
    }
    
    // 注册应用生命周期通知
    private func registerAppLifeCycleNotifications() {
        // 应用进入后台通知
        NotificationCenter.default.addObserver(self, selector: #selector(saveMusicListOnBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        
        // 应用即将终止通知
        NotificationCenter.default.addObserver(self, selector: #selector(saveMusicListOnTerminate), name: UIApplication.willTerminateNotification, object: nil)
    }
    
    // 处理从歌词详情页返回的通知
    @objc private func handleMusicPlayerReturn() {
        // 如果歌词是展开状态，则立即刷新位置
        if isLyricsExpanded {
            updateLyricDisplay()
        }
    }
    
    // 保存音乐列表
    private func saveMusicList() {
        // 简化的持久化功能，保存目录URL的书签数据
        // 复制当前目录列表到局部变量，避免在异步操作中访问已释放的self
        let currentRootDirectoryItems = self.rootDirectoryItems
        
        DispatchQueue.global().async {
            let defaults = UserDefaults.standard
            let key = "savedMusicDirectoriesBookmarks"
            
            // 检查是否有目录需要保存
            if currentRootDirectoryItems.isEmpty {
                // 没有目录时，从UserDefaults中删除数据键
                defaults.removeObject(forKey: key)
                print("[持久化] 所有目录已删除，清空保存的数据")
                return
            }
            
            // 创建书签数据数组
            var bookmarksToSave = [Data]()
            
            // 遍历所有根目录项
            for item in currentRootDirectoryItems {
                if let directoryURL = item.url {
                    do {
                        // 创建书签 (iOS中不需要withSecurityScope选项)
                        let bookmark = try directoryURL.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
                        bookmarksToSave.append(bookmark)
                    } catch {
                        // 捕获错误但继续执行
                        continue
                    }
                }
            }
            
            // 保存书签数据
            do {
                let data = try JSONEncoder().encode(bookmarksToSave)
                defaults.set(data, forKey: key)
                print("[持久化] 保存了\(bookmarksToSave.count)个目录书签数据")
            } catch {
                // 捕获编码错误
                print("[持久化] 保存失败")
            }
        }
    }
    
    // 应用进入后台时保存音乐列表
    @objc private func saveMusicListOnBackground() {
        print("📱 [MusicListVC] 应用进入后台，触发自动保存...")
        saveMusicList()
    }
    
    // 应用即将终止时保存音乐列表
    @objc private func saveMusicListOnTerminate() {
        print("📱 [MusicListVC] 应用即将终止，触发自动保存...")
        saveMusicList()
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
        title = "音乐库"
        view.backgroundColor = .systemBackground
        
        // 加载保存的设置
        loadThemeSetting()
        loadFolderIconSetting()
        applyTheme()
        
        // 设置导航栏左侧按钮（加号按钮和刷新按钮），受眼镜开关控制
        updateLeftBarButtonsVisibility()
        
        // 设置导航栏右侧按钮（眼镜图标按钮和主题切换按钮）
        
        // 初始化右侧导航栏按钮
        updateRightBarButtonsVisibility()
        
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
        view.bringSubviewToFront(expandButton) // 确保展开按钮在横幅上方
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
        
        // 为底部横幅添加悬浮样式和圆角
        bottomBanner.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.98) // 添加半透明背景色
        // bottomBanner.layer.shadowColor = UIColor.black.cgColor // 阴影颜色为黑色。
        // bottomBanner.layer.shadowOffset = CGSize(width: 0, height: -1) // 阴影向上偏移 2 个点（height = -2），因为 banner 在底部，要让阴影“向上”显示
        // bottomBanner.layer.shadowOpacity = 0.1 // 阴影不透明度为 0.1（很淡的阴影）
        // bottomBanner.layer.shadowRadius = 4 // 阴影的模糊半径
        // bottomBanner.layer.masksToBounds = true // 保留阴影。（如果设为 true，圆角之外的部分会被裁掉，阴影也会被剪掉，看不见了。）
        bottomBanner.layer.cornerRadius = 12 // 让视图的角变圆，半径是 12
        bottomBanner.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner] // 初始状态设置为四个角都是圆角，后续会根据歌词展开状态动态调整
        
        // 设置约束 - 全部使用百分比实现自适应布局
        NSLayoutConstraint.activate([
            // 表格视图 - 底部留出空间给悬浮横幅
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            // 展开/收起按钮
            expandButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            expandButton.widthAnchor.constraint(equalToConstant: 80),
            expandButton.heightAnchor.constraint(equalToConstant: 20),
            expandButton.bottomAnchor.constraint(equalTo: bottomBanner.topAnchor, constant: 20), // 调整位置
            
            // 歌词面板 - 与底部横幅融合
            lyricsPanel.leadingAnchor.constraint(equalTo: bottomBanner.leadingAnchor),
            lyricsPanel.trailingAnchor.constraint(equalTo: bottomBanner.trailingAnchor),
            lyricsPanel.bottomAnchor.constraint(equalTo: bottomBanner.topAnchor), // 直接连接到底部横幅顶部
            lyricsPanel.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.3), // 歌词面板高度为屏幕的30%
            
            // 歌词表格视图
            lyricsTableView.topAnchor.constraint(equalTo: lyricsPanel.topAnchor),
            lyricsTableView.leadingAnchor.constraint(equalTo: lyricsPanel.leadingAnchor),
            lyricsTableView.trailingAnchor.constraint(equalTo: lyricsPanel.trailingAnchor),
            lyricsTableView.bottomAnchor.constraint(equalTo: lyricsPanel.bottomAnchor),
            
            // 底部横幅 - 设置为悬浮样式，两侧留出空隙
            bottomBanner.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            bottomBanner.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            bottomBanner.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            bottomBanner.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.15), // 高度保持15%
            
            // 歌曲标题 - 靠左显示，相对于进度条上方
            songTitleLabel.leadingAnchor.constraint(equalTo: bottomBanner.leadingAnchor, constant: 16), // 固定16像素左侧边距
            songTitleLabel.widthAnchor.constraint(lessThanOrEqualTo: bottomBanner.widthAnchor, constant: -32), // 两侧各16像素边距
            songTitleLabel.bottomAnchor.constraint(equalTo: progressSlider.topAnchor, constant: -8), // 进度条上方8像素
            
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
        
        // 设置tableView的底部内容边距，避免内容被横幅遮挡
        tableView.contentInset.bottom = view.bounds.height * 0.15 + 16
        
        // 添加底部横幅的点击手势
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(bottomBannerTapped))
        bottomBanner.addGestureRecognizer(tapGesture)
        bottomBanner.isUserInteractionEnabled = true
        
        // 为歌曲标题添加点击手势，用于快速定位到列表中的歌曲
        let titleTapGesture = UITapGestureRecognizer(target: self, action: #selector(songTitleTapped))
        songTitleLabel.addGestureRecognizer(titleTapGesture)
        songTitleLabel.isUserInteractionEnabled = true
        songTitleLabel.isAccessibilityElement = true
        songTitleLabel.accessibilityLabel = "点击定位到当前播放歌曲"
        
        setupPlayerObservers()
        setupButtonActions()
        
        // 设置展开/收起按钮的点击事件
        expandButton.addTarget(self, action: #selector(toggleLyricsPanel), for: .touchUpInside)
        
        // 初始化梯形形状
        updateButtonTrapezoidShape()
        
        // 设置主题变化通知
        NotificationCenter.default.addObserver(self, selector: #selector(systemThemeChanged), name: Notification.Name(rawValue: "UIUserInterfaceStyleDidChangeNotification"), object: nil)
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
        
        // 添加二次确认弹框
        let confirmAlert = UIAlertController(
            title: "确认刷新", 
            message: "确定要重新扫描所有文件夹吗？", 
            preferredStyle: .alert
        )
        
        // 取消按钮
        confirmAlert.addAction(UIAlertAction(title: "取消", style: .cancel))
        
        // 确定按钮 - 用户确认后执行扫描
        confirmAlert.addAction(UIAlertAction(title: "确定", style: .default) { [weak self] _ in
            guard let self = self else { return }
            self.performRefresh()
        })
        
        // 显示确认弹框
        present(confirmAlert, animated: true)
    }
    
    // 执行刷新扫描的方法
    private func performRefresh() {
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
    
    // 歌曲标题点击事件 - 快速定位到列表中的歌曲
    @objc private func songTitleTapped() {
        guard let currentMusic = musicPlayer.currentMusic else { return }
        
        // 先展开歌曲所在的所有父文件夹
        expandParentDirectories(for: currentMusic)
        
        // 在更新后的displayItems中查找当前播放的歌曲
        for (index, item) in displayItems.enumerated() {
            if let (musicFile, _) = item as? (MusicItem, Int), musicFile.url == currentMusic.url {
                // 找到了对应的歌曲，滚动到该位置并添加短暂的高亮效果
                let indexPath = IndexPath(row: index, section: 0)
                tableView.selectRow(at: indexPath, animated: true, scrollPosition: .middle)
                
                // 0.5秒后取消选中状态，提供视觉反馈
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.tableView.deselectRow(at: indexPath, animated: true)
                }
                
                return
            }
        }
    }
    
    // 展开指定音乐文件所在的所有父文件夹
    private func expandParentDirectories(for musicFile: MusicItem) {
        var parent = musicFile.parentDirectory
        while let directory = parent {
            if !directory.isExpanded {
                directory.isExpanded = true
            }
            parent = directory.parentDirectory
        }
        
        // 更新显示列表以反映文件夹展开状态的变化
        updateDisplayItems()
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
    
    // 切换文件夹图标显示状态的按钮点击事件
    @objc private func folderIconToggleButtonTapped() {
        // 切换显示状态
        showFolderIcons.toggle()
        
        // 刷新表格视图
        tableView.reloadData()
        
        // 更新导航栏按钮可见性（包括更新眼镜图标）
        updateLeftBarButtonsVisibility()
        updateRightBarButtonsVisibility()
    }
    
    // 保存文件夹图标设置
    private func saveFolderIconSetting() {
        UserDefaults.standard.set(showFolderIcons, forKey: "showFolderIcons")
    }
    
    // 加载文件夹图标设置
    private func loadFolderIconSetting() {
        showFolderIcons = UserDefaults.standard.bool(forKey: "showFolderIcons")
    }
    
    // 更新左侧导航栏按钮可见性
    private func updateLeftBarButtonsVisibility() {
        // 添加
        let addImage = UIImage(systemName: "plus")
        let addButton = UIBarButtonItem(image: addImage, style: .plain, target: self, action: #selector(addFolderButtonTapped))
        
        // 刷新
        let refreshImage = UIImage(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
        let refreshButton = UIBarButtonItem(image: refreshImage, style: .plain, target: self, action: #selector(refreshButtonTapped))
        
        // 根据眼镜开关状态设置左侧按钮可见性
        navigationItem.leftBarButtonItems = showFolderIcons ? [addButton, refreshButton] : nil
    }
    
    // 更新右侧导航栏按钮可见性
    private func updateRightBarButtonsVisibility() {
        // 直接使用UIBarButtonItem创建眼镜图标按钮
        let folderIconImage = UIImage(systemName: showFolderIcons ? "eyeglasses" : "eyeglasses.slash")
        let folderIconBarButton = UIBarButtonItem(image: folderIconImage, style: .plain, target: self, action: #selector(folderIconToggleButtonTapped))
        folderIconBarButton.width = 32
        
        // 主题按钮受开关控制
        if showFolderIcons {
            let themeIconImage = UIImage(systemName: currentThemeMode.iconName)
            let themeBarButton = UIBarButtonItem(image: themeIconImage, style: .plain, target: self, action: #selector(themeButtonTapped))
            themeBarButton.width = 32
            navigationItem.rightBarButtonItems = [folderIconBarButton, themeBarButton]
        } else {
            // 只保留眼镜图标按钮
            navigationItem.rightBarButtonItems = [folderIconBarButton]
        }
    }
    
    // 主题切换按钮点击事件
    @objc private func themeButtonTapped() {
        // 切换到下一个主题模式
        currentThemeMode = currentThemeMode.next()
        
        // 重新更新右侧按钮，确保图标正确更新
        updateRightBarButtonsVisibility()
        
        // 应用新主题
        applyTheme()
        
        // 保存主题设置
        saveThemeSetting()
    }
    
    // 应用主题
    private func applyTheme() {
        switch currentThemeMode {
        case .light:
            window?.overrideUserInterfaceStyle = .light
        case .dark:
            window?.overrideUserInterfaceStyle = .dark
        case .system:
            window?.overrideUserInterfaceStyle = .unspecified
        }
    }
    
    // 系统主题变化通知处理
    @objc private func systemThemeChanged() {
        // 只有在跟随系统模式下才需要响应系统主题变化
        if currentThemeMode == .system {
            applyTheme()
        }
    }
    
    // 保存主题设置
    private func saveThemeSetting() {
        UserDefaults.standard.set(currentThemeMode.rawValue, forKey: "themeMode")
        UserDefaults.standard.synchronize()
    }
    
    // 加载主题设置
    private func loadThemeSetting() {
        let savedValue = UserDefaults.standard.integer(forKey: "themeMode")
        if let themeMode = ThemeMode(rawValue: savedValue) {
            currentThemeMode = themeMode
        } else {
            currentThemeMode = .system
        }
    }
    
    // 获取应用窗口
    private var window: UIWindow? {
        return UIApplication.shared.windows.first
    }
    
    private var isSeeking = false // 标记是否正在手动拖动滑块
    
    // 切换歌词面板展开/收起状态
    @objc private func toggleLyricsPanel() {
        isLyricsExpanded.toggle()
        let imageName = isLyricsExpanded ? "chevron.down" : "chevron.up"
        expandButton.setImage(UIImage(systemName: imageName), for: .normal)

        // 确保布局已解析
        view.layoutIfNeeded()

        if isLyricsExpanded {
            // 显示歌词面板
            lyricsPanel.isHidden = false
            // 重置变换，确保从正确的位置开始动画
            lyricsPanel.transform = CGAffineTransform(scaleX: 1.0, y: 0.0)
        }

        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut, animations: {
            // 使用简单的缩放动画
            let scaleY: CGFloat = self.isLyricsExpanded ? 1.0 : 0.0
            self.lyricsPanel.transform = CGAffineTransform(scaleX: 1.0, y: scaleY)

            // 更新底部横幅的圆角
            if self.isLyricsExpanded {
                self.bottomBanner.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
            } else {
                self.bottomBanner.layer.maskedCorners = [
                    .layerMinXMinYCorner, .layerMaxXMinYCorner,
                    .layerMinXMaxYCorner, .layerMaxXMaxYCorner
                ]
            }
            self.bottomBanner.layoutIfNeeded()
            self.updateButtonTrapezoidShape()
        }, completion: { [weak self] _ in
            guard let self = self else { return }
            if !self.isLyricsExpanded {
                // 收起完成后隐藏
                self.lyricsPanel.isHidden = true
                // 重置变换
                self.lyricsPanel.transform = .identity
            }

            // 加载或更新歌词
            if self.isLyricsExpanded {
                if let currentMusic = self.musicPlayer.currentMusic {
                    if !self.lyricsLoaded || self.currentPlayingMusicURL != currentMusic.url {
                        self.currentPlayingMusicURL = currentMusic.url
                        self.loadLyrics()
                    } else {
                        self.updateLyricDisplay()
                    }
                } else {
                    self.loadLyrics()
                }
            }
        })
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
        print("[MusicListViewController] ===== 开始加载歌词 =====")
        // 清空之前的歌词
        lyrics.removeAll()
        currentLyricIndex = 0
        lyricsLoaded = false
        
        if let currentMusic = musicPlayer.currentMusic {
            // 先尝试使用已有的歌词缓存
            if !currentMusic.lyrics.isEmpty {
                print("[MusicListViewController] 使用已缓存的歌词数据，共\(currentMusic.lyrics.count)行")
                lyrics = currentMusic.lyrics
            } 
            // 尝试从文件加载歌词
            else if let lyricsURL = currentMusic.lyricsURL {
                print("[MusicListViewController] 尝试从文件加载歌词: \(lyricsURL.lastPathComponent)")
                print("[MusicListViewController] 歌词文件路径: \(lyricsURL.path)")
                
                // 检查文件是否存在
                if FileManager.default.fileExists(atPath: lyricsURL.path) {
                    print("[MusicListViewController] 歌词文件存在")
                } else {
                    print("[MusicListViewController] 歌词文件不存在于路径: \(lyricsURL.path)")
                }
                
                // 为歌词加载添加访问权限处理
                var shouldStopAccess = false
                if lyricsURL.startAccessingSecurityScopedResource() {
                    shouldStopAccess = true
                    print("[MusicListViewController] 成功获取歌词文件临时访问权限")
                } else {
                    print("[MusicListViewController] 未能获取歌词文件临时访问权限")
                }
                
                // 尝试解析歌词
                if let parsedLyrics = LyricsParser.parseLyrics(from: lyricsURL) {
                    if !parsedLyrics.isEmpty {
                        lyrics = parsedLyrics
                        currentMusic.lyrics = parsedLyrics // 缓存解析结果
                        print("[MusicListViewController] 成功解析歌词，共\(lyrics.count)行")
                    } else {
                        print("[MusicListViewController] 歌词文件存在但内容为空或格式错误")
                    }
                } else {
                    print("[MusicListViewController] 解析歌词文件失败")
                }
                
                // 释放访问权限
                if shouldStopAccess {
                    lyricsURL.stopAccessingSecurityScopedResource()
                    print("[MusicListViewController] 已释放歌词文件访问权限")
                }
            } else {
                print("[MusicListViewController] 音乐项没有关联的歌词URL")
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
            print("[MusicListViewController] 准备刷新表格，当前歌词数量: \(lyrics.count)")
            DispatchQueue.main.async {
                print("[MusicListViewController] 在主线程执行表格刷新")
                self.lyricsTableView.reloadData()
                
                // 加载完成后设置标志并更新显示位置
                self.lyricsLoaded = true
                self.updateLyricDisplay()
                
                print("[MusicListViewController] 表格刷新完成")
            }
            
            print("[MusicListViewController] ===== 歌词加载结束 =====")
    }
    
    // 更新播放器UI
    @objc private func updatePlayerUI() {
        if let currentMusic = musicPlayer.currentMusic {
            bottomBanner.isHidden = false
            expandButton.isHidden = false // 有歌曲播放时显示展开按钮
            // 显示歌曲名 - 艺术家名格式，如果有艺术家信息
            if !currentMusic.artist.isEmpty && currentMusic.artist != "Unknown Artist" {
                songTitleLabel.text = "\(currentMusic.title) - \(currentMusic.artist)"
            } else {
                songTitleLabel.text = currentMusic.title
            }
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
            
            // 只有当歌曲发生变化时才重新加载歌词，避免暂停时重置歌词位置
            if isLyricsExpanded && (currentPlayingMusicURL != currentMusic.url) {
                currentPlayingMusicURL = currentMusic.url
                loadLyrics()
            } else if isLyricsExpanded {
                // 当暂停播放时，保持当前歌词位置
                updateLyricDisplay()
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
        
        // 更新歌词显示，无论是否在播放状态
        updateLyricDisplay()
        
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
        
        // 先获取文件夹名称
        let folderName = url.lastPathComponent
        
        // 先检查是否已存在同名同路径的文件夹
        let isDuplicate = self.rootDirectoryItems.contains {
            $0.name == folderName && $0.url == url
        }
        
        if isDuplicate {
            // 显示重复提示
            let duplicateAlert = UIAlertController(title: "提示", message: "该文件夹已存在", preferredStyle: .alert)
            duplicateAlert.addAction(UIAlertAction(title: "确定", style: .default))
            present(duplicateAlert, animated: true)
            return
        }
        
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
                
                if let newRoot = newRootItem {
                    // 添加到根目录列表
                    self.rootDirectoryItems.append(newRoot)
                    print("[MusicListViewController] 成功添加新的根目录: \(newRoot.name)")
                    
                    // 更新UI显示
                    self.updateDisplayItems()
                    
                    // 立即持久化保存更新后的目录状态
                    self.saveMusicList()
                    
                    // 显示成功提示
                    let successAlert = UIAlertController(title: "成功", message: "文件夹已添加到列表", preferredStyle: .alert)
                    successAlert.addAction(UIAlertAction(title: "确定", style: .default))
                    self.present(successAlert, animated: true)
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
        
        // 移除所有通知观察者
        NotificationCenter.default.removeObserver(self)
        
        // 暂时禁用持久化功能
         print("[MusicListViewController] 视图控制器销毁前，尝试保存音乐列表...")
         saveMusicList()
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
                content.textProperties.color = .tintColor
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
            
            // 根据showFolderIcons控制是否显示文件夹图标
            if showFolderIcons {
                let iconName = directory.isExpanded ? "folder.fill" : "folder"
                content.image = UIImage(systemName: iconName)
                content.imageProperties.tintColor = .tintColor
            } else {
                content.image = nil // 不显示图标
            }
            
            // 根据不同层级设置递增的缩进宽度
            // 基础缩进8像素，每层额外增加26像素
            cell.indentationLevel = 1 // 固定为1级
            let baseIndent = 0
            let additionalIndent = 26
            cell.indentationWidth = CGFloat(baseIndent + additionalIndent * level) // 第1层8px，第2层34px，第3层60px等
            
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
            
            // 显示格式：歌曲名 - 艺术家
            if musicFile.artist != "Unknown Artist" {
                content.text = "\(musicFile.title) - \(musicFile.artist)"
            } else {
                content.text = musicFile.title
            }
            
            // 如果是当前播放的歌曲，高亮显示
                if let currentMusic = musicPlayer.currentMusic, currentMusic.url == musicFile.url {
                    content.textProperties.font = UIFont.boldSystemFont(ofSize: 16)
                    content.textProperties.color = .tintColor
                } else {
                content.textProperties.font = UIFont.systemFont(ofSize: 16)
                content.textProperties.color = .label
            }
            
            
            // 根据showFolderIcons控制是否显示音乐图标
            if showFolderIcons {
                // 根据播放状态显示不同的音乐图标
                if let currentMusic = musicPlayer.currentMusic, currentMusic.url == musicFile.url && musicPlayer.isPlaying {
                    content.image = UIImage(systemName: "play.fill") // 播放中的歌曲显示实心图标
                } else {
                    content.image = UIImage(systemName: "play") // 非播放中的歌曲显示空心图标
                }
                // content.image = UIImage(systemName: "music.note")
                content.imageProperties.tintColor = .tintColor
            } else {
                content.image = nil // 不显示图标
            }

            // 基础缩进8像素，每层额外增加26像素
            cell.indentationLevel = 1 // 固定为1级
            let baseIndent = 0
            let additionalIndent = 26
            cell.indentationWidth = CGFloat(baseIndent + additionalIndent * level) // 与目录项保持一致的缩进规则
            
            // 根据showFolderIcons控制是否显示歌词图标
            if showFolderIcons {
                // 检查是否有歌词，根据歌词状态显示不同图标
                if musicFile.lyricsURL != nil || !musicFile.lyrics.isEmpty {
                    let lyricIcon = UIImageView(image: UIImage(systemName: "music.note"))
                    lyricIcon.tintColor = .tintColor
                    lyricIcon.contentMode = .scaleAspectFit
                    lyricIcon.frame = CGRect(x: 0, y: 0, width: 20, height: 20)
                    cell.accessoryView = lyricIcon
                } else {
                    // 使用更通用的图标表示无歌词状态
                    let noLyricIcon = UIImageView(image: UIImage(systemName: "music.note.slash"))
                    noLyricIcon.tintColor = .secondaryLabel
                    noLyricIcon.contentMode = .scaleAspectFit
                    noLyricIcon.frame = CGRect(x: 0, y: 0, width: 20, height: 20)
                    cell.accessoryView = noLyricIcon
                }
            } else {
                cell.accessoryView = nil // 不显示任何图标
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
        guard !lyrics.isEmpty else { return }
        
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
    
    // 参照MusicPlayerViewController实现歌词更新显示方法
    private func updateLyricDisplay() {
        if lyrics.isEmpty { return }
        
        let newIndex = LyricsParser.getCurrentLyricIndex(time: musicPlayer.currentTime, lyrics: lyrics)
        
        if newIndex != currentLyricIndex {
            // 确保索引在有效范围内
            currentLyricIndex = min(max(newIndex, 0), lyrics.count - 1)
            
            // 如果歌词面板是展开的，更新UI
            if isLyricsExpanded {
                // 滚动到当前歌词行，使其居中显示
                lyricsTableView.scrollToRow(at: IndexPath(row: currentLyricIndex, section: 0), at: .middle, animated: true)
                lyricsTableView.reloadData() // 刷新表格以更新高亮状态
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
                            
                            // 收起歌词面板
                            if isLyricsExpanded {
                                toggleLyricsPanel()
                            }
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
                    
                    // 立即保存更新后的目录状态
                    self.saveMusicList()
                    
                    // 检查是否所有文件夹都被删除，如果是则返回选择文件夹页面
                    if rootDirectoryItems.isEmpty {
                        // 停止播放
                        musicPlayer.stop()
                        
                        // 立即保存空目录状态
                        self.saveMusicList()
                        
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

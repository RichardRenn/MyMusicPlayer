import UIKit
import AVFoundation

// 导入Foundation以支持持久化功能
import Foundation

// 主题模式枚举
enum ThemeMode: Int, Codable {
    case light = 0    // 浅色模式
    case dark = 1     // 深色模式
    
    // 切换到下一个主题模式
    func next() -> ThemeMode {
        switch self {
        case .light:
            return .dark
        case .dark:
            return .light
        }
    }
    
    // 获取对应的图标名称
    var iconName: String {
        switch self {
        case .light:
            return "sun.min.fill"      // 太阳图标
        case .dark:
            return "moon.stars.fill"   // 月亮图标
        }
    }
}

class MusicListViewController: UIViewController, UITableViewDelegate, UITableViewDataSource, UIDocumentPickerDelegate, UIColorPickerViewControllerDelegate {
    
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
    private var currentThemeMode: ThemeMode = .light
    
    // 主题颜色设置
    private var themeColor: UIColor = .systemBlue { 
        didSet {
            saveThemeColorSetting()
            updateThemeColorUI()
        }
    }
    
    // 全局图标显示控制
    private var showIcons: Bool = true { 
        didSet {
            saveFolderIconSetting()
        }
    }
    
    // 编辑菜单是否展开
    private var isEditMenuExpanded = false
    // 设置菜单是否展开
    private var isSettingsMenuExpanded = false
    private var directoryProgresses: [Float] = [] // 存储各目录的扫描进度
    
    // UI元素
    // 展开/收起歌词按钮
    private let expandButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "chevron.up"), for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.backgroundColor = .clear  //不要背景色，避免遮挡歌曲名
        return button
    }()
    
    // 歌词面板容器
    private let lyricsContainer: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.clipsToBounds = false
        v.isHidden = true
        return v
    }()

    // 歌词面板
    private let lyricsPanel: UIView = {
        let view = UIView()
        // view.backgroundColor = .secondarySystemBackground.withAlphaComponent(0.98) // 与底部横幅统一背景色
        view.backgroundColor = .systemBackground
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        view.layer.cornerRadius = 12
        view.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner] // 只设置顶部两个角为圆角
        // 添加阴影效果
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.1
        view.layer.shadowOffset = CGSize(width: 0, height: -4)
        view.layer.shadowRadius = 8
        view.clipsToBounds = false
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
        // view.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.98)
        view.backgroundColor = .systemBackground
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        // 添加阴影效果
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.1
        view.layer.shadowOffset = CGSize(width: 0, height: -4)
        view.layer.shadowRadius = 8
        view.clipsToBounds = false
        return view
    }()
    
    // 创建一个透明的容器视图来扩大可点击区域
    private let songTitleContainer: UIButton = {
        let button = UIButton(type: .custom)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.backgroundColor = .clear
        return button
    }()
    
    private let songTitleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .left
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
        
        // 设置滑块尺寸为14x14，形状为圆角矩形
        let thumbSize = CGSize(width: 14, height: 14)
        let cornerRadius: CGFloat = 4.5
        let thumbImage = UIGraphicsImageRenderer(size: thumbSize).image { context in
            let ctx = context.cgContext
            
            // 创建圆角矩形路径
            let rect = CGRect(x: 0, y: 0, width: thumbSize.width, height: thumbSize.height)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius)
            
            // 填充内部，使用与进度条一致的颜色
            ctx.setFillColor(UIColor.systemBlue.cgColor)
            ctx.addPath(path.cgPath)
            ctx.fillPath()
        }
        
        slider.setThumbImage(thumbImage, for: .normal)
        slider.setThumbImage(thumbImage, for: .highlighted)
        
        return slider
    }()
    
    // 保留原来的进度视图作为背景指示器（可选，默认隐藏）

    
    private let timeLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let totalTimeLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        label.textAlignment = .right
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
        
        // 加载主题颜色设置
        loadThemeColorSetting()
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
        if isLyricsExpanded && !lyrics.isEmpty {
            // 强制获取最新的歌词索引并更新，不受当前索引是否变化的影响
            let newIndex = LyricsParser.getCurrentLyricIndex(time: musicPlayer.currentTime, lyrics: lyrics)
            let safeIndex = min(max(newIndex, 0), lyrics.count - 1)
            
            // 直接更新currentLyricIndex
            currentLyricIndex = safeIndex
            
            // 在主线程立即更新UI
            DispatchQueue.main.async {
                // 再次确认索引在有效范围内
                let finalIndex = min(max(safeIndex, 0), self.lyrics.count - 1)
                
                // 只有当索引有效时才滚动
                if finalIndex >= 0 && finalIndex < self.lyrics.count {
                    let indexPath = IndexPath(row: finalIndex, section: 0)
                    self.lyricsTableView.scrollToRow(at: indexPath, at: .middle, animated: true)
                    self.lyricsTableView.reloadData() // 刷新表格以更新高亮状态
                }
            }
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
                print("[MusicListVC] [持久化] 所有目录已删除，清空保存的数据")
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
                print("[MusicListVC] [持久化] 保存了\(bookmarksToSave.count)个目录书签数据")
            } catch {
                // 捕获编码错误
                print("[MusicListVC] [持久化] 保存失败")
            }
        }
    }
    
    // 应用进入后台时保存音乐列表
    @objc private func saveMusicListOnBackground() {
        print("[MusicListVC] 应用进入后台，触发自动保存...")
        saveMusicList()
    }
    
    // 应用即将终止时保存音乐列表
    @objc private func saveMusicListOnTerminate() {
        print("[MusicListVC] 应用即将终止，触发自动保存...")
        saveMusicList()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // 从详情页返回时，如果歌词面板是展开的，立即更新歌词高亮位置
        if isLyricsExpanded {
            updateLyricDisplay()
            print("[MusicListViewController] viewWillAppear - 立即更新歌词高亮位置")
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
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
        
        // 添加歌词面板（放在歌词面板容器中添加）
        view.addSubview(lyricsContainer)
        lyricsContainer.addSubview(lyricsPanel)
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
        // 先添加容器视图
        bottomBanner.addSubview(songTitleContainer)
        // 然后将标签添加到容器中
        songTitleContainer.addSubview(songTitleLabel) // 添加歌曲标题标签

        bottomBanner.addSubview(progressSlider) // 添加滑块
        bottomBanner.addSubview(timeLabel)
        bottomBanner.addSubview(totalTimeLabel)
        
        // 创建合并的按钮容器StackView，实现居中显示
        let allButtonsStack = UIStackView(arrangedSubviews: [playModeButton, previousButton, playPauseButton, nextButton, rangeLockButton])
        allButtonsStack.translatesAutoresizingMaskIntoConstraints = false
        allButtonsStack.axis = .horizontal
        allButtonsStack.alignment = .center
        allButtonsStack.distribution = .equalSpacing
        allButtonsStack.spacing = 14
        
        bottomBanner.addSubview(allButtonsStack)
        
        // 为底部横幅添加悬浮样式和圆角
        // bottomBanner.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.98) // 添加半透明背景色
        bottomBanner.backgroundColor = .systemBackground
        // 添加阴影效果
        bottomBanner.layer.shadowColor = UIColor.black.cgColor
        bottomBanner.layer.shadowOpacity = 0.1
        bottomBanner.layer.shadowOffset = CGSize(width: 0, height: -4)
        bottomBanner.layer.shadowRadius = 8
        bottomBanner.clipsToBounds = false
        bottomBanner.layer.cornerRadius = 12 // 让视图的角变圆，半径
        bottomBanner.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner] // 初始状态设置为四个角都是圆角，后续会根据歌词展开状态动态调整
        
        // 设置约束 - 全部使用百分比实现自适应布局
        NSLayoutConstraint.activate([
            // 表格视图 - 底部连接到底部横幅的顶部，确保不超过横幅底部
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: bottomBanner.bottomAnchor),
            
            // 展开/收起按钮
            expandButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            expandButton.widthAnchor.constraint(equalToConstant: 60), // 扩大宽度以增加可点击区域
            expandButton.heightAnchor.constraint(equalToConstant: 40), // 扩大高度以增加可点击区域
            expandButton.topAnchor.constraint(equalTo: bottomBanner.topAnchor, constant: -10), // 
            
            // 歌词面板 - 包在容器中 撑满容器
            lyricsPanel.leadingAnchor.constraint(equalTo: lyricsContainer.leadingAnchor),
            lyricsPanel.trailingAnchor.constraint(equalTo: lyricsContainer.trailingAnchor),
            lyricsPanel.bottomAnchor.constraint(equalTo: lyricsContainer.bottomAnchor),
            lyricsPanel.topAnchor.constraint(equalTo: lyricsContainer.topAnchor),
            
            // 歌词面板容器 - 与底部横幅融合
            lyricsContainer.leadingAnchor.constraint(equalTo: bottomBanner.leadingAnchor),
            lyricsContainer.trailingAnchor.constraint(equalTo: bottomBanner.trailingAnchor),
            lyricsContainer.bottomAnchor.constraint(equalTo: bottomBanner.topAnchor), // 直接连接到底部横幅顶部
            lyricsContainer.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.17), // 歌词面板高度/屏幕高度占比
            // 歌词表格视图
            lyricsTableView.topAnchor.constraint(equalTo: lyricsPanel.topAnchor),
            lyricsTableView.leadingAnchor.constraint(equalTo: lyricsPanel.leadingAnchor),
            lyricsTableView.trailingAnchor.constraint(equalTo: lyricsPanel.trailingAnchor),
            lyricsTableView.bottomAnchor.constraint(equalTo: lyricsPanel.bottomAnchor),
            
            // 底部横幅 - 修改为与列表页一致的布局
            bottomBanner.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16), // 添加左侧边距
            bottomBanner.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16), // 添加右侧边距
            bottomBanner.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -1),
            bottomBanner.heightAnchor.constraint(greaterThanOrEqualToConstant: 120), // 确保足够的高度来容纳所有元素
            
            // 歌曲标题容器 - 设置更大的可点击区域
            songTitleContainer.leadingAnchor.constraint(equalTo: bottomBanner.leadingAnchor, constant: 16),
            songTitleContainer.widthAnchor.constraint(lessThanOrEqualTo: bottomBanner.widthAnchor, constant: -32),
            songTitleContainer.topAnchor.constraint(equalTo: bottomBanner.topAnchor), // 顶部与横幅顶部齐平
            songTitleContainer.bottomAnchor.constraint(equalTo: progressSlider.topAnchor, constant: -6), // 进度条上方8像素
            // 歌曲标题 - 调整为底部对齐
            songTitleLabel.leadingAnchor.constraint(equalTo: songTitleContainer.leadingAnchor),
            songTitleLabel.trailingAnchor.constraint(equalTo: songTitleContainer.trailingAnchor),
            songTitleLabel.bottomAnchor.constraint(equalTo: songTitleContainer.bottomAnchor), // 与容器底部对齐
            
            // 进度滑块 - 调整为上方40% 下方60% 的比例
            progressSlider.leadingAnchor.constraint(equalTo: bottomBanner.leadingAnchor, constant: 16), // 固定16像素左侧边距
            progressSlider.trailingAnchor.constraint(equalTo: bottomBanner.trailingAnchor, constant: -16), // 固定16像素右侧边距
            progressSlider.centerYAnchor.constraint(equalTo: bottomBanner.centerYAnchor, constant: -8), // 进度滑块位于横幅中间靠上一些的位置
            
            // 时间标签 - 相对于进度滑块下方定位
            timeLabel.leadingAnchor.constraint(equalTo: bottomBanner.leadingAnchor, constant: 16), // 固定16像素左侧边距
            timeLabel.topAnchor.constraint(equalTo: progressSlider.bottomAnchor, constant: 4), // 固定4像素顶部边距
            
            totalTimeLabel.trailingAnchor.constraint(equalTo: bottomBanner.trailingAnchor, constant: -16), // 固定16像素右侧边距
            totalTimeLabel.topAnchor.constraint(equalTo: progressSlider.bottomAnchor, constant: 4), // 固定4像素顶部边距

            // 合并的按钮组 - 相对于进度滑块下方定位
            allButtonsStack.centerXAnchor.constraint(equalTo: bottomBanner.centerXAnchor),
            allButtonsStack.topAnchor.constraint(equalTo: progressSlider.bottomAnchor, constant: 8), // 进度滑块下方8像素
            allButtonsStack.widthAnchor.constraint(lessThanOrEqualTo: bottomBanner.widthAnchor, constant: -32), // 两侧各16像素边距
            
            // 按钮大小约束 - 使用底部横幅高度的百分比（降低乘数以避免约束冲突）
            previousButton.widthAnchor.constraint(equalTo: bottomBanner.heightAnchor, multiplier: 0.35),
            previousButton.heightAnchor.constraint(equalTo: bottomBanner.heightAnchor, multiplier: 0.35),
            
            playPauseButton.widthAnchor.constraint(equalTo: bottomBanner.heightAnchor, multiplier: 0.35),
            playPauseButton.heightAnchor.constraint(equalTo: bottomBanner.heightAnchor, multiplier: 0.35),
            
            nextButton.widthAnchor.constraint(equalTo: bottomBanner.heightAnchor, multiplier: 0.35),
            nextButton.heightAnchor.constraint(equalTo: bottomBanner.heightAnchor, multiplier: 0.35),
            
            playModeButton.widthAnchor.constraint(equalTo: bottomBanner.heightAnchor, multiplier: 0.35),
            playModeButton.heightAnchor.constraint(equalTo: bottomBanner.heightAnchor, multiplier: 0.35),
            
            rangeLockButton.widthAnchor.constraint(equalTo: bottomBanner.heightAnchor, multiplier: 0.35),
            rangeLockButton.heightAnchor.constraint(equalTo: bottomBanner.heightAnchor, multiplier: 0.35)
        ])
        
        // 设置tableView的底部内容边距，避免内容被横幅遮挡
        tableView.contentInset.bottom = view.bounds.height * 0.15 + 16
        
        // 添加底部横幅的点击手势
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(bottomBannerTapped))
        bottomBanner.addGestureRecognizer(tapGesture)
        bottomBanner.isUserInteractionEnabled = true
        
        // 为歌曲标题容器添加点击事件，用于快速定位到列表中的歌曲
        songTitleContainer.addTarget(self, action: #selector(songTitleTapped), for: .touchUpInside)
        songTitleContainer.isAccessibilityElement = true
        songTitleContainer.accessibilityLabel = "点击定位到当前播放歌曲"
        
        setupPlayerObservers()
        setupButtonActions()
        
        // 设置展开/收起按钮的点击事件
        expandButton.addTarget(self, action: #selector(toggleLyricsPanel), for: .touchUpInside)
        

    }
    
    // 设置按钮点击事件
    private func setupButtonActions() {
        previousButton.addTarget(self, action: #selector(previousButtonTapped), for: .touchUpInside)
        playPauseButton.addTarget(self, action: #selector(playPauseButtonTapped), for: .touchUpInside)
        nextButton.addTarget(self, action: #selector(nextButtonTapped), for: .touchUpInside)
        playModeButton.addTarget(self, action: #selector(playModeButtonTapped), for: .touchUpInside)
        rangeLockButton.addTarget(self, action: #selector(rangeLockButtonTapped), for: .touchUpInside)
        // 添加进度滑块事件
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

        
        // 初始化进度滑块
        progressSlider.value = 0
        
        // 配置时间标签
        timeLabel.text = "00:00"
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
        var currentDirectoryProgresses: [Int: Double] = [:]
        // 初始化所有目录的进度为0
        for index in 0..<totalDirectories {
            currentDirectoryProgresses[index] = 0.0
        }
        
        // 确保类成员变量directoryProgresses的大小正确
        self.directoryProgresses = Array(repeating: 0.0, count: totalDirectories)
        
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
        func updatePlayProgress() {
            DispatchQueue.main.async {
                // 计算总进度（所有目录进度的平均值）
                let totalProgress = currentDirectoryProgresses.values.reduce(0, +) / Double(totalDirectories)
                let progressPercentage = Int(totalProgress * 100)
                
                // 获取最后更新的文件夹名称
                if lastUpdatedDirectoryIndex < self.rootDirectoryItems.count {
                    let currentFolderName = self.rootDirectoryItems[lastUpdatedDirectoryIndex].name
                    
                    // 动态更新alert的消息内容，不重新创建alert
                    progressAlert.message = "正在扫描[\(currentFolderName)]\n进度: \(progressPercentage)%"
                }
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
            
            scanner.scanDirectory(directoryURL, scanProgressHandler: { [weak self] progress in
                guard let self = self else { return }
                
                // 首先更新局部字典变量
                currentDirectoryProgresses[index] = progress
                
                // 然后安全地更新类成员变量数组
                if index < self.directoryProgresses.count {
                    self.directoryProgresses[index] = Float(progress)
                }
                
                // 更新最后活动的目录索引
                lastUpdatedDirectoryIndex = index
                
                // 更新进度显示
                updatePlayProgress()
            }, completionHandler: { [weak self] newRootItem in
                guard let self = self else { return }
                
                DispatchQueue.main.async {
                    // 安全地更新对应的根目录项
                    if index < self.rootDirectoryItems.count, let newRoot = newRootItem {
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
        // 移除冗余调用，依赖PlayerStateChanged通知更新UI
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
        // 移除冗余调用，依赖PlayerStateChanged通知更新UI
    }
    
    @objc private func playModeButtonTapped() {
        musicPlayer.togglePlayMode()
        updatePlayModeButtonImage()
    }
    
    @objc private func rangeLockButtonTapped() {
        musicPlayer.toggleRangeLock()
        updateRangeLockButtonImage()
    }
    
    // 切换全局图标显示状态的按钮点击事件
    @objc private func showIconToggleButtonTapped() {
        // 切换显示状态
        showIcons.toggle()
        
        // 刷新表格视图
        tableView.reloadData()
        
        // 更新导航栏按钮可见性（包括更新眼镜图标）
        updateLeftBarButtonsVisibility()
        updateRightBarButtonsVisibility()
        
        // 更新设置面板中的按钮文字（无动画）
        if let showIconButton = settingsPanel.subviews.first as? UIButton {
            UIView.performWithoutAnimation {
                showIconButton.setTitle(showIcons ? "隐藏图标" : "显示图标", for: .normal)
                showIconButton.layoutIfNeeded() // 确保立即刷新布局
            }
        }
    }
    
    // 保存全局图标设置
    private func saveFolderIconSetting() {
        UserDefaults.standard.set(showIcons, forKey: "showIcons")
    }
    
    // 加载全局图标设置
    private func loadFolderIconSetting() {
        showIcons = UserDefaults.standard.bool(forKey: "showIcons")
    }
    
    // 更新左侧导航栏按钮可见性
    private func updateLeftBarButtonsVisibility() {
        // 创建编辑按钮（使用pencil图标）
        let editButton = UIBarButtonItem(image: UIImage(systemName: "pencil"), style: .plain, target: self, action: #selector(editButtonTapped))
        
        // 只显示编辑按钮在导航栏左侧
        navigationItem.leftBarButtonItems = [editButton]
    }
    
    // 编辑面板视图
    // 设置面板
    private lazy var settingsPanel: UIView = {
        let view = UIView()
        view.backgroundColor = .systemBackground
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 12
        // 仅保留左下角、右下角、左上角的圆角
        view.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner, .layerMinXMinYCorner]
        view.isHidden = true
        // 添加阴影效果
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.1
        view.layer.shadowOffset = CGSize(width: 0, height: 4)
        view.layer.shadowRadius = 8
        view.clipsToBounds = false
        
        // 全局图标切换按钮
        let showIconToggleButton = UIButton(type: .system)
        showIconToggleButton.setTitle(showIcons ? "隐藏图标" : "显示图标", for: .normal)
        showIconToggleButton.titleLabel?.font = UIFont.systemFont(ofSize: 16)
        showIconToggleButton.titleLabel?.textAlignment = .right
        showIconToggleButton.contentHorizontalAlignment = .right
        showIconToggleButton.translatesAutoresizingMaskIntoConstraints = false
        showIconToggleButton.addTarget(self, action: #selector(showIconToggleButtonTapped), for: .touchUpInside)
        view.addSubview(showIconToggleButton)
        
        // 主题切换按钮
        let themeToggleButton = UIButton(type: .system)
        themeToggleButton.setTitle(currentThemeMode == .light ? "深色模式" : "浅色模式", for: .normal)
        themeToggleButton.titleLabel?.font = UIFont.systemFont(ofSize: 16)
        themeToggleButton.titleLabel?.textAlignment = .right
        themeToggleButton.contentHorizontalAlignment = .right
        themeToggleButton.translatesAutoresizingMaskIntoConstraints = false
        themeToggleButton.addTarget(self, action: #selector(themeButtonTapped), for: .touchUpInside)
        view.addSubview(themeToggleButton)
        
        // 颜色调整按钮
        let colorAdjustButton = UIButton(type: .system)
        colorAdjustButton.setTitle("颜色调整", for: .normal)
        colorAdjustButton.titleLabel?.font = UIFont.systemFont(ofSize: 16)
        colorAdjustButton.titleLabel?.textAlignment = .right
        colorAdjustButton.contentHorizontalAlignment = .right
        colorAdjustButton.translatesAutoresizingMaskIntoConstraints = false
        colorAdjustButton.addTarget(self, action: #selector(colorAdjustButtonTapped), for: .touchUpInside)
        view.addSubview(colorAdjustButton)
        
        // 设置约束
        NSLayoutConstraint.activate([
            showIconToggleButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            showIconToggleButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            showIconToggleButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            showIconToggleButton.heightAnchor.constraint(equalToConstant: 40),
            
            themeToggleButton.topAnchor.constraint(equalTo: showIconToggleButton.bottomAnchor, constant: 8),
             themeToggleButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
             themeToggleButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
             themeToggleButton.heightAnchor.constraint(equalToConstant: 40),
             
             // 颜色调整按钮约束
             colorAdjustButton.topAnchor.constraint(equalTo: themeToggleButton.bottomAnchor, constant: 8),
             colorAdjustButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
             colorAdjustButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
             colorAdjustButton.heightAnchor.constraint(equalToConstant: 40),
             colorAdjustButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16)
        ])
        
        return view
    }()
    
    private lazy var editPanel: UIView = {
        let view = UIView()
        view.backgroundColor = .systemBackground
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 12
        // 仅保留左下角、右下角、右上角的圆角
        view.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner, .layerMaxXMinYCorner]
        view.isHidden = true
        // 添加阴影效果
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.1
        view.layer.shadowOffset = CGSize(width: 0, height: 4)
        view.layer.shadowRadius = 8
        view.clipsToBounds = false
        
        // 添加文件夹按钮
        let addFolderButton = UIButton(type: .system)
        addFolderButton.setTitle("添加", for: .normal)
        addFolderButton.titleLabel?.font = UIFont.systemFont(ofSize: 16)
        addFolderButton.titleLabel?.textAlignment = .left
        addFolderButton.contentHorizontalAlignment = .left
        addFolderButton.translatesAutoresizingMaskIntoConstraints = false
        addFolderButton.addTarget(self, action: #selector(addFolderButtonTapped), for: .touchUpInside)
        view.addSubview(addFolderButton)
        
        // 刷新音乐库按钮
        let refreshButton = UIButton(type: .system)
        refreshButton.setTitle("刷新", for: .normal)
        refreshButton.titleLabel?.font = UIFont.systemFont(ofSize: 16)
        refreshButton.titleLabel?.textAlignment = .left
        refreshButton.contentHorizontalAlignment = .left
        refreshButton.translatesAutoresizingMaskIntoConstraints = false
        refreshButton.addTarget(self, action: #selector(refreshButtonTapped), for: .touchUpInside)
        view.addSubview(refreshButton)
        
        // 设置按钮约束
        NSLayoutConstraint.activate([
            addFolderButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            addFolderButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            addFolderButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            addFolderButton.heightAnchor.constraint(equalToConstant: 40),
            
            refreshButton.topAnchor.constraint(equalTo: addFolderButton.bottomAnchor, constant: 8),
            refreshButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            refreshButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            refreshButton.heightAnchor.constraint(equalToConstant: 40),
            refreshButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16)
        ])
        
        return view
    }()
    
    // 编辑按钮点击事件
    @objc private func editButtonTapped() {
        // 先隐藏设置面板（如果显示）
        if isSettingsMenuExpanded {
            isSettingsMenuExpanded = false
            settingsPanel.isHidden = true
            settingsPanel.removeFromSuperview()
        }
        
        // 切换编辑面板显示状态
        isEditMenuExpanded.toggle()
        
        if isEditMenuExpanded {
            // 显示编辑面板
            view.addSubview(editPanel)
            
            // 设置编辑面板约束：紧贴导航栏下方，宽度根据内容自适应
            NSLayoutConstraint.activate([
                editPanel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                editPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                editPanel.heightAnchor.constraint(equalToConstant: 120) // 固定高度，包含两个按钮和间距：16+40+8+40+16=120
            ])
            
            // 直接显示面板，无需动画
            editPanel.alpha = 1
            editPanel.transform = .identity
            editPanel.isHidden = false
        } else {
            // 直接隐藏面板，无需动画
            editPanel.isHidden = true
            editPanel.removeFromSuperview()
        }
    }
    
    // 更新右侧导航栏按钮可见性
    // 设置按钮点击事件
    @objc private func settingsButtonTapped() {
        // 先隐藏编辑面板（如果显示）
        if isEditMenuExpanded {
            isEditMenuExpanded = false
            editPanel.isHidden = true
            editPanel.removeFromSuperview()
        }
        
        // 切换设置面板显示状态
        isSettingsMenuExpanded.toggle()
        
        if isSettingsMenuExpanded {
            // 显示设置面板
            view.addSubview(settingsPanel)
            
            // 设置设置面板约束：紧贴导航栏下方，宽度根据内容自适应
            NSLayoutConstraint.activate([
                settingsPanel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                settingsPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                settingsPanel.heightAnchor.constraint(equalToConstant: 168) // 调整高度以适应按钮和间距：16+40+8+40+8+40+16=168
            ])
            
            // 更新设置面板中的按钮文本
            if let showIconButton = settingsPanel.subviews[0] as? UIButton {
                showIconButton.setTitle(showIcons ? "隐藏图标" : "显示图标", for: .normal)
            }
            if let themeButton = settingsPanel.subviews[1] as? UIButton {
                themeButton.setTitle(currentThemeMode == .light ? "深色模式" : "浅色模式", for: .normal)
            }
            
            // 直接显示面板，无需动画
            settingsPanel.alpha = 1
            settingsPanel.transform = .identity
            settingsPanel.isHidden = false
        } else {
            // 直接隐藏面板，无需动画
            settingsPanel.isHidden = true
            settingsPanel.removeFromSuperview()
        }
    }
    
    private func updateRightBarButtonsVisibility() {
        // 创建设置按钮（使用齿轮图标）
        let settingsIconImage = UIImage(systemName: "gearshape")
        let settingsBarButton = UIBarButtonItem(image: settingsIconImage, style: .plain, target: self, action: #selector(settingsButtonTapped))
        settingsBarButton.width = 32
        navigationItem.rightBarButtonItems = [settingsBarButton]
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
    
    @objc private func colorAdjustButtonTapped() {
        let colorPicker = UIColorPickerViewController()
        colorPicker.selectedColor = themeColor
        colorPicker.delegate = self
        present(colorPicker, animated: true, completion: nil)
    }
    
    private func saveThemeColorSetting() {
        if let colorData = try? NSKeyedArchiver.archivedData(withRootObject: themeColor, requiringSecureCoding: false) {
            UserDefaults.standard.set(colorData, forKey: "themeColor")
        }
    }
    
    private func loadThemeColorSetting() {
        if let colorData = UserDefaults.standard.data(forKey: "themeColor"),
           let savedColor = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(colorData) as? UIColor {
            themeColor = savedColor
        }
    }
    
    private func updateThemeColorUI() {
        // 更新进度滑块颜色
        progressSlider.minimumTrackTintColor = themeColor
        
        // 更新滑块缩略图颜色
        let thumbSize = CGSize(width: 14, height: 14)
        let cornerRadius: CGFloat = 4.5
        let thumbImage = UIGraphicsImageRenderer(size: thumbSize).image { context in
            let ctx = context.cgContext
            let rect = CGRect(x: 0, y: 0, width: thumbSize.width, height: thumbSize.height)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius)
            ctx.setFillColor(themeColor.cgColor)
            ctx.addPath(path.cgPath)
            ctx.fillPath()
        }
        progressSlider.setThumbImage(thumbImage, for: .normal)
        progressSlider.setThumbImage(thumbImage, for: .highlighted)

        // 更新设置面板中的按钮文字（无动画）
        if let themeButton = settingsPanel.subviews[1] as? UIButton {
            UIView.performWithoutAnimation {
                themeButton.setTitle(currentThemeMode == .light ? "深色模式" : "浅色模式", for: .normal)
                themeButton.layoutIfNeeded() // 确保立即刷新布局
            }
        }
        
        // 刷新表格视图以更新播放中歌曲的高亮颜色
        tableView.reloadData()
        
        // 刷新歌词表格视图以更新高亮颜色
        if isLyricsExpanded {
            lyricsTableView.reloadData()
        }
    }
    
    // 应用主题
    private func applyTheme() {
        switch currentThemeMode {
        case .light:
            window?.overrideUserInterfaceStyle = .light
        case .dark:
            window?.overrideUserInterfaceStyle = .dark
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
            // 默认为浅色模式
            currentThemeMode = .light
        }
    }
    
    // 获取应用窗口
    private var window: UIWindow? {
        if #available(iOS 15.0, *) {
            // iOS 15及以上使用推荐的API
            return UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first?
                .windows
                .first
        } else {
            // 较早版本回退到旧API
            return UIApplication.shared.windows.first
        }
    }
    
    private var isSeeking = false // 标记是否正在手动拖动滑块
    
    // 切换歌词面板展开/收起状态
    @objc private func toggleLyricsPanel() {
        isLyricsExpanded.toggle()

        let imageName = isLyricsExpanded ? "chevron.down" : "chevron.up"
        expandButton.setImage(UIImage(systemName: imageName), for: .normal)

        if isLyricsExpanded {
            lyricsContainer.isHidden = false
            lyricsPanel.isHidden = false
            lyricsPanel.alpha = 1.0
            lyricsPanel.transform = .identity
            bottomBanner.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
            view.layoutIfNeeded()
            loadLyricsIfNeeded()
        } else {
            lyricsPanel.alpha = 1.0
            lyricsPanel.transform = .identity
            bottomBanner.layer.maskedCorners = [
                .layerMinXMinYCorner, .layerMaxXMinYCorner,
                .layerMinXMaxYCorner, .layerMaxXMaxYCorner
            ]
            view.layoutIfNeeded()
            lyricsContainer.isHidden = true
            lyricsPanel.isHidden = true
        }
    }

    // 辅助：加载歌词逻辑抽出
    private func loadLyricsIfNeeded() {
        if let currentMusic = musicPlayer.currentMusic {
            if !lyricsLoaded || currentPlayingMusicURL != currentMusic.url {
                currentPlayingMusicURL = currentMusic.url
                loadLyrics()
            } else {
                updateLyricDisplay()
            }
        } else {
            loadLyrics()
        }
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
            
            // 更新播放/暂停按钮
            let imageName = musicPlayer.isPlaying ? "pause.fill" : "play.fill"
            playPauseButton.setImage(UIImage(systemName: imageName), for: .normal)
            
            // 更新播放模式和范围锁定按钮
            updatePlayModeButtonImage()
            updateRangeLockButtonImage()
            
            // 只有当用户不在拖动滑块时才更新UI
            if !isSeeking {
                // 更新进度条和滑块
                let progress = Float(musicPlayer.currentTime / musicPlayer.totalTime)
        
                progressSlider.value = progress

                // 更新时间标签
                timeLabel.text = formatTime(musicPlayer.currentTime)
            }

            // 更新进度显示
            totalTimeLabel.text = formatTime(musicPlayer.totalTime)
            
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
        updateTimer = Timer.scheduledTimer(timeInterval: 0.5, target: self, selector: #selector(updatePlayProgress), userInfo: nil, repeats: true)
    }
    
    // 停止更新计时器
    private func stopUpdateTimer() {
        updateTimer?.invalidate()
        updateTimer = nil
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
        timeLabel.text = formatTime(seekTime)
        startUpdateTimer()
        
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
        let documentPicker: UIDocumentPickerViewController
        
        // 使用iOS 14.0及以上推荐的API，回退到旧API以支持较早版本
        if #available(iOS 14, *) {
            documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        } else {
            documentPicker = UIDocumentPickerViewController(documentTypes: ["public.folder"], in: .open)
        }
        
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
        scanner.scanDirectory(url, scanProgressHandler: { _ in
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
                content.textProperties.color = themeColor
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
            content.image = nil
            
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
                content.textProperties.color = themeColor
            } else {
            content.textProperties.font = UIFont.systemFont(ofSize: 16)
            content.textProperties.color = .label
            }
            
            content.image = nil

            // 基础缩进8像素，每层额外增加26像素
            cell.indentationLevel = 1 // 固定为1级
            let baseIndent = 0
            let additionalIndent = 26
            cell.indentationWidth = CGFloat(baseIndent + additionalIndent * level) // 与目录项保持一致的缩进规则
            
            // 根据showIcons控制是否显示歌词图标
            if showIcons {
                // 判断是否有歌词：有 lyricsURL 或歌词文本不为空
                let hasLyrics = (musicFile.lyricsURL != nil) || !musicFile.lyrics.isEmpty
                let imageName = hasLyrics ? "music.note" : "music.note.slash"
                let tintColor: UIColor = hasLyrics ? themeColor : .secondaryLabel
                let iconView = UIImageView(image: UIImage(systemName: imageName))
                iconView.tintColor = tintColor
                iconView.contentMode = .scaleAspectFit
                iconView.frame = CGRect(x: 0, y: 0, width: 20, height: 20)
                cell.accessoryView = iconView
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
    
    // 更新进度
    @objc private func updatePlayProgress() {
        // 只有当播放器正在播放且用户不在拖动滑块时才更新UI
        if musicPlayer.isPlaying && !isSeeking {
            let progress = musicPlayer.currentTime / musicPlayer.totalTime
    
            progressSlider.value = Float(progress) // 同时更新滑块位置
            
            // 更新时间标签
            timeLabel.text = formatTime(musicPlayer.currentTime)
            totalTimeLabel.text = formatTime(musicPlayer.totalTime)
            
            // 更新歌词显示
            updateLyricDisplay()
        } else if !musicPlayer.isPlaying {
            // 如果播放器已暂停，强制停止计时器
            stopUpdateTimer()
        }
    }
    
    // 参照MusicPlayerViewController实现歌词更新显示方法
    private func updateLyricDisplay() {
        // 添加额外的空数组检查
        guard !lyrics.isEmpty else { return }
        
        let newIndex = LyricsParser.getCurrentLyricIndex(time: musicPlayer.currentTime, lyrics: lyrics)
        
        // 严格确保索引在有效范围内，防止任何可能的越界
        let safeIndex = min(max(newIndex, 0), lyrics.count - 1)
        
        if safeIndex != currentLyricIndex {
            currentLyricIndex = safeIndex
            
            // 如果歌词面板是展开的，更新UI
            if isLyricsExpanded {
                // 在滚动前再次检查歌词数组是否为空，确保安全
                if !lyrics.isEmpty {
                    // 使用主线程确保UI操作安全
                    DispatchQueue.main.async {
                        // 再次确认索引在有效范围内
                        let finalIndex = min(max(safeIndex, 0), self.lyrics.count - 1)
                        
                        // 只有当索引有效时才滚动
                        if finalIndex >= 0 && finalIndex < self.lyrics.count {
                            let indexPath = IndexPath(row: finalIndex, section: 0)
                            self.lyricsTableView.scrollToRow(at: indexPath, at: .middle, animated: true)
                            self.lyricsTableView.reloadData() // 刷新表格以更新高亮状态
                        }
                    }
                }
            }
        }
    }
    
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
    
    // MARK: - UIColorPickerViewControllerDelegate methods
    func colorPickerViewControllerDidSelectColor(_ viewController: UIColorPickerViewController) {
        themeColor = viewController.selectedColor
    }
    
    func colorPickerViewControllerDidFinish(_ viewController: UIColorPickerViewController) {
        // 颜色选择完成，已在didSelectColor中更新
    }
}

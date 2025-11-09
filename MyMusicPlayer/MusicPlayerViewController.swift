import UIKit
import Foundation
import AVFoundation
import MediaPlayer

// 定义通知名称
extension Notification.Name {
    static let musicPlayerPlaybackStateChanged = Notification.Name("musicPlayerPlaybackStateChanged")
    static let musicPlayerProgressChanged = Notification.Name("musicPlayerProgressChanged")
}

class MusicPlayerViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {
    
    private var music: MusicItem
    private let musicPlayer = MusicPlayer.shared
    private var lyrics: [LyricsLine] = []
    private var currentLyricIndex: Int = 0
    
    // 主题颜色属性
    private var themeColor: UIColor {
        // 从UserDefaults加载主题颜色
        if let colorData = UserDefaults.standard.data(forKey: "themeColor"),
           let color = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(colorData) as? UIColor {
            return color
        }
        return .systemBlue // 默认颜色
    }
    
    // UI元素
    
    private let tableView: UITableView = {
        let tableView = UITableView()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "lyricCell")
        tableView.separatorStyle = .none
        tableView.backgroundColor = .clear
        tableView.showsVerticalScrollIndicator = false
        return tableView
    }()
    
    private let bottomBanner: UIView = {
        let view = UIView()
        // view.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.98)
        view.backgroundColor = .systemBackground
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = false
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
        // 初始状态将根据showIcons设置决定，在viewWillAppear中通过updateWaveformVisibility方法更新
        return label
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
    
    // 计时器用于更新进度
    private var updateTimer: Timer?
    
    // 初始化方法
    init(music: MusicItem) {
        self.music = music
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadLyrics()
        setupButtonActions()
        setupPlayerObservers()
        // 根据当前播放状态决定是否启动计时器
        if musicPlayer.isPlaying {
            startUpdateTimer()
        } else {
            stopUpdateTimer()
        }
        updateUI()
        
        // 添加左滑手势支持返回功能
        setupSwipeGesture()
        
        // 更新UI以使用主题颜色
        updateThemeColorUI()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // 更新UI以使用主题颜色
        updateThemeColorUI()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // 确保滑块位置与当前播放进度一致
        let progress = Float(musicPlayer.currentTime / musicPlayer.totalTime)
        progressSlider.value = progress
        timeLabel.text = formatTime(musicPlayer.currentTime)
        print("[MusicPlayerViewController] viewDidAppear - 同步滑块位置: \(progress)")
        
        // 立即更新歌词高亮位置，确保从列表页跳转过来时，歌词高亮与当前进度一致
        // 即使在暂停状态下也需要更新
        self.updateLyricDisplay()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
    }
    
    // 设置左滑手势
    private func setupSwipeGesture() {
        let swipeGesture = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handleSwipeGesture(_:)))
        swipeGesture.edges = .left
        view.addGestureRecognizer(swipeGesture)
    }
    
    // 处理左滑手势
    @objc private func handleSwipeGesture(_ gesture: UIScreenEdgePanGestureRecognizer) {
        if gesture.state == .recognized || gesture.state == .ended {
            // 执行与返回按钮相同的操作
            backButtonTapped()
        }
    }
    
    deinit {
        stopUpdateTimer()
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name("PlayerStateChanged"), object: nil)
        NotificationCenter.default.removeObserver(self, name: .musicPlayerProgressChanged, object: nil)
    }
    
    // 设置UI
    private func setupUI() {
        // 显示歌曲名 - 艺术家名格式，如果有艺术家信息
        if !music.artist.isEmpty && music.artist != "Unknown Artist" {
            title = "\(music.title) - \(music.artist)"
        } else {
            title = music.title
        }
        view.backgroundColor = .systemBackground
        
        // 设置导航栏左侧返回按钮
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "chevron.backward"), style: .plain, target: self, action: #selector(backButtonTapped))
        
        // 添加歌词显示表格
        view.addSubview(tableView)
        tableView.delegate = self
        tableView.dataSource = self
        // 注册表格单元格
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "lyricCell")
        
        // 添加底部横幅
        view.addSubview(bottomBanner)

        bottomBanner.addSubview(songTitleContainer) // 添加歌曲标题容器
        songTitleContainer.addSubview(songTitleLabel) // 保留歌曲标题标签但默认隐藏

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
        
        // 设置约束
        NSLayoutConstraint.activate([
            // 歌词表格
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: bottomBanner.topAnchor),
            
            // 底部横幅 - 修改为与列表页一致的布局
            bottomBanner.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16), // 添加左侧边距
            bottomBanner.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16), // 添加右侧边距
            bottomBanner.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -1),
            bottomBanner.heightAnchor.constraint(greaterThanOrEqualToConstant: 120), // 确保足够的高度来容纳所有元素
            
            // 歌曲标题容器 - 设置更大的可点击区域
            songTitleContainer.leadingAnchor.constraint(equalTo: bottomBanner.leadingAnchor, constant: 16),
            songTitleContainer.widthAnchor.constraint(lessThanOrEqualTo: bottomBanner.widthAnchor, constant: -32),
            songTitleContainer.topAnchor.constraint(equalTo: bottomBanner.topAnchor), // 顶部与横幅顶部齐平
            songTitleContainer.bottomAnchor.constraint(equalTo: progressSlider.topAnchor, constant: -6), // 进度条上方6像素
            // 歌曲标题 - 调整为底部对齐
            songTitleLabel.leadingAnchor.constraint(equalTo: songTitleContainer.leadingAnchor),
            songTitleLabel.trailingAnchor.constraint(equalTo: songTitleContainer.trailingAnchor),
            songTitleLabel.bottomAnchor.constraint(equalTo: songTitleContainer.bottomAnchor), // 与容器底部对齐
            
            // 进度滑块 - 调整为上方40% 下方60% 的比例
            progressSlider.leadingAnchor.constraint(equalTo: bottomBanner.leadingAnchor, constant: 16), // 左侧16像素边距
            progressSlider.trailingAnchor.constraint(equalTo: bottomBanner.trailingAnchor, constant: -16), // 右侧16像素边距
            // 使用简单的负值常量将进度滑块向上移动，实现上方40%位置
            progressSlider.centerYAnchor.constraint(equalTo: bottomBanner.centerYAnchor, constant: -8),
            
            // 时间标签 - 相对于进度滑块下方定位
            timeLabel.leadingAnchor.constraint(equalTo: bottomBanner.leadingAnchor, constant: 16), // 左侧16像素边距
            timeLabel.topAnchor.constraint(equalTo: progressSlider.bottomAnchor, constant: 4), // 固定4像素顶部边距
            
            totalTimeLabel.trailingAnchor.constraint(equalTo: bottomBanner.trailingAnchor, constant: -16), // 右侧16像素边距
            totalTimeLabel.topAnchor.constraint(equalTo: progressSlider.bottomAnchor, constant: 4), // 固定4像素顶部边距
            
            // 合并的按钮组 - 相对于进度滑块下方定位
            allButtonsStack.centerXAnchor.constraint(equalTo: bottomBanner.centerXAnchor),
            allButtonsStack.topAnchor.constraint(equalTo: progressSlider.bottomAnchor, constant: 8), // 进度滑块下方8像素
            allButtonsStack.widthAnchor.constraint(lessThanOrEqualTo: bottomBanner.widthAnchor, constant: -32), // 两侧各16像素边距
            
            // 按钮大小约束 - 降低宽度乘数以避免约束冲突
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
    
        // 为底部横幅添加点击手势，点击时返回列表页
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(backButtonTapped))
        bottomBanner.addGestureRecognizer(tapGesture)
        bottomBanner.isUserInteractionEnabled = true
        
        // 为歌曲标题容器添加点击事件
        songTitleContainer.addTarget(self, action: #selector(backButtonTapped), for: .touchUpInside)
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
        
        // 监听进度更新通知，用于同步播放页拖动后的进度
        NotificationCenter.default.addObserver(self, selector: #selector(handleProgressUpdateNotification), name: .musicPlayerProgressChanged, object: nil)
        
        // 配置时间标签
        timeLabel.text = formatTime(musicPlayer.currentTime)
        totalTimeLabel.text = formatTime(musicPlayer.totalTime)
        
        // 初始化滑块位置
        let progress = Float(musicPlayer.currentTime / max(musicPlayer.totalTime, 0.1)) // 防止除以0
        progressSlider.value = progress
        // 播放器观察者设置完成
    }
    
    // 处理进度更新通知
    @objc private func handleProgressUpdateNotification(_ notification: Notification) {
        if let userInfo = notification.userInfo,
           let currentTime = userInfo["currentTime"] as? TimeInterval,
           let totalTime = userInfo["totalTime"] as? TimeInterval {
            
            // 更新滑块和时间标签
            let progress = Float(currentTime / max(totalTime, 0.1)) // 防止除以0
            progressSlider.value = progress
            timeLabel.text = formatTime(currentTime)
            print("[MusicPlayerViewController] 收到进度更新通知: \(currentTime)/\(totalTime)")
        }
    }
    
    // 频谱数据回调功能已移除
    
    // 加载歌词
    private func loadLyrics() {
        print("[MusicPlayerViewController] ===== 开始加载歌词 =====")
        // 清空之前的歌词
        lyrics.removeAll()
        
        // 先尝试使用已有的歌词缓存
        if !music.lyrics.isEmpty {
            print("[MusicPlayerViewController] 使用已缓存的歌词数据，共\(music.lyrics.count)行")
            lyrics = music.lyrics
        } 
        // 尝试从文件加载歌词
        else if let lyricsURL = music.lyricsURL {
            print("[MusicPlayerViewController] 尝试从文件加载歌词: \(lyricsURL.lastPathComponent)")
            print("[MusicPlayerViewController] 歌词文件路径: \(lyricsURL.path)")
            
            // 检查文件是否存在
            if FileManager.default.fileExists(atPath: lyricsURL.path) {
                print("[MusicPlayerViewController] 歌词文件存在")
            } else {
                print("[MusicPlayerViewController] 歌词文件不存在于路径: \(lyricsURL.path)")
            }
            
            // 为歌词加载添加访问权限处理
            var shouldStopAccess = false
            if lyricsURL.startAccessingSecurityScopedResource() {
                shouldStopAccess = true
                print("[MusicPlayerViewController] 成功获取歌词文件临时访问权限")
            } else {
                print("[MusicPlayerViewController] 未能获取歌词文件临时访问权限")
            }
            
            // 尝试解析歌词
            if let parsedLyrics = LyricsParser.parseLyrics(from: lyricsURL) {
                if !parsedLyrics.isEmpty {
                    lyrics = parsedLyrics
                    music.lyrics = parsedLyrics // 缓存解析结果
                    print("[MusicPlayerViewController] 成功解析歌词，共\(lyrics.count)行")
                } else {
                    print("[MusicPlayerViewController] 歌词文件存在但内容为空或格式错误")
                }
            } else {
                print("[MusicPlayerViewController] 解析歌词文件失败")
            }
            
            // 释放访问权限
            if shouldStopAccess {
                lyricsURL.stopAccessingSecurityScopedResource()
                print("[MusicPlayerViewController] 已释放歌词文件访问权限")
            }
        } else {
            print("[MusicPlayerViewController] 音乐项没有关联的歌词URL")
        }
        
        // 如果没有歌词，添加默认文本
        if lyrics.isEmpty {
            if music.lyricsURL != nil {
                // 有歌词文件路径但未能成功加载
                lyrics.append(LyricsLine(time: 0, text: "无法加载歌词文件"))
                lyrics.append(LyricsLine(time: 1, text: "可能是文件格式不兼容或权限问题"))
            } else {
                // 没有歌词文件
                lyrics.append(LyricsLine(time: 0, text: "暂无歌词"))
            }
        }
        
        // 刷新表格显示
        print("[MusicPlayerViewController] 准备刷新表格，当前歌词数量: \(lyrics.count)")
        DispatchQueue.main.async {
            print("[MusicPlayerViewController] 在主线程执行表格刷新")
            self.tableView.reloadData()
            print("[MusicPlayerViewController] 表格刷新完成")
        }
        
        print("[MusicPlayerViewController] ===== 歌词加载结束 =====")
    }
    
    // 启动更新计时器
    private func startUpdateTimer() {
        stopUpdateTimer() // 先停止之前可能存在的计时器
        updateTimer = Timer.scheduledTimer(timeInterval: 0.5, target: self, selector: #selector(updatePlayProgress), userInfo: nil, repeats: true)
    }
    
    // 停止更新计时器
    private func stopUpdateTimer() {
        updateTimer?.invalidate()
        updateTimer = nil
    }
    
    private var isSeeking = false // 标记是否正在手动拖动滑块
    
    // 更新UI
    private func updateThemeColorUI() {
        // 更新进度滑块颜色
        progressSlider.minimumTrackTintColor = themeColor
        
        // 重新创建滑块缩略图以更新颜色
        let thumbSize = CGSize(width: 14, height: 14)
        let cornerRadius: CGFloat = 4.5
        let thumbImage = UIGraphicsImageRenderer(size: thumbSize).image { context in
            let ctx = context.cgContext
            
            // 创建圆角矩形路径
            let rect = CGRect(x: 0, y: 0, width: thumbSize.width, height: thumbSize.height)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius)
            
            // 填充内部，使用与进度条一致的颜色
            ctx.setFillColor(themeColor.cgColor)
            ctx.addPath(path.cgPath)
            ctx.fillPath()
        }
        
        progressSlider.setThumbImage(thumbImage, for: .normal)
        progressSlider.setThumbImage(thumbImage, for: .highlighted)
        
        // 更新歌词表格视图
        tableView.reloadData()
    }
    
    private func updateUI() {
        
        // 设置歌曲标题标签的初始文本（虽然默认隐藏）
        if !music.artist.isEmpty && music.artist != "Unknown Artist" {
            songTitleLabel.text = "\(music.title) - \(music.artist)"
        } else {
            songTitleLabel.text = music.title
        }

        // 根据当前播放状态更新播放/暂停按钮图标
        let imageName = musicPlayer.isPlaying ? "pause.fill" : "play.fill"
        playPauseButton.setImage(UIImage(systemName: imageName), for: .normal)
        
        // 更新播放模式和范围锁定按钮
        updatePlayModeButtonImage()
        updateRangeLockButtonImage()
        
        // 初始滚动到第一行歌词
        if !lyrics.isEmpty {
            tableView.scrollToRow(at: IndexPath(row: 0, section: 0), at: .middle, animated: false)
        }
    }
    
    // 更新播放器UI
    @objc private func updatePlayerUI() {
        // 更新标题
        if let currentMusic = musicPlayer.currentMusic {
            // 显示歌曲名 - 艺术家名格式，如果有艺术家信息
            if !currentMusic.artist.isEmpty && currentMusic.artist != "Unknown Artist" {
                title = "\(currentMusic.title) - \(currentMusic.artist)"
            } else {
                title = currentMusic.title
            }
            totalTimeLabel.text = formatTime(musicPlayer.totalTime)

            self.music = currentMusic // 更新当前控制器的music引用
            
            // 更新歌曲标题标签（虽然默认隐藏）
            songTitleLabel.text = title
            
            // 重新加载歌词
            loadLyrics()
            
            // 更新播放/暂停按钮
            let imageName = musicPlayer.isPlaying ? "pause.fill" : "play.fill"
            playPauseButton.setImage(UIImage(systemName: imageName), for: .normal)
            
            // 根据播放状态控制进度更新计时器
            if musicPlayer.isPlaying {
                startUpdateTimer()
            } else {
                stopUpdateTimer()
            }
            
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
    
    // 格式化时间
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time / 60)
        let seconds = Int(time.truncatingRemainder(dividingBy: 60))
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    // 按钮点击事件处理
    @objc private func backButtonTapped() {
        // 发送返回通知，让列表页能感知返回事件
        NotificationCenter.default.post(name: NSNotification.Name("MusicPlayerReturned"), object: nil)
        
        // 使用popViewController返回上一个页面
        navigationController?.popViewController(animated: true)
    }
    
    @objc private func previousButtonTapped() {
        musicPlayer.playPrevious()
        // 移除冗余调用，依赖PlayerStateChanged通知更新UI
    }
    
    @objc private func playPauseButtonTapped() {
        musicPlayer.togglePlayPause()
        // 立即更新UI以确保播放/暂停图标正确切换
        updatePlayerUI()
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
        // 添加调试打印
        
        // 执行跳转
        let seekTime = TimeInterval(slider.value) * musicPlayer.totalTime
        musicPlayer.seek(to: seekTime)
        
        // 立即更新UI
        timeLabel.text = formatTime(seekTime)
        
        // 重置isSeeking状态并重启计时器
        isSeeking = false
        startUpdateTimer()
        
        // 更新歌词显示
        updateLyricDisplay()
        
        // 确保UI更新正确，直接设置滑块位置
        progressSlider.value = slider.value
        
        // 根据播放状态控制计时器
        if musicPlayer.isPlaying {
            // 正在播放时启动计时器
            startUpdateTimer()
        } else {
            // 暂停状态时停止计时器
            stopUpdateTimer()
        }
        
        // 发送通知，通知其他页面（如MusicListViewController）更新滑块位置
        NotificationCenter.default.post(name: .musicPlayerProgressChanged, object: nil, userInfo: ["currentTime": seekTime, "totalTime": musicPlayer.totalTime])
    }
    
    // 更新进度
    @objc private func updatePlayProgress() {
        // 只有当播放器正在播放且用户不在拖动滑块时才更新UI
        if musicPlayer.isPlaying && !isSeeking {
            let progress = musicPlayer.currentTime / musicPlayer.totalTime
            
            progressSlider.value = Float(progress)
            
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
    
    // 更新歌词显示
    private func updateLyricDisplay() {
        // 添加额外的空数组检查
        guard !lyrics.isEmpty else { return }
        
        let newIndex = LyricsParser.getCurrentLyricIndex(time: musicPlayer.currentTime, lyrics: lyrics)
        
        // 严格确保索引在有效范围内，防止任何可能的越界
        let safeIndex = min(max(newIndex, 0), lyrics.count - 1)
        
        if safeIndex != currentLyricIndex {
            currentLyricIndex = safeIndex
            
            // 在滚动前再次检查歌词数组是否为空，确保安全
            if !lyrics.isEmpty {
                // 使用主线程确保UI操作安全
                DispatchQueue.main.async {
                    // 再次确认索引在有效范围内
                    let finalIndex = min(max(safeIndex, 0), self.lyrics.count - 1)
                    
                    // 只有当索引有效时才滚动
                    if finalIndex >= 0 && finalIndex < self.lyrics.count {
                        let indexPath = IndexPath(row: finalIndex, section: 0)
                        self.tableView.scrollToRow(at: indexPath, at: .middle, animated: true)
                        self.tableView.reloadData() // 刷新表格以更新高亮状态
                    }
                }
            }
        }
    }
    
    // UITableViewDataSource 方法
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return lyrics.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "lyricCell", for: indexPath)
        cell.backgroundColor = .clear
        
        let lyricLine = lyrics[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = lyricLine.text
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
        return cell
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 50 // 固定行高，使歌词显示更美观
    }
}



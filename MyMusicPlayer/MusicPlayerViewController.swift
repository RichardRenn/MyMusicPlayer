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
        view.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.98) // 与列表页保持一致的半透明背景
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = false
        return view
    }()
    
    // 波形图视图 - 替换歌曲标题标签
    private let waveformView: WaveformView = {
        let view = WaveformView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        return view
    }()
    
    // 保留歌曲标题标签但默认隐藏
    private let songTitleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .left
        label.isHidden = true
        return label
    }()
    
    private let progressSlider: UISlider = {
        let slider = UISlider()
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.minimumValue = 0.0
        slider.maximumValue = 1.0
        slider.minimumTrackTintColor = .tintColor
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
            ctx.setFillColor(UIColor.tintColor.cgColor)
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
        startUpdateTimer()
        updateUI()
        
        // 添加左滑手势支持返回功能
        setupSwipeGesture()
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
        // 移除通知监听
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name("PlayerStateChanged"), object: nil)
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
        bottomBanner.addSubview(waveformView) // 添加波形图视图
        bottomBanner.addSubview(songTitleLabel) // 保留歌曲标题标签但默认隐藏
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
        allButtonsStack.spacing = 14

        bottomBanner.addSubview(allButtonsStack)

        // 为底部横幅添加悬浮样式和圆角
        bottomBanner.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.98) // 添加半透明背景色
        // bottomBanner.layer.shadowColor = UIColor.black.cgColor // 阴影颜色为黑色。
        // bottomBanner.layer.shadowOffset = CGSize(width: 0, height: -2) // 阴影向上偏移 2 个点（height = -2），因为 banner 在底部，要让阴影“向上”显示
        // bottomBanner.layer.shadowOpacity = 0.2 // 阴影不透明度为 0.1（很淡的阴影）
        // bottomBanner.layer.shadowRadius = 1 // 阴影的模糊半径
        // bottomBanner.layer.masksToBounds = false // 保留阴影。（如果设为 true，圆角之外的部分会被裁掉，阴影也会被剪掉，看不见了。）
        bottomBanner.layer.cornerRadius = 24 // 让视图的角变圆，半径是 24
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
            bottomBanner.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            bottomBanner.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.16), // 屏幕高度的16%
            
            // 波形图 - 水平居中显示，相对于进度条上方
            waveformView.centerXAnchor.constraint(equalTo: bottomBanner.centerXAnchor),
            waveformView.widthAnchor.constraint(equalTo: bottomBanner.widthAnchor, multiplier: 0.8),
            waveformView.bottomAnchor.constraint(equalTo: progressSlider.topAnchor, constant: -8),
            waveformView.heightAnchor.constraint(equalToConstant: 30),
            
            // 歌曲标题 - 靠左显示，相对于进度条上方（默认隐藏）
            songTitleLabel.leadingAnchor.constraint(equalTo: bottomBanner.leadingAnchor, constant: 16),
            songTitleLabel.widthAnchor.constraint(lessThanOrEqualTo: bottomBanner.widthAnchor, constant: -32),
            songTitleLabel.bottomAnchor.constraint(equalTo: progressSlider.topAnchor, constant: -8),
            
            // 进度条（隐藏）- 相对于按钮组上方定位
            progressView.leadingAnchor.constraint(equalTo: bottomBanner.leadingAnchor, constant: 16), // 左侧16像素边距
            progressView.trailingAnchor.constraint(equalTo: bottomBanner.trailingAnchor, constant: -16), // 右侧16像素边距
            progressView.bottomAnchor.constraint(equalTo: allButtonsStack.topAnchor, constant: -6), // 按钮组上方6像素
            
            // 进度滑块 - 相对于按钮组上方定位
            progressSlider.leadingAnchor.constraint(equalTo: bottomBanner.leadingAnchor, constant: 16), // 左侧16像素边距
            progressSlider.trailingAnchor.constraint(equalTo: bottomBanner.trailingAnchor, constant: -16), // 右侧16像素边距
            progressSlider.bottomAnchor.constraint(equalTo: allButtonsStack.topAnchor, constant: -6), // 按钮组上方6像素
            
            // 时间标签 - 相对于进度滑块下方定位
            timeLabel.leadingAnchor.constraint(equalTo: bottomBanner.leadingAnchor, constant: 16), // 左侧16像素边距
            timeLabel.topAnchor.constraint(equalTo: progressSlider.bottomAnchor, constant: 4), // 固定4像素顶部边距
            
            totalTimeLabel.trailingAnchor.constraint(equalTo: bottomBanner.trailingAnchor, constant: -16), // 右侧16像素边距
            totalTimeLabel.topAnchor.constraint(equalTo: progressSlider.bottomAnchor, constant: 4), // 固定4像素顶部边距
            
            // 合并的按钮组 - 居中显示
            allButtonsStack.centerXAnchor.constraint(equalTo: bottomBanner.centerXAnchor),
            allButtonsStack.bottomAnchor.constraint(equalTo: bottomBanner.bottomAnchor, constant: -1), // 固定1像素底部边距
            allButtonsStack.widthAnchor.constraint(lessThanOrEqualTo: bottomBanner.widthAnchor, constant: -32), // 两侧各16像素边距
            
            // 按钮大小约束
            previousButton.widthAnchor.constraint(equalTo: bottomBanner.heightAnchor, multiplier: 0.45),
            previousButton.heightAnchor.constraint(equalTo: bottomBanner.heightAnchor, multiplier: 0.45),
            
            playPauseButton.widthAnchor.constraint(equalTo: bottomBanner.heightAnchor, multiplier: 0.45),
            playPauseButton.heightAnchor.constraint(equalTo: bottomBanner.heightAnchor, multiplier: 0.45),
            
            nextButton.widthAnchor.constraint(equalTo: bottomBanner.heightAnchor, multiplier: 0.45),
            nextButton.heightAnchor.constraint(equalTo: bottomBanner.heightAnchor, multiplier: 0.45),
            
            playModeButton.widthAnchor.constraint(equalTo: bottomBanner.heightAnchor, multiplier: 0.45),
            playModeButton.heightAnchor.constraint(equalTo: bottomBanner.heightAnchor, multiplier: 0.45),
            
            rangeLockButton.widthAnchor.constraint(equalTo: bottomBanner.heightAnchor, multiplier: 0.45),
            rangeLockButton.heightAnchor.constraint(equalTo: bottomBanner.heightAnchor, multiplier: 0.45)
        ])
    
        // 为底部横幅添加点击手势，点击时返回列表页
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(backButtonTapped))
        bottomBanner.addGestureRecognizer(tapGesture)
        bottomBanner.isUserInteractionEnabled = true
        
        // 为波形图添加点击手势
        let waveformTapGesture = UITapGestureRecognizer(target: self, action: #selector(backButtonTapped))
        waveformView.addGestureRecognizer(waveformTapGesture)
        waveformView.isUserInteractionEnabled = true
        
        // 为歌曲标题添加点击手势（虽然默认隐藏）
        let titleTapGesture = UITapGestureRecognizer(target: self, action: #selector(backButtonTapped))
        songTitleLabel.addGestureRecognizer(titleTapGesture)
        songTitleLabel.isUserInteractionEnabled = true
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
        progressView.progress = 0
        
        // 初始化进度滑块
        progressSlider.value = 0
        
        // 配置时间标签
        timeLabel.text = "00:00"
        totalTimeLabel.text = "00:00"
    }
    
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
        updateTimer = Timer.scheduledTimer(timeInterval: 0.1, target: self, selector: #selector(updateProgress), userInfo: nil, repeats: true)
    }
    
    // 停止更新计时器
    private func stopUpdateTimer() {
        updateTimer?.invalidate()
        updateTimer = nil
    }
    
    private var isSeeking = false // 标记是否正在手动拖动滑块
    
    // 更新UI
    private func updateUI() {
        
        // 设置歌曲标题标签的初始文本（虽然默认隐藏）
        if !music.artist.isEmpty && music.artist != "Unknown Artist" {
            songTitleLabel.text = "\(music.title) - \(music.artist)"
        } else {
            songTitleLabel.text = music.title
        }
        
        // 更新波形图动画状态
        print("[MusicPlayerViewController] 更新波形图动画状态: \(musicPlayer.isPlaying)")
        waveformView.isAnimating = musicPlayer.isPlaying

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
            
            // 更新波形图动画状态
            print("[MusicPlayerViewController] updatePlayerUI - 设置波形图动画状态: \(musicPlayer.isPlaying)")
            waveformView.isAnimating = musicPlayer.isPlaying
            
            // 更新播放模式和范围锁定按钮
            updatePlayModeButtonImage()
            updateRangeLockButtonImage()

            // 只有当用户不在拖动滑块时才更新UI
            if !isSeeking {
                // 更新进度条和滑块
                let progress = Float(musicPlayer.currentTime / musicPlayer.totalTime)
                progressView.progress = progress
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
        // 立即更新UI（虽然playMusic方法会发送通知，但这里添加冗余调用确保UI立即响应）
        updatePlayerUI()
    }
    
    @objc private func playPauseButtonTapped() {
        musicPlayer.togglePlayPause()
        // 立即更新UI以确保播放/暂停图标正确切换
        updatePlayerUI()
    }
    
    @objc private func nextButtonTapped() {
        musicPlayer.playNext()
        // 立即更新UI（虽然playMusic方法会发送通知，但这里添加冗余调用确保UI立即响应）
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
        
        // 立即更新UI
        progressView.progress = slider.value
        timeLabel.text = formatTime(seekTime)
        
        // 发送通知，通知其他页面（如MusicListViewController）更新滑块位置
        NotificationCenter.default.post(name: .musicPlayerProgressChanged, object: nil, userInfo: ["currentTime": seekTime, "totalTime": musicPlayer.totalTime])
        
        // 更新歌词显示
        updateLyricDisplay()
        
        if musicPlayer.isPlaying {
            startUpdateTimer()
        }
    }
    
    // 更新进度
    @objc private func updateProgress() {
        // 只有当用户不在拖动滑块时才更新UI
        if !isSeeking {
            // 更新进度条和滑块
            let progress = musicPlayer.currentTime / musicPlayer.totalTime
            progressView.progress = Float(progress)
            progressSlider.value = Float(progress) // 同时更新滑块位置
            
            // 更新时间标签
            timeLabel.text = formatTime(musicPlayer.currentTime)
            totalTimeLabel.text = formatTime(musicPlayer.totalTime)
            
            // 更新歌词显示
            updateLyricDisplay()
        }
    }
    
    // 更新歌词显示
    private func updateLyricDisplay() {
        guard !lyrics.isEmpty else { return }
        
        let newIndex = LyricsParser.getCurrentLyricIndex(time: musicPlayer.currentTime, lyrics: lyrics)
        
        if newIndex != currentLyricIndex {
            // 确保索引在有效范围内
            currentLyricIndex = min(max(newIndex, 0), lyrics.count - 1)
            
            // 滚动到当前歌词行，使其居中显示
            tableView.scrollToRow(at: IndexPath(row: currentLyricIndex, section: 0), at: .middle, animated: true)
            tableView.reloadData() // 刷新表格以更新高亮状态
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
            content.textProperties.color = .tintColor
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

// 波形图视图 - 简单模拟音量变化的波形效果
class WaveformView: UIView {
    
    // 是否正在动画
    var isAnimating: Bool = false {
        didSet {
            print("[WaveformView] isAnimating changed to: \(isAnimating)")
            if isAnimating {
                startAnimating()
            } else {
                stopAnimating()
            }
        }
    }
    
    // 波形条的数量
    private let barCount: Int = 24
    
    // 波形条的宽度
    private let barWidth: CGFloat = 3.0
    
    // 波形条之间的间距
    private let barSpacing: CGFloat = 4.0
    
    // 波形条的颜色
    private let barColor: UIColor = .tintColor
    
    // 上半部分波形条数组
    private var topBars: [UIView] = []
    
    // 下半部分波形条数组
    private var bottomBars: [UIView] = []
    
    // 动画计时器
    private var animationTimer: Timer?
    
    // 基础波形高度数组（确保为正数）
    private var baseHeights: [CGFloat] = []
    
    // 动画开始时间
    private var animationStartTime: TimeInterval = 0
    
    // 初始化
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupWaveform()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupWaveform()
    }
    
    // 设置波形图
    private func setupWaveform() {
        print("[WaveformView] 设置波形图开始")
        // 清空现有的波形条
        topBars.forEach { $0.removeFromSuperview() }
        bottomBars.forEach { $0.removeFromSuperview() }
        topBars.removeAll()
        bottomBars.removeAll()
        baseHeights.removeAll()
        
        // 计算可用宽度并调整间距
        let availableWidth = bounds.width
        let totalBarWidth = CGFloat(barCount) * barWidth
        let totalSpacing = CGFloat(barCount - 1) * barSpacing
        
        var effectiveSpacing = barSpacing
        if totalBarWidth + totalSpacing > availableWidth {
            effectiveSpacing = max(1.0, (availableWidth - totalBarWidth) / CGFloat(barCount - 1))
            print("[WaveformView] 调整间距为: \(effectiveSpacing)")
        }
        
        // 创建波形条（上下对称）
        for i in 0..<barCount {
            // 生成基础高度（确保为正数）
            let baseHeight = 5.0 + 8.0 * abs(sin(Double(i) * 0.3 + Double.random(in: 0...1)))
            baseHeights.append(CGFloat(baseHeight))
            
            // 创建上半部分波形条 - 只保留顶部圆角
            let topBar = UIView()
            topBar.backgroundColor = barColor
            topBar.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner] // 只设置顶部两个角的圆角
            topBar.layer.cornerRadius = barWidth / 2
            topBar.translatesAutoresizingMaskIntoConstraints = false
            addSubview(topBar)
            topBars.append(topBar)
            
            // 创建下半部分波形条 - 只保留底部圆角
            let bottomBar = UIView()
            bottomBar.backgroundColor = barColor
            bottomBar.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner] // 只设置底部两个角的圆角
            bottomBar.layer.cornerRadius = barWidth / 2
            bottomBar.translatesAutoresizingMaskIntoConstraints = false
            addSubview(bottomBar)
            bottomBars.append(bottomBar)
            
            // 设置上半部分约束
            NSLayoutConstraint.activate([
                topBar.widthAnchor.constraint(equalToConstant: barWidth),
                topBar.bottomAnchor.constraint(equalTo: centerYAnchor), // 从中间向上延伸（修改为bottomAnchor确保与中心线对齐）
                topBar.heightAnchor.constraint(equalToConstant: baseHeights[i])
            ])
            
            // 设置下半部分约束
            NSLayoutConstraint.activate([
                bottomBar.widthAnchor.constraint(equalToConstant: barWidth),
                bottomBar.topAnchor.constraint(equalTo: centerYAnchor), // 从中间向下延伸（修改为topAnchor确保与中心线对齐）
                bottomBar.heightAnchor.constraint(equalToConstant: baseHeights[i])
            ])
            
            // 设置水平位置（上下条水平对齐，确保整体水平居中）
            let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * effectiveSpacing
            let startOffset = (bounds.width - totalWidth) / 2
            let xOffset = startOffset + CGFloat(i) * (barWidth + effectiveSpacing)
            topBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: xOffset).isActive = true
            bottomBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: xOffset).isActive = true
        }
        
        print("[WaveformView] 波形图设置完成，创建了\(barCount * 2)个波形条（上下各\(barCount)个）")
    }
    
    // 开始动画
    private func startAnimating() {
        print("[WaveformView] 开始动画")
        // 停止之前的动画
        stopAnimating()
        
        // 记录动画开始时间
        animationStartTime = Date().timeIntervalSince1970
        
        // 创建新的动画计时器
        animationTimer = Timer.scheduledTimer(timeInterval: 0.2, target: self, selector: #selector(updateWaveform), userInfo: nil, repeats: true)
        print("[WaveformView] 动画计时器已启动，间隔: 0.2秒")
    }
    
    // 停止动画
    private func stopAnimating() {
        print("[WaveformView] 停止动画")
        animationTimer?.invalidate()
        animationTimer = nil
        
        // 重置波形条高度 - 直接设置，不使用动画
        DispatchQueue.main.async {
            for (index, (topBar, bottomBar)) in zip(self.topBars, self.bottomBars).enumerated() {
                // 移除旧的高度约束
                NSLayoutConstraint.deactivate(topBar.constraints.filter { $0.firstAttribute == .height })
                NSLayoutConstraint.deactivate(bottomBar.constraints.filter { $0.firstAttribute == .height })
                
                // 设置静态状态下的高度（稍微缩小的基础高度）
                let staticHeight = max(0.0, self.baseHeights[index] * 0.9)
                
                // 更新上半部分约束
                let topHeightConstraint = topBar.heightAnchor.constraint(equalToConstant: staticHeight)
                topHeightConstraint.isActive = true
                
                // 更新下半部分约束
                let bottomHeightConstraint = bottomBar.heightAnchor.constraint(equalToConstant: staticHeight)
                bottomHeightConstraint.isActive = true
                
                // 只打印前几个条的高度变化，避免日志过多
                if index < 5 {
                    print("[WaveformView] 停止时重置条 \(index) 高度到: \(staticHeight)")
                }
            }
            
            // 强制布局更新
            self.setNeedsLayout()
            self.layoutIfNeeded()
        }
    }
    
    // 更新波形图
    @objc private func updateWaveform() {
        // 计算动画时间偏移
        let currentTime = Date().timeIntervalSince1970
        let animationTime = currentTime - animationStartTime
        
        // 使用不同频率的正弦波创建更自然的波形效果
        let baseFrequency = 2.0
        let secondaryFrequency = 5.0
        let tertiaryFrequency = 0.5
        
        // 更新每个波形条
        for (index, (topBar, bottomBar)) in zip(topBars, bottomBars).enumerated() {
            // 为每个波形条生成独特的动画模式
            let barOffset = Double(index) * 0.2
            
            // 主波形 - 快速变化
            let primaryWave = sin(animationTime * baseFrequency + barOffset)
            
            // 次波形 - 中等变化
            let secondaryWave = sin(animationTime * secondaryFrequency + barOffset * 0.5)
            
            // 基础波形 - 缓慢变化的基础高度
            let baseWave = 0.5 + 0.5 * sin(animationTime * tertiaryFrequency + barOffset * 0.1)
            
            // 组合波形，确保为正数
            let combinedWave = abs(primaryWave * 0.6 + secondaryWave * 0.4)
            
            // 计算最终高度，确保为正数且有最小高度
            let targetHeight = max(0.0, baseHeights[index] * CGFloat(baseWave) * (0.8 + 1.2 * CGFloat(combinedWave)))
            
            // 移除旧的高度约束
            NSLayoutConstraint.deactivate(topBar.constraints.filter { $0.firstAttribute == .height })
            NSLayoutConstraint.deactivate(bottomBar.constraints.filter { $0.firstAttribute == .height })
            
            // 添加新的高度约束（上下对称）
            let topHeightConstraint = topBar.heightAnchor.constraint(equalToConstant: targetHeight)
            topHeightConstraint.priority = .required
            topHeightConstraint.isActive = true
            
            let bottomHeightConstraint = bottomBar.heightAnchor.constraint(equalToConstant: targetHeight)
            bottomHeightConstraint.priority = .required
            bottomHeightConstraint.isActive = true
            
            // 只打印前几个条的高度变化，避免日志过多
            if index < 2 {
                print("[WaveformView] 条 \(index) 高度更新为: \(targetHeight)")
            }
        }
        
        // 直接布局更新，不使用UIView.animate
        setNeedsLayout()
        layoutIfNeeded()
    }
    
    // 重写layoutSubviews以适应视图大小变化
    override func layoutSubviews() {
        super.layoutSubviews()
        
        // 重新设置波形图
        setupWaveform()
    }
}

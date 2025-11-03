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
        // 根据设备型号设置不同颜色
        let isiPhone13Mini = UIScreen.main.bounds.size == CGSize(width: 375, height: 812) && UIDevice.current.userInterfaceIdiom == .phone
        slider.minimumTrackTintColor = isiPhone13Mini ? .systemBlue : .tintColor
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
            ctx.setFillColor(isiPhone13Mini ? UIColor.systemBlue.cgColor : UIColor.tintColor.cgColor)
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
        // 根据当前播放状态决定是否启动计时器
        if musicPlayer.isPlaying {
            startUpdateTimer()
        } else {
            stopUpdateTimer()
        }
        updateUI()
        
        // 添加左滑手势支持返回功能
        setupSwipeGesture()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // 进入播放页时启用频谱分析
        musicPlayer.isSpectrumAnalysisEnabled = true
        print("[MusicPlayerViewController] 进入播放页，已启用频谱分析")
        
        // 如果正在播放，确保FFT分析器已启动
        if musicPlayer.isPlaying {
            musicPlayer.setupFFTAnalysis()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // 离开播放页时禁用频谱分析，节省性能
        musicPlayer.isSpectrumAnalysisEnabled = false
        print("[MusicPlayerViewController] 离开播放页，已禁用频谱分析")
        
        // 确保波形图停止动画
        waveformView.isAnimating = false
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
            bottomBanner.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -1),
            bottomBanner.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.14), // 屏幕高度的16%
            
            // 波形图 - 调整位置，确保在进度条上方且可见
            waveformView.centerXAnchor.constraint(equalTo: bottomBanner.centerXAnchor),
            waveformView.bottomAnchor.constraint(equalTo: progressSlider.topAnchor, constant: -4),
            waveformView.topAnchor.constraint(equalTo: bottomBanner.topAnchor, constant: 8),
            waveformView.widthAnchor.constraint(equalTo: bottomBanner.widthAnchor, constant: -32), // 与进度条宽度一致，左右各留16像素边距
            
            // 歌曲标题 - 靠左显示，相对于进度条上方（默认隐藏）
            songTitleLabel.leadingAnchor.constraint(equalTo: bottomBanner.leadingAnchor, constant: 16),
            songTitleLabel.widthAnchor.constraint(lessThanOrEqualTo: bottomBanner.widthAnchor, constant: -32),
            songTitleLabel.bottomAnchor.constraint(equalTo: progressSlider.topAnchor, constant: -8),
            
            // 进度条（隐藏）- 相对于按钮组上方定位
            progressView.leadingAnchor.constraint(equalTo: bottomBanner.leadingAnchor, constant: 16), // 左侧16像素边距
            progressView.trailingAnchor.constraint(equalTo: bottomBanner.trailingAnchor, constant: -16), // 右侧16像素边距
            progressView.bottomAnchor.constraint(equalTo: allButtonsStack.topAnchor, constant: -8), // 按钮组上方8像素
            
            // 进度滑块 - 相对于按钮组上方定位
            progressSlider.leadingAnchor.constraint(equalTo: bottomBanner.leadingAnchor, constant: 16), // 左侧16像素边距
            progressSlider.trailingAnchor.constraint(equalTo: bottomBanner.trailingAnchor, constant: -16), // 右侧16像素边距
            progressSlider.bottomAnchor.constraint(equalTo: allButtonsStack.topAnchor, constant: -8), // 按钮组上方8像素
            
            // 时间标签 - 相对于进度滑块下方定位
            timeLabel.leadingAnchor.constraint(equalTo: bottomBanner.leadingAnchor, constant: 16), // 左侧16像素边距
            timeLabel.topAnchor.constraint(equalTo: progressSlider.bottomAnchor, constant: 4), // 固定4像素顶部边距
            
            totalTimeLabel.trailingAnchor.constraint(equalTo: bottomBanner.trailingAnchor, constant: -16), // 右侧16像素边距
            totalTimeLabel.topAnchor.constraint(equalTo: progressSlider.bottomAnchor, constant: 4), // 固定4像素顶部边距
            
            // 合并的按钮组 - 居中显示
            allButtonsStack.centerXAnchor.constraint(equalTo: bottomBanner.centerXAnchor),
            allButtonsStack.bottomAnchor.constraint(equalTo: bottomBanner.bottomAnchor, constant: -8), // 固定8像素底部边距
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
        
        // 设置频谱数据回调
        setupSpectrumDataCallback()
    }
    
    // 设置频谱数据回调
    private func setupSpectrumDataCallback() {
        musicPlayer.spectrumDataCallback = { [weak self] fftData in
            // 更新波形视图
            self?.waveformView.updateWithSpectrumData(fftData)
        }
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
        stopUpdateTimer() // 先停止之前可能存在的计时器
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
        // 添加调试打印

        
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
        
        // 无论播放状态如何，都需要重置isSeeking标志
        // 不再使用延迟启动计时器，因为MusicPlayer的seek方法已经内部管理了计时器
        isSeeking = false
        
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
    }
    
    // 更新进度
    @objc private func updateProgress() {
        // 只有当播放器正在播放且用户不在拖动滑块时才更新UI
        if musicPlayer.isPlaying && !isSeeking {
            // 添加调试打印

            
            // 更新进度条和滑块
            let progress = musicPlayer.currentTime / musicPlayer.totalTime

            progressView.progress = Float(progress)
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

// 优化的波形图视图 - 专为真实FFT频谱数据设计
class WaveformView: UIView {
    
    // 是否正在动画（控制FFT数据处理和视觉效果）
    var isAnimating: Bool = false {
        didSet {
            if isAnimating {
                // 当设置为动画状态时，清除之前的静态数据缓存
                previousFFTData = nil
                print("[WaveformView] 波形图进入动画模式，准备接收FFT数据")
            } else {
                // 当停止动画时，重置波形条
                resetWaveformBars()
                print("[WaveformView] 波形图进入静态模式")
            }
        }
    }
    
    // 增加波形条数量以更好地展示频谱细节
    private let barCount: Int = 41
    
    // 波形条的宽度
    private let barWidth: CGFloat = 4.5
    
    // 波形条之间的间距
    private let barSpacing: CGFloat = 3
    
    // 波形条的颜色（使用渐变色增强视觉效果）
    private var gradientColors: [UIColor] = [
        .systemBlue.withAlphaComponent(0.95),
        .systemPurple.withAlphaComponent(0.95),
        .systemPink.withAlphaComponent(0.95)
    ]
    
    // 上半部分波形条数组（只显示上半部分波形）
    private var topBars: [UIView] = []
    
    // 上半部分渐变层数组
    private var topGradientLayers: [CAGradientLayer] = []
    
    // 动画计时器
    private var animationTimer: Timer?
    
    // 基础波形高度数组（为真实频谱数据优化）
    private var baseHeights: [CGFloat] = []
    
    // 最大波形高度（根据视图高度动态调整）
    private var maxBarHeight: CGFloat = 0
    
    // 存储上一次的FFT数据，用于平滑过渡
    private var previousFFTData: [Float]? = nil
    
    // 快速滚动标志，用于暂停动画
    public var isFastScrolling: Bool = false
    
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
        // 清空现有的波形条和渐变层
        topBars.forEach { $0.removeFromSuperview() }
        topGradientLayers.forEach { $0.removeFromSuperlayer() }
        
        topBars.removeAll()
        topGradientLayers.removeAll()
        baseHeights.removeAll()
        
        // 计算可用宽度并调整间距
        let availableWidth = bounds.width
        let totalBarWidth = CGFloat(barCount) * barWidth
        let totalSpacing = CGFloat(barCount - 1) * barSpacing
        
        var effectiveSpacing = barSpacing
        if totalBarWidth + totalSpacing > availableWidth {
            effectiveSpacing = max(1.0, (availableWidth - totalBarWidth) / CGFloat(barCount - 1))
        }
        
        // 计算最大波形高度（整个视图高度，因为只显示上半部分）
        maxBarHeight = bounds.height * 0.95
        
        // 创建波形条（只创建上半部分）
        for i in 0..<barCount {
            // 为真实频谱数据设计的基础高度（不再使用随机值）
            // 基于频率分布的对数特性，低频部分可以有更高的基础高度
            let frequencyFactor = CGFloat(i) / CGFloat(barCount)
            // 使用对数曲线分配基础高度，让低频部分（左侧）有更高的基础高度
            let logFactor = 1.0 - log10(frequencyFactor * 9.0 + 1.0) / log10(10.0)
            // 大幅提高基础高度系数，让波形更加明显
            let baseHeight = maxBarHeight * 0.4 + maxBarHeight * 0.5 * logFactor
            baseHeights.append(baseHeight)
            
            // 创建上半部分波形条 - 只保留顶部圆角
            let topBar = UIView()
            topBar.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
            topBar.layer.cornerRadius = barWidth / 2
            topBar.clipsToBounds = true
            topBar.translatesAutoresizingMaskIntoConstraints = false
            addSubview(topBar)
            topBars.append(topBar)
            
            // 为上半部分添加渐变层
            let topGradientLayer = CAGradientLayer()
            topGradientLayer.colors = gradientColors.map { $0.cgColor }
            topGradientLayer.startPoint = CGPoint(x: 0.5, y: 1.0)
            topGradientLayer.endPoint = CGPoint(x: 0.5, y: 0.0)
            topGradientLayer.frame = topBar.bounds
            topBar.layer.insertSublayer(topGradientLayer, at: 0)
            topGradientLayers.append(topGradientLayer)
            
            // 设置上半部分约束 - 从底部向上延伸
            let widthConstraint = topBar.widthAnchor.constraint(equalToConstant: barWidth)
            let bottomConstraint = topBar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5) // 从底部向上延伸，留出一点边距
            let heightConstraint = topBar.heightAnchor.constraint(equalToConstant: baseHeights[i])
            
            // 设置高优先级
            widthConstraint.priority = .required
            bottomConstraint.priority = .required
            heightConstraint.priority = .required
            
            // 激活约束
            NSLayoutConstraint.activate([widthConstraint, bottomConstraint, heightConstraint])
            
            // 将高度约束添加到缓存中
            topBarHeightConstraints[topBar] = heightConstraint
            
            // 设置水平位置，确保整体水平居中
            let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * effectiveSpacing
            let startOffset = (bounds.width - totalWidth) / 2
            let xOffset = startOffset + CGFloat(i) * (barWidth + effectiveSpacing)
            
            // 方法2：获取superview中与这些视图相关的约束
            if let superview = topBar.superview {
                let superviewConstraintsToRemove = superview.constraints.filter { constraint in
                    let involvesTopBar = (constraint.firstItem as? UIView == topBar || constraint.secondItem as? UIView == topBar)
                    let isLeadingConstraint = (constraint.firstAttribute == .leading || constraint.secondAttribute == .leading)
                    return involvesTopBar && isLeadingConstraint
                }
                NSLayoutConstraint.deactivate(superviewConstraintsToRemove)
            }
            
            // 创建并激活新的水平位置约束
            let topLeadingConstraint = topBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: xOffset)
            
            // 设置高优先级
            topLeadingConstraint.priority = UILayoutPriority.required
            
            // 激活约束
            NSLayoutConstraint.activate([topLeadingConstraint])
        }
        
        // print("[WaveformView] 波形图设置完成，创建了\(barCount * 2)个波形条（上下各\(barCount)个）")
    }
    
    // 不再需要启动动画方法，因为我们使用实际FFT数据
    private func startAnimating() {
        print("[WaveformView] 开始使用实际FFT数据更新波形图")
    }
    
    // 停止动画（仍然保留以清理可能的资源）
    private func stopAnimating() {
        animationTimer?.invalidate()
        animationTimer = nil
        
        // 重置波形条高度 - 使用updateBarHeight方法保持一致性
        DispatchQueue.main.async {
            for (index, topBar) in self.topBars.enumerated() {
                // 设置静态状态下的高度（稍微缩小的基础高度）
                let staticHeight = max(0.0, self.baseHeights[index] * 0.9)
                
                // 使用统一的更新方法
                self.updateBarHeight(topBar: topBar, height: staticHeight)
            }
            
            // 强制布局更新
            self.layoutIfNeeded()
        }
    }
    
    // 不再使用模拟数据更新波形图，完全依赖实际FFT数据
    // 此方法保留但为空，以避免定时器调用错误
    @objc private func updateWaveform() {
        // 现在只使用实际的FFT数据，不再生成随机模拟数据
    }
    
    // 更新波形图（使用实际频谱数据）
    public func updateWithSpectrumData(_ fftData: [Float]) {
        // 只有在动画模式下才处理数据
        guard isAnimating else {
            return
        }
        
        // 确保有足够的数据
        guard !fftData.isEmpty else {
            resetWaveformBars()
            return
        }
        
        // 过滤掉NaN和无效值，只保留有效的FFT数据
        let validFFTData = fftData.filter { !$0.isNaN && !$0.isInfinite && $0 >= 0 }
        
        // 确保有足够的有效数据
        guard validFFTData.count > Int(Double(fftData.count) * 0.5) else {
            return
        }
        
        // 准备当前FFT数据和前一次数据（用于平滑过渡）
        let currentData = validFFTData
        
        // 如果数据长度变化，重新开始平滑计算
        var smoothData: [Float]
        if let previous = previousFFTData, previous.count == currentData.count {
            // 使用指数移动平均平滑数据
            smoothData = zip(currentData, previous).map { current, prev in
                return current * 0.4 + prev * 0.6 // 给当前数据40%权重，前一次数据60%权重
            }
        } else {
            smoothData = currentData
        }
        
        // 存储当前数据用于下次平滑
        previousFFTData = smoothData
        
        // 更新UI操作
        DispatchQueue.main.async {
            // 更新每个波形条（只更新上半部分）
            for (index, (topBar, topGradient)) in zip(self.topBars, self.topGradientLayers).enumerated() {
                // 实现镜像对称效果：高音在中间，低音在两边
                let centerPosition = CGFloat(self.barCount) / 2.0
                let distanceFromCenter = abs(CGFloat(index) - centerPosition)
                let normalizedDistance = distanceFromCenter / centerPosition
                
                // 优化的FFT数据索引计算
                let linearIndex = Int(normalizedDistance * CGFloat(smoothData.count))
                let fftIndex = min(max(linearIndex, 0), smoothData.count - 1)
                let magnitude = smoothData[fftIndex]
                
                // 确保magnitude是有效值
                guard !magnitude.isNaN && !magnitude.isInfinite && magnitude >= 0 else {
                    continue
                }
                
                // 改进的对数缩放
                let logMagnitude = magnitude > 0 ? 20.0 * log10(max(magnitude, 1e-10)) : -120.0
                
                // 分贝映射范围
                let minDecibels: Double = -80.0
                let maxDecibels: Double = -10.0
                
                // 简化的归一化计算
                let adjustedMagnitude = logMagnitude - Float(minDecibels)
                let range = Float(maxDecibels) - Float(minDecibels)
                let rawNormalized = adjustedMagnitude / range
                let normalizedMagnitude = max(0.0, min(1.0, rawNormalized))
                
                // 计算最终高度
                let dynamicHeight = self.maxBarHeight * CGFloat(normalizedMagnitude)
                let targetHeight = self.baseHeights[index] + dynamicHeight
                
                // 更新波形条高度
                self.updateBarHeight(topBar: topBar, height: targetHeight)
                
                // 更新渐变层frame
                topGradient.frame = topBar.bounds
            }
            
            // 执行动画
            UIView.animate(withDuration: 0.05, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
                self.layoutIfNeeded()
            }
        }
    }
    
    // 在视图大小变化时更新视图尺寸
    override func layoutSubviews() {
        super.layoutSubviews()
        
        // 更新每个波形条的约束
        updateBarConstraints()
        
        // 更新最大波形高度（整个视图高度，因为只显示上半部分）
        maxBarHeight = bounds.height * 0.95
        
        // 更新渐变层frame
        for (topBar, topGradient) in zip(topBars, topGradientLayers) {
            topGradient.frame = topBar.bounds
        }
    }
    
    // 重置波形条高度
    private func resetWaveformBars() {
        // 清除之前的FFT数据缓存
        previousFFTData = nil
        
        // 更新操作
        DispatchQueue.main.async {
            for (index, (topBar, topGradient)) in zip(self.topBars, self.topGradientLayers).enumerated() {
                // 使用静止状态的高度（更小，更稳定）
                let staticHeight = max(0.0, self.baseHeights[index] * 0.5)
                self.updateBarHeight(topBar: topBar, height: staticHeight)
                
                // 更新渐变层frame
                topGradient.frame = topBar.bounds
            }
            
            // 使用动画平滑过渡到静止状态
            UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseInOut, .allowUserInteraction]) {        
                self.layoutIfNeeded()
            }
        }
    }
    
    // 更新单个波形条的高度 - 使用transform替代约束，提高性能
    private func updateBarHeight(topBar: UIView, height: CGFloat) {
        // 缓存基础高度约束，避免重复创建
        if let existingHeightConstraint = topBarHeightConstraints[topBar] {
            existingHeightConstraint.constant = height
        } else {
            // 只在首次创建时添加约束
            let heightConstraint = topBar.heightAnchor.constraint(equalToConstant: height)
            heightConstraint.priority = .required
            heightConstraint.isActive = true
            topBarHeightConstraints[topBar] = heightConstraint
        }
    }
    
    // 缓存高度约束的字典
    private var topBarHeightConstraints: [UIView: NSLayoutConstraint] = [:]
    
    // 更新单个波形条的约束
    private func updateBarConstraints() {
        // 确保波形条已经创建
        guard !topBars.isEmpty else {
            return
        }
        
        // 计算可用宽度并调整间距（与setupWaveform方法保持一致）
        let availableWidth = bounds.width
        let totalBarWidth = CGFloat(barCount) * barWidth
        let totalSpacing = CGFloat(barCount - 1) * barSpacing
        
        var effectiveSpacing = barSpacing
        if totalBarWidth + totalSpacing > availableWidth {
            effectiveSpacing = max(1.0, (availableWidth - totalBarWidth) / CGFloat(barCount - 1))
        }
        
        // 计算整体水平居中的起始偏移量（与setupWaveform方法保持一致）
        let totalWidth = totalBarWidth + CGFloat(barCount - 1) * effectiveSpacing
        let startOffset = (availableWidth - totalWidth) / 2
        
        // 更简单高效的约束管理方式：先清除所有可能的水平约束
        if let superview = topBars.first?.superview {
            // 找出所有与波形条相关的水平约束
            let horizontalConstraints = superview.constraints.filter { constraint in
                let affectsTopBars = topBars.contains { bar in
                    constraint.firstItem as? UIView == bar || constraint.secondItem as? UIView == bar
                }
                let isHorizontalConstraint = constraint.firstAttribute == .leading || constraint.firstAttribute == .trailing
                return affectsTopBars && isHorizontalConstraint
            }
            // 停用所有找到的水平约束
            NSLayoutConstraint.deactivate(horizontalConstraints)
        }
        
        // 重新设置每个波形条的水平位置约束
        for (index, topBar) in topBars.enumerated() {
            // 计算正确的X偏移量（与setupWaveform方法保持一致）
            let xOffset = startOffset + CGFloat(index) * (barWidth + effectiveSpacing)
            
            // 确保移除所有可能的旧约束
            NSLayoutConstraint.deactivate(topBar.constraints.filter { $0.firstAttribute == .leading })
            
            // 创建并激活新的水平位置约束
            let topLeadingConstraint = topBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: xOffset)
            
            // 设置高优先级
            topLeadingConstraint.priority = .required
            
            // 激活约束
            NSLayoutConstraint.activate([topLeadingConstraint])
        }
        
    }
}

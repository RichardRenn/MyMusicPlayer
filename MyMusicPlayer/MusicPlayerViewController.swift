import UIKit
import Foundation
import AVFoundation
import MediaPlayer

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
    
    private let bottomControls: UIView = {
        let view = UIView()
        view.backgroundColor = .secondarySystemBackground
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let progressView: UIProgressView = {
        let progressView = UIProgressView(progressViewStyle: .default)
        progressView.progress = 0
        progressView.translatesAutoresizingMaskIntoConstraints = false
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
    }
    
    deinit {
        stopUpdateTimer()
        // 移除通知监听
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name("PlayerStateChanged"), object: nil)
    }
    
    // 设置播放器观察者
    private func setupPlayerObservers() {
        // 监听当前播放音乐的变化
        NotificationCenter.default.addObserver(self, selector: #selector(updatePlayerUI), name: NSNotification.Name("PlayerStateChanged"), object: nil)
    }
    
    // 更新播放器UI
    @objc private func updatePlayerUI() {
        // 更新标题
        if let currentMusic = musicPlayer.currentMusic {
            title = currentMusic.title
            self.music = currentMusic // 更新当前控制器的music引用
            
            // 重新加载歌词
            loadLyrics()
            
            // 更新播放/暂停按钮
            let imageName = musicPlayer.isPlaying ? "pause.fill" : "play.fill"
            playPauseButton.setImage(UIImage(systemName: imageName), for: .normal)
            
            // 更新播放模式和范围锁定按钮
            updatePlayModeButtonImage()
            updateRangeLockButtonImage()
            
            // 更新进度显示
            totalTimeLabel.text = formatTime(musicPlayer.totalTime)
        }
    }
    
    // 设置UI
    private func setupUI() {
        title = music.title
        view.backgroundColor = .systemBackground
        
        // 设置导航栏左侧返回按钮
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(closeButtonTapped))
        
        // 添加歌词显示表格
        view.addSubview(tableView)
        tableView.delegate = self
        tableView.dataSource = self
        // 注册表格单元格
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "lyricCell")
        
        // 添加底部控制栏
        view.addSubview(bottomControls)
        bottomControls.addSubview(progressView)
        bottomControls.addSubview(timeLabel)
        bottomControls.addSubview(totalTimeLabel)
        bottomControls.addSubview(previousButton)
        bottomControls.addSubview(playPauseButton)
        bottomControls.addSubview(nextButton)
        bottomControls.addSubview(playModeButton)
        bottomControls.addSubview(rangeLockButton)
        
        // 设置约束
        NSLayoutConstraint.activate([
            // 歌词表格
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: bottomControls.topAnchor),
            
            // 底部控制栏
            bottomControls.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomControls.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomControls.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            bottomControls.heightAnchor.constraint(equalToConstant: 120),
            
            // 进度条
            progressView.leadingAnchor.constraint(equalTo: bottomControls.leadingAnchor, constant: 16),
            progressView.trailingAnchor.constraint(equalTo: bottomControls.trailingAnchor, constant: -16),
            progressView.topAnchor.constraint(equalTo: bottomControls.topAnchor, constant: 8),
            
            // 时间标签
            timeLabel.leadingAnchor.constraint(equalTo: bottomControls.leadingAnchor, constant: 16),
            timeLabel.topAnchor.constraint(equalTo: progressView.bottomAnchor, constant: 4),
            
            totalTimeLabel.trailingAnchor.constraint(equalTo: bottomControls.trailingAnchor, constant: -16),
            totalTimeLabel.topAnchor.constraint(equalTo: progressView.bottomAnchor, constant: 4),
            
            // 控制按钮
            previousButton.leadingAnchor.constraint(equalTo: bottomControls.leadingAnchor, constant: 32),
            previousButton.centerYAnchor.constraint(equalTo: bottomControls.centerYAnchor, constant: 20),
            previousButton.widthAnchor.constraint(equalToConstant: 40),
            previousButton.heightAnchor.constraint(equalToConstant: 40),
            
            playPauseButton.leadingAnchor.constraint(equalTo: previousButton.trailingAnchor, constant: 24),
            playPauseButton.centerYAnchor.constraint(equalTo: bottomControls.centerYAnchor, constant: 20),
            playPauseButton.widthAnchor.constraint(equalToConstant: 50),
            playPauseButton.heightAnchor.constraint(equalToConstant: 50),
            
            nextButton.leadingAnchor.constraint(equalTo: playPauseButton.trailingAnchor, constant: 24),
            nextButton.centerYAnchor.constraint(equalTo: bottomControls.centerYAnchor, constant: 20),
            nextButton.widthAnchor.constraint(equalToConstant: 40),
            nextButton.heightAnchor.constraint(equalToConstant: 40),
            
            playModeButton.trailingAnchor.constraint(equalTo: rangeLockButton.leadingAnchor, constant: -24),
            playModeButton.centerYAnchor.constraint(equalTo: bottomControls.centerYAnchor, constant: 20),
            playModeButton.widthAnchor.constraint(equalToConstant: 40),
            playModeButton.heightAnchor.constraint(equalToConstant: 40),
            
            rangeLockButton.trailingAnchor.constraint(equalTo: bottomControls.trailingAnchor, constant: -32),
            rangeLockButton.centerYAnchor.constraint(equalTo: bottomControls.centerYAnchor, constant: 20),
            rangeLockButton.widthAnchor.constraint(equalToConstant: 40),
            rangeLockButton.heightAnchor.constraint(equalToConstant: 40)
        ])
        
        // 添加进度条点击手势
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(progressViewTapped(_:)))
        progressView.addGestureRecognizer(tapGesture)
        progressView.isUserInteractionEnabled = true
    }
    
    // 设置按钮点击事件
    private func setupButtonActions() {
        previousButton.addTarget(self, action: #selector(previousButtonTapped), for: .touchUpInside)
        playPauseButton.addTarget(self, action: #selector(playPauseButtonTapped), for: .touchUpInside)
        nextButton.addTarget(self, action: #selector(nextButtonTapped), for: .touchUpInside)
        playModeButton.addTarget(self, action: #selector(playModeButtonTapped), for: .touchUpInside)
        rangeLockButton.addTarget(self, action: #selector(rangeLockButtonTapped), for: .touchUpInside)
    }
    
    // 加载歌词
    private func loadLyrics() {
        print("===== 开始加载歌词 =====")
        // 清空之前的歌词
        lyrics.removeAll()
        
        // 先尝试使用已有的歌词缓存
        if !music.lyrics.isEmpty {
            print("使用已缓存的歌词数据，共\(music.lyrics.count)行")
            lyrics = music.lyrics
        } 
        // 尝试从文件加载歌词
        else if let lyricsURL = music.lyricsURL {
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
                    music.lyrics = parsedLyrics // 缓存解析结果
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
        print("准备刷新表格，当前歌词数量: \(lyrics.count)")
        DispatchQueue.main.async {
            print("在主线程执行表格刷新")
            self.tableView.reloadData()
            print("表格刷新完成")
        }
        
        print("===== 歌词加载结束 =====")
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
    
    // 更新进度
    @objc private func updateProgress() {
        // 更新进度条
        let progress = musicPlayer.currentTime / musicPlayer.totalTime
        progressView.progress = Float(progress)
        
        // 更新时间标签
        timeLabel.text = formatTime(musicPlayer.currentTime)
        totalTimeLabel.text = formatTime(musicPlayer.totalTime)
        
        // 更新歌词显示
        updateLyricDisplay()
        
        // 更新播放/暂停按钮
        let imageName = musicPlayer.isPlaying ? "pause.fill" : "play.fill"
        playPauseButton.setImage(UIImage(systemName: imageName), for: .normal)
    }
    
    // 更新歌词显示
    private func updateLyricDisplay() {
        if lyrics.isEmpty { return }
        
        let newIndex = LyricsParser.getCurrentLyricIndex(time: musicPlayer.currentTime, lyrics: lyrics)
        
        if newIndex != currentLyricIndex {
            currentLyricIndex = newIndex
            
            // 滚动到当前歌词行，使其居中显示
            tableView.scrollToRow(at: IndexPath(row: currentLyricIndex, section: 0), at: .middle, animated: true)
            tableView.reloadData() // 刷新表格以更新高亮状态
        }
    }
    
    // 更新UI
    private func updateUI() {
        // 更新播放模式按钮
        updatePlayModeButtonImage()
        
        // 更新范围锁定按钮
        updateRangeLockButtonImage()
        
        // 初始滚动到第一行歌词
        if !lyrics.isEmpty {
            tableView.scrollToRow(at: IndexPath(row: 0, section: 0), at: .middle, animated: false)
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
    @objc private func closeButtonTapped() {
        // 使用popViewController返回上一个页面，而不是dismiss
        navigationController?.popViewController(animated: true)
    }
    
    @objc private func previousButtonTapped() {
        musicPlayer.playPrevious()
        // 立即更新UI（虽然playMusic方法会发送通知，但这里添加冗余调用确保UI立即响应）
        updatePlayerUI()
    }
    
    @objc private func playPauseButtonTapped() {
        musicPlayer.togglePlayPause()
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
    
    @objc private func progressViewTapped(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: progressView)
        let progress = location.x / progressView.bounds.width
        let seekTime = TimeInterval(progress) * musicPlayer.totalTime
        musicPlayer.seek(to: seekTime)
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
            content.textProperties.color = .systemBlue
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
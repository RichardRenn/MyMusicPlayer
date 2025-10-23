import UIKit

class ViewController: UIViewController, UIDocumentPickerDelegate {
    
    private let musicScanner = MusicScanner()
    private var selectedDirectoryURL: URL?
    private var securityScopedResources: [URL] = [] // 用于跟踪需要保持访问权限的资源
    private var hasSelectedDirectory = false // 跟踪是否已选择过文件夹
    
    // UI元素
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "欢迎使用音乐播放器"
        label.font = UIFont.systemFont(ofSize: 24, weight: .bold)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.text = "请选择一个包含音乐文件的文件夹"
        label.font = UIFont.systemFont(ofSize: 16)
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let selectButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("选择文件夹", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .medium)
        button.backgroundColor = .systemBlue
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 10
        button.clipsToBounds = true
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(selectButtonTapped), for: .touchUpInside)
        return button
    }()
    
    private let progressView: UIProgressView = {
        let progressView = UIProgressView(progressViewStyle: .default)
        progressView.progress = 0
        progressView.isHidden = true
        progressView.translatesAutoresizingMaskIntoConstraints = false
        return progressView
    }()
    
    private let progressLabel: UILabel = {
        let label = UILabel()
        label.text = "0%"
        label.font = UIFont.systemFont(ofSize: 14)
        label.textAlignment = .center
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    // 设置UI
    private func setupUI() {
        view.backgroundColor = .systemBackground
        
        // 添加UI元素
        view.addSubview(titleLabel)
        view.addSubview(subtitleLabel)
        view.addSubview(selectButton)
        view.addSubview(progressView)
        view.addSubview(progressLabel)
        
        // 设置约束
        NSLayoutConstraint.activate([
            // 标题
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 100),
            
            // 副标题
            subtitleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            
            // 选择按钮
            selectButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            selectButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            selectButton.widthAnchor.constraint(equalToConstant: 200),
            selectButton.heightAnchor.constraint(equalToConstant: 50),
            
            // 进度条
            progressView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            progressView.topAnchor.constraint(equalTo: selectButton.bottomAnchor, constant: 50),
            progressView.widthAnchor.constraint(equalTo: view.widthAnchor, constant: -40),
            
            // 进度标签
            progressLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            progressLabel.topAnchor.constraint(equalTo: progressView.bottomAnchor, constant: 8)
        ])
    }
    
    // 选择文件夹按钮点击事件
    @objc private func selectButtonTapped() {
        let documentPicker = UIDocumentPickerViewController(documentTypes: ["public.folder"], in: .open)
        documentPicker.delegate = self
        documentPicker.allowsMultipleSelection = false
        
        // iOS 14及以上支持文件夹选择
        if #available(iOS 14, *) {
            documentPicker.directoryURL = nil
        }
        
        present(documentPicker, animated: true, completion: nil)
    }
    
    // 通知处理方法已移除，因为MusicListViewController现在直接处理添加文件夹的逻辑
    
    // UIDocumentPickerDelegate 方法
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        
        // 清除之前的权限记录
        clearSecurityScopedResources()
        
        // 尝试获取并保持文件夹访问权限
        if url.startAccessingSecurityScopedResource() {
            securityScopedResources.append(url)
            print("成功获取并保持文件夹访问权限: \(url.lastPathComponent)")
        }
        
        selectedDirectoryURL = url
        hasSelectedDirectory = true // 标记已选择过文件夹
        
        // 显示进度条并隐藏选择按钮
        progressView.isHidden = false
        progressLabel.isHidden = false
        selectButton.isHidden = true
        
        // 开始扫描文件夹
        musicScanner.scanDirectory(url, progressHandler: { [weak self] progress in
            // 更新进度条和标签
            DispatchQueue.main.async { [weak self] in
                self?.progressView.progress = Float(progress)
                self?.progressLabel.text = "\(Int(progress * 100))%"
            }
        }, completionHandler: { [weak self] rootDirectoryItem in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                // 隐藏进度条（选择按钮保持隐藏状态）
                self.progressView.isHidden = true
                self.progressLabel.isHidden = true
                
                // 扫描完成，更新UI
                if let rootItem = rootDirectoryItem {
                    print("扫描完成，找到文件夹: \(rootItem.name)")
                    
                    // 直接跳转到音乐列表页面
                    let musicListVC = MusicListViewController(rootDirectoryItem: rootItem, scanner: self.musicScanner)
                    let navigationController = UINavigationController(rootViewController: musicListVC)
                    navigationController.modalPresentationStyle = .fullScreen
                    self.present(navigationController, animated: true, completion: nil)
                } else {
                    // 扫描失败，显示错误提示
                    let alert = UIAlertController(title: "扫描失败", message: "无法扫描所选文件夹，请重试", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "确定", style: .default))
                    self.present(alert, animated: true)
                }
            }
        })
    }
    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        // 用户取消了选择
        clearSecurityScopedResources()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // 根据是否已选择过文件夹控制按钮可见性
        selectButton.isHidden = hasSelectedDirectory
    }
    
    // 清理安全范围资源的访问权限
    private func clearSecurityScopedResources() {
        for url in securityScopedResources {
            url.stopAccessingSecurityScopedResource()
        }
        securityScopedResources.removeAll()
    }
    
    // 重置文件夹选择状态（供其他控制器调用）
    public func resetSelectionState() {
        hasSelectedDirectory = false
        clearSecurityScopedResources()
        selectedDirectoryURL = nil
        DispatchQueue.main.async {
            self.selectButton.isHidden = false
        }
    }
    
    // 通知处理方法已移除，因为MusicListViewController现在直接处理添加文件夹的逻辑
    
    // 确保在视图控制器销毁时释放所有权限
    deinit {
        clearSecurityScopedResources()
    }
    

}
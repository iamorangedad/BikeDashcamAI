import UIKit
import AVFoundation

class MainViewController: UIViewController {
    private var previewView: UIView!
    private var recordButton: UIButton!
    private var statusLabel: UILabel!
    private var frameCountLabel: UILabel!
    private var cameraManager: SimpleCameraManager!
    private var previewLayer: AVCaptureVideoPreviewLayer?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupCameraManager()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = previewView.bounds
    }
    
    private func setupUI() {
        view.backgroundColor = .black
        
        previewView = UIView()
        previewView.backgroundColor = .darkGray
        previewView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(previewView)
        
        statusLabel = UILabel()
        statusLabel.textColor = .white
        statusLabel.textAlignment = .center
        statusLabel.text = "准备就绪"
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)
        
        frameCountLabel = UILabel()
        frameCountLabel.textColor = .lightGray
        frameCountLabel.textAlignment = .center
        frameCountLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 14, weight: .regular)
        frameCountLabel.text = "保存帧: 0 / 总帧: 0"
        frameCountLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(frameCountLabel)
        
        recordButton = UIButton(type: .system)
        recordButton.setTitle("REC", for: .normal)
        recordButton.backgroundColor = .red
        recordButton.setTitleColor(.white, for: .normal)
        recordButton.layer.cornerRadius = 35
        recordButton.translatesAutoresizingMaskIntoConstraints = false
        recordButton.addTarget(self, action: #selector(toggleRecording), for: .touchUpInside)
        view.addSubview(recordButton)
        
        NSLayoutConstraint.activate([
            previewView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            previewView.bottomAnchor.constraint(equalTo: view.centerYAnchor),
            
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.topAnchor.constraint(equalTo: previewView.bottomAnchor, constant: 20),
            
            frameCountLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            frameCountLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 10),
            
            recordButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            recordButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -50),
            recordButton.widthAnchor.constraint(equalToConstant: 70),
            recordButton.heightAnchor.constraint(equalToConstant: 70)
        ])
    }
    
    private func setupCameraManager() {
        cameraManager = SimpleCameraManager()
        cameraManager.delegate = self
        
        Task {
            let hasPermission = await cameraManager.checkPermission()
            if hasPermission {
                do {
                    try cameraManager.setupSession()
                    cameraManager.startSession()
                    setupPreviewLayer()
                } catch {
                    showError("相机配置失败: \(error.localizedDescription)")
                }
            } else {
                showError("请在设置中允许相机权限")
            }
        }
    }
    
    private func setupPreviewLayer() {
        guard let session = cameraManager.captureSession else { return }
        
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = previewView.bounds
        previewView.layer.insertSublayer(layer, at: 0)
        previewLayer = layer
    }
    
    @objc private func toggleRecording() {
        switch cameraManager.recordingState {
        case .idle:
            cameraManager.startRecording()
            recordButton.setTitle("STOP", for: .normal)
            recordButton.backgroundColor = .blue
            statusLabel.text = "录制中..."
        case .recording:
            cameraManager.stopRecording()
            recordButton.setTitle("REC", for: .normal)
            recordButton.backgroundColor = .red
            statusLabel.text = "已保存到相册"
        case .paused:
            break
        }
    }
    
    private func showError(_ message: String) {
        let alert = UIAlertController(title: "错误", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
}

extension MainViewController: SimpleCameraManagerDelegate {
    func cameraManager(_ manager: SimpleCameraManager, didChangeState state: SimpleRecordingState) {
        switch state {
        case .idle:
            statusLabel.text = "已保存到相册"
        case .recording:
            statusLabel.text = "录制中..."
        case .paused:
            statusLabel.text = "已暂停"
        }
    }
    
    func cameraManager(_ manager: SimpleCameraManager, didFailWithError error: SimpleCameraError) {
        let message: String
        switch error {
        case .permissionDenied:
            message = "相机权限被拒绝"
        case .sessionFailed(let err):
            message = "相机会话失败: \(err.localizedDescription)"
        case .writerFailed(let err):
            message = "写入失败: \(err.localizedDescription)"
        case .unknown:
            message = "未知错误"
        }
        showError(message)
    }
    
    func cameraManager(_ manager: SimpleCameraManager, didUpdateFrameCount current: Int, total: Int) {
        frameCountLabel.text = "保存帧: \(current) / 总帧: \(total) (\(Int(Double(current)/Double(total)*100))%)"
    }
}

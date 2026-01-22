import UIKit
import AVFoundation
import Combine

class MainViewController: UIViewController {
    private var previewView: UIView!
    private var recordButton: UIButton!
    private var statusLabel: UILabel!
    private var frameCountLabel: UILabel!
    private var infoLabel: UILabel!
    private var capabilitiesLabel: UILabel!
    private var bitrateSegmentedControl: UISegmentedControl!
    private var statsLabel: UILabel!
    private var sensorDataLabel: UILabel!
    private var speedDistanceView: UIView!
    private var currentSpeedLabel: UILabel!
    private var totalDistanceLabel: UILabel!
    private var averageSpeedLabel: UILabel!
    private var cameraManager: SimpleCameraManager!
    private var sensorCollector: SensorDataCollector!
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var cancellables = Set<AnyCancellable>()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupCameraManager()
        setupSensorCollector()
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
        frameCountLabel.text = "保存帧: 0 / 总帧: 0 (0%)"
        frameCountLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(frameCountLabel)
        
        infoLabel = UILabel()
        infoLabel.textColor = .systemGreen
        infoLabel.textAlignment = .center
        infoLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        infoLabel.numberOfLines = 2
        infoLabel.text = "初始化中..."
        infoLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(infoLabel)
        
        capabilitiesLabel = UILabel()
        capabilitiesLabel.textColor = .secondaryLabel
        capabilitiesLabel.textAlignment = .center
        capabilitiesLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        capabilitiesLabel.numberOfLines = 0
        capabilitiesLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(capabilitiesLabel)
        
        bitrateSegmentedControl = UISegmentedControl(items: ["35M", "25M", "15M", "10M"])
        bitrateSegmentedControl.selectedSegmentIndex = 1
        bitrateSegmentedControl.translatesAutoresizingMaskIntoConstraints = false
        bitrateSegmentedControl.addTarget(self, action: #selector(bitrateChanged), for: .valueChanged)
        view.addSubview(bitrateSegmentedControl)
        
        speedDistanceView = UIView()
        speedDistanceView.backgroundColor = UIColor.white.withAlphaComponent(0.1)
        speedDistanceView.layer.cornerRadius = 12
        speedDistanceView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(speedDistanceView)
        
        let speedStackView = UIStackView()
        speedStackView.axis = .horizontal
        speedStackView.distribution = .fillEqually
        speedStackView.spacing = 8
        speedStackView.translatesAutoresizingMaskIntoConstraints = false
        speedDistanceView.addSubview(speedStackView)
        
        let currentSpeedContainer = createMetricContainer()
        currentSpeedLabel = createMetricLabel(title: "当前速度", value: "0.0 km/h", container: currentSpeedContainer)
        
        let totalDistanceContainer = createMetricContainer()
        totalDistanceLabel = createMetricLabel(title: "总距离", value: "0.00 km", container: totalDistanceContainer)
        
        let averageSpeedContainer = createMetricContainer()
        averageSpeedLabel = createMetricLabel(title: "平均速度", value: "0.0 km/h", container: averageSpeedContainer)
        
        speedStackView.addArrangedSubview(currentSpeedContainer)
        speedStackView.addArrangedSubview(totalDistanceContainer)
        speedStackView.addArrangedSubview(averageSpeedContainer)
        
        NSLayoutConstraint.activate([
            speedStackView.topAnchor.constraint(equalTo: speedDistanceView.topAnchor, constant: 8),
            speedStackView.leadingAnchor.constraint(equalTo: speedDistanceView.leadingAnchor, constant: 8),
            speedStackView.trailingAnchor.constraint(equalTo: speedDistanceView.trailingAnchor, constant: -8),
            speedStackView.bottomAnchor.constraint(equalTo: speedDistanceView.bottomAnchor, constant: -8)
        ])
        
        statsLabel = UILabel()
        statsLabel.textColor = .systemBlue
        statsLabel.textAlignment = .center
        statsLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        statsLabel.numberOfLines = 0
        statsLabel.text = "编码统计: 等待开始..."
        statsLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statsLabel)
        
        sensorDataLabel = UILabel()
        sensorDataLabel.textColor = .systemOrange
        sensorDataLabel.textAlignment = .center
        sensorDataLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        sensorDataLabel.numberOfLines = 0
        sensorDataLabel.text = "传感器: 等待GPS..."
        sensorDataLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sensorDataLabel)
        
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
            previewView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.45),
            
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.topAnchor.constraint(equalTo: previewView.bottomAnchor, constant: 16),
            
            frameCountLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            frameCountLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 6),
            
            infoLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            infoLabel.topAnchor.constraint(equalTo: frameCountLabel.bottomAnchor, constant: 6),
            
            capabilitiesLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            capabilitiesLabel.topAnchor.constraint(equalTo: infoLabel.bottomAnchor, constant: 6),
            capabilitiesLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            capabilitiesLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            bitrateSegmentedControl.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            bitrateSegmentedControl.topAnchor.constraint(equalTo: capabilitiesLabel.bottomAnchor, constant: 12),
            bitrateSegmentedControl.widthAnchor.constraint(equalToConstant: 200),
            
            speedDistanceView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            speedDistanceView.topAnchor.constraint(equalTo: bitrateSegmentedControl.bottomAnchor, constant: 12),
            speedDistanceView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            speedDistanceView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            speedDistanceView.heightAnchor.constraint(equalToConstant: 70),
            
            statsLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statsLabel.topAnchor.constraint(equalTo: speedDistanceView.bottomAnchor, constant: 8),
            
            sensorDataLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            sensorDataLabel.topAnchor.constraint(equalTo: statsLabel.bottomAnchor, constant: 6),
            sensorDataLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            sensorDataLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            recordButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            recordButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -30),
            recordButton.widthAnchor.constraint(equalToConstant: 70),
            recordButton.heightAnchor.constraint(equalToConstant: 70)
        ])
    }
    
    private func createMetricContainer() -> UIView {
        let container = UIView()
        container.backgroundColor = UIColor.white.withAlphaComponent(0.05)
        container.layer.cornerRadius = 8
        container.translatesAutoresizingMaskIntoConstraints = false
        return container
    }
    
    private func createMetricLabel(title: String, value: String, container: UIView) -> UILabel {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.textColor = .lightGray
        titleLabel.font = UIFont.systemFont(ofSize: 10)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        
        let valueLabel = UILabel()
        valueLabel.text = value
        valueLabel.textColor = .white
        valueLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 18, weight: .bold)
        valueLabel.textAlignment = .center
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        
        container.addSubview(titleLabel)
        container.addSubview(valueLabel)
        
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
            titleLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            
            valueLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            valueLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor)
        ])
        
        return valueLabel
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
                    displayCapabilities()
                    displayCurrentInfo()
                } catch {
                    showError("相机配置失败: \(error.localizedDescription)")
                }
            } else {
                showError("请在设置中允许相机权限")
            }
        }
    }
    
    private func setupSensorCollector() {
        sensorCollector = SensorDataCollector.shared
        
        Task {
            let (motionOK, locationOK) = await sensorCollector.checkPermissions()
            if locationOK {
                sensorCollector.startCollection()
                subscribeToSensorData()
            } else {
                showError("请在设置中允许位置权限")
            }
        }
    }
    
    private func subscribeToSensorData() {
        sensorCollector.sensorFramePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] frame in
                self?.updateSensorDisplay(frame)
            }
            .store(in: &cancellables)
        
        sensorCollector.statisticsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] stats in
                self?.updateStatisticsDisplay(stats)
            }
            .store(in: &cancellables)
    }
    
    private func updateSensorDisplay(_ frame: SensorFrame) {
        let speed = frame.currentSpeed ?? 0
        let speedKmh = speed * 3.6
        currentSpeedLabel.text = String(format: "%.1f km/h", speedKmh)
        
        let distance = frame.totalDistance ?? 0
        totalDistanceLabel.text = String(format: "%.2f km", distance / 1000.0)
        
        var sensorText = "传感器: "
        if let lat = frame.latitude, let lon = frame.longitude {
            sensorText += String(format: "%.5f, %.5f | ", lat, lon)
        }
        sensorText += String(format: "Acc: %.2f | Gyro: %.2f", 
                            sqrt(frame.accelerationX * frame.accelerationX + frame.accelerationY * frame.accelerationY + frame.accelerationZ * frame.accelerationZ),
                            sqrt(frame.gyroscopeX * frame.gyroscopeX + frame.gyroscopeY * frame.gyroscopeY + frame.gyroscopeZ * frame.gyroscopeZ))
        
        if let accuracy = frame.horizontalAccuracy {
            sensorText += String(format: " | GPS精度: %.0fm", accuracy)
        }
        
        sensorDataLabel.text = sensorText
    }
    
    private func updateStatisticsDisplay(_ stats: SensorStatistics) {
        let avgSpeedKmh = stats.averageSpeed * 3.6
        averageSpeedLabel.text = String(format: "%.1f km/h", avgSpeedKmh)
    }
    
    private func setupPreviewLayer() {
        guard let session = cameraManager.captureSession else { return }
        
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = previewView.bounds
        previewView.layer.insertSublayer(layer, at: 0)
        previewLayer = layer
    }
    
    private func displayCapabilities() {
        let capabilities = cameraManager.getSupportedCapabilities()
        
        var capabilityText = "设备支持:\n"
        capabilityText += "• 4K: \((capabilities["4KSupport"] as? Bool) == true ? "✓" : "✗")  "
        capabilityText += "60fps: \((capabilities["60fpsSupport"] as? Bool) == true ? "✓" : "✗")  "
        capabilityText += "HDR: \((capabilities["HDRSupport"] as? Bool) == true ? "✓" : "✗")\n"
        capabilityText += "• 防抖: ✓ (cinematicExtended)"
        
        capabilitiesLabel.text = capabilityText
    }
    
    private func displayCurrentInfo() {
        let info = cameraManager.getCurrentRecordingInfo()
        let infoText = String(format: "4K %dfps | 防抖: %@ | HDR: %@ | %@",
                              info["frameRate"] as? Int ?? 30,
                              (info["stabilization"] as? Bool) == true ? "✓" : "✗",
                              (info["hdrEnabled"] as? Bool) == true ? "✓" : "✗",
                              info["bitratePreset"] as? String ?? "standard")
        infoLabel.text = infoText
    }
    
    @objc private func bitrateChanged() {
        let presets: [VideoEncoderConfiguration.BitratePreset] = [.highQuality, .standard, .powerSaving, .compression]
        let selectedPreset = presets[bitrateSegmentedControl.selectedSegmentIndex]
        cameraManager.setBitratePreset(selectedPreset)
    }
    
    @objc private func toggleRecording() {
        switch cameraManager.recordingState {
        case .idle:
            cameraManager.startRecording()
            recordButton.setTitle("STOP", for: .normal)
            recordButton.backgroundColor = .blue
            statusLabel.text = "录制中 (4K 抽帧中)..."
            statsLabel.text = "编码统计: 编码中..."
        case .recording:
            cameraManager.stopRecording()
            recordButton.setTitle("REC", for: .normal)
            recordButton.backgroundColor = .red
            statusLabel.text = "已保存到相册"
            statsLabel.text = "编码统计: 等待开始..."
        case .paused:
            break
        }
    }
    
    private func showError(_ message: String) {
        let alert = UIAlertController(title: "错误", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
    
    deinit {
        sensorCollector.stopCollection()
    }
}

extension MainViewController: SimpleCameraManagerDelegate {
    func cameraManager(_ manager: SimpleCameraManager, didChangeState state: SimpleRecordingState) {
        switch state {
        case .idle:
            statusLabel.text = "已保存到相册"
        case .recording:
            statusLabel.text = "录制中 (4K 抽帧中)..."
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
        case .encoderFailed(let err):
            message = "编码失败: \(err.localizedDescription)"
        case .highFrameRateUnavailable:
            message = "设备不支持60fps，已降级至30fps"
        case .hdrUnavailable:
            message = "设备不支持HDR"
        case .deviceUnavailable:
            message = "相机设备不可用"
        case .unknown:
            message = "未知错误"
        }
        showError(message)
    }
    
    func cameraManager(_ manager: SimpleCameraManager, didUpdateFrameCount current: Int, total: Int) {
        let percentage = total > 0 ? Int(Double(current) / Double(total) * 100) : 0
        frameCountLabel.text = "保存帧: \(current) / 总帧: \(total) (\(percentage)%)"
    }
    
    func cameraManager(_ manager: SimpleCameraManager, didUpdateRecordingInfo info: [String: Any]) {
        displayCurrentInfo()
    }
    
    func cameraManager(_ manager: SimpleCameraManager, didUpdateStatistics stats: [String: Any]) {
        let bitrate = stats["averageBitrate"] as? Double ?? 0
        let fps = stats["fps"] as? Double ?? 0
        let encodedFrames = stats["encodedFrames"] as? Int ?? 0
        let droppedFrames = stats["droppedFrames"] as? Int ?? 0
        let bytes = stats["encodedBytes"] as? Double ?? 0
        
        let statsText = String(format: "码率: %.1f Mbps | FPS: %.1f | 编码: %d | 丢帧: %d | 大小: %.1f MB",
                              bitrate, fps, encodedFrames, droppedFrames, bytes)
        statsLabel.text = "编码统计: " + statsText
    }
}

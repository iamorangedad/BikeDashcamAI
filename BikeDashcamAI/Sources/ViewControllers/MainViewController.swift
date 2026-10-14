import UIKit
import AVFoundation
import Combine

final class MainViewController: UIViewController {
    private let previewView = UIView()
    private let topPanel = UIView()
    private let bottomPanel = UIView()
    private let speedLabel = UILabel()
    private let averageSpeedLabel = UILabel()
    private let durationLabel = UILabel()
    private let sizeLabel = UILabel()
    private let distanceLabel = UILabel()
    private let infoLabel = UILabel()
    private let warningLabel = UILabel()
    private let statusLabel = UILabel()
    private let bitrateControl = UISegmentedControl(items: ["35M", "25M", "15M", "10M"])
    private let recordButton = UIButton(type: .system)
    private let pauseButton = UIButton(type: .system)
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var cancellables = Set<AnyCancellable>()

    private let coordinator = RecordingCoordinator(camera: CameraManager(), sensors: .shared)
    private var markCount = 0
    private var distanceKilometers = 0.0

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        coordinator.camera.delegate = self
        startPipeline()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = previewView.bounds
        updatePreviewOrientation()
    }

    private func setupUI() {
        view.backgroundColor = .black

        previewView.backgroundColor = .black
        previewView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(previewView)

        configure(panel: topPanel)
        configure(panel: bottomPanel)
        view.addSubview(topPanel)
        view.addSubview(bottomPanel)

        speedLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 40, weight: .bold)
        speedLabel.textColor = .white
        speedLabel.text = "--"
        let unitLabel = UILabel()
        unitLabel.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        unitLabel.textColor = UIColor.white.withAlphaComponent(0.75)
        unitLabel.text = "km/h"
        averageSpeedLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        averageSpeedLabel.textColor = UIColor.white.withAlphaComponent(0.75)
        averageSpeedLabel.text = "平均 -- km/h"

        let speedValueRow = UIStackView(arrangedSubviews: [speedLabel, unitLabel])
        speedValueRow.axis = .horizontal
        speedValueRow.alignment = .lastBaseline
        speedValueRow.spacing = 4

        durationLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 22, weight: .semibold)
        durationLabel.textColor = .white
        durationLabel.textAlignment = .right
        durationLabel.text = "00:00:00"
        sizeLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        sizeLabel.textColor = UIColor.white.withAlphaComponent(0.75)
        sizeLabel.textAlignment = .right
        sizeLabel.text = "0 MB"

        let speedStack = UIStackView(arrangedSubviews: [speedValueRow, averageSpeedLabel])
        speedStack.axis = .vertical
        speedStack.spacing = 2
        let timeStack = UIStackView(arrangedSubviews: [durationLabel, sizeLabel])
        timeStack.axis = .vertical
        timeStack.spacing = 2
        let topRow = UIStackView(arrangedSubviews: [speedStack, timeStack])
        topRow.axis = .horizontal
        topRow.distribution = .equalSpacing
        topRow.alignment = .center
        topRow.translatesAutoresizingMaskIntoConstraints = false
        topPanel.addSubview(topRow)

        distanceLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        distanceLabel.textColor = .white
        distanceLabel.text = "距离 0.00 km"
        infoLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        infoLabel.textColor = UIColor.white.withAlphaComponent(0.8)
        infoLabel.numberOfLines = 2
        infoLabel.text = "正在配置相机"
        warningLabel.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        warningLabel.textColor = .systemOrange
        warningLabel.numberOfLines = 2
        warningLabel.text = ""
        statusLabel.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        statusLabel.textColor = UIColor.white.withAlphaComponent(0.85)
        statusLabel.text = "准备就绪"
        bitrateControl.selectedSegmentIndex = 1
        bitrateControl.selectedSegmentTintColor = .white
        bitrateControl.addTarget(self, action: #selector(bitrateChanged), for: .valueChanged)

        recordButton.setTitle("REC", for: .normal)
        recordButton.setTitleColor(.white, for: .normal)
        recordButton.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .bold)
        recordButton.backgroundColor = .systemRed
        recordButton.layer.cornerRadius = 36
        recordButton.translatesAutoresizingMaskIntoConstraints = false
        recordButton.addTarget(self, action: #selector(toggleRecording), for: .touchUpInside)
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(markRide))
        longPress.minimumPressDuration = 0.45
        longPress.cancelsTouchesInView = true
        recordButton.addGestureRecognizer(longPress)

        pauseButton.tintColor = .white
        pauseButton.backgroundColor = UIColor.white.withAlphaComponent(0.16)
        pauseButton.layer.cornerRadius = 22
        pauseButton.isHidden = true
        pauseButton.translatesAutoresizingMaskIntoConstraints = false
        pauseButton.addTarget(self, action: #selector(togglePause), for: .touchUpInside)
        setPauseSymbol(named: "pause.fill")

        let buttonRow = UIStackView(arrangedSubviews: [pauseButton, recordButton])
        buttonRow.axis = .horizontal
        buttonRow.alignment = .center
        buttonRow.spacing = 28
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        let buttonHolder = UIView()
        buttonHolder.translatesAutoresizingMaskIntoConstraints = false
        buttonHolder.addSubview(buttonRow)

        let bottomStack = UIStackView(arrangedSubviews: [
            distanceLabel, infoLabel, warningLabel, statusLabel, bitrateControl, buttonHolder
        ])
        bottomStack.axis = .vertical
        bottomStack.spacing = 8
        bottomStack.alignment = .fill
        bottomStack.translatesAutoresizingMaskIntoConstraints = false
        bottomPanel.addSubview(bottomStack)

        NSLayoutConstraint.activate([
            previewView.topAnchor.constraint(equalTo: view.topAnchor),
            previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            previewView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            topPanel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            topPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            topPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            topRow.topAnchor.constraint(equalTo: topPanel.topAnchor, constant: 12),
            topRow.leadingAnchor.constraint(equalTo: topPanel.leadingAnchor, constant: 16),
            topRow.trailingAnchor.constraint(equalTo: topPanel.trailingAnchor, constant: -16),
            topRow.bottomAnchor.constraint(equalTo: topPanel.bottomAnchor, constant: -12),

            bottomPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            bottomPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            bottomPanel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),

            bottomStack.topAnchor.constraint(equalTo: bottomPanel.topAnchor, constant: 14),
            bottomStack.leadingAnchor.constraint(equalTo: bottomPanel.leadingAnchor, constant: 16),
            bottomStack.trailingAnchor.constraint(equalTo: bottomPanel.trailingAnchor, constant: -16),
            bottomStack.bottomAnchor.constraint(equalTo: bottomPanel.bottomAnchor, constant: -14),

            recordButton.widthAnchor.constraint(equalToConstant: 72),
            recordButton.heightAnchor.constraint(equalToConstant: 72),
            pauseButton.widthAnchor.constraint(equalToConstant: 44),
            pauseButton.heightAnchor.constraint(equalToConstant: 44),

            buttonRow.centerXAnchor.constraint(equalTo: buttonHolder.centerXAnchor),
            buttonRow.topAnchor.constraint(equalTo: buttonHolder.topAnchor),
            buttonRow.bottomAnchor.constraint(equalTo: buttonHolder.bottomAnchor)
        ])
    }

    private func startPipeline() {
        Task {
            let granted = await coordinator.camera.checkPermission()
            guard granted else {
                showError("请在设置中允许相机权限")
                return
            }
            do {
                try coordinator.camera.setupSession()
                coordinator.camera.startSession()
                installPreview()
            } catch {
                showError(error.localizedDescription)
                return
            }

            let (_, locationGranted) = await coordinator.sensors.checkPermissions()
            if locationGranted {
                coordinator.sensors.startCollection()
                subscribeToSensors()
            } else {
                statusLabel.text = "未获得定位，仍可录制视频"
            }
            refreshWarnings()
        }
    }

    private func subscribeToSensors() {
        coordinator.sensors.sensorFramePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] frame in
                self?.render(frame)
            }
            .store(in: &cancellables)

        coordinator.sensors.statisticsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] stats in
                let kmh = stats.averageSpeed * 3.6
                self?.averageSpeedLabel.text = String(format: "平均 %.1f km/h", kmh)
            }
            .store(in: &cancellables)
    }

    private func render(_ frame: SensorFrame) {
        if let speed = frame.currentSpeed {
            speedLabel.text = String(format: "%.1f", speed * 3.6)
        } else {
            speedLabel.text = "--"
        }
        distanceKilometers = (frame.totalDistance ?? 0) / 1000
        updateDistance(coordinator.camera.statisticsSnapshot())
    }

    private func installPreview() {
        guard let session = coordinator.camera.captureSession else { return }
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = previewView.bounds
        previewView.layer.insertSublayer(layer, at: 0)
        previewLayer = layer
        updatePreviewOrientation()
    }

    private func updatePreviewOrientation() {
        guard let connection = previewLayer?.connection else { return }
        let angle: CGFloat
        switch view.window?.windowScene?.interfaceOrientation {
        case .landscapeRight: angle = 180
        case .landscapeLeft: angle = 0
        case .portraitUpsideDown: angle = 270
        default: angle = 90
        }
        if connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
    }

    @objc private func bitrateChanged() {
        let presets: [VideoEncoderConfiguration.BitratePreset] = [.highQuality, .standard, .powerSaving, .compression]
        let index = bitrateControl.selectedSegmentIndex
        guard presets.indices.contains(index) else { return }
        coordinator.camera.setBitratePreset(presets[index])
    }

    @objc private func toggleRecording() {
        switch coordinator.camera.recordingState {
        case .idle:
            refreshWarnings()
            do {
                markCount = 0
                try coordinator.startRecording()
            } catch {
                showError(error.localizedDescription)
            }
        case .recording, .paused:
            statusLabel.text = "正在保存"
            coordinator.stopRecording { [weak self] result in
                switch result {
                case .success(let metadata):
                    self?.statusLabel.text = "已保存 \(metadata.videoFileName)"
                case .failure(let error):
                    self?.statusLabel.text = "保存失败"
                    self?.showError(error.localizedDescription)
                }
            }
        case .preparing, .stopping:
            break
        }
    }

    @objc private func togglePause() {
        switch coordinator.camera.recordingState {
        case .recording:
            coordinator.pauseRecording()
        case .paused:
            coordinator.resumeRecording()
        default:
            break
        }
    }

    @objc private func markRide(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        guard coordinator.camera.recordingState == .recording || coordinator.camera.recordingState == .paused else { return }
        coordinator.addMark()
        markCount += 1
        warningLabel.text = "已标记 \(formatDuration(coordinator.camera.recordingDuration))  ·  共 \(markCount) 处"
    }

    private func renderTransport(_ state: RecordingState) {
        switch state {
        case .idle:
            recordButton.setTitle("REC", for: .normal)
            recordButton.backgroundColor = .systemRed
            pauseButton.isHidden = true
            bitrateControl.isEnabled = true
        case .preparing, .stopping:
            recordButton.setTitle("···", for: .normal)
            pauseButton.isHidden = true
            bitrateControl.isEnabled = false
        case .recording:
            recordButton.setTitle("STOP", for: .normal)
            recordButton.backgroundColor = .systemRed
            pauseButton.isHidden = false
            setPauseSymbol(named: "pause.fill")
            bitrateControl.isEnabled = false
            statusLabel.text = "录制中，长按可标记"
        case .paused:
            recordButton.setTitle("STOP", for: .normal)
            pauseButton.isHidden = false
            setPauseSymbol(named: "play.fill")
            bitrateControl.isEnabled = false
            statusLabel.text = "已暂停"
        }
    }

    private func apply(_ configuration: CaptureConfiguration) {
        let hdr = configuration.hdrSupported ? "HDR 可用" : "HDR 不可用"
        infoLabel.text = "\(configuration.width)×\(configuration.height) · \(configuration.frameRate)fps · HEVC \(configuration.bitratePreset.bitrate / 1_000_000)Mbps · \(configuration.colorSpace) · \(hdr)"
    }

    private func apply(_ statistics: RecordingStatistics) {
        durationLabel.text = formatDuration(statistics.duration)
        sizeLabel.text = formatBytes(statistics.fileBytes)
        updateDistance(statistics)
    }

    private func updateDistance(_ statistics: RecordingStatistics) {
        let recording = coordinator.camera.recordingState == .recording
            || coordinator.camera.recordingState == .paused
            || statistics.encodedFrames > 0
        if recording {
            distanceLabel.text = String(
                format: "距离 %.2f km  ·  分析帧 %d  ·  丢帧 %d",
                distanceKilometers,
                statistics.sampledFrames,
                statistics.droppedFrames
            )
        } else {
            distanceLabel.text = String(format: "距离 %.2f km", distanceKilometers)
        }
    }

    private func refreshWarnings() {
        var messages: [String] = []
        let capacity = FileSystemManager.shared.availableCapacity()
        if capacity > 0 && capacity < 500_000_000 {
            messages.append("存储空间不足")
        }
        switch ProcessInfo.processInfo.thermalState {
        case .serious, .critical:
            messages.append("设备温度过高")
        default:
            break
        }
        if markCount == 0 {
            warningLabel.text = messages.joined(separator: "  ·  ")
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let total = max(0, Int(duration))
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1_000_000
        if mb >= 1000 {
            return String(format: "%.2f GB", mb / 1000)
        }
        return String(format: "%.1f MB", mb)
    }

    private func setPauseSymbol(named name: String) {
        let image = UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold))
        pauseButton.setImage(image, for: .normal)
    }

    private func configure(panel: UIView) {
        panel.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        panel.layer.cornerRadius = 16
        panel.translatesAutoresizingMaskIntoConstraints = false
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: "BikeDashcam", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }

    deinit {
        coordinator.camera.stopSession()
        coordinator.sensors.stopCollection()
    }
}

extension MainViewController: CameraManagerDelegate {
    func cameraManager(_ manager: CameraManager, didChangeState state: RecordingState) {
        renderTransport(state)
    }

    func cameraManager(_ manager: CameraManager, didFailWithError error: CameraError) {
        statusLabel.text = "录制失败"
        showError(error.localizedDescription)
    }

    func cameraManager(_ manager: CameraManager, didUpdateConfiguration configuration: CaptureConfiguration) {
        apply(configuration)
    }

    func cameraManager(_ manager: CameraManager, didUpdateStatistics statistics: RecordingStatistics) {
        apply(statistics)
        refreshWarnings()
    }
}

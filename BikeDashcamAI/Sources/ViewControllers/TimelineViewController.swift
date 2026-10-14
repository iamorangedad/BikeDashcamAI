import AVFoundation
import Photos
import UIKit

final class TimelineViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    private let recording: RideRecording
    private var segments: [SceneSegment] = []
    private var bookmarks: [Bookmark] = []
    private var selectedIndex = 0
    private let player = AVPlayer()
    private let playerLayer = AVPlayerLayer()
    private let previewView = UIView()
    private let timeLabel = UILabel()
    private let descriptionLabel = UILabel()
    private var collectionView: UICollectionView!
    private var timeObserver: Any?
    private var playbackRate: Float = 1

    init(recording: RideRecording) {
        self.recording = recording
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = Date(timeIntervalSince1970: recording.startTime).formatted(date: .abbreviated, time: .shortened)
        segments = SegmentManager.shared.getSegments(for: recording.id)
        bookmarks = (try? DatabaseManager.shared.getBookmarks(forRecording: recording.id)) ?? []
        NotificationCenter.default.addObserver(self, selector: #selector(thumbnailsDidChange), name: .rideLibraryDidChange, object: nil)
        setupUI()
        loadPlayer()
        if let first = segments.first {
            play(first)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        playerLayer.frame = previewView.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        player.pause()
    }

    deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
    }

    private func setupUI() {
        previewView.backgroundColor = .black
        previewView.translatesAutoresizingMaskIntoConstraints = false
        playerLayer.videoGravity = .resizeAspect
        playerLayer.player = player
        previewView.layer.addSublayer(playerLayer)
        view.addSubview(previewView)

        timeLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        timeLabel.textColor = .secondaryLabel
        timeLabel.text = "00:00:00"
        descriptionLabel.font = UIFont.systemFont(ofSize: 15)
        descriptionLabel.numberOfLines = 3
        descriptionLabel.text = segments.first?.description

        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 8
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.register(SegmentCell.self, forCellWithReuseIdentifier: SegmentCell.reuseID)
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(confirmDelete))
        collectionView.addGestureRecognizer(longPress)

        let playButton = makeButton("播放", action: #selector(togglePlay))
        playButton.tag = 42
        let previousButton = makeButton("上一段", action: #selector(previousSegment))
        let nextButton = makeButton("下一段", action: #selector(nextSegment))
        let rateButton = makeButton("1x", action: #selector(cycleRate))
        rateButton.tag = 41
        let exportButton = makeButton("导出", action: #selector(exportSelection))
        let splitButton = makeButton("分割", action: #selector(splitAtPlayhead))
        let mergeButton = makeButton("合并下一段", action: #selector(mergeNext))
        let editButton = makeButton("改描述", action: #selector(editDescription))
        let tools = UIStackView(arrangedSubviews: [previousButton, playButton, nextButton, rateButton, exportButton])
        tools.axis = .horizontal
        tools.distribution = .fillEqually
        tools.spacing = 8
        let edits = UIStackView(arrangedSubviews: [splitButton, mergeButton, editButton])
        edits.axis = .horizontal
        edits.distribution = .fillEqually
        edits.spacing = 8

        let stack = UIStackView(arrangedSubviews: [timeLabel, descriptionLabel, collectionView, tools, edits])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            previewView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            previewView.heightAnchor.constraint(equalTo: previewView.widthAnchor, multiplier: 9.0 / 16.0),
            stack.topAnchor.constraint(equalTo: previewView.bottomAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            collectionView.heightAnchor.constraint(equalToConstant: 96)
        ])
    }

    private func loadPlayer() {
        guard let path = segments.first?.videoPath ?? recording.videoPath.nilIfEmpty else { return }
        let url = FileSystemManager.shared.recordingRoot(recording.id).appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        let interval = CMTime(seconds: 0.2, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.playerAdvanced(to: time.seconds)
        }
    }

    private func play(_ segment: SceneSegment) {
        guard segments.indices.contains(selectedIndex) else { return }
        let start = CMTime(seconds: segment.startTime, preferredTimescale: 600)
        player.seek(to: start, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            guard finished else { return }
            DispatchQueue.main.async {
                self?.player.rate = self?.playbackRate ?? 1
            }
        }
        descriptionLabel.text = segment.description
        timeLabel.text = "\(format(segment.startTime)) / \(format(segment.endTime ?? segment.startTime))"
        setPlayTitle("暂停")
        collectionView.selectItem(at: IndexPath(item: selectedIndex, section: 0), animated: true, scrollPosition: .centeredHorizontally)
    }

    private func playerAdvanced(to seconds: TimeInterval) {
        guard segments.indices.contains(selectedIndex) else { return }
        let segment = segments[selectedIndex]
        let end = segment.endTime ?? seconds
        timeLabel.text = "\(format(seconds)) / \(format(end))"
        if seconds >= end - 0.05 {
            player.pause()
            setPlayTitle("播放")
        }
    }

    private func setPlayTitle(_ title: String) {
        (view.viewWithTag(42) as? UIButton)?.setTitle(title, for: .normal)
    }

    @objc private func togglePlay() {
        if player.timeControlStatus == .playing {
            player.pause()
            setPlayTitle("播放")
        } else if segments.indices.contains(selectedIndex) {
            play(segments[selectedIndex])
            setPlayTitle("暂停")
        }
    }

    @objc private func previousSegment() {
        guard selectedIndex > 0 else { return }
        selectedIndex -= 1
        play(segments[selectedIndex])
    }

    @objc private func nextSegment() {
        guard selectedIndex + 1 < segments.count else { return }
        selectedIndex += 1
        play(segments[selectedIndex])
    }

    @objc private func cycleRate() {
        switch playbackRate {
        case 0.5: playbackRate = 1
        case 1: playbackRate = 2
        default: playbackRate = 0.5
        }
        if player.timeControlStatus == .playing {
            player.rate = playbackRate
        }
        if let button = view.viewWithTag(41) as? UIButton {
            button.setTitle(playbackRate == 0.5 ? "0.5x" : (playbackRate == 2 ? "2x" : "1x"), for: .normal)
        }
    }

    @objc private func splitAtPlayhead() {
        guard segments.indices.contains(selectedIndex) else { return }
        let time = player.currentTime().seconds
        guard let created = SegmentManager.shared.split(segments[selectedIndex], at: time) else {
            presentNotice("播放头需要离片段两端至少 1 秒")
            return
        }
        refresh()
        if let index = segments.firstIndex(where: { $0.id == created.id }) {
            selectedIndex = index
            play(created)
        }
    }

    @objc private func mergeNext() {
        guard selectedIndex + 1 < segments.count else { return }
        guard let merged = SegmentManager.shared.merge(segments[selectedIndex], with: segments[selectedIndex + 1]) else { return }
        refresh()
        if let index = segments.firstIndex(where: { $0.id == merged.id }) {
            selectedIndex = index
            descriptionLabel.text = merged.description
        }
    }

    @objc private func editDescription() {
        guard segments.indices.contains(selectedIndex) else { return }
        let segment = segments[selectedIndex]
        let alert = UIAlertController(title: "场景描述", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.text = segment.description }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "保存", style: .default) { [weak self] _ in
            let text = alert.textFields?.first?.text ?? ""
            guard let updated = SegmentManager.shared.updateDescription(segment.id, description: text) else { return }
            self?.refresh()
            self?.descriptionLabel.text = updated.description
        })
        present(alert, animated: true)
    }

    @objc private func confirmDelete(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        let point = gesture.location(in: collectionView)
        guard let indexPath = collectionView.indexPathForItem(at: point) else { return }
        let index = indexPath.item
        guard segments.indices.contains(index), segments.count > 1 else { return }
        let segment = segments[index]
        let alert = UIAlertController(title: "删除这个片段？", message: "只从时间线上移除，不裁剪视频文件。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "删除", style: .destructive) { [weak self] _ in
            guard let self else { return }
            SegmentManager.shared.deleteSegment(segment)
            if self.selectedIndex > index {
                self.selectedIndex -= 1
            } else if self.selectedIndex == index {
                self.selectedIndex = min(index, self.segments.count - 2)
            }
            self.refresh()
            if self.segments.indices.contains(self.selectedIndex) {
                self.play(self.segments[self.selectedIndex])
            }
        })
        present(alert, animated: true)
    }

    @objc private func exportSelection() {
        guard segments.indices.contains(selectedIndex) else { return }
        let segment = segments[selectedIndex]
        let source = FileSystemManager.shared.recordingRoot(recording.id).appendingPathComponent(segment.videoPath)
        guard FileManager.default.fileExists(atPath: source.path) else {
            presentNotice("找不到视频文件")
            return
        }
        let asset = AVURLAsset(url: source)
        let preset = AVAssetExportSession.exportPresets(compatibleWith: asset).contains(AVAssetExportPresetHEVC1920x1080)
            ? AVAssetExportPresetHEVC1920x1080
            : AVAssetExportPresetHighestQuality
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { return }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("\(segment.id.uuidString).mov")
        try? FileManager.default.removeItem(at: output)
        session.outputURL = output
        session.outputFileType = .mov
        let start = CMTime(seconds: segment.startTime, preferredTimescale: 600)
        let length = max(0.1, segment.duration)
        session.timeRange = CMTimeRange(start: start, duration: CMTime(seconds: length, preferredTimescale: 600))
        timeLabel.text = "正在导出"
        session.exportAsynchronously { [weak self] in
            DispatchQueue.main.async {
                guard session.status == .completed else {
                    self?.presentNotice(session.error?.localizedDescription ?? "导出失败")
                    return
                }
                self?.saveToPhotos(output)
            }
        }
    }

    private func saveToPhotos(_ url: URL) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { self?.presentNotice("没有相册权限") }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            } completionHandler: { success, _ in
                DispatchQueue.main.async {
                    self?.presentNotice(success ? "已保存到相册" : "保存失败")
                }
            }
        }
    }

    @objc private func thumbnailsDidChange() {
        DispatchQueue.main.async { [weak self] in
            self?.refresh()
        }
    }

    private func refresh() {
        segments = SegmentManager.shared.getSegments(for: recording.id)
        collectionView.reloadData()
    }

    private func presentNotice(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }

    private func makeButton(_ title: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    private func format(_ time: TimeInterval) -> String {
        let total = max(0, Int(time))
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        segments.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: SegmentCell.reuseID, for: indexPath) as! SegmentCell
        let segment = segments[indexPath.item]
        let marked = bookmarks.contains { bookmark in
            bookmark.timestamp >= segment.startTime && bookmark.timestamp <= (segment.endTime ?? bookmark.timestamp)
        }
        cell.configure(segment: segment, recordingID: recording.id, marked: marked, selected: indexPath.item == selectedIndex)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        selectedIndex = indexPath.item
        play(segments[selectedIndex])
        collectionView.reloadData()
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let duration = segments[indexPath.item].duration
        let width = min(180, max(84, duration * 8))
        return CGSize(width: width, height: 88)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

private final class SegmentCell: UICollectionViewCell {
    static let reuseID = "segment"
    private let imageView = UIImageView()
    private let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.cornerRadius = 8
        contentView.clipsToBounds = true
        contentView.backgroundColor = .secondarySystemBackground
        imageView.contentMode = .scaleAspectFill
        imageView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = UIFont.systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.shadowColor = UIColor.black.withAlphaComponent(0.8)
        titleLabel.shadowOffset = CGSize(width: 0, height: 1)
        titleLabel.numberOfLines = 2
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(imageView)
        contentView.addSubview(titleLabel)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 6),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -6),
            titleLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6)
        ])
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func configure(segment: SceneSegment, recordingID: UUID, marked: Bool, selected: Bool) {
        titleLabel.text = "\(segment.sceneType.rawValue)\(marked ? " · 标记" : "")"
        contentView.layer.borderWidth = selected ? 2 : 0
        contentView.layer.borderColor = UIColor.systemBlue.cgColor
        if let relative = segment.thumbnailPath {
            let url = FileSystemManager.shared.recordingRoot(recordingID).appendingPathComponent(relative)
            imageView.image = UIImage(contentsOfFile: url.path)
        } else {
            imageView.image = ThumbnailGenerator.shared.cachedThumbnail(for: segment.id)
        }
    }
}

import UIKit

final class LibraryViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let emptyLabel = UILabel()
    private var recordings: [RideRecording] = []
    private let files = FileSystemManager.shared
    private let database = DatabaseManager.shared

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "骑行记录"
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "关闭", style: .plain, target: self, action: #selector(close))
        tableView.dataSource = self
        tableView.delegate = self
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        emptyLabel.text = "还没有骑行记录"
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.textAlignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: .rideLibraryDidChange, object: nil)
        importLegacyRecordings()
        reload()
    }

    @objc private func close() {
        dismiss(animated: true)
    }

    @objc private func reload() {
        let apply = { [weak self] in
            guard let self else { return }
            self.recordings = (try? self.database.getAllRecordings()) ?? []
            self.emptyLabel.isHidden = !self.recordings.isEmpty
            if let stats = try? self.database.getTotalStats(), stats.totalRecordings > 0 {
                let distance = stats.totalDistance / 1000
                self.navigationItem.rightBarButtonItem = UIBarButtonItem(
                    title: String(format: "%.1f km", distance),
                    style: .plain,
                    target: nil,
                    action: nil
                )
            }
            self.tableView.reloadData()
        }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        recordings.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ride") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "ride")
        let ride = recordings[indexPath.row]
        let date = Date(timeIntervalSince1970: ride.startTime)
        cell.textLabel?.text = date.formatted(date: .abbreviated, time: .shortened)
        cell.detailTextLabel?.text = String(
            format: "%.2f km · %@",
            ride.totalDistance / 1000,
            formatDuration(ride.totalDuration)
        )
        cell.accessoryType = .disclosureIndicator
        if let path = ride.thumbnailPath {
            let url = files.recordingRoot(ride.id).appendingPathComponent(path)
            cell.imageView?.image = UIImage(contentsOfFile: url.path)
        } else {
            cell.imageView?.image = nil
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let timeline = TimelineViewController(recording: recordings[indexPath.row])
        navigationController?.pushViewController(timeline, animated: true)
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let ride = recordings[indexPath.row]
        let delete = UIContextualAction(style: .destructive, title: "删除") { [weak self] _, _, done in
            try? self?.database.deleteRecording(id: ride.id)
            try? self?.files.deleteRecording(ride.id)
            SegmentManager.shared.discard(recordingID: ride.id)
            self?.reload()
            done(true)
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }

    private func importLegacyRecordings() {
        guard let folders = try? FileManager.default.contentsOfDirectory(
            at: files.recordingsURL,
            includingPropertiesForKeys: nil
        ) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for folder in folders {
            guard let id = UUID(uuidString: folder.lastPathComponent) else { continue }
            if (try? database.getRecording(id: id)) != nil { continue }
            let metadataURL = folder.appendingPathComponent("metadata.json")
            guard let data = try? Data(contentsOf: metadataURL),
                  let metadata = try? decoder.decode(RecordingMetadata.self, from: data) else { continue }
            let ride = RideRecording(
                id: metadata.id,
                startTime: metadata.startedAt.timeIntervalSince1970,
                endTime: metadata.endedAt?.timeIntervalSince1970,
                totalDistance: metadata.distanceMeters,
                avgSpeed: metadata.averageSpeedMetersPerSecond,
                maxSpeed: metadata.maxSpeedMetersPerSecond,
                totalDuration: metadata.endedAt.map { $0.timeIntervalSince(metadata.startedAt) } ?? 0,
                totalAscent: 0,
                totalDescent: 0,
                createdAt: metadata.startedAt,
                thumbnailPath: nil,
                videoPath: metadata.videoFileName
            )
            try? database.createRecording(ride)
            let segment = SceneSegment(
                id: metadata.segmentID,
                recordingID: metadata.id,
                startTime: 0,
                endTime: ride.totalDuration,
                sceneType: .other,
                description: "整段骑行",
                latitude: nil,
                longitude: nil,
                avgSpeed: metadata.averageSpeedMetersPerSecond,
                thumbnailPath: nil,
                videoPath: metadata.videoFileName,
                isCompressed: false,
                compressionRatio: nil,
                createdAt: metadata.startedAt
            )
            try? database.createSegment(segment)
            for mark in metadata.marks {
                let bookmark = Bookmark(
                    id: UUID(),
                    recordingID: metadata.id,
                    timestamp: mark.videoTime,
                    type: "manual",
                    description: "手动标记",
                    voiceNotePath: nil,
                    thumbnailPath: nil,
                    isUserCreated: true,
                    createdAt: mark.createdAt
                )
                try? database.createBookmark(bookmark)
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let total = max(0, Int(duration))
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }
}

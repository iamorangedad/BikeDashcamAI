import SwiftUI
import AVFoundation

struct ContentView: View {
    @StateObject private var videoCaptureManager = VideoCaptureManager()
    @StateObject private var videoProcessor = VideoProcessor()
    
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var showingVideoPlayer = false
    @State private var finalVideoURL: URL?
    
    var body: some View {
        ZStack {
            // Camera preview
            CameraPreviewView(videoCaptureManager: videoCaptureManager)
                .edgesIgnoringSafeArea(.all)
            
            // Overlay UI
            VStack {
                // Top status bar
                topStatusBar
                
                Spacer()
                
                // Bottom controls
                bottomControls
            }
            .padding()
        }
        .onAppear {
            setupVideoCapture()
        }
        .alert("提示", isPresented: $showingAlert) {
            Button("确定") { }
        } message: {
            Text(alertMessage)
        }
        .sheet(isPresented: $showingVideoPlayer) {
            if let url = finalVideoURL {
                VideoPlayerView(videoURL: url)
            }
        }
    }
    
    private var topStatusBar: some View {
        HStack {
            // Recording indicator
            if videoCaptureManager.isRecording {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 12, height: 12)
                        .scaleEffect(videoCaptureManager.isRecording ? 1.2 : 1.0)
                        .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: videoCaptureManager.isRecording)
                    
                    Text("录制中")
                        .font(.caption)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.6))
                .cornerRadius(20)
            }
            
            Spacer()
            
            // AI processing status
            if videoProcessor.isProcessing {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    
                    Text("AI剪辑中 \(Int(videoProcessor.progress * 100))%")
                        .font(.caption)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.6))
                .cornerRadius(20)
            }
            
            // Segment count
            HStack(spacing: 8) {
                Image(systemName: "film")
                    .foregroundColor(.white)
                
                Text("\(videoProcessor.getSegmentCount())")
                    .font(.caption)
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.6))
            .cornerRadius(20)
        }
    }
    
    private var bottomControls: some View {
        HStack(spacing: 30) {
            // Settings button
            Button(action: {
                // Show settings
            }) {
                Image(systemName: "gearshape.fill")
                    .font(.title2)
                    .foregroundColor(.white)
                    .frame(width: 50, height: 50)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
            }
            
            // Record button
            Button(action: {
                if videoCaptureManager.isRecording {
                    stopRecording()
                } else {
                    startRecording()
                }
            }) {
                ZStack {
                    Circle()
                        .fill(videoCaptureManager.isRecording ? Color.red : Color.white)
                        .frame(width: 80, height: 80)
                    
                    if videoCaptureManager.isRecording {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white)
                            .frame(width: 32, height: 32)
                    } else {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 60, height: 60)
                    }
                }
            }
            
            // Preview button
            Button(action: {
                if let url = finalVideoURL {
                    showingVideoPlayer = true
                }
            }) {
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundColor(.white)
                    .frame(width: 50, height: 50)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
            }
            .disabled(finalVideoURL == nil)
        }
        .padding(.bottom, 30)
    }
    
    private func setupVideoCapture() {
        // Request camera permissions
        AVCaptureDevice.requestAccess(for: .video) { granted in
            if granted {
                AVCaptureDevice.requestAccess(for: .audio) { audioGranted in
                    DispatchQueue.main.async {
                        if audioGranted {
                            videoCaptureManager.startSession()
                            setupCallbacks()
                        } else {
                            showAlert("需要麦克风权限来录制音频")
                        }
                    }
                }
            } else {
                DispatchQueue.main.async {
                    showAlert("需要相机权限来录制视频")
                }
            }
        }
    }
    
    private func setupCallbacks() {
        videoCaptureManager.onAnalysisResult = { result in
            videoProcessor.addFrame(videoCaptureManager.getRecentFrames().last ?? CMSampleBuffer(), analysisResult: result)
        }
        
        videoProcessor.onProcessingComplete = { url in
            finalVideoURL = url
            showAlert("AI剪辑完成！")
        }
        
        videoCaptureManager.onRecordingComplete = { url in
            // Start AI processing when recording is complete
            videoProcessor.createFinalVideo { processedURL in
                if let processedURL = processedURL {
                    finalVideoURL = processedURL
                }
            }
        }
    }
    
    private func startRecording() {
        videoProcessor.clearSegments()
        videoCaptureManager.startRecording()
    }
    
    private func stopRecording() {
        videoCaptureManager.stopRecording()
    }
    
    private func showAlert(_ message: String) {
        alertMessage = message
        showingAlert = true
    }
}

// MARK: - Camera Preview View
struct CameraPreviewView: UIViewRepresentable {
    let videoCaptureManager: VideoCaptureManager
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let previewLayer = videoCaptureManager.getPreviewLayer()
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        if let previewLayer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
            previewLayer.frame = uiView.bounds
        }
    }
}

// MARK: - Video Player View
struct VideoPlayerView: UIViewControllerRepresentable {
    let videoURL: URL
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let player = AVPlayer(url: videoURL)
        let playerViewController = AVPlayerViewController()
        playerViewController.player = player
        return playerViewController
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        // No updates needed
    }
}

// MARK: - Preview
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
} 
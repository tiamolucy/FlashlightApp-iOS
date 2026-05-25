import AVFoundation
import SwiftUI

class CameraManager: NSObject, ObservableObject {
    private let session = AVCaptureSession()
    private var device: AVCaptureDevice?
    private var movieOutput: AVCaptureMovieFileOutput?

    @Published var isTorchOn = false
    @Published var isRecording = false
    @Published var isReady = false
    @Published var recordingDuration: TimeInterval = 0

    private var timer: Timer?
    private var startTime: Date?

    private var recordingsDir: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recordings")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func setup() {
        session.sessionPreset = .high
        guard let d = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: d),
              session.canAddInput(input) else { return }
        session.addInput(input)

        if let audio = AVCaptureDevice.default(for: .audio),
           let ai = try? AVCaptureDeviceInput(device: audio),
           session.canAddInput(ai) { session.addInput(ai) }

        let out = AVCaptureMovieFileOutput()
        guard session.canAddOutput(out) else { return }
        session.addOutput(out)
        device = d
        movieOutput = out

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
            DispatchQueue.main.async { self?.isReady = true }
        }
    }

    func toggleTorch() {
        guard let d = device, d.hasTorch, !isRecording else { return }
        try? d.lockForConfiguration()
        d.torchMode = isTorchOn ? .off : .on
        d.unlockForConfiguration()
        isTorchOn = d.torchMode == .on
    }

    private func setTorch(_ on: Bool) {
        guard let d = device, d.hasTorch else { return }
        try? d.lockForConfiguration()
        d.torchMode = on ? .on : .off
        d.unlockForConfiguration()
        isTorchOn = on
    }

    func startRecording() {
        guard let out = movieOutput, !isRecording, isReady else { return }
        let url = recordingsDir.appendingPathComponent("recording_\(Int(Date().timeIntervalSince1970)).mp4")
        setTorch(true)
        out.startRecording(to: url, recordingDelegate: self)
        isRecording = true
        startTime = Date()
        recordingDuration = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let s = self, let st = s.startTime else { return }
            s.recordingDuration = Date().timeIntervalSince(st)
        }
    }

    func stopRecording() {
        timer?.invalidate(); timer = nil
        movieOutput?.stopRecording()
        setTorch(false)
        isRecording = false
    }

    var recordings: [URL] {
        let files = try? FileManager.default.contentsOfDirectory(at: recordingsDir, includingPropertiesForKeys: [.creationDateKey])
        return (files ?? []).filter { $0.pathExtension == "mp4" }
            .sorted { a, b in
                let da = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return da > db
            }
    }

    func delete(_ url: URL) { try? FileManager.default.removeItem(at: url) }
}

extension CameraManager: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo: URL, from: [AVCaptureConnection], error: Error?) {
        DispatchQueue.main.async { [weak self] in self?.isRecording = false }
    }
}

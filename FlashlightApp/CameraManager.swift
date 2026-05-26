import AVFoundation
import SwiftUI
import OSLog
import UIKit

private let log = OSLog(subsystem: "com.flashlightapp.ios", category: "camera")

class CameraManager: NSObject, ObservableObject {
    private let session = AVCaptureSession()
    private var device: AVCaptureDevice?
    private var movieOutput: AVCaptureMovieFileOutput?
    private var previewLayer: AVCaptureVideoPreviewLayer?

    @Published var isTorchOn = false
    @Published var isRecording = false
    @Published var isReady = false
    @Published var recordingDuration: TimeInterval = 0

    private var timer: Timer?
    private var startTime: Date?
    private var pendingTorchOn = false

    private var recordingsDir: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recordings")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func setup() {
        os_log(.info, log: log, "setup()")
        session.sessionPreset = .high
        guard let d = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            os_log(.error, log: log, "setup: no back camera"); return }
        guard let input = try? AVCaptureDeviceInput(device: d), session.canAddInput(input) else {
            os_log(.error, log: log, "setup: cannot add camera input"); return }
        session.addInput(input)
        device = d
        os_log(.info, log: log, "setup: camera input added")

        if let audio = AVCaptureDevice.default(for: .audio),
           let ai = try? AVCaptureDeviceInput(device: audio),
           session.canAddInput(ai) {
            session.addInput(ai)
            os_log(.info, log: log, "setup: audio input added")
        }

        // Hidden preview layer stabilizes the video pipeline
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer?.frame = .zero

        let out = AVCaptureMovieFileOutput()
        guard session.canAddOutput(out) else { os_log(.error, log: log, "setup: cannot add movie output"); return }
        session.addOutput(out)
        movieOutput = out
        os_log(.info, log: log, "setup: movie output added")

        // Configure audio session
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .videoRecording)
            try AVAudioSession.sharedInstance().setActive(true)
            os_log(.info, log: log, "setup: audio session configured")
        } catch {
            os_log(.error, log: log, "setup: audio session error %{public}@", error.localizedDescription)
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
            os_log(.info, log: log, "session.startRunning() called")
            // Give session time to stabilize
            Thread.sleep(forTimeInterval: 0.3)
            DispatchQueue.main.async {
                self?.isReady = true
                os_log(.info, log: log, "session ready")
            }
        }
    }

    func toggleTorch() {
        guard let d = device, d.hasTorch, !isRecording else { return }
        do {
            try d.lockForConfiguration()
            d.torchMode = isTorchOn ? .off : .on
            d.unlockForConfiguration()
            isTorchOn = d.torchMode == .on
            os_log(.info, log: log, "toggleTorch -> %{public}@", isTorchOn ? "ON" : "OFF")
        } catch {
            os_log(.error, log: log, "toggleTorch error: %{public}@", error.localizedDescription)
        }
    }

    private func setTorch(_ on: Bool) {
        guard let d = device, d.hasTorch else { return }
        do {
            try d.lockForConfiguration()
            d.torchMode = on ? .on : .off
            d.unlockForConfiguration()
            isTorchOn = d.torchMode == .on
            os_log(.info, log: log, "setTorch(%{public}@) -> %{public}@",
                   on ? "ON" : "OFF", isTorchOn ? "ON" : "OFF")
        } catch {
            os_log(.error, log: log, "setTorch error: %{public}@", error.localizedDescription)
        }
    }

    func startRecording() {
        os_log(.info, log: log, "startRecording() session.isRunning=%{public}@", session.isRunning ? "YES" : "NO")
        guard let out = movieOutput, !isRecording, isReady else {
            os_log(.error, log: log, "startRecording: guard failed (out=%{public}@ isRecording=%{public}@ isReady=%{public}@)",
                   movieOutput != nil ? "ok" : "nil", isRecording ? "T" : "F", isReady ? "T" : "F")
            return
        }

        let url = recordingsDir.appendingPathComponent("recording_\(Int(Date().timeIntervalSince1970)).mp4")
        os_log(.info, log: log, "startRecording: output=%@", url.path)

        // Start recording FIRST, then set torch in delegate callback
        pendingTorchOn = true
        out.startRecording(to: url, recordingDelegate: self)
        isRecording = true
        startTime = Date()
        recordingDuration = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let s = self, let st = s.startTime else { return }
            s.recordingDuration = Date().timeIntervalSince(st)
        }
        os_log(.info, log: log, "startRecording: done")
    }

    func stopRecording() {
        os_log(.info, log: log, "stopRecording() isRecording=%{public}@", isRecording ? "T" : "F")
        pendingTorchOn = false
        timer?.invalidate(); timer = nil
        movieOutput?.stopRecording()
        setTorch(false)
        isRecording = false
        os_log(.info, log: log, "stopRecording: complete")
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

    func delete(_ url: URL) {
        os_log(.info, log: log, "delete %@", url.lastPathComponent)
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate
extension CameraManager: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        os_log(.info, log: log, "DELEGATE didStartRecordingTo: %@ connections=%d", fileURL.lastPathComponent, connections.count)
        // Torch is set AFTER recording pipeline is live
        if pendingTorchOn {
            DispatchQueue.main.async { [weak self] in self?.setTorch(true) }
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        os_log(.info, log: log, "DELEGATE didFinishRecordingTo: %@", outputFileURL.lastPathComponent)
        pendingTorchOn = false
        if let e = error as? NSError {
            os_log(.error, log: log, "DELEGATE error domain=%@ code=%ld description=%{public}@",
                   e.domain, e.code, e.localizedDescription)
        }
        DispatchQueue.main.async { [weak self] in
            self?.timer?.invalidate()
            self?.timer = nil
            self?.setTorch(false)
            self?.isRecording = false
            os_log(.info, log: log, "DELEGATE: cleaned up")
        }
    }
}

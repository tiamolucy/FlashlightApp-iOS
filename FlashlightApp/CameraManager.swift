import AVFoundation
import SwiftUI
import OSLog

private let log = OSLog(subsystem: "com.flashlightapp.ios", category: "camera")

class CameraManager: NSObject, ObservableObject {
    private let session = AVCaptureSession()
    private var device: AVCaptureDevice?
    private var movieOutput: AVCaptureMovieFileOutput?

    @Published var isTorchOn = false
    @Published var isRecording = false
    @Published var ready = false
    @Published var duration: TimeInterval = 0

    private var timer: Timer?
    private var startTime: Date?

    private var docs: URL {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recordings")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    // Flashlight — works independently of the session
    func toggleTorch() {
        guard let d = AVCaptureDevice.default(for: .video) ?? device, d.hasTorch, !isRecording else { return }
        do {
            try d.lockForConfiguration()
            d.torchMode = isTorchOn ? .off : .on
            d.unlockForConfiguration()
            isTorchOn = d.torchMode == .on
        } catch {
            os_log(.error, log: log, "toggleTorch: %{public}@", error.localizedDescription)
        }
    }

    private func setTorch(_ on: Bool) {
        guard let d = device ?? AVCaptureDevice.default(for: .video), d.hasTorch else { return }
        do {
            try d.lockForConfiguration()
            d.torchMode = on ? .on : .off
            d.unlockForConfiguration()
            isTorchOn = d.torchMode == .on
        } catch {
            os_log(.error, log: log, "setTorch: %{public}@", error.localizedDescription)
        }
    }

    // Setup
    func setup() {
        os_log(.default, log: log, "setup")
        session.sessionPreset = .high
        guard let d = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: d),
              session.canAddInput(input)
        else { os_log(.error, log: log, "setup: camera unavailable"); return }
        session.addInput(input)
        device = d

        if let a = AVCaptureDevice.default(for: .audio),
           let ai = try? AVCaptureDeviceInput(device: a),
           session.canAddInput(ai) { session.addInput(ai) }

        let out = AVCaptureMovieFileOutput()
        guard session.canAddOutput(out) else { os_log(.error, log: log, "setup: no output"); return }
        session.addOutput(out)
        movieOutput = out

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
            Thread.sleep(forTimeInterval: 1.5)
            DispatchQueue.main.async {
                self?.ready = true
                os_log(.default, log: log, "setup: ready, isRunning=%{public}@",
                       self?.session.isRunning == true ? "Y" : "N")
            }
        }
    }

    // Recording
    func startRecording() {
        os_log(.default, log: log, "startRecording ready=%{public}@ recording=%{public}@",
               ready ? "T" : "F", isRecording ? "T" : "F")
        guard let out = movieOutput, !isRecording, ready else { return }
        let url = docs.appendingPathComponent("rec_\(Int(Date().timeIntervalSince1970)).mp4")
        out.startRecording(to: url, recordingDelegate: self)
        isRecording = true
        startTime = Date()
        duration = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let me = self, let t = me.startTime else { return }
            me.duration = Date().timeIntervalSince(t)
        }
        os_log(.default, log: log, "startRecording done")
    }

    func stopRecording() {
        os_log(.default, log: log, "stopRecording")
        guard isRecording else { return }
        timer?.invalidate(); timer = nil
        movieOutput?.stopRecording()
        setTorch(false)
        isRecording = false
        duration = 0
    }

    var files: [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil)) ?? []
        return items.filter { $0.pathExtension == "mp4" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    func delete(_ url: URL) { try? FileManager.default.removeItem(at: url) }
}

// MARK: - Delegate
extension CameraManager: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo url: URL, from connections: [AVCaptureConnection]) {
        os_log(.default, log: log, "didStartRecordingTo %@", url.lastPathComponent)
        DispatchQueue.main.async { [weak self] in self?.setTorch(true) }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo url: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let e = error as? NSError { os_log(.error, log: log, "didFinish error %@ %ld", e.domain, e.code) }
        else { os_log(.default, log: log, "didFinish success") }
        DispatchQueue.main.async { [weak self] in
            self?.timer?.invalidate(); self?.timer = nil
            self?.setTorch(false); self?.isRecording = false
        }
    }
}

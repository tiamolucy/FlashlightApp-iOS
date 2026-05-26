import AVFoundation
import SwiftUI
import OSLog

private let log = OSLog(subsystem: "com.flashlightapp.ios", category: "camera")

class CameraManager: NSObject, ObservableObject {
    private let session = AVCaptureSession()
    private var device: AVCaptureDevice?
    private var movieOutput: AVCaptureMovieFileOutput?

    @Published var isTorchOn = false { didSet { os_log(.debug, log: log, "isTorchOn -> %{public}@", isTorchOn ? "true" : "false") } }
    @Published var isRecording = false { didSet { os_log(.debug, log: log, "isRecording -> %{public}@", isRecording ? "true" : "false") } }
    @Published var isReady = false { didSet { os_log(.debug, log: log, "isReady -> %{public}@", isReady ? "true" : "false") } }
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
        os_log(.info, log: log, "setup() start")
        session.sessionPreset = .high
        guard let d = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            os_log(.error, log: log, "setup: no back camera")
            return
        }
        guard let input = try? AVCaptureDeviceInput(device: d), session.canAddInput(input) else {
            os_log(.error, log: log, "setup: cannot add camera input")
            return
        }
        session.addInput(input)
        os_log(.info, log: log, "setup: camera input added")

        device = d

        if let audio = AVCaptureDevice.default(for: .audio),
           let ai = try? AVCaptureDeviceInput(device: audio),
           session.canAddInput(ai) {
            session.addInput(ai)
            os_log(.info, log: log, "setup: audio input added")
        } else {
            os_log(.info, log: log, "setup: no audio input available")
        }

        let out = AVCaptureMovieFileOutput()
        guard session.canAddOutput(out) else {
            os_log(.error, log: log, "setup: cannot add movie output")
            return
        }
        session.addOutput(out)
        movieOutput = out
        os_log(.info, log: log, "setup: movie output added")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
            os_log(.info, log: log, "session.startRunning() called (async)")
            DispatchQueue.main.async {
                self?.isReady = true
                os_log(.info, log: log, "session ready")
            }
        }
    }

    func toggleTorch() {
        os_log(.info, log: log, "toggleTorch() called, current isTorchOn=%{public}@, isRecording=%{public}@",
               isTorchOn ? "true" : "false", isRecording ? "true" : "false")
        guard let d = device, d.hasTorch else {
            os_log(.error, log: log, "toggleTorch: no torch available")
            return
        }
        guard !isRecording else {
            os_log(.info, log: log, "toggleTorch: ignored during recording")
            return
        }
        do {
            try d.lockForConfiguration()
            d.torchMode = isTorchOn ? .off : .on
            d.unlockForConfiguration()
            isTorchOn = d.torchMode == .on
            os_log(.info, log: log, "toggleTorch: torchMode=%{public}@", isTorchOn ? "ON" : "OFF")
        } catch {
            os_log(.error, log: log, "toggleTorch lock error: %{public}@", error.localizedDescription)
        }
    }

    private func setTorch(_ on: Bool) {
        os_log(.info, log: log, "setTorch(%{public}@)", on ? "ON" : "OFF")
        guard let d = device, d.hasTorch else {
            os_log(.error, log: log, "setTorch: no torch available")
            return
        }
        do {
            try d.lockForConfiguration()
            d.torchMode = on ? .on : .off
            d.unlockForConfiguration()
            isTorchOn = d.torchMode == .on
            os_log(.info, log: log, "setTorch done: torchMode=%{public}@", isTorchOn ? "ON" : "OFF")
        } catch {
            os_log(.error, log: log, "setTorch error: %{public}@", error.localizedDescription)
        }
    }

    func startRecording() {
        os_log(.info, log: log, "startRecording() called")
        guard let out = movieOutput else {
            os_log(.error, log: log, "startRecording: movieOutput is nil")
            return
        }
        guard !isRecording else {
            os_log(.info, log: log, "startRecording: already recording")
            return
        }
        guard isReady else {
            os_log(.error, log: log, "startRecording: camera not ready")
            return
        }
        os_log(.info, log: log, "startRecording: session isRunning=%{public}@", session.isRunning ? "YES" : "NO")

        let url = recordingsDir.appendingPathComponent("recording_\(Int(Date().timeIntervalSince1970)).mp4")
        os_log(.info, log: log, "startRecording: output file=%{public}@", url.path)

        setTorch(true)

        // Check if torch is actually on
        if let d = device, d.hasTorch {
            os_log(.info, log: log, "startRecording: torchMode after setTorch=%{public}@",
                   d.torchMode == .on ? "ON" : "OFF")
        }

        out.startRecording(to: url, recordingDelegate: self)
        os_log(.info, log: log, "startRecording: startRecording() called on output")
        isRecording = true
        startTime = Date()
        recordingDuration = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let s = self, let st = s.startTime else { return }
            s.recordingDuration = Date().timeIntervalSince(st)
        }
        os_log(.info, log: log, "startRecording: done, timer started")
    }

    func stopRecording() {
        os_log(.info, log: log, "stopRecording() called, isRecording=%{public}@", isRecording ? "true" : "false")
        timer?.invalidate()
        timer = nil
        os_log(.info, log: log, "stopRecording: timer invalidated")

        if let out = movieOutput {
            os_log(.info, log: log, "stopRecording: calling movieOutput.stopRecording()")
            out.stopRecording()
            os_log(.info, log: log, "stopRecording: movieOutput.stopRecording() returned")
        } else {
            os_log(.error, log: log, "stopRecording: movieOutput is nil")
        }

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
        os_log(.info, log: log, "delete: %{public}@", url.lastPathComponent)
        try? FileManager.default.removeItem(at: url)
    }
}

extension CameraManager: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        os_log(.info, log: log, "DELEGATE didStartRecordingTo: %{public}@", fileURL.lastPathComponent)
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        os_log(.info, log: log, "DELEGATE didFinishRecordingTo: %{public}@", outputFileURL.lastPathComponent)
        if let e = error {
            os_log(.error, log: log, "DELEGATE recording error: %{public}@ (domain=%{public}@ code=%ld)",
                   e.localizedDescription, (e as NSError).domain, (e as NSError).code)
        } else {
            os_log(.info, log: log, "DELEGATE recording finished with no error")
        }
        DispatchQueue.main.async { [weak self] in
            self?.isRecording = false
            if error != nil {
                // Recording never started or failed — force torch off
                self?.isTorchOn = false
                self?.timer?.invalidate()
                self?.timer = nil
                os_log(.info, log: log, "DELEGATE: error -> torch off + timer cleared")
            }
            os_log(.info, log: log, "DELEGATE: didFinishRecordingTo -> isRecording=false")
        }
    }
}

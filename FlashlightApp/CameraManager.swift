import AVFoundation
import SwiftUI
import OSLog

private let log = OSLog(subsystem: "com.flashlightapp.ios", category: "camera")

class CameraManager: NSObject, ObservableObject {
    private let session = AVCaptureSession()
    private var device: AVCaptureDevice?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var audioOutput: AVCaptureAudioDataOutput?

    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?

    private let vq = DispatchQueue(label: "cam.video")
    private let aq = DispatchQueue(label: "cam.audio")

    @Published var isTorchOn = false
    @Published var isRecording = false
    @Published var ready = false
    @Published var duration: TimeInterval = 0

    private var timer: Timer?
    private var startTime: Date?
    private var firstSample = true

    private var docs: URL {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recordings")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    // ── Flashlight ──
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

    // ── Setup ──
    func setup() {
        os_log(.default, log: log, "setup")
        session.sessionPreset = .high

        guard let d = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let vi = try? AVCaptureDeviceInput(device: d),
              session.canAddInput(vi)
        else { os_log(.error, log: log, "setup: no camera"); return }
        session.addInput(vi)
        device = d

        if let a = AVCaptureDevice.default(for: .audio),
           let ai = try? AVCaptureDeviceInput(device: a),
           session.canAddInput(ai) { session.addInput(ai) }

        let vout = AVCaptureVideoDataOutput()
        vout.setSampleBufferDelegate(self, queue: vq)
        vout.alwaysDiscardsLateVideoFrames = true
        guard session.canAddOutput(vout) else { os_log(.error, log: log, "setup: no vout"); return }
        session.addOutput(vout)
        videoOutput = vout

        let aout = AVCaptureAudioDataOutput()
        aout.setSampleBufferDelegate(self, queue: aq)
        if session.canAddOutput(aout) { session.addOutput(aout) }
        audioOutput = aout

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
            Thread.sleep(forTimeInterval: 1.5)
            DispatchQueue.main.async {
                self?.ready = true
                os_log(.default, log: log, "setup: ready")
            }
        }
    }

    // ── Recording ──
    func startRecording() {
        os_log(.default, log: log, "startRecording ready=%{public}@ recording=%{public}@",
               ready ? "T" : "F", isRecording ? "T" : "F")
        guard !isRecording, ready else { return }

        let url = docs.appendingPathComponent("rec_\(Int(Date().timeIntervalSince1970)).mp4")
        guard let w = try? AVAssetWriter(outputURL: url, fileType: .mp4) else {
            os_log(.error, log: log, "startRecording: no writer"); return
        }
        writer = w

        guard let vs = videoOutput?.recommendedVideoSettingsForAssetWriter(writingTo: .mp4) else {
            os_log(.error, log: log, "startRecording: no video settings"); return
        }
        let vi = AVAssetWriterInput(mediaType: .video, outputSettings: vs)
        vi.expectsMediaDataInRealTime = true
        guard w.canAdd(vi) else { os_log(.error, log: log, "startRecording: cannot add vi"); return }
        w.add(vi)
        videoInput = vi

        if let aout = audioOutput,
           let as_ = aout.recommendedAudioSettingsForAssetWriter(writingTo: .mp4) as? [String: Any] {
            let ai = AVAssetWriterInput(mediaType: .audio, outputSettings: as_)
            ai.expectsMediaDataInRealTime = true
            if w.canAdd(ai) { w.add(ai); audioInput = ai }
        }

        guard w.startWriting() else {
            os_log(.error, log: log, "startWriting failed: %{public}@", w.error?.localizedDescription ?? "?")
            writer = nil; return
        }

        isRecording = true
        firstSample = true
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
        isRecording = false
        timer?.invalidate(); timer = nil
        duration = 0
        setTorch(false)

        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        writer?.finishWriting { os_log(.default, log: log, "writer finished") }
        writer = nil
        videoInput = nil
        audioInput = nil
    }

    var files: [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil)) ?? []
        return items.filter { $0.pathExtension == "mp4" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    func delete(_ url: URL) { try? FileManager.default.removeItem(at: url) }
}

// MARK: - Sample buffer delegate
extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard isRecording, let w = writer, w.status == .writing else { return }

        if output === videoOutput {
            if firstSample {
                firstSample = false
                w.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
                DispatchQueue.main.async { [weak self] in self?.setTorch(true) }
            }
            guard let vi = videoInput, vi.isReadyForMoreMediaData else { return }
            vi.append(sampleBuffer)
        } else if output === audioOutput {
            guard let ai = audioInput, ai.isReadyForMoreMediaData else { return }
            ai.append(sampleBuffer)
        }
    }
}

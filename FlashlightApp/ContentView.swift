import SwiftUI
import AVFoundation
import OSLog

private let log = OSLog(subsystem: "com.flashlightapp.ios", category: "ui")

struct Beam: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            let mx = rect.midX
            p.move(to: .init(x: mx - 10, y: 0))
            p.addLine(to: .init(x: mx + 10, y: 0))
            p.addLine(to: .init(x: mx + rect.width * 0.7, y: rect.height))
            p.addLine(to: .init(x: mx - rect.width * 0.7, y: rect.height))
        }
    }
}

struct ContentView: View {
    @StateObject private var cam = CameraManager()
    @State private var showRecordings = false
    @State private var headTaps = 0
    @State private var powerTaps = 0
    @State private var unlockStage = 0
    @State private var toastMsg = ""
    @State private var showToast = false
    @State private var showSettings = false
    @State private var headTimer: DispatchWorkItem?
    @State private var powerTimer: DispatchWorkItem?

    var body: some View {
        ZStack {
            Color(white: 0.02).ignoresSafeArea()

            if cam.isTorchOn || cam.isRecording {
                Beam().fill(.yellow.opacity(0.25)).blur(radius: 24)
                    .frame(width: 200, height: 300).offset(y: -170)
                Beam().fill(.yellow.opacity(0.1)).blur(radius: 50)
                    .frame(width: 240, height: 360).offset(y: -190)
                Beam().fill(.white.opacity(0.05)).blur(radius: 40)
                    .frame(width: 160, height: 200).offset(y: -130)
            }

            VStack(spacing: 0) {
                Spacer().frame(height: 30)

                // === HEAD (tap = flashlight toggle) ===
                VStack(spacing: 0) {
                    ZStack {
                        Circle().fill(Color(white: 0.35)).frame(width: 50)
                        Circle().fill(.white.opacity(cam.isTorchOn || cam.isRecording ? 0.5 : 0.15))
                            .frame(width: 34)
                        Circle().stroke(Color(white: 0.5), lineWidth: 2).frame(width: 50)
                    }
                    .background(
                        Circle().fill(.yellow.opacity(cam.isTorchOn || cam.isRecording ? 0.5 : 0))
                            .blur(radius: 14).frame(width: 70)
                    )

                    RoundedRectangle(cornerRadius: 10)
                        .fill(LinearGradient(colors: [Color(white: 0.3), Color(white: 0.12), Color(white: 0.2)],
                                              startPoint: .top, endPoint: .bottom))
                        .frame(width: 140, height: 50)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.1), lineWidth: 1))

                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(white: 0.18)).frame(width: 150, height: 14)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.white.opacity(0.05), lineWidth: 1))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(white: 0.14)).frame(width: 150, height: 14)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.white.opacity(0.05), lineWidth: 1))
                }
                .onTapGesture {
                    os_log(.info, log: log, "HEAD tapped, unlockStage=%d headTaps=%d", unlockStage, headTaps)
                    if unlockStage == 0 {
                        headTimer?.cancel()
                        headTaps += 1
                        let w = DispatchWorkItem { self.headTaps = 0; os_log(.info, log: log, "HEAD: tap timeout reset") }
                        headTimer = w
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: w)
                        if headTaps >= 8 {
                            headTimer?.cancel()
                            headTaps = 0; powerTaps = 0; unlockStage = 1
                            toastMsg = "已解锁，再点击8次开关进入管理页"
                            withAnimation { showToast = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                withAnimation(.easeOut(duration: 0.3)) { showToast = false }
                            }
                            os_log(.info, log: log, "HEAD: unlock stage 1")
                            return
                        }
                    }
                    if !cam.isRecording {
                        os_log(.info, log: log, "HEAD: toggle torch")
                        cam.toggleTorch()
                    } else {
                        os_log(.info, log: log, "HEAD: ignored (recording)")
                    }
                }
                .overlay(unlockStage == 1 ?
                    RoundedRectangle(cornerRadius: 4).stroke(.purple.opacity(0.5), lineWidth: 2)
                        .frame(width: 150, height: 78) : nil)

                // === NECK ===
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(white: 0.12)).frame(width: 120, height: 8)

                // === BODY (power button = record) ===
                RoundedRectangle(cornerRadius: 14)
                    .fill(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.08), Color(white: 0.12)],
                                          startPoint: .top, endPoint: .bottom))
                    .frame(width: 130, height: 260)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.06), lineWidth: 1))
                    .overlay(alignment: .center) {
                        if cam.isTorchOn || cam.isRecording {
                            Circle().fill(.yellow.opacity(0.1)).frame(width: 110, height: 110).blur(radius: 14)
                        }
                        Button(action: handleTap) {
                            ZStack {
                                Circle().fill(Color(white: 0.2)).frame(width: 72, height: 72)
                                Circle().fill(cam.isRecording ? .red :
                                              cam.isTorchOn ? Color(red: 1, green: 0.85, blue: 0.2) : Color(white: 0.35))
                                    .frame(width: 64, height: 64)
                                Circle().stroke(.white.opacity(0.2), lineWidth: 1).frame(width: 72, height: 72)
                                Image(systemName: cam.isRecording ? "stop.fill" : "flashlight.on.fill")
                                    .font(.title2).foregroundStyle(.white)
                            }
                        }
                        .offset(y: -10)
                    }

                Text(statusText)
                    .font(cam.isRecording ? .title2.monospacedDigit() : .subheadline)
                    .foregroundStyle(cam.isRecording ? .yellow : .gray)
                    .padding(.top, 20)

                Spacer()
            }
        }
        .onAppear {
            os_log(.info, log: log, "onAppear: requesting permissions")
            cam.setup()
            AVCaptureDevice.requestAccess(for: .video) { g in
                os_log(.info, log: log, "camera permission: %{public}@", g ? "granted" : "denied")
                AVAudioSession.sharedInstance().requestRecordPermission { g2 in
                    os_log(.info, log: log, "audio permission: %{public}@", g2 ? "granted" : "denied")
                }
            }
        }
        .overlay(alignment: .top) {
            if showToast {
                Text(toastMsg).font(.subheadline).foregroundStyle(.white)
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 60).transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4), value: cam.isRecording)
        .animation(.easeInOut(duration: 0.3), value: cam.isTorchOn)
        .alert("需要权限", isPresented: $showSettings) {
            Button("设置") { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) }
            Button("取消", role: .cancel) {}
        } message: { Text("请在设置中允许相机和麦克风权限") }
        .sheet(isPresented: $showRecordings) { RecordingsView(cam: cam) }
    }

    private var statusText: String {
        if cam.isRecording { return String(format: "%02.0f:%02.0f", cam.duration / 60, cam.duration.truncatingRemainder(dividingBy: 60)) }
        if unlockStage == 1 { return "已解锁，继续点击开关" }
        if !cam.ready { return "相机初始化中" }
        return "点头部开手电 · 按开关录像"
    }

    private func handleTap() {
        os_log(.info, log: log, "POWER tapped: unlockStage=%d powerTaps=%d isRecording=%{public}@ isReady=%{public}@",
               unlockStage, powerTaps, cam.isRecording ? "true" : "false", cam.ready ? "true" : "false")

        if unlockStage == 1 {
            powerTimer?.cancel()
            powerTaps += 1
            let w = DispatchWorkItem { self.powerTaps = 0; os_log(.info, log: log, "POWER: tap timeout reset") }
            powerTimer = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: w)
            os_log(.info, log: log, "POWER: unlock stage, powerTaps now %d", powerTaps)
            if powerTaps >= 8 { powerTimer?.cancel(); powerTaps = 0; unlockStage = 0; showRecordings = true; os_log(.info, log: log, "POWER: opening recordings") }
            return
        }
        guard cam.ready else { os_log(.error, log: log, "POWER: camera not ready"); return }

        if cam.isRecording {
            os_log(.info, log: log, "POWER: stopping recording")
            cam.stopRecording()
            return
        }

        // Start recording
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        os_log(.info, log: log, "POWER: starting recording, auth=%d", status.rawValue)

        switch status {
        case .authorized:
            headTaps = 0; powerTaps = 0; unlockStage = 0
            cam.startRecording()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { g in
                os_log(.info, log: log, "POWER: permission callback granted=%{public}@", g ? "true" : "false")
                if g { DispatchQueue.main.async { self.cam.startRecording() } }
            }
        default:
            os_log(.error, log: log, "POWER: no permission")
            showSettings = true
        }
    }
}

import SwiftUI
import AVFoundation

struct LightCone: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            let mx = rect.midX
            p.move(to: .init(x: mx - 12, y: 0))
            p.addLine(to: .init(x: mx + 12, y: 0))
            p.addLine(to: .init(x: mx + rect.width * 0.6, y: rect.height))
            p.addLine(to: .init(x: mx - rect.width * 0.6, y: rect.height))
            p.closeSubpath()
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
    @State private var torchHaptic = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Light cone + glow
            if cam.isTorchOn || cam.isRecording {
                LightCone()
                    .fill(.yellow.opacity(0.18))
                    .blur(radius: 28)
                    .frame(width: 200, height: 260)
                    .offset(y: -140)

                LightCone()
                    .fill(.yellow.opacity(0.08))
                    .blur(radius: 50)
                    .frame(width: 220, height: 300)
                    .offset(y: -160)
            }

            VStack(spacing: 0) {
                Spacer().frame(height: 40)

                // === Flashlight Head (tap = toggle torch) ===
                VStack(spacing: 0) {
                    Circle()
                        .fill(.white.opacity(cam.isTorchOn || cam.isRecording ? 0.35 : 0.15))
                        .frame(width: 42, height: 42)
                        .overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 1))
                        .background(
                            Circle()
                                .fill(.yellow.opacity(cam.isTorchOn || cam.isRecording ? 0.4 : 0))
                                .blur(radius: 12)
                                .frame(width: 60, height: 60)
                        )

                    RoundedRectangle(cornerRadius: 18)
                        .fill(LinearGradient(
                            colors: [Color(white: 0.28), Color(white: 0.12)],
                            startPoint: .top, endPoint: .bottom))
                        .frame(width: 170, height: 80)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(.white.opacity(0.08), lineWidth: 1)
                        )
                }
                .onTapGesture {
                    if unlockStage == 0 {
                        headTaps += 1
                        if headTaps >= 5 {
                            headTaps = 0; powerTaps = 0; unlockStage = 1
                            toastMsg = "隐藏入口已解锁，再点击5次开关进入管理页"
                            withAnimation { showToast = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                withAnimation(.easeOut(duration: 0.3)) { showToast = false }
                            }
                            return
                        }
                    }
                    // Toggle flashlight independently (only when not recording)
                    if !cam.isRecording { cam.toggleTorch() }
                }
                .overlay(unlockStage == 1 ?
                    RoundedRectangle(cornerRadius: 18).stroke(.purple.opacity(0.5), lineWidth: 2) : nil)

                // Connector
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(white: 0.15))
                    .frame(width: 130, height: 10)

                // === Flashlight Body (power button = record) ===
                RoundedRectangle(cornerRadius: 22)
                    .fill(LinearGradient(
                        colors: [Color(white: 0.13), Color(white: 0.08)],
                        startPoint: .top, endPoint: .bottom))
                    .frame(width: 155, height: 280)
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.06), lineWidth: 1))
                    .overlay(alignment: .center) {
                        // Glow near button
                        if cam.isTorchOn || cam.isRecording {
                            Circle().fill(.yellow.opacity(0.12)).frame(width: 120, height: 120).blur(radius: 16)
                        }

                        Button(action: handlePowerTap) {
                            Circle()
                                .fill(cam.isRecording ? .red :
                                      cam.isTorchOn ? .yellow : Color(white: 0.3))
                                .frame(width: 82, height: 82)
                                .overlay(
                                    Image(systemName: cam.isRecording ? "stop.fill" : "flashlight.on.fill")
                                        .font(.title).foregroundStyle(.white)
                                )
                        }
                    }

                // Status
                Text(statusText)
                    .font(cam.isRecording ? .title2.monospacedDigit() : .subheadline)
                    .foregroundStyle(cam.isRecording ? .yellow : .gray)
                    .padding(.top, 24)

                Spacer()
            }
        }
        .onAppear {
            cam.setup()
            AVCaptureDevice.requestAccess(for: .video) { _ in
                AVAudioSession.sharedInstance().requestRecordPermission { _ in }
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
        if cam.isRecording {
            return String(format: "%02.0f:%02.0f",
                          cam.recordingDuration / 60,
                          cam.recordingDuration.truncatingRemainder(dividingBy: 60))
        }
        if unlockStage == 1 { return "已解锁，继续点击开关" }
        if !cam.isReady { return "相机初始化中" }
        return "点头部开手电 · 按开关录像"
    }

    private func handlePowerTap() {
        if unlockStage == 1 {
            powerTaps += 1
            if powerTaps >= 5 { powerTaps = 0; unlockStage = 0; showRecordings = true }
            return
        }
        guard cam.isReady else { return }

        if cam.isRecording {
            cam.stopRecording()
            return
        }

        // Start recording — check permissions on the fly
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            headTaps = 0; powerTaps = 0; unlockStage = 0
            cam.startRecording()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted { DispatchQueue.main.async { self.cam.startRecording() } }
            }
        default:
            showSettings = true
        }
    }
}

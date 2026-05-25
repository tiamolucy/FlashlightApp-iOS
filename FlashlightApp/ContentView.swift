import SwiftUI
import AVFoundation

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

    var body: some View {
        ZStack {
            Color(white: 0.02).ignoresSafeArea()

            // === Beam glow ===
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
                    // Lens
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

                    // Head body
                    RoundedRectangle(cornerRadius: 10)
                        .fill(LinearGradient(colors: [Color(white: 0.3), Color(white: 0.12), Color(white: 0.2)],
                                              startPoint: .top, endPoint: .bottom))
                        .frame(width: 140, height: 50)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.1), lineWidth: 1))

                    // Ridges
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(white: 0.18)).frame(width: 150, height: 14)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.white.opacity(0.05), lineWidth: 1))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(white: 0.14)).frame(width: 150, height: 14)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.white.opacity(0.05), lineWidth: 1))
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
                    if !cam.isRecording { cam.toggleTorch() }
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

                // Status
                Text(statusText)
                    .font(cam.isRecording ? .title2.monospacedDigit() : .subheadline)
                    .foregroundStyle(cam.isRecording ? .yellow : .gray)
                    .padding(.top, 20)

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
        if cam.isRecording { return String(format: "%02.0f:%02.0f", cam.recordingDuration / 60, cam.recordingDuration.truncatingRemainder(dividingBy: 60)) }
        if unlockStage == 1 { return "已解锁，继续点击开关" }
        if !cam.isReady { return "相机初始化中" }
        return "点头部开手电 · 按开关录像"
    }

    private func handleTap() {
        if unlockStage == 1 {
            powerTaps += 1
            if powerTaps >= 5 { powerTaps = 0; unlockStage = 0; showRecordings = true }
            return
        }
        guard cam.isReady else { return }
        if cam.isRecording { cam.stopRecording(); return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: headTaps = 0; powerTaps = 0; unlockStage = 0; cam.startRecording()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { g in
                if g { DispatchQueue.main.async { self.cam.startRecording() } }
            }
        default: showSettings = true
        }
    }
}

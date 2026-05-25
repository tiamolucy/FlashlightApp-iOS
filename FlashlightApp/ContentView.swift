import SwiftUI
import AVFoundation

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
            LinearGradient(colors: cam.isRecording
                ? [Color(red: 0.08, green: 0.04, blue: 0.04), Color(red: 0.15, green: 0.06, blue: 0.09)]
                : [Color(red: 0.02, green: 0.03, blue: 0.04), Color(red: 0.04, green: 0.07, blue: 0.12)],
                           startPoint: .top, endPoint: .bottom).ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Flashlight head
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(white: unlockStage == 1 ? 0.25 : 0.2))
                    .frame(width: 180, height: 80)
                    .overlay(Circle().fill(.white.opacity(0.2)).frame(width: 20, height: 20).offset(y: -16))
                    .overlay(unlockStage == 1 ? RoundedRectangle(cornerRadius: 24).stroke(.purple.opacity(0.5), lineWidth: 2) : nil)
                    .onTapGesture {
                        if unlockStage == 0 {
                            headTaps += 1
                            if headTaps >= 5 {
                                headTaps = 0; powerTaps = 0; unlockStage = 1
                                showToast("隐藏入口已解锁，再点击5次开关进入管理页")
                            }
                        }
                    }

                Rectangle().fill(Color(white: 0.15)).frame(width: 140, height: 10)

                RoundedRectangle(cornerRadius: 28)
                    .fill(Color(white: 0.12))
                    .frame(width: 170, height: 300)
                    .overlay(alignment: .center) {
                        if cam.isTorchOn || cam.isRecording {
                            Circle().fill(.yellow.opacity(0.15)).frame(width: 130, height: 130).blur(radius: 20)
                        }
                        Circle()
                            .fill(cam.isRecording ? .red : (cam.isTorchOn ? .yellow : Color(white: 0.25)))
                            .frame(width: 90, height: 90)
                            .overlay(
                                Image(systemName: cam.isRecording ? "stop.fill" : "flashlight.on.fill")
                                    .font(.title2).foregroundStyle(.white)
                            )
                            .onTapGesture(perform: handlePowerTap)
                    }

                Text(statusText)
                    .font(cam.isRecording ? .title2.monospacedDigit() : .subheadline)
                    .foregroundStyle(cam.isRecording ? .yellow : .gray).padding(.top, 20)

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
        .animation(.spring(duration: 0.4), value: cam.isRecording)
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
        return "点击开关开始闪光灯录像"
    }

    private func handlePowerTap() {
        if unlockStage == 1 {
            powerTaps += 1
            if powerTaps >= 5 { powerTaps = 0; unlockStage = 0; showRecordings = true }
            return
        }
        guard cam.isReady else { return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            if cam.isRecording { cam.stopRecording() } else {
                headTaps = 0; powerTaps = 0; unlockStage = 0
                cam.startRecording()
            }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted { DispatchQueue.main.async { cam.startRecording() } }
            }
        default: showSettings = true
        }
    }

    private func showToast(_ msg: String) {
        toastMsg = msg; showToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation(.easeOut(duration: 0.3)) { showToast = false }
        }
    }
}

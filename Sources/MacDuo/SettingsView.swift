import SwiftUI

struct SettingsView: View {
    @ObservedObject var state: AppState
    private let ink = Color(red: 0.10, green: 0.13, blue: 0.17)

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("MacDuo").font(.system(size: 30, weight: .semibold, design: .rounded))
                    Text("画面停在原处，屏幕向它靠近。")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("启用效果", isOn: $state.enabled)
                    .toggleStyle(.switch).labelsHidden().accessibilityLabel("启用开盖对焦")
                    .padding(.top, 8)
            }

            VStack(spacing: 16) {
                HStack(spacing: 5) {
                    Image(systemName: state.isPreviewing ? "play.circle" : "viewfinder")
                    Text(state.isPreviewing ? "正在演示开合" : !state.enabled ? "效果已暂停" : state.currentBlur > 0.2 ? "正在与画面重合" : "画面已重合")
                }.font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(state.angle.map { String(format: "%.0f", $0) } ?? "—")
                        .font(.system(size: 58, weight: .light, design: .rounded)).monospacedDigit()
                    Text("°").font(.system(size: 32, weight: .light)).foregroundStyle(.secondary)
                }
                HStack {
                    Label("实时机盖角度", systemImage: "laptopcomputer")
                    Spacer()
                    Text("清晰点 \(Int(state.focusAngle))°").monospacedDigit()
                }.font(.system(size: 12)).foregroundStyle(.secondary)
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(ink.opacity(0.07))
                        Capsule().fill(Color.accentColor.opacity(0.75))
                            .frame(width: geometry.size.width * min(1, max(0, (state.angle ?? 0) / state.focusAngle)))
                    }
                }.frame(height: 4)
            }
            .padding(22).background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 22))

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("清晰角度").fontWeight(.medium)
                    Spacer()
                    Text("\(Int(state.focusAngle))°").monospacedDigit().foregroundStyle(.secondary)
                }
                Slider(value: $state.focusAngle, in: 25...180, step: 1)
                    .accessibilityLabel("画面完全清晰的机盖角度")
                Button { state.calibrate() } label: {
                    Label("将当前开盖位置设为清晰点", systemImage: "scope")
                        .frame(maxWidth: .infinity).padding(.vertical, 5)
                }
                .buttonStyle(.bordered).disabled((state.angle ?? 0) < 25)
                Text("把机盖打开到你希望的最大位置，再点击校准。")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }.font(.system(size: 13))

            VStack(alignment: .leading, spacing: 8) {
                Label(state.perspectiveStatus, systemImage: "rectangle.inset.filled.bottomthird")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                if state.needsCapturePermission {
                    if state.captureAuthorizationRequested {
                        HStack {
                            Button("我已授权，重新打开") { state.reopenAfterAuthorization() }
                                .buttonStyle(.borderedProminent)
                            Button("打开权限设置") { state.openCaptureSettings() }
                        }
                    } else {
                        Button("授权屏幕录制，启用立体效果") { state.authorizeCapture() }
                            .buttonStyle(.borderedProminent)
                    }
                    Text("实时画面仅在本机处理，不保存、不上传。")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                } else if state.perspective.error != nil {
                    Button("重试立体效果") { state.refreshCapture() }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("顶部离焦强度").fontWeight(.medium)
                    Spacer()
                    Text("\(Int(state.maximumBlur))").monospacedDigit().foregroundStyle(.secondary)
                }
                Slider(value: $state.maximumBlur, in: 1...80, step: 1).accessibilityLabel("顶部最大模糊强度")
                HStack {
                    Text("轻柔")
                    Spacer()
                    Text("朦胧")
                }.font(.system(size: 11)).foregroundStyle(.secondary)
            }.font(.system(size: 13))

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("空间倾斜").fontWeight(.medium)
                    Spacer()
                    Text("\(Int((state.perspectiveStrength * 100).rounded()))%")
                        .monospacedDigit().foregroundStyle(.secondary)
                }
                Slider(value: $state.perspectiveStrength, in: 0...1, step: 0.01)
                    .accessibilityLabel("空间倾斜强度")
                HStack {
                    Text("更竖直")
                    Spacer()
                    Text("更有纵深")
                }.font(.system(size: 11)).foregroundStyle(.secondary)
            }.font(.system(size: 13))

            if let error = state.error {
                Label(error, systemImage: "exclamationmark.triangle").font(.system(size: 12)).foregroundStyle(.orange)
            } else if state.angle == nil {
                Label("正在寻找机盖传感器；暂不改变屏幕。", systemImage: "sensor").font(.system(size: 12)).foregroundStyle(.secondary)
            }

            HStack {
                Button(state.isPreviewing ? "结束演示" : "预览开合效果", systemImage: state.isPreviewing ? "stop.fill" : "play.fill") {
                    if state.isPreviewing { state.stopPreview() } else { state.preview() }
                }.buttonStyle(.borderedProminent).disabled(state.error != nil)
                Spacer()
                Text("⌃⌥⌘B  一键恢复清晰")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Text("窗口与背景均上重下轻地模糊，合盖越多，离焦越强。")
                .font(.system(size: 11)).foregroundStyle(.tertiary)
        }
        .padding(28)
        .frame(width: 440)
        .foregroundStyle(ink)
        .background(Color(red: 0.94, green: 0.955, blue: 0.975))
        .preferredColorScheme(.light)
        .onExitCommand { state.emergencyClear() }
    }
}

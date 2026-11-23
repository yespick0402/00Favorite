// MARK: - MAINT1: 새 설치 / 삭제 전 정리 마법사
// macOS TCC 데이터베이스는 직접 수정하지 않습니다.
// 사용자가 시작한 경우에만 시스템 승인 API 또는 tccutil을 호출합니다.
import Foundation
import AppKit
import SwiftUI

private enum FavoriteAppPrivacyMaintenance {
    static let expectedBundleID = "win.yespick.00favorite"

    static var isCurrentAppVerified: Bool {
        Bundle.main.bundleIdentifier == expectedBundleID
    }

    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    // 비밀번호 / sudo / shell 없이 macOS 기본 도구만 실행합니다.
    // 정확히 00Favorite의 번들 식별자에 해당하는 권한 결정만 초기화합니다.
    static func resetPrivacyForCurrentApp() -> String {
        guard isCurrentAppVerified else {
            return "권한 초기화 중단: 실행 중인 앱 식별자가 예상값과 다릅니다. 다른 앱의 권한은 변경하지 않았습니다."
        }
        let executable = URL(fileURLWithPath: "/usr/bin/tccutil")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            return "권한 초기화 불가: macOS의 tccutil을 실행할 수 없습니다. 아래 시스템 설정 버튼에서 직접 해제하세요."
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = ["reset", "All", expectedBundleID]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let detail = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if process.terminationReason == .exit && process.terminationStatus == 0 {
                return "개인정보 보호 권한 초기화 요청 성공 (\(expectedBundleID)). 시스템 설정에 기존 항목이 남아 있으면 직접 해제·제거 여부를 확인하세요."
            }
            let hint = detail.isEmpty ? "종료 코드 \(process.terminationStatus)" : String(detail.prefix(260))
            return "권한 초기화 일부/전체 실패: \(hint). macOS 시스템 설정에서 직접 해제하세요."
        } catch {
            return "권한 초기화 실행 실패: \(error.localizedDescription). macOS 시스템 설정에서 직접 해제하세요."
        }
    }

    static func eraseLocalPreferencesThenQuit() {
        // 사용자가 별도로 선택한 경우에만 현재 00Favorite 앱의 UserDefaults를 지웁니다.
        // Finder 원본 파일, 변환 결과물, 임의 폴더 및 다른 앱의 설정은 삭제하지 않습니다.
        if isCurrentAppVerified {
            UserDefaults.standard.removePersistentDomain(forName: expectedBundleID)
            // 재설치 시 과거 MyTangerine 설정이 자동으로 다시 유입되지 않도록,
            // 개인정보를 담지 않는 1회성 이관 완료 표시만 남깁니다.
            UserDefaults.standard.set(true, forKey: "favorite_legacy_settings_migrated_hk8")
            UserDefaults.standard.synchronize()
        }
        NSApp.terminate(nil)
    }
}

struct FavoriteSetupCleanupView: View {
    @State private var inputGranted = CGPreflightListenEventAccess()
    @State private var accessibilityGranted = AXIsProcessTrusted()
    @State private var loginState = FavoriteLaunchAtLogin.statusDescription
    @State private var registerAtLogin = FavoriteLaunchAtLogin.isRegistered
    @State private var eraseLocalSettings = false
    @State private var eraseOnExit = false
    @State private var setupMessage = ""
    @State private var cleanupMessages: [String] = []
    @State private var cleaning = false
    @State private var cleanupFinished = false

    private func refreshStatus() {
        inputGranted = CGPreflightListenEventAccess()
        accessibilityGranted = AXIsProcessTrusted()
        loginState = FavoriteLaunchAtLogin.statusDescription
    }

    private func statusLine(_ name: String, ready: Bool, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: ready ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundColor(ready ? .green : .orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.subheadline.bold())
                Text(detail).font(.caption).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 2)
            Text(ready ? "확인" : "확인 필요")
                .font(.caption.bold()).foregroundColor(ready ? .green : .orange)
        }
    }

    private func startInitialSetup() {
        guard FavoriteAppPrivacyMaintenance.isCurrentAppVerified else {
            setupMessage = "실행 중인 앱 식별자를 확인하지 못했습니다. 다른 앱에 대한 설정은 진행하지 않습니다."
            return
        }
        var notes: [String] = []
        if registerAtLogin {
            do {
                try FavoriteLaunchAtLogin.setRegistered(true)
                notes.append("로그인 자동 실행 등록을 요청했습니다.")
            } catch {
                notes.append("로그인 자동 실행 등록 오류: \(error.localizedDescription)")
            }
        } else {
            notes.append("로그인 자동 실행은 선택하지 않아 변경하지 않았습니다.")
        }
        if !CGPreflightListenEventAccess() {
            _ = CGRequestListenEventAccess()
            notes.append("입력 모니터링 승인을 macOS에 요청했습니다.")
        } else {
            notes.append("입력 모니터링은 이미 승인되어 있습니다.")
        }
        if !AXIsProcessTrusted() {
            // macOS는 비동기 승인창을 표시할 수 있습니다. 사용자가 직접 승인해야 합니다.
            FavoriteAppPrivacyMaintenance.requestAccessibility()
            notes.append("손쉬운 사용 승인을 macOS에 요청했습니다.")
        } else {
            notes.append("손쉬운 사용은 이미 승인되어 있습니다.")
        }
        notes.append("Mac에 나타난 시스템 승인창이나 아래 시스템 설정에서 직접 허용한 다음 [상태 다시 확인]을 누르세요.")
        setupMessage = notes.joined(separator: "\n")
        refreshStatus()
    }

    private func startCleanup() {
        guard !cleaning else { return }
        guard FavoriteAppPrivacyMaintenance.isCurrentAppVerified else {
            cleanupMessages = ["실행 중인 앱 식별자가 예상한 00Favorite와 다릅니다. 안전을 위해 정리를 시작하지 않았습니다."]
            return
        }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "00Favorite 삭제 전 정리를 시작할까요?"
        alert.informativeText = """
        로그인 자동 실행 등록을 해제하고, macOS에서 00Favorite(\(FavoriteAppPrivacyMaintenance.expectedBundleID))에 기록된 개인정보 보호 권한의 초기화를 요청합니다.

        다른 앱 권한이나 원본 사진·영상·변환 파일은 삭제하지 않습니다.
        \(eraseLocalSettings ? "추가 선택: 최종 종료 시 00Favorite의 단축키·패턴·폴더 선택 등 앱 설정도 삭제합니다." : "저장된 앱 설정은 유지합니다.")

        시스템 설정에 일부 등록 흔적이 남으면 직접 확인해야 합니다.
        """
        alert.addButton(withTitle: "선택 항목 정리")
        alert.addButton(withTitle: "취소")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        cleanupFinished = false
        cleaning = true
        eraseOnExit = eraseLocalSettings
        cleanupMessages = ["정리 중: 로그인 항목 해제 및 앱 권한 초기화 요청"]
        var loginResult = ""
        do {
            try FavoriteLaunchAtLogin.setRegistered(false)
            loginResult = "로그인 항목: 해제 요청 완료 (\(FavoriteLaunchAtLogin.statusDescription))"
        } catch {
            loginResult = "로그인 항목: 자동 해제 실패 (\(error.localizedDescription)). 시스템 설정에서 직접 확인하세요."
        }
        // tccutil을 별도 작업 큐에서 수행해 설정창과 마우스 입력을 막지 않습니다.
        DispatchQueue.global(qos: .userInitiated).async {
            let privacyResult = FavoriteAppPrivacyMaintenance.resetPrivacyForCurrentApp()
            DispatchQueue.main.async {
                self.cleanupMessages = [
                    loginResult,
                    privacyResult,
                    eraseOnExit
                        ? "앱 저장 설정: [앱 종료하고 마무리]를 누를 때 현재 00Favorite 설정만 삭제합니다."
                        : "앱 저장 설정: 그대로 보존합니다.",
                    "시스템 설정에 남은 항목을 확인하고, 완료 후 앱을 종료한 다음 00Favorite.app을 직접 삭제하세요."
                ]
                self.cleaning = false
                self.cleanupFinished = true
                self.refreshStatus()
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Image(systemName: "checkmark.shield").font(.title2).foregroundColor(.orange)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("00Favorite 설치·삭제 관리").font(.title2.bold())
                        Text("새 버전을 설치할 때와 앱을 지우기 전에 사용하는 관리 도구")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
                GroupBox("1. 새 설치 후 한 번에 설정 시작") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("버튼 한 번으로 현재 권한을 점검하고 필요한 macOS 승인 요청을 시작합니다. 보안 권한을 실제로 켜는 마지막 클릭은 macOS에서 직접 승인해야 합니다.")
                            .font(.caption).foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Toggle("Mac 로그인 시 자동 실행도 함께 등록", isOn: $registerAtLogin)
                        Button {
                            startInitialSetup()
                        } label: {
                            Label("새 설치 초기 설정 시작", systemImage: "sparkles")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!FavoriteAppPrivacyMaintenance.isCurrentAppVerified)
                        if !setupMessage.isEmpty {
                            Text(setupMessage)
                                .font(.caption).textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }.padding(8)
                }

                GroupBox("2. 현재 macOS 권한 확인") {
                    VStack(alignment: .leading, spacing: 12) {
                        statusLine("입력 모니터링", ready: inputGranted,
                                   detail: "Finder 파일 드래그 중 전역 휠 감시에 필요합니다.")
                        statusLine("손쉬운 사용", ready: accessibilityGranted,
                                   detail: "다른 앱 창의 이동·크기 조절에 필요합니다.")
                        statusLine("로그인 자동 실행", ready: FavoriteLaunchAtLogin.status == .enabled,
                                   detail: loginState)
                        HStack(spacing: 8) {
                            Button("입력 모니터링 설정") {
                                FolderAccessPreferences.shared.openInputMonitoringSettings()
                            }
                            Button("손쉬운 사용 설정") {
                                FolderAccessPreferences.shared.openAccessibilitySettings()
                            }
                            Button("로그인 항목 설정") {
                                FavoriteLaunchAtLogin.openSystemSettings()
                            }
                        }
                        HStack(spacing: 8) {
                            Button("파일 및 폴더 설정") {
                                FolderAccessPreferences.shared.openFilesAndFoldersSettings()
                            }
                            Button("전체 디스크 접근 설정") {
                                FolderAccessPreferences.shared.openFullDiskAccessSettings()
                            }
                        }
                        Text("파일 및 폴더 권한은 실제 파일 선택·처리 시 macOS에서 별도로 요청할 수 있습니다. 전체 디스크 접근은 필수 기본 권한이 아니므로 자동으로 요청하지 않습니다.")
                            .font(.caption2).foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("상태 다시 확인") { refreshStatus() }
                            .buttonStyle(.bordered)
                        Text("권한 변경 직후에는 상태에 반영되지 않을 수 있습니다. 앱을 완전히 종료했다가 다시 실행하면 정확하게 확인할 수 있습니다.")
                            .font(.caption2).foregroundColor(.secondary)
                    }.padding(8)
                }

                GroupBox("3. 앱을 삭제하기 전 한 번에 정리") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("로그인 항목 등록 해제 + 현재 00Favorite만 대상으로 macOS 개인정보 보호 권한 초기화를 요청합니다. 어떤 Mac에서는 보안 정책 때문에 사용자가 시스템 설정에서 직접 해제해야 합니다.")
                            .font(.caption).foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Toggle("단축키·이름 양식·선택한 폴더 등 저장 설정도 삭제", isOn: $eraseLocalSettings)
                            .disabled(cleaning || cleanupFinished)
                        Text("기본값은 OFF입니다. 다른 버전으로 교체할 때 기존 개인 설정을 유지하려면 체크하지 마세요.")
                            .font(.caption2).foregroundColor(.secondary)
                        Button {
                            startCleanup()
                        } label: {
                            Label(cleaning ? "정리 작업 실행 중" : "삭제 전 정리 시작", systemImage: "trash.slash")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .disabled(cleaning || cleanupFinished || !FavoriteAppPrivacyMaintenance.isCurrentAppVerified)
                        if !cleanupMessages.isEmpty {
                            VStack(alignment: .leading, spacing: 7) {
                                ForEach(cleanupMessages, id: \.self) { line in
                                    Text("• \(line)")
                                        .font(.caption)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                        if cleanupFinished {
                            Button("앱 종료하고 마무리") {
                                if eraseOnExit {
                                    FavoriteAppPrivacyMaintenance.eraseLocalPreferencesThenQuit()
                                } else {
                                    NSApp.terminate(nil)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            Text("앱 종료 후 Finder에서 00Favorite.app을 직접 삭제하세요. 권한 목록에 남은 00Favorite은 위 시스템 설정 버튼으로 확인할 수 있습니다.")
                                .font(.caption2).foregroundColor(.secondary)
                        }
                    }.padding(8)
                }
                Text("정리 대상 식별자: \(Bundle.main.bundleIdentifier ?? "식별자 없음") · 다른 앱과 사용자 파일은 변경하지 않습니다.")
                    .font(.caption2).foregroundColor(.secondary)
                    .textSelection(.enabled)
            }.padding(20)
        }
        .frame(minWidth: 650, minHeight: 570)
        .onAppear { refreshStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshStatus()
        }
    }
}

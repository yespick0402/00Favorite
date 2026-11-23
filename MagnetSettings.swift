// MAGNET S3-B – 창 정렬의 한국어 설정 화면.
// 독립 SwiftUI 화면입니다. Finder 휠 이벤트 탭과 잠자기 방지에는 연결하지 않습니다.
import SwiftUI
import AppKit

final class FavoriteMagnetPreferences: ObservableObject {
    static let shared = FavoriteMagnetPreferences()
    @Published private(set) var revision = 0
    private let menuKey = "favorite_magnet_settings_menu_visibility_v1"
    private let edgeKey = "favorite_magnet_settings_drag_areas_v1"
    private let frameKey = "favorite_magnet_settings_frames_v1"
    private let shortcutKey = "favorite_magnet_settings_shortcut_enabled_v1"

    struct NormalizedFrame: Codable {
        var x: Double
        var top: Double
        var width: Double
        var height: Double
    }
    enum Edge: Int, CaseIterable {
        case upperLeft = 0, upper = 1, upperRight = 2
        case left = 3, right = 5
        case lowerLeft = 6, lower = 7, lowerRight = 8
        var title: String {
            switch self {
            case .upperLeft: return "좌상단"
            case .upper: return "위"
            case .upperRight: return "우상단"
            case .left: return "왼쪽"
            case .right: return "오른쪽"
            case .lowerLeft: return "좌하단"
            case .lower: return "아래"
            case .lowerRight: return "우하단"
            }
        }
    }

    private var hiddenMenu: Set<Int> = []
    private var disabledShortcuts: Set<Int> = []
    private var dragZones: [String: Int] = [:]
    private var customFrames: [String: NormalizedFrame] = [:]

    private init() {
        hiddenMenu = Set(UserDefaults.standard.array(forKey: menuKey) as? [Int] ?? [])
        disabledShortcuts = Set(UserDefaults.standard.array(forKey: shortcutKey) as? [Int] ?? [])
        dragZones = UserDefaults.standard.dictionary(forKey: edgeKey) as? [String: Int] ?? [:]
        if let data = UserDefaults.standard.data(forKey: frameKey),
           let decoded = try? PropertyListDecoder().decode([String: NormalizedFrame].self, from: data) {
            customFrames = decoded
        }
    }

    func isVisibleInMenu(_ layout: FavoriteWindowSnap.Layout) -> Bool { !hiddenMenu.contains(layout.rawValue) }
    func setVisibleInMenu(_ enabled: Bool, for layout: FavoriteWindowSnap.Layout) {
        if enabled { hiddenMenu.remove(layout.rawValue) } else { hiddenMenu.insert(layout.rawValue) }
        UserDefaults.standard.set(Array(hiddenMenu), forKey: menuKey)
        notify()
    }
    func isShortcutEnabled(_ layout: FavoriteWindowSnap.Layout) -> Bool { !disabledShortcuts.contains(layout.rawValue) }
    func setShortcutEnabled(_ enabled: Bool, for layout: FavoriteWindowSnap.Layout) {
        if enabled { disabledShortcuts.remove(layout.rawValue) } else { disabledShortcuts.insert(layout.rawValue) }
        UserDefaults.standard.set(Array(disabledShortcuts), forKey: shortcutKey)
        FavoriteWindowSnapHotKeys.shared.refresh()
        notify()
    }

    private func defaultEdgeLayout(_ edge: Edge) -> FavoriteWindowSnap.Layout {
        switch edge {
        case .upperLeft: return .topLeft
        case .upper: return .maximize
        case .upperRight: return .topRight
        case .left: return .leftHalf
        case .right: return .rightHalf
        case .lowerLeft: return .bottomLeft
        case .lower: return .bottomHalf
        case .lowerRight: return .bottomRight
        }
    }
    func layoutForEdge(_ edge: Edge) -> FavoriteWindowSnap.Layout? {
        let id = dragZones[String(edge.rawValue)] ?? defaultEdgeLayout(edge).rawValue
        return FavoriteWindowSnap.Layout(rawValue: id)
    }
    func toggleEdge(_ edge: Edge, for layout: FavoriteWindowSnap.Layout) {
        // 원래 위치 복원은 저장된 이전 창 위치를 사용하므로 드래그 활성 영역에 할당하지 않습니다.
        guard layout != .restore && layout != .nextDisplay && layout != .previousDisplay else { return }
        let old = layoutForEdge(edge)
        dragZones[String(edge.rawValue)] = old == layout ? 0 : layout.rawValue
        UserDefaults.standard.set(dragZones, forKey: edgeKey)
        notify()
    }

    func frame(for layout: FavoriteWindowSnap.Layout) -> NormalizedFrame {
        if let custom = customFrames[String(layout.rawValue)] { return custom }
        switch layout {
        case .leftHalf: return .init(x: 0, top: 0, width: 0.5, height: 1)
        case .rightHalf: return .init(x: 0.5, top: 0, width: 0.5, height: 1)
        case .topHalf: return .init(x: 0, top: 0, width: 1, height: 0.5)
        case .bottomHalf: return .init(x: 0, top: 0.5, width: 1, height: 0.5)
        case .topLeft: return .init(x: 0, top: 0, width: 0.5, height: 0.5)
        case .topRight: return .init(x: 0.5, top: 0, width: 0.5, height: 0.5)
        case .bottomLeft: return .init(x: 0, top: 0.5, width: 0.5, height: 0.5)
        case .bottomRight: return .init(x: 0.5, top: 0.5, width: 0.5, height: 0.5)
        case .leftThird: return .init(x: 0, top: 0, width: 1.0 / 3.0, height: 1)
        case .middleThird: return .init(x: 1.0 / 3.0, top: 0, width: 1.0 / 3.0, height: 1)
        case .rightThird: return .init(x: 2.0 / 3.0, top: 0, width: 1.0 / 3.0, height: 1)
        case .leftTwoThirds: return .init(x: 0, top: 0, width: 2.0 / 3.0, height: 1)
        case .centerTwoThirds: return .init(x: 1.0 / 6.0, top: 0, width: 2.0 / 3.0, height: 1)
        case .rightTwoThirds: return .init(x: 1.0 / 3.0, top: 0, width: 2.0 / 3.0, height: 1)
        case .maximize: return .init(x: 0, top: 0, width: 1, height: 1)
        case .center, .restore: return .init(x: 0.2, top: 0.2, width: 0.6, height: 0.6)
        case .nextDisplay, .previousDisplay: return .init(x: 0, top: 0, width: 1, height: 1)
        }
    }

    func customFrame(_ layout: FavoriteWindowSnap.Layout, visible v: CGRect) -> CGRect? {
        guard layout != .restore && layout != .nextDisplay && layout != .previousDisplay,
              let rect = customFrames[String(layout.rawValue)] else { return nil }
        return CGRect(x: v.minX + v.width * rect.x,
                      y: v.maxY - v.height * (rect.top + rect.height),
                      width: v.width * rect.width, height: v.height * rect.height)
    }
    func saveFrame(_ frame: NormalizedFrame, for layout: FavoriteWindowSnap.Layout) {
        guard layout != .restore && layout != .nextDisplay && layout != .previousDisplay else { return }
        let w = max(0.05, min(1, frame.width)), h = max(0.05, min(1, frame.height))
        customFrames[String(layout.rawValue)] = .init(
            x: max(0, min(1 - w, frame.x)), top: max(0, min(1 - h, frame.top)),
            width: w, height: h)
        persistFrames()
        notify()
    }
    func resetFrame(_ layout: FavoriteWindowSnap.Layout) {
        customFrames.removeValue(forKey: String(layout.rawValue))
        persistFrames()
        notify()
    }
    private func persistFrames() {
        if let data = try? PropertyListEncoder().encode(customFrames) {
            UserDefaults.standard.set(data, forKey: frameKey)
        }
    }
    func notify() {
        revision &+= 1
        (NSApp.delegate as? AppDelegate)?.updateStatusBarMenu()
    }
}

private struct FavoriteMagnetGrid: View {
    @ObservedObject var prefs = FavoriteMagnetPreferences.shared
    let layout: FavoriteWindowSnap.Layout
    @State private var anchorColumn: Int?
    @State private var anchorRow: Int?
    @State private var active: FavoriteMagnetPreferences.NormalizedFrame?
    private let columns = 18
    private let rows = 12

    var body: some View {
        GeometryReader { geometry in
            let rect = active ?? prefs.frame(for: layout)
            VStack(spacing: 2) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: 2) {
                        ForEach(0..<columns, id: \.self) { col in
                            let cx = (Double(col) + 0.5) / Double(columns)
                            let cy = (Double(row) + 0.5) / Double(rows)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(cx >= rect.x && cx < rect.x + rect.width &&
                                      cy >= rect.top && cy < rect.top + rect.height
                                      ? Color.accentColor : Color.gray.opacity(0.24))
                        }
                    }
                }
            }
            .padding(8)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard layout != .restore && layout != .nextDisplay && layout != .previousDisplay else { return }
                    let col = min(columns - 1, max(0, Int((value.location.x - 8) /
                                                         max(1, geometry.size.width - 16) * CGFloat(columns))))
                    let row = min(rows - 1, max(0, Int((value.location.y - 8) /
                                                       max(1, geometry.size.height - 16) * CGFloat(rows))))
                    if anchorColumn == nil { anchorColumn = col; anchorRow = row }
                    let left = min(anchorColumn ?? col, col)
                    let top = min(anchorRow ?? row, row)
                    let right = max(anchorColumn ?? col, col)
                    let bottom = max(anchorRow ?? row, row)
                    active = .init(x: Double(left) / Double(columns),
                                   top: Double(top) / Double(rows),
                                   width: Double(right - left + 1) / Double(columns),
                                   height: Double(bottom - top + 1) / Double(rows))
                }
                .onEnded { _ in
                    if let saved = active { prefs.saveFrame(saved, for: layout) }
                    anchorColumn = nil
                    anchorRow = nil
                    active = nil
                })
        }
        .frame(height: 215)
        .onChange(of: layout.rawValue) { _ in
            active = nil; anchorColumn = nil; anchorRow = nil
        }
        .accessibilityLabel("선택된 창 배치 영역 미리보기")
    }
}

struct FavoriteMagnetSettingsView: View {
    @ObservedObject private var prefs = FavoriteMagnetPreferences.shared
    @State private var selected: FavoriteWindowSnap.Layout = .leftHalf

    private var groups: [(String, [(FavoriteWindowSnap.Layout, String)])] {
        [
            ("2분할", [(.leftHalf, "왼쪽 절반"), (.rightHalf, "오른쪽 절반"),
                        (.topHalf, "위쪽 절반"), (.bottomHalf, "아래쪽 절반")]),
            ("4분할", [(.topLeft, "왼쪽 위"), (.topRight, "오른쪽 위"),
                        (.bottomLeft, "왼쪽 아래"), (.bottomRight, "오른쪽 아래")]),
            ("3분할", [(.leftThird, "왼쪽 1/3"), (.middleThird, "가운데 1/3"),
                        (.rightThird, "오른쪽 1/3")]),
            ("2/3 분할", [(.leftTwoThirds, "왼쪽 2/3"), (.centerTwoThirds, "가운데 2/3"),
                           (.rightTwoThirds, "오른쪽 2/3")]),
            ("디스플레이 이동", [(.nextDisplay, "다음 디스플레이"), (.previousDisplay, "이전 디스플레이")]),
            ("기타", [(.maximize, "최대 크기"), (.center, "가운데 배치"),
                        (.restore, "원래 위치로 복원")])
        ]
    }

    private var selectedName: String {
        groups.flatMap { $0.1 }.first(where: { $0.0 == selected })?.1 ?? "창 정렬"
    }

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("창 정렬 명령").font(.headline).padding(.bottom, 6)
                    ForEach(groups.indices, id: \.self) { sectionIndex in
                        let group = groups[sectionIndex]
                        Text(group.0).font(.caption.bold()).foregroundColor(.secondary)
                            .padding(.top, 10)
                        ForEach(group.1.indices, id: \.self) { entryIndex in
                            let entry = group.1[entryIndex]
                            Button {
                                selected = entry.0
                            } label: {
                                HStack {
                                    Image(systemName: selected == entry.0 ? "rectangle.inset.filled" : "rectangle")
                                        .frame(width: 20)
                                    Text(entry.1).font(.subheadline)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 10).padding(.vertical, 7)
                                .background(selected == entry.0 ? Color.accentColor.opacity(0.18) : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 7))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }.padding(12)
            }
            .frame(width: 205)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text(selectedName).font(.title2.bold())
                        Spacer()
                        if selected == .maximize {
                            Text("macOS 전체 화면 전환이 아닌 창 최대화")
                                .font(.caption2).foregroundColor(.secondary)
                        }
                    }
                    GroupBox("창 크기와 위치 미리보기") {
                        VStack(alignment: .leading, spacing: 6) {
                            FavoriteMagnetGrid(layout: selected)
                            Text(selected == .restore
                                 ? "복원은 정렬 전 저장된 크기와 위치를 사용합니다."
                                 : (selected == .nextDisplay || selected == .previousDisplay)
                                   ? "디스플레이 이동은 창의 현재 크기·상대 위치를 최대한 유지합니다. 격자 편집은 적용하지 않습니다."
                                   : "격자에서 드래그하면 이 명령의 창 크기와 위치가 변경·저장됩니다.")
                                .font(.caption).foregroundColor(.secondary)
                            HStack {
                                Spacer()
                                Button("기본 크기·위치로 복원") { prefs.resetFrame(selected) }
                                    .disabled(selected == .restore || selected == .nextDisplay || selected == .previousDisplay)
                            }
                        }.padding(8)
                    }
                    GroupBox("키보드 단축키") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                Text(FavoriteWindowSnapHotKeys.shared.displayLabel(for: selected))
                                    .font(.system(size: 17, weight: .semibold, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Button("입력하기") {
                                    FavoriteWindowSnapHotKeys.shared.recordInSettings(selected)
                                    prefs.notify()
                                }
                                Button("해제") {
                                    FavoriteWindowSnapHotKeys.shared.clearInSettings(selected)
                                    prefs.notify()
                                }
                            }
                            Toggle("단축키 사용", isOn: Binding(
                                get: { prefs.isShortcutEnabled(selected) },
                                set: { prefs.setShortcutEnabled($0, for: selected) }
                            ))
                            HStack {
                                Button("첨부 이미지의 기본 단축키 복원") {
                                    FavoriteWindowSnapHotKeys.shared.restoreMagnetDefaults()
                                    prefs.notify()
                                }
                                Spacer()
                            }
                            Text("Control·Option·Command·Shift 중 2개 이상과 문자·방향키·Return(Enter)·Delete를 조합할 수 있습니다.")
                                .font(.caption).foregroundColor(.secondary)
                        }.padding(8)
                    }
                    GroupBox("창 드래그 활성 영역") {
                        VStack(alignment: .leading, spacing: 9) {
                            Text("선택한 정렬 기능이 작동할 화면 가장자리를 지정하세요. 같은 칸을 다시 누르면 해제됩니다.")
                                .font(.caption).foregroundColor(.secondary)
                            VStack(spacing: 4) {
                                ForEach(0..<3, id: \.self) { row in
                                    HStack(spacing: 4) {
                                        ForEach(0..<3, id: \.self) { col in
                                            if let edge = FavoriteMagnetPreferences.Edge(rawValue: row * 3 + col) {
                                                let current = prefs.layoutForEdge(edge)
                                                Button {
                                                    prefs.toggleEdge(edge, for: selected)
                                                } label: {
                                                    VStack(spacing: 3) {
                                                        Image(systemName: current == selected ? "checkmark.circle.fill" : "circle")
                                                        Text(edge.title).font(.caption2)
                                                    }
                                                    .frame(maxWidth: .infinity, minHeight: 43)
                                                    .background(current == selected ? Color.accentColor.opacity(0.22) : Color.gray.opacity(0.10),
                                                                in: RoundedRectangle(cornerRadius: 6))
                                                }.buttonStyle(.plain)
                                                 .disabled(selected == .restore || selected == .nextDisplay || selected == .previousDisplay)
                                            } else {
                                                Text("화면").font(.caption).foregroundColor(.secondary)
                                                    .frame(maxWidth: .infinity, minHeight: 43)
                                            }
                                        }
                                    }
                                }
                            }
                            Text("다른 명령에 배정된 칸을 누르면 해당 명령 대신 현재 명령이 적용됩니다.")
                                .font(.caption2).foregroundColor(.secondary)
                        }.padding(8)
                    }
                    GroupBox("표시 설정") {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("메뉴 막대에서 이 명령 표시", isOn: Binding(
                                get: { prefs.isVisibleInMenu(selected) },
                                set: { prefs.setVisibleInMenu($0, for: selected) }
                            ))
                            Toggle("초록색 창 버튼 메뉴에 표시 (추후 지원)", isOn: .constant(false))
                                .disabled(true)
                            Text("macOS 시스템의 초록색 버튼 메뉴를 직접 수정하는 기능은 지원되지 않습니다. 안정적인 별도 메뉴 방식은 후속 단계에서 검토합니다.")
                                .font(.caption2).foregroundColor(.secondary)
                        }.padding(8)
                    }
                    HStack {
                        Image(systemName: "display.2")
                        Text("연결된 디스플레이: \(NSScreen.screens.count)대")
                    }
                    .font(.caption2).foregroundColor(.secondary)
                    Text("⌃⌥→: 현재 화면 오른쪽 절반 → 한 번 더 누르면 오른쪽 모니터 왼쪽 절반.")
                        .font(.caption2).foregroundColor(.secondary)
                    Text("⌃⌥←: 현재 화면 왼쪽 절반 → 한 번 더 누르면 왼쪽 모니터 오른쪽 절반.")
                        .font(.caption2).foregroundColor(.secondary)
                    Text("화면이 끝나는 곳에서는 다른 화면으로 순환하지 않습니다. 별도 다음·이전 디스플레이 명령도 필요하다면 단축키를 직접 지정할 수 있습니다.")
                        .font(.caption2).foregroundColor(.secondary)
                }
                .padding(16)
            }
            .frame(maxWidth: .infinity)
        }
        .onAppear { prefs.notify() }
    }
}

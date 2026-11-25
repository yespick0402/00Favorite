import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

// ACTIONS RESIZE-01: 원본은 읽기 전용, 같은 폴더에 다른 이름의 이미지 파일만 생성.
enum FavoriteResizeBasis: String, CaseIterable, Identifiable {
    case width = "가로 기준"
    case height = "세로 기준"
    case longEdge = "긴 변 기준"
    case percent = "비율 (%)"
    var id: String { rawValue }
}

enum FavoriteResizeFormat: String, CaseIterable, Identifiable {
    case original = "원본 형식 유지"
    case jpeg = "JPG"
    case png = "PNG"
    case heic = "HEIC"
    case tiff = "TIFF"
    var id: String { rawValue }
}

struct FavoriteResizeOptions {
    let basis: FavoriteResizeBasis
    let requestedValue: Int
    let allowUpscale: Bool
    let outputFormat: FavoriteResizeFormat
    let jpegQuality: Double
    let keepMetadata: Bool
    let removeGPS: Bool
}

final class FavoriteResizeCancellation {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

struct FavoriteResizeResult {
    let outputs: [URL]
    let errors: [String]
    let cancelled: Bool
}

struct FavoriteImageResizeView: View {
    @State private var files: [URL]
    @State private var basis: FavoriteResizeBasis
    @State private var valueText = "1920"
    @State private var allowUpscale = false
    @State private var format: FavoriteResizeFormat = .original
    @State private var quality = 0.92
    @State private var keepMetadata = true
    @State private var removeGPS = false
    @State private var showAdvanced = false
    @State private var running = false
    @State private var progress = 0
    @State private var currentFile = ""
    @State private var cancellation: FavoriteResizeCancellation?
    @State private var result: FavoriteResizeResult?

    init(files: [URL]) {
        var seen = Set<String>()
        let selected = files.filter {
            FavoriteImageResizeProcessor.isCandidate($0) &&
            seen.insert($0.standardizedFileURL.path).inserted
        }
        _files = State(initialValue: selected)
        _basis = State(initialValue: selected.count > 1 ? .longEdge : .width)
    }

    private var inputSize: FavoriteImageResizeProcessor.PixelSize? {
        files.first.flatMap { FavoriteImageResizeProcessor.inspect($0)?.size }
    }

    private var validValue: Int? {
        guard let value = Int(valueText.trimmingCharacters(in: .whitespacesAndNewlines)),
              value > 0 else { return nil }
        return basis == .percent ? ((1...400).contains(value) ? value : nil)
                                 : ((1...16000).contains(value) ? value : nil)
    }

    private var targetSize: FavoriteImageResizeProcessor.PixelSize? {
        guard let original = inputSize, let value = validValue else { return nil }
        return FavoriteImageResizeProcessor.scaledSize(original, basis: basis,
                                                        requested: value, allowUpscale: allowUpscale)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 25)).foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text("이미지 크기 변경").font(.title2.bold())
                    Text("픽셀 크기 조정 · 비율 유지 · 원본 파일 보존")
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Text("\(files.count)장 선택").font(.subheadline.bold()).monospacedDigit()
            }
            .padding(.horizontal, 22).padding(.vertical, 16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    GroupBox("1. 이미지 크기") {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("조정 기준", selection: $basis) {
                                ForEach(FavoriteResizeBasis.allCases) { item in
                                    Text(item.rawValue).tag(item)
                                }
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: basis) { newValue in
                                valueText = newValue == .percent ? "50" : "1920"
                            }
                            HStack(spacing: 12) {
                                Text(basis == .percent ? "변경 비율" : "목표 픽셀")
                                TextField("1920", text: $valueText)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 130)
                                Text(basis == .percent ? "%" : "px")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Toggle("작은 이미지 확대 허용", isOn: $allowUpscale)
                            }
                            Text("가로와 세로의 비율을 항상 유지합니다. 작은 이미지는 '확대 허용'을 켜지 않는 한 확대하지 않습니다.")
                                .font(.caption).foregroundColor(.secondary)
                            if validValue == nil {
                                Text(basis == .percent ? "비율은 1~400%로 입력하세요." : "픽셀은 1~16,000으로 입력하세요.")
                                    .font(.caption).foregroundColor(.red)
                            }
                        }.padding(8)
                    }

                    GroupBox("2. 출력 크기 미리보기") {
                        VStack(alignment: .leading, spacing: 9) {
                            if let original = inputSize, let target = targetSize {
                                HStack(spacing: 16) {
                                    sizeCard("원본 첫 이미지", width: original.width, height: original.height)
                                    Image(systemName: "arrow.right").foregroundColor(.secondary)
                                    sizeCard("변경 후", width: target.width, height: target.height)
                                }
                                Text("여러 장은 각 이미지의 원본 비율에 맞춰 각각 크기를 계산합니다.")
                                    .font(.caption).foregroundColor(.secondary)
                            } else {
                                Text("파일을 읽을 수 없거나 목표 크기가 올바르지 않습니다.")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                    }

                    GroupBox("3. 저장") {
                        VStack(alignment: .leading, spacing: 10) {
                            Picker("파일 형식", selection: $format) {
                                ForEach(FavoriteResizeFormat.allCases) { f in
                                    Text(f.rawValue).tag(f)
                                }
                            }
                            .frame(maxWidth: 360)
                            Text("원본과 같은 폴더에 ‘파일명_1920x1280.jpg’처럼 새 파일을 생성합니다. 기존 파일과 이름이 겹치면 번호를 붙입니다.")
                                .font(.caption).foregroundColor(.secondary)
                            Text("WebP·AVIF·GIF 입력은 원본 형식 유지 모드에서 PNG로 저장합니다. 움직이는 GIF와 다중 프레임 이미지는 건너뜁니다.")
                                .font(.caption2).foregroundColor(.secondary)
                        }.padding(8)
                    }

                    DisclosureGroup("고급 설정", isExpanded: $showAdvanced) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("JPG·HEIC 저장 품질")
                                Slider(value: $quality, in: 0.65...1.0, step: 0.01)
                                Text("\(Int((quality * 100).rounded()))%")
                                    .monospacedDigit().frame(width: 45, alignment: .trailing)
                            }
                            Toggle("촬영일시 등 가능한 메타데이터 유지", isOn: $keepMetadata)
                            Toggle("GPS 위치정보 제거", isOn: $removeGPS)
                                .disabled(!keepMetadata)
                            Text("EXIF 방향은 출력 이미지에 적용하고 회전 태그를 초기화합니다. ICC 색상 프로파일은 가능한 범위에서 유지합니다. RAW 파일과 애니메이션은 이번 버전의 대상이 아닙니다.")
                                .font(.caption2).foregroundColor(.secondary)
                        }.padding(.top, 8)
                    }
                    if running {
                        VStack(alignment: .leading, spacing: 7) {
                            ProgressView(value: Double(progress), total: Double(max(files.count, 1)))
                            Text("\(progress)/\(files.count)장 처리 · \(currentFile)")
                                .font(.caption).foregroundColor(.secondary).lineLimit(1)
                        }
                    }
                    if let result = result {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(result.cancelled ? "중단됨 · 처리된 파일은 보존되었습니다." : "작업 완료")
                                .font(.subheadline.bold())
                            Text("새 파일 \(result.outputs.count)개 · 건너뛰거나 실패한 파일 \(result.errors.count)개")
                                .font(.caption)
                            ForEach(Array(result.errors.prefix(10)), id: \.self) { error in
                                Text("• \(error)").font(.caption).foregroundColor(.secondary)
                                    .textSelection(.enabled)
                            }
                            if result.errors.count > 10 {
                                Text("그 외 \(result.errors.count - 10)개 오류").font(.caption)
                            }
                            if !result.outputs.isEmpty {
                                Button("결과 파일 Finder에서 보기") {
                                    NSWorkspace.shared.activateFileViewerSelecting(result.outputs)
                                }
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))
                    }
                }
                .padding(20)
            }
            Divider()
            HStack(spacing: 12) {
                Button("닫기") {
                    if running { cancellation?.cancel() }
                    else { NSApp.keyWindow?.close() }
                }
                Spacer()
                if running {
                    Button("처리 중단") { cancellation?.cancel() }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("크기 변경 시작") { start() }
                        .buttonStyle(.borderedProminent).tint(.orange)
                        .disabled(files.isEmpty || validValue == nil || inputSize == nil)
                }
            }
            .padding(16)
        }
        .frame(minWidth: 690, minHeight: 610)
    }

    private func sizeCard(_ title: String, width: Int, height: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundColor(.secondary)
            Text("\(width.formatted()) × \(height.formatted()) px")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func start() {
        guard !running, let value = validValue, !files.isEmpty else { return }
        let options = FavoriteResizeOptions(basis: basis, requestedValue: value, allowUpscale: allowUpscale,
                                            outputFormat: format, jpegQuality: quality,
                                            keepMetadata: keepMetadata, removeGPS: removeGPS)
        let control = FavoriteResizeCancellation()
        cancellation = control
        result = nil
        progress = 0
        currentFile = ""
        running = true
        FavoriteImageResizeProcessor.start(files: files, options: options, control: control,
            progress: { finished, filename in
                progress = finished
                currentFile = filename
            },
            completion: { finished in
                result = finished
                running = false
                cancellation = nil
            })
    }
}

enum FavoriteImageResizeProcessor {
    struct PixelSize {
        let width: Int
        let height: Int
    }

    private struct OutputType {
        let ext: String
        let uti: String
        let lossy: Bool
        let whiteBackground: Bool
    }

    private static let inputExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "hif", "tif", "tiff", "bmp",
        "webp", "avif", "gif"
    ]
    private static let maxPixels = 60_000_000

    static func isCandidate(_ url: URL) -> Bool {
        inputExtensions.contains(url.pathExtension.lowercased()) &&
        !url.hasDirectoryPath && FileManager.default.fileExists(atPath: url.path)
    }

    static func inspect(_ url: URL) -> (size: PixelSize, pages: Int)? {
        guard isCandidate(url),
              let source = CGImageSourceCreateWithURL(url as CFURL,
                  [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let w = props[kCGImagePropertyPixelWidth as String] as? Int,
              let h = props[kCGImagePropertyPixelHeight as String] as? Int,
              w > 0, h > 0 else { return nil }
        let orientation = (props[kCGImagePropertyOrientation as String] as? Int) ?? 1
        let rotated = [5, 6, 7, 8].contains(orientation)
        return (PixelSize(width: rotated ? h : w, height: rotated ? w : h),
                CGImageSourceGetCount(source))
    }

    static func scaledSize(_ original: PixelSize, basis: FavoriteResizeBasis,
                           requested: Int, allowUpscale: Bool) -> PixelSize? {
        guard original.width > 0, original.height > 0, requested > 0 else { return nil }
        let multiplier: Double
        switch basis {
        case .width: multiplier = Double(requested) / Double(original.width)
        case .height: multiplier = Double(requested) / Double(original.height)
        case .longEdge: multiplier = Double(requested) / Double(max(original.width, original.height))
        case .percent: multiplier = Double(requested) / 100.0
        }
        let factor = allowUpscale ? multiplier : min(multiplier, 1.0)
        guard factor.isFinite, factor > 0 else { return nil }
        let w = max(1, Int((Double(original.width) * factor).rounded()))
        let h = max(1, Int((Double(original.height) * factor).rounded()))
        guard w <= 16000, h <= 16000,
              Int64(w) * Int64(h) <= Int64(maxPixels) else { return nil }
        return PixelSize(width: w, height: h)
    }

    private static func outputType(for input: URL, selection: FavoriteResizeFormat) -> OutputType {
        let kind = selection == .original ? input.pathExtension.lowercased() : selection.rawValue.lowercased()
        switch kind {
        case "jpg", "jpeg":
            return OutputType(ext: kind, uti: UTType.jpeg.identifier, lossy: true, whiteBackground: true)
        case "heic", "heif", "hif":
            return OutputType(ext: "heic", uti: UTType.heic.identifier, lossy: true, whiteBackground: false)
        case "tif", "tiff":
            return OutputType(ext: kind, uti: UTType.tiff.identifier, lossy: false, whiteBackground: false)
        case "bmp":
            return OutputType(ext: "bmp", uti: UTType.bmp.identifier, lossy: false, whiteBackground: true)
        default:
            return OutputType(ext: "png", uti: UTType.png.identifier, lossy: false, whiteBackground: false)
        }
    }

    static func start(files: [URL], options: FavoriteResizeOptions,
                      control: FavoriteResizeCancellation,
                      progress: @escaping (Int, String) -> Void,
                      completion: @escaping (FavoriteResizeResult) -> Void) {
        let jobID = JobProgressManager.shared.startJob(title: "이미지 크기 변경 (\(files.count)장)")
        DispatchQueue.global(qos: .userInitiated).async {
            var outputs: [URL] = []
            var errors: [String] = []
            var completed = 0
            for file in files {
                if control.isCancelled { break }
                let response = autoreleasepool {
                    resizeOne(file, options: options, cancelled: control)
                }
                if let saved = response.output { outputs.append(saved) }
                if let error = response.error { errors.append("\(file.lastPathComponent): \(error)") }
                completed += 1
                let n = completed
                DispatchQueue.main.async {
                    JobProgressManager.shared.updateJob(id: jobID,
                        progress: Double(n) / Double(max(files.count, 1)))
                    progress(n, file.lastPathComponent)
                }
            }
            let summary = FavoriteResizeResult(outputs: outputs, errors: errors,
                                               cancelled: control.isCancelled)
            DispatchQueue.main.async {
                JobProgressManager.shared.finishJob(id: jobID)
                completion(summary)
            }
        }
    }

    private static func resizeOne(_ file: URL, options: FavoriteResizeOptions,
                                  cancelled: FavoriteResizeCancellation) -> (output: URL?, error: String?) {
        let noCache: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(file as CFURL, noCache as CFDictionary),
              CGImageSourceGetCount(source) == 1 else {
            return (nil, "파일을 읽을 수 없거나 다중 프레임 이미지입니다.")
        }
        guard let info = inspect(file),
              let target = scaledSize(info.size, basis: options.basis,
                                      requested: options.requestedValue,
                                      allowUpscale: options.allowUpscale) else {
            return (nil, "이미지 크기가 잘못되었거나 안전 크기 제한(6천만 픽셀)을 초과했습니다.")
        }
        if cancelled.isCancelled { return (nil, nil) }
        let thumbnailOpts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(target.width, target.height),
            kCGImageSourceShouldCacheImmediately: false
        ]
        // 전체 원본 디코딩 fallback을 금지합니다. 초대형 카메라 사진을 무심코
        // 풀사이즈로 메모리에 올리는 대신, 다운샘플링 실패를 파일별로 보고합니다.
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOpts as CFDictionary) else {
            return (nil, "다운샘플링할 수 없는 형식입니다. PNG/JPG로 변환 후 다시 시도해 주세요.")
        }
        if cancelled.isCancelled { return (nil, nil) }
        let format = outputType(for: file, selection: options.outputFormat)
        let sourceColor = image.colorSpace
        let color = (sourceColor?.model == .rgb ? sourceColor : nil)
            ?? CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: target.width, height: target.height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: color, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return (nil, "출력 이미지를 위한 메모리를 확보하지 못했습니다.")
        }
        let canvas = CGRect(x: 0, y: 0, width: target.width, height: target.height)
        if format.whiteBackground {
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(canvas)
        } else {
            context.clear(canvas)
        }
        context.interpolationQuality = .high
        context.draw(image, in: canvas)
        guard let rendered = context.makeImage() else { return (nil, "크기 조정에 실패했습니다.") }
        if cancelled.isCancelled { return (nil, nil) }

        let dest = FileProcessor.uniqueOutputURL(for: file, newExt: format.ext,
                                                  suffix: "_\(target.width)x\(target.height)")
        let temp = dest.deletingLastPathComponent().appendingPathComponent(
            ".00Favorite-resize-\(UUID().uuidString).\(format.ext)")
        defer { try? FileManager.default.removeItem(at: temp) }
        guard let writer = CGImageDestinationCreateWithURL(temp as CFURL, format.uti as CFString, 1, nil) else {
            return (nil, "선택한 파일 형식의 인코더를 사용할 수 없습니다.")
        }
        var metadata: [String: Any] = [:]
        if options.keepMetadata,
           let original = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] {
            for category in [kCGImagePropertyExifDictionary, kCGImagePropertyTIFFDictionary,
                             kCGImagePropertyIPTCDictionary] {
                let name = category as String
                if let item = original[name] { metadata[name] = item }
            }
            if !options.removeGPS,
               let gps = original[kCGImagePropertyGPSDictionary as String] {
                metadata[kCGImagePropertyGPSDictionary as String] = gps
            }
            if var exif = metadata[kCGImagePropertyExifDictionary as String] as? [String: Any] {
                exif[kCGImagePropertyExifPixelXDimension as String] = target.width
                exif[kCGImagePropertyExifPixelYDimension as String] = target.height
                metadata[kCGImagePropertyExifDictionary as String] = exif
            }
            if var tiff = metadata[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
                tiff["Orientation"] = 1
                metadata[kCGImagePropertyTIFFDictionary as String] = tiff
            }
        }
        metadata[kCGImagePropertyOrientation as String] = 1
        metadata[kCGImagePropertyPixelWidth as String] = target.width
        metadata[kCGImagePropertyPixelHeight as String] = target.height
        if format.lossy {
            metadata[kCGImageDestinationLossyCompressionQuality as String] =
                max(0.65, min(1, options.jpegQuality))
        }
        CGImageDestinationAddImage(writer, rendered, metadata as CFDictionary)
        guard CGImageDestinationFinalize(writer) else { return (nil, "이미지 저장에 실패했습니다.") }
        if cancelled.isCancelled { return (nil, nil) }
        do {
            // 임시 파일을 완성한 뒤 이동. 원본을 덮어쓰지 않고 동일 이름 충돌도 회피.
            try FileManager.default.moveItem(at: temp, to: dest)
            FileProcessor.preserveFileDates(from: file, to: dest)
            return (dest, nil)
        } catch {
            return (nil, "새 파일 확정 실패: \(error.localizedDescription)")
        }
    }
}

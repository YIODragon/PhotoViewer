import CoreGraphics
import Foundation
import ImageIO
import PhotoViewerCore
import UniformTypeIdentifiers

@main
struct PhotoViewerChecks {
    static func main() async {
        if let flagIndex = CommandLine.arguments.firstIndex(of: "--scan") {
            let pathIndex = flagIndex + 1
            guard pathIndex < CommandLine.arguments.count else {
                fputs("usage: PhotoViewerChecks --scan <folder>\n", stderr)
                exit(2)
            }
            scanReport(folder: URL(fileURLWithPath: CommandLine.arguments[pathIndex]))
            return
        }

        do {
            try await run()
            print("\nAll checks passed.")
        } catch {
            fputs("\nFAILED: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func scanReport(folder: URL) {
        do {
            let shots = try FolderScanner().scanShots(folder)
            let pairs = shots.filter { $0.hasPairedFormats }.count
            let rawOnly = shots.filter { $0.isRawOnly }.count
            let jpegOnly = shots.filter { $0.jpeg != nil && $0.raw == nil }.count

            print("folder: \(folder.path)")
            print("shots: \(shots.count)  pairs: \(pairs)  raw-only: \(rawOnly)  jpeg-only: \(jpegOnly)")
            if let first = shots.first {
                print("first: \(first.baseName) [\(first.formatBadge)] files=\(first.fileCount)")
            }
            if let last = shots.last {
                print("last:  \(last.baseName) [\(last.formatBadge)] files=\(last.fileCount)")
            }
        } catch {
            fputs("scan failed: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func run() async throws {
        let root = URL(fileURLWithPath: "/tmp/PhotoViewerChecks-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try writePNG(to: root.appendingPathComponent("IMG_1.png"), width: 320, height: 200)
        try writePNG(to: root.appendingPathComponent("IMG_2.png"), width: 120, height: 120)
        try writePNG(to: root.appendingPathComponent("IMG_4.PNG"), width: 64, height: 48)
        try writePNG(to: root.appendingPathComponent("IMG_10.png"), width: 800, height: 600)
        try "not an image".write(
            to: root.appendingPathComponent("notes.txt"),
            atomically: true,
            encoding: .utf8
        )

        let scanner = FolderScanner()
        let photos = try scanner.scan(root)
        let names = photos.map(\.name)
        expect(
            names == ["IMG_1.png", "IMG_2.png", "IMG_4.PNG", "IMG_10.png"],
            "natural sort should be IMG_1, IMG_2, IMG_4, IMG_10; got \(names)"
        )
        print("PASS natural sort")

        let first = try require(photos.first, "expected at least one photo")
        let size = try require(ImageDecoder.pixelSize(at: first.url), "expected pixel size")
        expect(size == CGSize(width: 320, height: 200), "unexpected pixel size \(size)")
        print("PASS read pixel size")

        let thumb = try require(
            ImageDecoder.downsampledImage(at: first.url, maxPixel: 64),
            "expected a decoded thumbnail"
        )
        expect(max(thumb.width, thumb.height) == 64, "thumbnail should be max 64px; got \(thumb.width)x\(thumb.height)")
        print("PASS downsample decode")

        expect(BrowserMath.indexAfterDeleting(index: 0, count: 3) == 0, "delete first should keep next")
        expect(BrowserMath.indexAfterDeleting(index: 1, count: 3) == 1, "delete middle should keep next")
        expect(BrowserMath.indexAfterDeleting(index: 2, count: 3) == 1, "delete last should go previous")
        expect(BrowserMath.indexAfterDeleting(index: 0, count: 1) == nil, "deleting only photo should empty")
        print("PASS delete index rules")

        do {
            _ = try scanner.scan(first.url)
            throw CheckFailure("scanning a file as a folder should fail")
        } catch is FolderScannerError {
            print("PASS reject non-folder")
        }

        let pairRoot = root.appendingPathComponent("pairing", isDirectory: true)
        try FileManager.default.createDirectory(at: pairRoot, withIntermediateDirectories: true)
        for name in ["PAIR_1.JPG", "PAIR_1.NEF", "PAIR_2.NEF", "PAIR_3.jpg"] {
            try Data().write(to: pairRoot.appendingPathComponent(name))
        }

        let pairedShots = try FolderScanner().scanShots(pairRoot)
        expect(pairedShots.count == 3, "297 pairs + 3 NEF-only should become 3 test shots; got \(pairedShots.count)")
        expect(pairedShots[0].hasPairedFormats, "first shot should be a RAW+JPEG pair")
        expect(pairedShots[0].fileCount == 2, "pair should contain two files")
        expect(
            pairedShots[0].photo(preferRAW: false).url.pathExtension.lowercased() == "jpg",
            "default display should be JPEG"
        )
        expect(
            pairedShots[0].photo(preferRAW: true).url.pathExtension.lowercased() == "nef",
            "RAW preference should select the NEF"
        )
        expect(pairedShots[0].formatBadge == "NEF+JPG", "pair badge should be NEF+JPG")
        expect(pairedShots[1].isRawOnly, "second shot should be NEF-only")
        expect(pairedShots[2].jpeg != nil && pairedShots[2].raw == nil, "third shot should be JPEG-only")
        print("PASS RAW/JPEG pairing")

        let markStore = ShotMarkStore(fileURL: pairRoot.appendingPathComponent("marks.json"))
        let savedMark = ShotMark(rating: 4, flag: .pick)
        try markStore.save(["shot-1": savedMark])
        let loadedMarks = try markStore.load()
        expect(loadedMarks["shot-1"] == savedMark, "marks should survive a JSON round trip")
        expect(ShotMark(rating: 99).rating == 5, "rating should clamp to 5")
        print("PASS mark persistence")

        expect(ShotFilter.all.matches(ShotMark()), "all should match everything")
        expect(ShotFilter.unrated.matches(ShotMark()), "unrated should match an empty mark")
        expect(!ShotFilter.unrated.matches(ShotMark(rating: 1)), "rated shot is not unrated")
        expect(ShotFilter.picked.matches(ShotMark(flag: .pick)), "pick filter should match picks")
        expect(ShotFilter.rejected.matches(ShotMark(flag: .reject)), "reject filter should match rejects")
        print("PASS filters")

        let shotA = Shot(files: [Photo(url: pairRoot.appendingPathComponent("A.JPG"))])
        let shotB = Shot(files: [Photo(url: pairRoot.appendingPathComponent("B.JPG"))])
        let shotC = Shot(files: [Photo(url: pairRoot.appendingPathComponent("C.JPG"))])
        expect(
            CullingMath.nextIndexAfterMark(
                shotID: shotA.id,
                visible: [shotA, shotB, shotC],
                oldIndex: 0,
                autoAdvance: true
            ) == 1,
            "auto-advance should select the next visible shot"
        )
        expect(
            CullingMath.nextIndexAfterMark(
                shotID: shotA.id,
                visible: [shotA, shotB, shotC],
                oldIndex: 0,
                autoAdvance: false
            ) == 0,
            "without auto-advance the marked shot should stay selected"
        )
        expect(
            CullingMath.nextIndexAfterMark(
                shotID: shotA.id,
                visible: [shotB, shotC],
                oldIndex: 0,
                autoAdvance: true
            ) == 0,
            "when the marked shot leaves the filter, the next item takes its index"
        )
        expect(
            CullingMath.nextIndexAfterMark(
                shotID: shotA.id,
                visible: [],
                oldIndex: 0,
                autoAdvance: true
            ) == nil,
            "empty filter should have no selected index"
        )
        print("PASS culling advance")

        await MainActor.run {
            testZoomGeometry()
        }

        await testChromeVisibility()
    }

    @MainActor
    private static func testZoomGeometry() {
        let zoom = ZoomState(backingScale: 2, padding: 32)
        zoom.updateViewport(CGSize(width: 1000, height: 800))
        zoom.setOriginalSize(CGSize(width: 4000, height: 3000))

        expect(abs(zoom.fitScale - 0.242) < 0.001, "fit scale should be 0.242; got \(zoom.fitScale)")
        expect(zoom.zoomPercent == 48, "fit zoom should be about 48%; got \(zoom.zoomPercent)")

        zoom.actualSize()
        expect(zoom.mode == .actual, "mode should be actual")
        expect(abs(zoom.currentScale - 0.5) < 0.0001, "100% should be 0.5 pt per pixel on a 2x display")
        expect(zoom.zoomPercent == 100, "actual size should be 100%")

        zoom.setScale(1.0)
        zoom.setOffset(CGSize(width: 10_000, height: 10_000))
        expect(zoom.offset.width <= 1516.01, "pan should clamp horizontally; got \(zoom.offset.width)")
        expect(zoom.offset.height <= 1116.01, "pan should clamp vertically; got \(zoom.offset.height)")

        zoom.fit()
        expect(zoom.mode == .fit, "fit() should restore fit mode")
        expect(zoom.offset == .zero, "fit() should reset the pan offset")

        print("PASS zoom geometry")
    }

    @MainActor
    private static func testChromeVisibility() async {
        let chrome = ChromeVisibility(
            idleDelay: .milliseconds(120),
            tick: .milliseconds(20)
        )

        chrome.showTemporarily()
        expect(chrome.isVisible, "controls should be visible after activity")

        try? await Task.sleep(for: .milliseconds(280))
        expect(!chrome.isVisible, "controls should hide after the idle delay")

        chrome.mouseMoved(to: CGPoint(x: 24, y: 24))
        expect(chrome.isVisible, "mouse activity should reveal controls again")
        chrome.pointerEnteredControls()

        try? await Task.sleep(for: .milliseconds(280))
        expect(chrome.isVisible, "controls should stay visible while the pointer is over them")

        chrome.pointerExitedControls()
        try? await Task.sleep(for: .milliseconds(280))
        expect(!chrome.isVisible, "controls should hide after leaving the controls")

        chrome.mouseMoved(to: CGPoint(x: 48, y: 48))
        expect(chrome.isVisible, "mouse move should show controls")
        chrome.mouseExited()
        expect(!chrome.isVisible, "leaving the image should hide controls immediately")

        print("PASS chrome auto-hide")
    }

    private static func writePNG(to url: URL, width: Int, height: Int) throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw CheckFailure("could not create CGContext")
        }

        context.setFillColor(CGColor(red: 0.15, green: 0.55, blue: 0.85, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else {
            throw CheckFailure("could not create CGImage")
        }

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw CheckFailure("could not create image destination")
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CheckFailure("could not write \(url.lastPathComponent)")
        }
    }

    private static func expect(_ condition: Bool, _ message: String) {
        if !condition {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }

    private static func require<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw CheckFailure(message) }
        return value
    }
}

private struct CheckFailure: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}

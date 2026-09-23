import CubeKit
import XCTest
@testable import CubeScan

final class LabColorTests: XCTestCase {

    func test_srgbToLabMatchesKnownValues() {
        // 参考值取自标准 sRGB→Lab 换算（D65）
        let white = LabColor(srgbRed: 1, green: 1, blue: 1)
        XCTAssertEqual(white.l, 100, accuracy: 0.1)
        XCTAssertEqual(white.a, 0, accuracy: 0.1)
        XCTAssertEqual(white.b, 0, accuracy: 0.1)

        let black = LabColor(srgbRed: 0, green: 0, blue: 0)
        XCTAssertEqual(black.l, 0, accuracy: 0.1)

        let red = LabColor(srgbRed: 1, green: 0, blue: 0)
        XCTAssertEqual(red.l, 53.24, accuracy: 0.1)
        XCTAssertEqual(red.a, 80.09, accuracy: 0.1)
        XCTAssertEqual(red.b, 67.20, accuracy: 0.1)

        let green = LabColor(srgbRed: 0, green: 1, blue: 0)
        XCTAssertEqual(green.l, 87.73, accuracy: 0.1)
        XCTAssertEqual(green.a, -86.18, accuracy: 0.1)
        XCTAssertEqual(green.b, 83.18, accuracy: 0.1)

        let blue = LabColor(srgbRed: 0, green: 0, blue: 1)
        XCTAssertEqual(blue.l, 32.30, accuracy: 0.1)
        XCTAssertEqual(blue.a, 79.19, accuracy: 0.1)
        XCTAssertEqual(blue.b, -107.86, accuracy: 0.1)
    }

    func test_xyzRoundTripIsStable() {
        for red in stride(from: 0.0, through: 1.0, by: 0.2) {
            for green in stride(from: 0.0, through: 1.0, by: 0.2) {
                for blue in stride(from: 0.0, through: 1.0, by: 0.2) {
                    let lab = LabColor(srgbRed: red, green: green, blue: blue)
                    let restored = LabColor.fromXYZ(LabColor.xyz(from: lab))
                    XCTAssertEqual(lab.distance(to: restored), 0, accuracy: 1e-6,
                                   "rgb(\(red), \(green), \(blue)) 往返失真")
                }
            }
        }
    }

    func test_chromaAndHueSeparateTheSixCubeColors() {
        let white = StickerClassifier.references[.white]!
        // 白色是唯一彩度接近 0 的
        XCTAssertLessThan(white.chroma, 5)
        for color in [CubeColor.yellow, .green, .blue, .red, .orange] {
            XCTAssertGreaterThan(StickerClassifier.references[color]!.chroma, 40,
                                 "\(color) 的彩度不足以和白区分")
        }
        // 五个彩色里白之外的两两色相都拉得开
        XCTAssertEqual(StickerClassifier.references[.red]!.hueAngle, 40, accuracy: 12)
        XCTAssertEqual(StickerClassifier.references[.orange]!.hueAngle, 57, accuracy: 12)
        XCTAssertEqual(StickerClassifier.references[.yellow]!.hueAngle, 95, accuracy: 12)
        XCTAssertEqual(StickerClassifier.references[.green]!.hueAngle, 143, accuracy: 12)
        XCTAssertEqual(StickerClassifier.references[.blue]!.hueAngle, 300, accuracy: 12)
    }

    func test_whiteAdaptationRemovesIlluminantCast() {
        // 暖光下白块被染黄、蓝块整体偏色。用识别出来的白做校正之后，
        // 六种颜色都该回到参考值上——这是"拿白块自标定"能成立的前提。
        var generator = SplitMix64(seed: 1)
        let warm = SyntheticCapture.Lighting.warm
        let white = StickerClassifier.references[.white]!
        let observedWhite = warm.apply(white, generator: &generator)

        var worstRaw = 0.0
        for color in CubeColor.allCases {
            let reference = StickerClassifier.references[color]!
            let observed = warm.apply(reference, generator: &generator)
            worstRaw = max(worstRaw, observed.distance(to: reference))

            let adapted = observed.adapted(fromWhite: observedWhite, toWhite: white)
            XCTAssertLessThan(adapted.distance(to: reference), 1,
                              "\(color) 白点校正后仍偏 \(adapted.distance(to: reference))")
        }
        XCTAssertGreaterThan(worstRaw, 20, "光照模型没造出足够偏色，这个测试就没意义了")
    }

    func test_adaptationLeavesColorAloneWhenLightIsAlreadyNeutral() {
        let neutral = LabColor(srgbRed: 1, green: 1, blue: 1)
        let sample = StickerClassifier.references[.blue]!
        let adapted = sample.adapted(fromWhite: neutral, toWhite: neutral)
        XCTAssertEqual(sample.distance(to: adapted), 0, accuracy: 0.5)
    }
}

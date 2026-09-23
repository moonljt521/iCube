import CubeKit
import XCTest
@testable import CubeScan

final class StickerClassifierTests: XCTestCase {

    private func state(seed: UInt64, length: Int = 20) -> CubeState {
        Scramble.random(size: 3, length: length, seed: seed).initialState
    }

    /// 分类器只认颜色、不摆正朝向——每个面拍进去时转了 0/90/180/270° 是随机的，
    /// 分类器无从知道，摆正是 `FaceletAssembler` 的活。所以比对必须容许一个旋转。
    private func assertFacesMatch(
        _ result: ClassifiedFaces,
        _ original: CubeState,
        _ context: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for face in Face.allCases {
            guard let grid = result.colors[face] else {
                XCTFail("\(context)\(face.letter) 面缺失", file: file, line: line)
                continue
            }
            let expected = SyntheticCapture.grid(of: original, face: face)
            XCTAssertTrue(SyntheticCapture.equalUpToRotation(grid, expected),
                          "\(context)\(face.letter) 面认错了：\(grid)",
                          file: file, line: line)
        }
    }

    func test_recoversEveryFaceUnderDaylight() throws {
        for seed in UInt64(1)...20 {
            let original = state(seed: seed)
            let captures = SyntheticCapture.captures(
                of: original,
                rotations: SyntheticCapture.randomRotations(seed: seed),
                seed: seed
            )
            let result = try StickerClassifier.classify(captures)
            assertFacesMatch(result, original, "seed \(seed) ")
        }
    }

    func test_survivesWarmAndCoolLighting() throws {
        let original = state(seed: 3)
        for (name, lighting) in [("暖光", SyntheticCapture.Lighting.warm),
                                 ("冷光", SyntheticCapture.Lighting.cool)] {
            let captures = SyntheticCapture.captures(
                of: original,
                rotations: SyntheticCapture.randomRotations(seed: 11),
                lighting: lighting,
                seed: 11
            )
            let result = try StickerClassifier.classify(captures)
            assertFacesMatch(result, original, "\(name)下 ")
        }
    }

    func test_survivesDimLightingAndNoise() throws {
        let original = state(seed: 5)
        var lighting = SyntheticCapture.Lighting.dim
        lighting.noise = 0.03
        let captures = SyntheticCapture.captures(
            of: original,
            rotations: SyntheticCapture.randomRotations(seed: 13),
            lighting: lighting,
            seed: 13
        )
        let result = try StickerClassifier.classify(captures)
        assertFacesMatch(result, original, "暗光 + 噪声下 ")
    }

    func test_ignoresCaptureOrderAndRotation() throws {
        // 同一批面，打乱拍摄顺序、每个面再各自转一个角度，结果必须一样。
        // 这是"用户怎么拿手机拍都行"这条产品承诺的核心。
        let original = state(seed: 8)
        let base = SyntheticCapture.captures(of: original, rotations: [:], seed: 8)
        let shuffled = [3, 0, 5, 2, 1, 4].enumerated().map { offset, index in
            FaceCapture(samples: SyntheticCapture.rotated(base[index].samples, quarterTurns: offset))
        }

        let result = try StickerClassifier.classify(shuffled)
        assertFacesMatch(result, original, "打乱顺序后 ")
        XCTAssertEqual(FaceletAssembler.assemble(result.colors), original,
                       "打乱顺序后拼不回原状态")
    }

    func test_eachColorAppearsExactlyNineTimes() throws {
        let original = state(seed: 21)
        let result = try StickerClassifier.classify(SyntheticCapture.captures(
            of: original,
            rotations: SyntheticCapture.randomRotations(seed: 21),
            seed: 21
        ))
        var counts: [CubeColor: Int] = [:]
        for grid in result.colors.values { for color in grid { counts[color, default: 0] += 1 } }
        XCTAssertEqual(result.colors.count, 6)
        for color in CubeColor.allCases {
            XCTAssertEqual(counts[color], 9, "\(color) 不是 9 个")
        }
    }

    func test_centerStickerAlwaysMatchesItsFaceColor() throws {
        for seed in UInt64(1)...10 {
            let original = state(seed: seed)
            let result = try StickerClassifier.classify(SyntheticCapture.captures(
                of: original,
                rotations: SyntheticCapture.randomRotations(seed: seed),
                seed: seed
            ))
            for face in Face.allCases {
                XCTAssertEqual(result.colors[face]?[4], face.defaultColor,
                               "seed \(seed) 的 \(face.letter) 面中心块认错了")
            }
        }
    }

    func test_confidenceIsHighForCleanInput() throws {
        let original = state(seed: 2)
        let result = try StickerClassifier.classify(SyntheticCapture.captures(
            of: original,
            rotations: SyntheticCapture.randomRotations(seed: 2),
            seed: 2
        ))
        XCTAssertGreaterThan(result.margin, 15, "干净输入的把握度不该这么低：\(result.margin)")
    }

    func test_rejectsWrongCaptureCount() {
        XCTAssertThrowsError(try StickerClassifier.classify([])) { error in
            XCTAssertEqual(error as? ScanError, .wrongFaceCount(0))
        }
    }

    func test_rejectsWrongSampleCount() {
        let capture = FaceCapture(samples: [StickerClassifier.references[.white]!])
        XCTAssertThrowsError(try StickerClassifier.classify(Array(repeating: capture, count: 6))) { error in
            XCTAssertEqual(error as? ScanError, .wrongSampleCount(face: 0, count: 1))
        }
    }

    func test_detectsTheSameFacePhotographedTwice() {
        // 六个 capture 里有三个是同一面：中心块颜色必然撞车
        let original = state(seed: 4)
        let one = SyntheticCapture.captures(of: original, rotations: [:], seed: 4)
        let captures = [one[0], one[0], one[1], one[1], one[2], one[2]]
        XCTAssertThrowsError(try StickerClassifier.classify(captures)) { error in
            guard case .duplicateCenter = error as? ScanError else {
                return XCTFail("应报 duplicateCenter，实际 \(error)")
            }
        }
    }

    func test_boundarySampleIsPulledBackByTheNinePerColorRule() throws {
        // 把一格绿贴纸推到"绿蓝之间、偏向蓝"的位置：单看颜色它离蓝更近，
        // 聚类会把它归进蓝簇；但"每色恰好 9 个"这条硬约束应当把它拽回绿。
        let original = state(seed: 6)
        var captures = SyntheticCapture.captures(of: original, rotations: [:], seed: 6)
        let green = SyntheticCapture.referenceLab(.green)
        let blue = SyntheticCapture.referenceLab(.blue)
        let biased = LabColor(
            l: green.l + (blue.l - green.l) * 0.6,
            a: green.a + (blue.a - green.a) * 0.6,
            b: green.b + (blue.b - green.b) * 0.6
        )

        var touched: (face: Face, position: Int)?
        outer: for face in Face.allCases {
            let index = Face.allCases.firstIndex(of: face)!
            var samples = captures[index].samples
            // 中心块不能动——它决定这个面是什么颜色
            for position in 0..<9 where position != 4 && samples[position].distance(to: green) < 0.01 {
                samples[position] = biased
                captures[index] = FaceCapture(samples: samples)
                touched = (face, position)
                break outer
            }
        }
        let target = try XCTUnwrap(touched, "造不出这个用例：没有找到绿贴纸")

        let result = try StickerClassifier.classify(captures)
        var counts: [CubeColor: Int] = [:]
        for grid in result.colors.values { for color in grid { counts[color, default: 0] += 1 } }
        for color in CubeColor.allCases {
            XCTAssertEqual(counts[color], 9, "\(color) 数量不对，硬约束没生效")
        }
        XCTAssertEqual(result.colors[target.face]?[target.position], .green,
                       "硬约束没把骑墙的那一格拽回绿色")
    }
}

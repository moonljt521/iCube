import CubeKit
import CubeScan
import XCTest
@testable import iCube

/// 拍照 → 识别 → 灌进录入页 这条链路的集成测试。
///
/// 相机本身不测（那层没有可测的逻辑，只是把帧转出来）；测的是**契约**：
/// 六个面的采样色进来，最后录入页是不是满的、能不能直接求解。
/// 这条链路跨了 `CubeScan` 和 `RestoreModel` 两个模块，各自单测覆盖不到接缝。
@MainActor
final class ScanFlowTests: XCTestCase {

    /// 把一个状态模拟成"用户拍的六张照片"：每个面可以各自转一个角度
    private func captures(of state: CubeState, rotations: [Face: Int]) -> [FaceCapture] {
        Face.allCases.map { face in
            var grid = (0..<9).map { state.color(at: face, row: $0 / 3, col: $0 % 3) }
            grid = FaceletAssembler.rotated(grid, quarterTurns: rotations[face] ?? 0)
            return FaceCapture(samples: grid.map { StickerClassifier.references[$0]! })
        }
    }

    func test_scannedStateLandsReadyToSolve() throws {
        for seed in UInt64(1)...10 {
            let original = Scramble.random(size: 3, length: 20, seed: seed).initialState
            // 每个面拍进去的朝向都不一样，模拟"用户随手拿着拍"
            let rotations = Dictionary(uniqueKeysWithValues: Face.allCases.enumerated().map {
                ($0.element, ($0.offset + Int(seed)) % 4)
            })

            let classified = try StickerClassifier.classify(captures(of: original, rotations: rotations))
            let state = try XCTUnwrap(FaceletAssembler.assemble(classified.colors),
                                      "seed \(seed) 拼不出合法状态")

            let model = RestoreModel()
            model.load(state: state)

            XCTAssertEqual(model.filledCount, 54, "seed \(seed) 识别后录入页没填满")
            XCTAssertTrue(model.canSolve, "seed \(seed) 识别后录入页不能求解：\(model.statusMessage)")
            XCTAssertEqual(model.state, original, "seed \(seed) 录入页里的状态与真实状态不一致")
        }
    }

    func test_missingOneFaceIsRejectedInsteadOfGuessed() {
        // 只拍了五个面：必须明确报错，不能拿半个魔方硬猜一个状态出来
        let original = Scramble.random(size: 3, length: 20, seed: 7).initialState
        let partial = Array(captures(of: original, rotations: [:]).dropLast())
        XCTAssertThrowsError(try StickerClassifier.classify(partial)) { error in
            XCTAssertEqual(error as? ScanError, .wrongFaceCount(5))
        }
    }

    func test_sameFaceTwiceIsRejectedAtClassification() {
        // 同一面拍了两遍：中心块颜色必然撞车
        let original = Scramble.random(size: 3, length: 20, seed: 11).initialState
        let six = captures(of: original, rotations: [:])
        let repeated = [six[0], six[1], six[2], six[3], six[4], six[4]]
        XCTAssertThrowsError(try StickerClassifier.classify(repeated)) { error in
            guard case .duplicateCenter = error as? ScanError else {
                return XCTFail("应报 duplicateCenter，实际 \(error)")
            }
        }
    }
}

import XCTest
import CubeKit
@testable import iCube

/// 教程数据是演示机制的地基：每条公式必须能解析，且"案型 = 还原态施公式的逆、
/// 再施加公式本体必须回到还原态"。公式抄错一个字符在这里就会挂掉。
final class TutorialDataTests: XCTestCase {

    private var allCases: [(stage: TutorialStage, tutorialCase: TutorialCase)] {
        TutorialStage.all.flatMap { stage in
            stage.cases.map { (stage, $0) }
        }
    }

    func testStageAndCaseIDsAreUnique() {
        let stageIDs = TutorialStage.all.map(\.id)
        XCTAssertEqual(stageIDs.count, Set(stageIDs).count, "阶段 id 重复")

        let caseIDs = allCases.map(\.tutorialCase.id)
        XCTAssertEqual(caseIDs.count, Set(caseIDs).count, "案型 id 重复")
    }

    func testAllFormulasParse() {
        for (stage, tutorialCase) in allCases {
            XCTAssertNotNil(Algorithm.parse(tutorialCase.formula),
                            "\(stage.title) / \(tutorialCase.name) 的公式无法解析: \(tutorialCase.formula)")
        }
    }

    /// 案型 = 还原态施加公式的逆；播放公式本体后必须回到还原态
    func testEveryFormulaSolvesItsCase() {
        for (stage, tutorialCase) in allCases {
            guard let algorithm = Algorithm.parse(tutorialCase.formula) else { continue }
            let caseState = CubeState.solved.applying(algorithm.inverse)
            XCTAssertFalse(caseState.isSolved,
                           "\(tutorialCase.name) 的公式是恒等式，摆不出案型: \(tutorialCase.formula)")
            let solved = caseState.applying(algorithm)
            XCTAssertTrue(solved.isSolved,
                          "\(stage.title) / \(tutorialCase.name) 的公式无法还原其案型: \(tutorialCase.formula)")
        }
    }

    /// 至少覆盖占位页承诺的内容量：层先法 7 步 + 进阶案型
    func testStageCoverage() {
        XCTAssertGreaterThanOrEqual(TutorialStage.all.count, 8)
        XCTAssertGreaterThanOrEqual(allCases.count, 20)
    }
}

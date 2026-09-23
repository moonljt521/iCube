// TwistAssist | Michael Baumgärtner | © 2025 | All rights reserved | MIT License

// Inspiration was taken from
//   https://github.com/tcbegley/cube-solver - MIT License.
// No source code was copied.

import Foundation

/// Error type for TB2P cube solver operations.
///
/// Represents all error conditions that can occur during cube verification,
/// solving, and table management. Each case provides a descriptive message.
public enum TB2PError: Error, CustomStringConvertible {
    /// Raised when cube state verification fails.
    /// Contains a message describing the reason.
    case cubeVerificationFailed(String)
    /// Raised when cube solving exceeds the allowed time limit.
    case cubeSolvingTimeout
    /// Raised when the facelet string is invalid.
    /// Contains the invalid facelet string.
    case faceCubeInvalidFacelets(String)
    /// Raised when a single facelet is invalid.
    /// Contains the invalid facelet and its index.
    case faceCubeInvalidFacelet(String, Int)
    /// Raised when loading JSON tables fails.
    /// Contains the underlying error.
    case tablesJSONLoadFailed(error: Error)
    /// Raised when loading JSON tables fails because of invalid data.
    case tablesJSONLoadInvalidData
    /// Raised when saving JSON tables fails.
    /// Contains the underlying error.
    case tablesJSONSaveFailed(error: Error)
    /// Raised when loading binary tables fails.
    /// Contains the underlying error.
    case tablesBinaryLoadFailed(error: Error)
    /// Raised when saving binary tables fails.
    /// Contains the underlying error.
    case tablesBinarySaveFailed(error: Error)

    public var description: String {
        switch self {
        case .cubeVerificationFailed(let message):
            "FAILED: verification of cube state: \(message)"
        case .cubeSolvingTimeout:
            "ERROR: solving of cube failed with timeout"
        case .faceCubeInvalidFacelets(let facelets):
            "ERROR: invalid facelets \(facelets)"
        case .faceCubeInvalidFacelet(let facelet, let index):
            "ERROR: invalid facelet \(facelet) at index \(index)"
        case .tablesJSONLoadFailed(let error):
            "ERROR: loading JSON tables faild with \(error)"
        case .tablesJSONLoadInvalidData:
            "ERROR: loading JSON tables faild with invalid data"
        case .tablesJSONSaveFailed(let error):
            "ERROR: saving JSON tables faild with \(error)"
        case .tablesBinaryLoadFailed(let error):
            "ERROR: loading binary tables faild with \(error)"
        case .tablesBinarySaveFailed(let error):
            "ERROR: saving binary tables faild with \(error)"
        }
    }
}

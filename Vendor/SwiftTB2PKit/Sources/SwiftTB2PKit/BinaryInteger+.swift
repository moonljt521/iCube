// TwistAssist | Michael Baumgärtner | © 2025 | All rights reserved | MIT License

import Foundation

extension BinaryInteger {
    /// Returns the mathematical floor division of self by the given divisor.
    ///
    /// The result is the largest integer less than or equal to the exact
    /// quotient. Handles negative values as expected in mathematics.
    ///
    /// - Parameter divisor: The value to divide by. Must not be zero.
    /// - Returns: The floored quotient of the division.
    func floorDiv(by divisor: Self) -> Self {
        precondition(divisor != 0, "Division by zero")
        let quotient = self / divisor
        let remainder = self % divisor
        return (remainder != 0 && (self < 0) != (divisor < 0)) ? quotient - 1 : quotient
    }

    /// Returns the wrapped (always positive) modulus of self by the divisor.
    ///
    /// The result is always in the range 0..<divisor, even for negative
    /// values. Useful for modular arithmetic with negative numbers.
    ///
    /// - Parameter divisor: The modulus base.
    /// - Returns: The positive remainder after wrapping.
    func wrappedMod(by divisor: Self) -> Self {
        let remainder = self % divisor
        return remainder >= 0 ? remainder : remainder + divisor
    }
}

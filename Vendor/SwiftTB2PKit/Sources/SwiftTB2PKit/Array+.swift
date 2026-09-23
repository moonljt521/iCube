// TwistAssist | Michael Baumgärtner | © 2025 | All rights reserved | MIT License

extension Array {
    /// Safely accesses the element at the specified index.
    ///
    /// Returns the element at the given index if it is within bounds,
    /// otherwise returns `nil`. Does not cause a runtime error for
    /// out-of-bounds access.
    ///
    /// - Parameter index: The index of the element to access.
    /// - Returns: The element at `index` if it exists, otherwise `nil`.
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }

    /// Accesses the element at the specified index, supporting negative
    /// indices.
    ///
    /// Negative indices wrap around from the end of the array (e.g., -1 is
    /// the last element). Triggers a runtime error if the index is out of
    /// bounds after wrapping.
    ///
    /// - Parameter index: The index of the element to access. Negative
    ///     values wrap from the end.
    /// - Returns: The element at the wrapped index.
    subscript(wrapped index: Int) -> Element {
        get {
            let idx = index >= 0 ? index : self.count + index
            precondition(idx >= 0 && idx < self.count, "Index out of bounds: \(index)")
            return self[idx]
        }
        set {
            let idx = index >= 0 ? index : self.count + index
            precondition(idx >= 0 && idx < self.count, "Index out of bounds: \(index)")
            self[idx] = newValue
        }
    }
}

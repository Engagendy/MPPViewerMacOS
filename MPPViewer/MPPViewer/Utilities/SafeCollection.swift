import Foundation

extension Dictionary {
    /// Creates a dictionary from key/value pairs while tolerating duplicate keys.
    ///
    /// The last duplicate wins by default, which preserves current source order while
    /// avoiding runtime crashes from duplicate keys in imported/corrupted data.
    init(
        nonThrowingUniquePairs: some Sequence<(Key, Value)>,
        keepLast: Bool = true
    ) {
        self.init()
        for (key, value) in nonThrowingUniquePairs {
            if keepLast || self[key] == nil {
                self[key] = value
            }
        }
    }
}


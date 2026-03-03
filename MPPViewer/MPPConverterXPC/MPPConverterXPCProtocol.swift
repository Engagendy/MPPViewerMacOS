import Foundation

/// The protocol that this service will vend as its API.
/// This protocol is also visible to the main app process via a shared copy.
@objc protocol MPPConverterXPCProtocol {
    /// Convert an MPP file at the given path to JSON data.
    func convertMPP(atPath inputPath: String, reply: @escaping (Data?, String?) -> Void)
}

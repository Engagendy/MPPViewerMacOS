import Foundation

/// Protocol for the XPC service that converts MPP files to JSON.
/// This file is shared between the main app and the XPC service.
@objc protocol MPPConverterXPCProtocol {
    /// Convert an MPP file at the given path to JSON data.
    /// - Parameters:
    ///   - inputPath: Absolute path to the .mpp file
    ///   - reply: Callback with optional JSON data and optional error message
    func convertMPP(atPath inputPath: String, reply: @escaping (Data?, String?) -> Void)

    /// Convert MPP file data to JSON data.
    /// - Parameters:
    ///   - inputData: Raw .mpp file bytes staged by the main app
    ///   - fileExtension: Original file extension, used only for the temporary staged filename
    ///   - reply: Callback with optional JSON data and optional error message
    func convertMPPData(_ inputData: Data, fileExtension: String, reply: @escaping (Data?, String?) -> Void)

    /// Export a native-plan interchange JSON payload to MSPDI (MS Project XML) data.
    /// - Parameters:
    ///   - planJSON: Interchange JSON describing the native plan
    ///   - reply: Callback with optional MSPDI XML data and optional error message
    func exportPlanToMSPDI(_ planJSON: Data, reply: @escaping (Data?, String?) -> Void)
}

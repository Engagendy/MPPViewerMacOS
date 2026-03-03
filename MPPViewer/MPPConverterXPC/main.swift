import Foundation

// Create the delegate for the service.
let delegate = MPPConverterXPCDelegate()

// Set up the one NSXPCListener for this service.
let listener = NSXPCListener.service()
listener.delegate = delegate

// Resuming the serviceListener starts this service. This method does not return.
listener.resume()

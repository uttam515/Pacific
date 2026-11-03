import Foundation
import SwiftUI
import Combine

@MainActor
public final class NetworkViewModel: ObservableObject {
    @Published public var localNodeId: String = ""
    @Published public var localDeviceName: String = ""

    public let logger: NetworkDiagnosticLogger = .shared

    public init() {
        self.localNodeId = KeychainHelper.shared.getOrCreateNodeId()
        self.localDeviceName = UIDevice.current.name
    }

    public func clearLogs() {
        logger.clear()
    }
}

import Foundation
import SwiftUI

@MainActor
public final class NetworkViewModel: ObservableObject {
    @Published public var localNodeId: String = ""
    @Published public var isScanning: Bool = true

    public init() {
        self.localNodeId = KeychainHelper.shared.getOrCreateNodeId()
    }
}

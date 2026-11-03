import Foundation
import CoreBluetooth

public final class BLEManager: NSObject, @unchecked Sendable {
    public static let sharedServiceUUID = CBUUID(string: "7B6E0001-C72B-4E36-96F1-30AA4B848694")
    public static let txCharUUID = CBUUID(string: "7B6E0002-C72B-4E36-96F1-30AA4B848694")
    public static let rxCharUUID = CBUUID(string: "7B6E0003-C72B-4E36-96F1-30AA4B848694")

    private var centralManager: CBCentralManager?
    private var peripheralManager: CBPeripheralManager?
    private var rxCharacteristic: CBMutableCharacteristic?

    private var discoveredPeripherals: [UUID: CBPeripheral] = [:]
    public weak var delegate: PeerDiscoveryDelegate?

    public override init() {
        super.init()
    }

    public func start() {
        centralManager = CBCentralManager(delegate: self, queue: nil)
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
    }

    public func stop() {
        centralManager?.stopScan()
        peripheralManager?.stopAdvertising()
        discoveredPeripherals.removeAll()
    }

    private func setupPeripheralService() {
        guard let peripheralManager = peripheralManager, peripheralManager.state == .poweredOn else { return }

        let tx = CBMutableCharacteristic(
            type: Self.txCharUUID,
            properties: [.write, .writeWithoutResponse],
            value: nil,
            permissions: [.writeable]
        )

        let rx = CBMutableCharacteristic(
            type: Self.rxCharUUID,
            properties: [.notify, .read],
            value: nil,
            permissions: [.readable]
        )
        self.rxCharacteristic = rx

        let service = CBMutableService(type: Self.sharedServiceUUID, primary: true)
        service.characteristics = [tx, rx]

        peripheralManager.removeAllServices()
        peripheralManager.add(service)

        let advertisementData: [String: Any] = [
            CBAdvertisementDataServiceUUIDsKey: [Self.sharedServiceUUID],
            CBAdvertisementDataLocalNameKey: "OFFGRID-Node"
        ]
        peripheralManager.startAdvertising(advertisementData)
        print("[BLE] Started advertising OFFGRID GATT service")
    }
}

extension BLEManager: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            print("[BLE Central] Powered ON, scanning for OFFGRID peers...")
            central.scanForPeripherals(withServices: [Self.sharedServiceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        } else {
            print("[BLE Central] State: \(central.state.rawValue)")
        }
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        discoveredPeripherals[peripheral.identifier] = peripheral
        let peer = DiscoveredPeer(
            id: peripheral.identifier.uuidString,
            displayName: peripheral.name ?? "Android/BLE Peer",
            transportType: .bluetooth,
            isConnected: false
        )
        delegate?.didDiscoverPeer(peer)
    }
}

extension BLEManager: CBPeripheralManagerDelegate {
    public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if peripheral.state == .poweredOn {
            setupPeripheralService()
        }
    }

    public func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            if let data = request.value {
                delegate?.didReceivePacketData(data, from: "BLE-Remote", transport: .bluetooth)
                peripheral.respond(to: request, withResult: .success)
            }
        }
    }
}

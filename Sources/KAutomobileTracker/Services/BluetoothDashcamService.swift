import Combine
import CoreBluetooth
import Foundation

struct DiscoveredPeripheral: Identifiable, Hashable {
    let id: UUID
    let name: String
    let rssi: Int
}

/// Links to a dashcam over Bluetooth Low Energy. Video is not carried over BLE; pairing indicates
/// the active dashcam for trip metadata. Import recorded files from the camera’s storage when needed.
@MainActor
final class BluetoothDashcamService: NSObject, ObservableObject {
    @Published private(set) var bluetoothState: CBManagerState = .unknown
    @Published private(set) var discovered: [DiscoveredPeripheral] = []
    @Published private(set) var connectedPeripheralName: String?
    @Published private(set) var statusMessage: String = "Bluetooth idle."

    private var central: CBCentralManager!
    private var connected: CBPeripheral?
    private var peripheralCache: [UUID: CBPeripheral] = [:]

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionShowPowerAlertKey: true])
    }

    func startScanning() {
        guard central.state == .poweredOn else {
            statusMessage = "Turn on Bluetooth to scan for dashcams."
            return
        }
        discovered = []
        statusMessage = "Scanning for peripherals…"
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func stopScanning() {
        central.stopScan()
        if connected == nil {
            statusMessage = "Scan stopped."
        }
    }

    func connect(to id: UUID) {
        guard let peripheral = peripheralCache[id] ?? central.retrievePeripherals(withIdentifiers: [id]).first else {
            statusMessage = "Could not resolve peripheral."
            return
        }
        stopScanning()
        statusMessage = "Connecting…"
        connected = peripheral
        peripheral.delegate = self
        central.connect(peripheral, options: nil)
    }

    func disconnect() {
        if let p = connected {
            central.cancelPeripheralConnection(p)
        }
        connected = nil
        connectedPeripheralName = nil
        statusMessage = "Disconnected."
    }
}

extension BluetoothDashcamService: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            bluetoothState = central.state
            switch central.state {
            case .poweredOn:
                statusMessage = "Bluetooth on. You can scan for your dashcam."
            case .poweredOff:
                statusMessage = "Bluetooth is off."
            case .unauthorized:
                statusMessage = "Bluetooth permission required in System Settings."
            default:
                break
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        Task { @MainActor in
            peripheralCache[peripheral.identifier] = peripheral
            let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "Unnamed"
            let item = DiscoveredPeripheral(id: peripheral.identifier, name: name, rssi: RSSI.intValue)
            if !discovered.contains(where: { $0.id == item.id }) {
                discovered.append(item)
                discovered.sort { $0.rssi > $1.rssi }
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            connectedPeripheralName = peripheral.name ?? "Connected device"
            statusMessage = "Linked to \(connectedPeripheralName ?? "dashcam"). Import video files for analysis."
            peripheral.discoverServices(nil)
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        Task { @MainActor in
            statusMessage = error?.localizedDescription ?? "Connection failed."
            connected = nil
            connectedPeripheralName = nil
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        Task { @MainActor in
            connectedPeripheralName = nil
            connected = nil
            statusMessage = error?.localizedDescription ?? "Disconnected from dashcam."
        }
    }
}

extension BluetoothDashcamService: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        // Services vary by manufacturer; connection alone marks the linked dashcam for this trip.
    }
}

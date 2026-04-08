import Combine
import CoreBluetooth
import Foundation

public struct DiscoveredPeripheral: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public let rssi: Int

    public init(id: UUID, name: String, rssi: Int) {
        self.id = id
        self.name = name
        self.rssi = rssi
    }
}

@MainActor
public final class BluetoothDashcamService: NSObject, ObservableObject {
    @Published public private(set) var bluetoothState: CBManagerState = .unknown
    @Published public private(set) var discovered: [DiscoveredPeripheral] = []
    @Published public private(set) var connectedPeripheralName: String?
    @Published public private(set) var statusMessage: String = "Bluetooth idle."

    private var central: CBCentralManager!
    private var connected: CBPeripheral?
    private var peripheralCache: [UUID: CBPeripheral] = [:]

    public override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionShowPowerAlertKey: true])
    }

    public func startScanning() {
        guard central.state == .poweredOn else {
            statusMessage = "Turn on Bluetooth to scan for dashcams."
            return
        }
        discovered = []
        statusMessage = "Scanning for peripherals…"
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        AppLog.bluetooth.debug("Started BLE scan")
    }

    public func stopScanning() {
        central.stopScan()
        if connected == nil {
            statusMessage = "Scan stopped."
        }
    }

    public func connect(to id: UUID) {
        guard let peripheral = peripheralCache[id] ?? central.retrievePeripherals(withIdentifiers: [id]).first else {
            statusMessage = "Could not resolve peripheral."
            AppLog.bluetooth.notice("Connect failed: unknown peripheral id")
            return
        }
        stopScanning()
        statusMessage = "Connecting…"
        connected = peripheral
        peripheral.delegate = self
        central.connect(peripheral, options: nil)
    }

    public func disconnect() {
        if let p = connected {
            central.cancelPeripheralConnection(p)
        }
        connected = nil
        connectedPeripheralName = nil
        statusMessage = "Disconnected."
    }
}

extension BluetoothDashcamService: CBCentralManagerDelegate {
    nonisolated public func centralManagerDidUpdateState(_ central: CBCentralManager) {
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

    nonisolated public func centralManager(
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

    nonisolated public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            connectedPeripheralName = peripheral.name ?? "Connected device"
            statusMessage = "Linked to \(connectedPeripheralName ?? "dashcam"). Import video files for analysis."
            AppLog.bluetooth.info("Connected peripheral \(self.connectedPeripheralName ?? "")")
            peripheral.discoverServices(nil)
        }
    }

    nonisolated public func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        Task { @MainActor in
            statusMessage = error?.localizedDescription ?? "Connection failed."
            AppLog.bluetooth.error("Connect failed: \(error?.localizedDescription ?? "unknown")")
            connected = nil
            connectedPeripheralName = nil
        }
    }

    nonisolated public func centralManager(
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
    nonisolated public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {}
}

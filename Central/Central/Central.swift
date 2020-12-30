//
//  ViewController.swift
//  Central
//
//  Created by Gregory Williams on 12/23/20.
//

import UIKit
import CoreBluetooth
import os
import Sodium

struct MailboxService {
    static let serviceUUID = CBUUID(string: "E20A39F4-73F5-4BC4-A12F-17D1AD07A961")
    static let characteristicUUID = CBUUID(string: "08590F7E-DB05-467E-8757-72F6FAEB13D4")
    static let mailboxID = CBUUID(string: "11111111-DB05-467E-8757-72F6FAEB13D4")
}

protocol CentralBlueToothEvent {
    func Authenicate()
    func Event(message: Message)
    func Report(status: String)
}

class Central: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    
    var delegate: CentralBlueToothEvent?
    var RSSIDistance: Int = -50
    
    var mailBoxPublicKey: Box.PublicKey?
    let phoneKeyPair = sodium.box.keyPair()!
    
    var centralManager: CBCentralManager!

    var discoveredPeripheral: CBPeripheral?
    var messageCharacteristic: CBCharacteristic?
    var writeIterationsComplete = 0
    var connectionIterationsComplete = 0
    var defaultIterations = 5
    
    static let EOM = Data([69,79,77])
    static var data = Data()
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionShowPowerAlertKey: true])
    }

    deinit {
        // Don't keep it going while we're not showing.
        centralManager.stopScan()
        delegate?.Report(status: "Scanning stopped")
        os_log("Scanning stopped")

        Central.data.removeAll(keepingCapacity: false)
        
    }
    
    /*
     * We will first check if we are already connected to our counterpart
     * Otherwise, scan for peripherals - specifically for our service's 128bit CBUUID
     */
    private func retrievePeripheral() {
        
        let connectedPeripherals: [CBPeripheral] = (centralManager.retrieveConnectedPeripherals(withServices: [MailboxService.serviceUUID]))
        
        delegate?.Report(status: String(format: "Found connected Peripherals with transfer service: %@", connectedPeripherals))
        os_log("Found connected Peripherals with transfer service: %@", connectedPeripherals)
        
        if let connectedPeripheral = connectedPeripherals.last {
            delegate?.Report(status: String(format: "Connecting to peripheral %@", connectedPeripheral))
            os_log("Connecting to peripheral %@", connectedPeripheral)
            self.discoveredPeripheral = connectedPeripheral
            centralManager.connect(connectedPeripheral, options: nil)
        } else {
            // We were not connected to our counterpart, so start scanning
            centralManager.scanForPeripherals(withServices: [MailboxService.serviceUUID, MailboxService.mailboxID],
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        }
    }
    
    /*
     *  Call this when things either go wrong, or you're done with the connection.
     *  This cancels any subscriptions if there are any, or straight disconnects if not.
     *  (didUpdateNotificationStateForCharacteristic will cancel the connection if a subscription is involved)
     */
    func cleanup() {
        // Don't do anything if we're not connected
        guard let discoveredPeripheral = discoveredPeripheral,
            case .connected = discoveredPeripheral.state else { return }
        
        for service in (discoveredPeripheral.services ?? [] as [CBService]) {
            for characteristic in (service.characteristics ?? [] as [CBCharacteristic]) {
                if characteristic.uuid == MailboxService.characteristicUUID && characteristic.isNotifying {
                    // It is notifying, so unsubscribe
                    self.discoveredPeripheral?.setNotifyValue(false, for: characteristic)
                }
            }
        }
        
        // If we've gotten this far, we're connected, but we're not subscribed, so we just disconnect
        centralManager.cancelPeripheralConnection(discoveredPeripheral)
    }
    
    /*
     *  centralManagerDidUpdateState is a required protocol method.
     *  Usually, you'd check for other states to make sure the current device supports LE, is powered on, etc.
     *  In this instance, we're just using it to wait for CBCentralManagerStatePoweredOn, which indicates
     *  the Central is ready to be used.
     */
    internal func centralManagerDidUpdateState(_ central: CBCentralManager) {

        switch central.state {
        case .poweredOn:
            // ... so start working with the peripheral
            os_log("CBManager is powered on")
            retrievePeripheral()
        case .poweredOff:
            os_log("CBManager is not powered on")
            // In a real app, you'd deal with all the states accordingly
            return
        case .resetting:
            os_log("CfBManager is resetting")
            // In a real app, you'd deal with all the states accordingly
            return
        case .unauthorized:
            // In a real app, you'd deal with all the states accordingly
            if #available(iOS 13.0, *) {
                switch central.authorization {
                case .denied:
                    os_log("You are not authorized to use Bluetooth")
                case .restricted:
                    os_log("Bluetooth is restricted")
                default:
                    os_log("Unexpected authorization")
                }
            } else {
                // Fallback on earlier versions
            }
            return
        case .unknown:
            os_log("CBManager state is unknown")
            // In a real app, you'd deal with all the states accordingly
            return
        case .unsupported:
            os_log("Bluetooth is not supported on this device")
            // In a real app, you'd deal with all the states accordingly
            return
        @unknown default:
            os_log("A previously unknown central manager state occurred")
            // In a real app, you'd deal with yet unknown cases that might occur in the future
            return
        }
    }

    /*
     *  This callback comes whenever a peripheral that is advertising the transfer serviceUUID is discovered.
     *  We check the RSSI, to make sure it's close enough that we're interested in it, and if it is,
     *  we start the connection process
     */
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        
        // Reject if the signal strength is too low to attempt data transfer.
        // Change the minimum RSSI value depending on your app’s use case.
        guard RSSI.intValue >= RSSIDistance
            else {
                delegate?.Report(status: String(format: "Discovered perhiperal not in expected range, at %d", RSSI.intValue))
                os_log("Discovered perhiperal not in expected range, at %d", RSSI.intValue)
                return
        }
        
        os_log("Discovered %s at %d", String(describing: peripheral.name), RSSI.intValue)
        delegate?.Report(status: String(format: "Discovered %s at %d", String(describing: peripheral.name), RSSI.intValue))
        
        // Device is in range - have we already seen it?
        if discoveredPeripheral != peripheral {
            
            // Save a local copy of the peripheral, so CoreBluetooth doesn't get rid of it.
            discoveredPeripheral = peripheral
            
            // And finally, connect to the peripheral.
            os_log("Connecting to perhiperal %@", peripheral)
            delegate?.Report(status: String(format: "Connecting to perhiperal %@", peripheral))
            centralManager.connect(peripheral, options: nil)
        }
    }

    /*
     *  If the connection fails for whatever reason, we need to deal with it.
     */
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        delegate?.Report(status: String(format: "Failed to connect to %@. %s", peripheral, String(describing: error)))
        os_log("Failed to connect to %@. %s", peripheral, String(describing: error))
        cleanup()
    }
    
    /*
     *  We've connected to the peripheral, now we need to discover the services and characteristics to find the 'transfer' characteristic.
     */
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        
        //self.ConnectedLbl.text = "Connected To Mailbox: true"
        
        delegate?.Report(status: "Peripheral Connected")
        os_log("Peripheral Connected")
        
        // Stop scanning
        centralManager.stopScan()
        delegate?.Report(status: "Scanning stopped")
        os_log("Scanning stopped")
        
        // set iteration info
        connectionIterationsComplete += 1
        writeIterationsComplete = 0
        
        // Clear the data that we may already have
        Central.data.removeAll(keepingCapacity: false)
        
        // Make sure we get the discovery callbacks
        peripheral.delegate = self
        
        // Search only for services that match our UUID
        peripheral.discoverServices([MailboxService.serviceUUID, MailboxService.mailboxID])
    }
    
    /*
     *  Once the disconnection happens, we need to clean up our local copy of the peripheral
     */
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        delegate?.Report(status: "Perhiperal Disconnected")
        os_log("Perhiperal Disconnected")
        discoveredPeripheral = nil
        
        // We're disconnected, so start scanning again
        if connectionIterationsComplete < defaultIterations {
            retrievePeripheral()
        } else {
            delegate?.Report(status: "Connection iterations completed")
            os_log("Connection iterations completed")
        }
    }

    // implementations of the CBPeripheralDelegate methods

    /*
     *  The peripheral letting us know when services have been invalidated.
     */
    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        for service in invalidatedServices where service.uuid == MailboxService.serviceUUID {
            delegate?.Report(status: "Transfer service is invalidated - rediscover services")
            os_log("Transfer service is invalidated - rediscover services")
            peripheral.discoverServices([MailboxService.serviceUUID])
        }
    }

    /*
     *  The Transfer Service was discovered
     */
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            os_log("Error discovering services: %s", error.localizedDescription)
            delegate?.Report(status: String(format: "Error discovering services: %s", error.localizedDescription))
            cleanup()
            return
        }
        
        // Discover the characteristic we want...
        
        // Loop through the newly filled peripheral.services array, just in case there's more than one.
        guard let peripheralServices = peripheral.services else { return }
        for service in peripheralServices {
            peripheral.discoverCharacteristics([MailboxService.characteristicUUID], for: service)
        }
    }
    
    /*
     *  The Transfer characteristic was discovered.
     *  Once this has been found, we want to subscribe to it, which lets the peripheral know we want the data it contains
     */
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        // Deal with errors (if any).
        if let error = error {
            delegate?.Report(status: String(format: "Error discovering characteristics: %s", error.localizedDescription))
            os_log("Error discovering characteristics: %s", error.localizedDescription)
            cleanup()
            return
        }
        
        // Again, we loop through the array, just in case and check if it's the right one
        guard let serviceCharacteristics = service.characteristics else { return }
        for characteristic in serviceCharacteristics where characteristic.uuid == MailboxService.characteristicUUID {
            // If it is, subscribe to it
            messageCharacteristic = characteristic
            peripheral.setNotifyValue(true, for: characteristic)
        }
        
        // Once this is complete, we just need to wait for the data to come in.
    }
    
    /*
     *   This callback lets us know more data has arrived via notification on the characteristic
     */
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        // Deal with errors (if any)
        if let error = error {
            os_log("Error discovering characteristics: %s", error.localizedDescription)
            cleanup()
            return
        }
        
        guard let characteristicData = characteristic.value else { return }
        
        //os_log("Received %d bytes: %s", characteristicData.count, stringFromData)
        
        // Have we received the end-of-message token?
        if characteristicData == Central.EOM {
            let message = decryptMessage(encryptedMessage: Central.data, publicKey: theirPublicKey ?? [UInt8](), secretKey: myKey?.secretKey ?? [UInt8]())
            self.delegate?.Event(message: message)
            Central.data = Data()
            Central.sendDataIndex = 0
        } else {
            // Otherwise, just append the data to what we have previously received.
            Central.data.append(characteristicData)
        }
    }

    /*
     *  The peripheral letting us know whether our subscribe/unsubscribe happened or not
     */
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        // Deal with errors (if any)
        if let error = error {
            os_log("Error changing notification state: %s", error.localizedDescription)
            return
        }
        
        // Exit if it's not the transfer characteristic
        guard characteristic.uuid == MailboxService.characteristicUUID else { return }
        
        if characteristic.isNotifying {
            // Notification has started
            os_log("Notification began on %@", characteristic)
            delegate?.Authenicate()
        } else {
            // Notification has stopped, so disconnect from the peripheral
            os_log("Notification stopped on %@. Disconnecting", characteristic)
            cleanup()
        }
        
    }
    
    /*
    func sendData(data: Data) {
        let mtu = discoveredPeripheral!.maximumWriteValueLength (for: .withoutResponse)
        var rawPacket = [UInt8]()
                    
        let bytesToCopy: size_t = min(mtu, data.count)
        data.copyBytes(to: &rawPacket, count: bytesToCopy)
        let packetData = Data(bytes: &rawPacket, count: bytesToCopy)
        
        let stringFromData = String(data: packetData, encoding: .utf8)
        os_log("Writing %d bytes: %s", bytesToCopy, String(describing: stringFromData))
        
        discoveredPeripheral!.writeValue(packetData, for: messageCharacteristic!, type: .withoutResponse)
    }
    */
        
    /*
     *  Write some test data to peripheral
     */
    func sendMessage(message messageType: Message, encrpytion: EncryptionType) {
        
        let message = MessageStruct(encryptionType: encrpytion, message: messageType)
        
        guard let data2 = encryptMessage(message: message, publicKey: theirPublicKey ?? [UInt8](), secretKey: myKey?.secretKey ?? [UInt8]())
        else { return }
        
        Central.data = Data(data2)
        Central.sendingData = true
        self.sendData()
        
        //discoveredPeripheral!.setNotifyValue(false, for: messageCharacteristic!)
        /*
        if writeIterationsComplete == defaultIterations {
            // Cancel our subscription to the characteristic
        }
        */
    }

    static var sendingEOM = false
    static var sendDataIndex = 0
    static var sendingData = false
    
    private func sendData() {
        
        guard messageCharacteristic != nil else {
           return
        }
        
        // We're not sending an EOM, so we're sending data
        // Is there any left to send?
        if Central.sendDataIndex >= Central.data.count {
           // No data left.  Do nothing
           if Central.sendingData {
              Central.sendingEOM = true
           } else {
              Central.sendingData = false
              return
           }
        }
                
        // First up, check if we're meant to be sending an EOM
        if Central.sendingEOM {
            // send it
            discoveredPeripheral!.writeValue(Central.EOM, for: messageCharacteristic!, type: .withResponse)
            Central.sendingEOM = false
            Central.data = Data()
            Central.sendDataIndex = 0
            Central.sendingData = false
            return
        }
        
        if !Central.sendingData {
            return
        }
        
        // Work out how big it should be
        var amountToSend = Central.data.count - Central.sendDataIndex
        let mtu = discoveredPeripheral!.maximumWriteValueLength (for: .withResponse)
        amountToSend = min(amountToSend, mtu)
            
        // Copy out the data we want
        let chunk = Central.data.subdata(in: Central.sendDataIndex..<(Central.sendDataIndex + amountToSend))
        
        // Send it
        discoveredPeripheral!.writeValue(chunk, for: messageCharacteristic!, type: .withResponse)
        
        let stringFromData = String(data: chunk, encoding: .utf8)
        os_log("Sent %d bytes: %s", chunk.count, String(describing: stringFromData))
        
        // It did send, so update our index
        Central.sendDataIndex += amountToSend
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if error == nil {
            sendData()
        } else {
            Central.sendingData = false
            Central.sendDataIndex = 0
            Central.data = Data()
        }
    }
        
}

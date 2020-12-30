//
//  ViewController.swift
//  MailBox
//
//  Created by Gregory Williams on 12/23/20.
//

import UIKit
import CoreBluetooth
import os
import Sodium

protocol PeripheralBlueToothEvent {
    func Event(message: Message) -> MessageStruct
    func Report(status: String)
}

class Peripheral: NSObject, CBPeripheralManagerDelegate {
    
    var isLocked = false

    var delegate: PeripheralBlueToothEvent?
    
    var peripheralManager: CBPeripheralManager!

    var messageCharacteristic: CBMutableCharacteristic?
    var connectedCentral: CBCentral?
    
    static var dataToSend = Data()
    static var sendDataIndex: Int = 0
    static var sendingEOM = false
    static let EOM = Data([69,79,77])
    
    override init() {
        super.init()
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil, options: [CBPeripheralManagerOptionShowPowerAlertKey: true])
    }
    
    /*
     *  Required protocol method.  A full app should take care of all the possible states,
     *  but we're just waiting for to know when the CBPeripheralManager is ready
     *
     *  Starting from iOS 13.0, if the state is CBManagerStateUnauthorized, you
     *  are also required to check for the authorization state of the peripheral to ensure that
     *  your app is allowed to use bluetooth
     */
    internal func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        
        switch peripheral.state {
        case .poweredOn:
            // ... so start working with the peripheral
            delegate?.Report(status: "CBManager is powered on")
            setupPeripheral()
            delegate?.Report(status: "CBManager startAd")
            peripheralManager.startAdvertising([CBAdvertisementDataLocalNameKey : "Mailbox", CBAdvertisementDataServiceUUIDsKey: [MailboxService.serviceUUID, MailboxService.mailboxID]])
            delegate?.Report(status: "CBManager currently Ad")
        case .poweredOff:
            delegate?.Report(status: "CBManager is not powered on")
            return
        case .resetting:
            delegate?.Report(status: "CBManager is resetting")
            return
        case .unauthorized:
            
            if #available(iOS 13.0, *) {
                switch peripheral.authorization {
                case .denied:
                    delegate?.Report(status: "You are not authorized to use Bluetooth")
                case .restricted:
                    delegate?.Report(status: "Bluetooth is restricted")
                default:
                    delegate?.Report(status: "Unexpected authorization")
                }
            } else {
                // Fallback on earlier versions
            }
            return
        case .unknown:
            delegate?.Report(status: "CBManager state is unknown")
            return
        case .unsupported:
            delegate?.Report(status: "Bluetooth is not supported on this device")
            return
        @unknown default:
            delegate?.Report(status: "A previously unknown peripheral manager state occurred")
            return
        }
    }
    
    private func setupPeripheral() {
        
        delegate?.Report(status: "setup")
        
        // Build our service.
        
        // Start with the CBMutableCharacteristic.
        let isLockedCharacteristic = CBMutableCharacteristic(type: MailboxService.characteristicUUID,
                                                             properties: [.notify, .write], //.writeWithoutResponse],
                                                         value: nil,
                                                         permissions: [.readable, .writeable])
        
        // Create a service from the characteristic.
        let mailboxService = CBMutableService(type: MailboxService.serviceUUID, primary: true)
        
        // Add the characteristic to the service.
        mailboxService.characteristics = [isLockedCharacteristic]
        
        // And add it to the peripheral manager.
        peripheralManager.add(mailboxService)
        
        // Save the characteristic for later.
        self.messageCharacteristic = isLockedCharacteristic

        delegate?.Report(status: "finished setup")
    }
        
    /*
     *  Catch when someone subscribes to our characteristic, then start sending them data
     */
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        delegate?.Report(status: "Central subscribed to characteristic")
        
        // Reset the index
        Peripheral.sendDataIndex = 0
        
        // save central
        connectedCentral = central
    }
    
    /*
     *  Recognize when the central unsubscribes
     */
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        delegate?.Report(status: "Central unsubscribed from characteristic")
        connectedCentral = nil
    }
    
    /*
     *  This callback comes in when the PeripheralManager is ready to send the next chunk of data.
     *  This is to ensure that packets will arrive in the order they are sent
     */
    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        // Start sending again
        sendData()
    }
        
    /*
     * This callback comes in when the PeripheralManager received write to characteristics
     */
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for aRequest in requests {
            guard let requestValue = aRequest.value
            else {
                continue
            }
            self.peripheralManager.respond(to: aRequest, withResult: CBATTError.success)
            if requestValue == Peripheral.EOM {
                processData(result: Peripheral.dataToSend)
            } else {
                Peripheral.dataToSend.append(requestValue)
            }
        }
    }
    
    func processData(result: Data) {
        let message = decryptMessage(encryptedMessage: Data(result), publicKey: theirPublicKey ?? [UInt8](), secretKey: myKey?.secretKey ?? [UInt8]())
        guard let response = delegate?.Event(message: message) else { return }
        Peripheral.dataToSend = Data(encryptMessage(message: response, publicKey: theirPublicKey ?? [UInt8](), secretKey: myKey?.secretKey ?? [UInt8]())!)
        sendData()
    }
    
    private func sendData() {
        
        guard let messageCharacteristic = messageCharacteristic else {
            return
        }
        
        // First up, check if we're meant to be sending an EOM
        if Peripheral.sendingEOM {
            // send it
            let didSend = peripheralManager.updateValue("EOM".data(using: .utf8)!, for: messageCharacteristic, onSubscribedCentrals: nil)
            // Did it send?
            if didSend {
                // It did, so mark it as sent
                Peripheral.sendingEOM = false
                delegate?.Report(status: "Sent: EOM")
                Peripheral.dataToSend = Data()
                Peripheral.sendDataIndex = 0

            }
            // It didn't send, so we'll exit and wait for peripheralManagerIsReadyToUpdateSubscribers to call sendData again
            return
        }
        
        // We're not sending an EOM, so we're sending data
        // Is there any left to send?
        if Peripheral.sendDataIndex >= Peripheral.dataToSend.count {
            // No data left.  Do nothing
            return
        }
        
        // There's data left, so send until the callback fails, or we're done.
        var didSend = true
        //Peripheral.sendDataIndex = 0
        while didSend {
            
            // Work out how big it should be
            var amountToSend = Peripheral.dataToSend.count - Peripheral.sendDataIndex
            if let mtu = connectedCentral?.maximumUpdateValueLength {
                amountToSend = min(amountToSend, mtu)
            }
            
            // Copy out the data we want
            let chunk = Peripheral.dataToSend.subdata(in: Peripheral.sendDataIndex..<(Peripheral.sendDataIndex + amountToSend))
            
            // Send it
            didSend = peripheralManager.updateValue(chunk, for: messageCharacteristic, onSubscribedCentrals: nil)
            
            // If it didn't work, drop out and wait for the callback
            if !didSend {
                return
            }
            
            let stringFromData = String(data: chunk, encoding: .utf8)
            os_log("Sent %d bytes: %s", chunk.count, String(describing: stringFromData))
            
            // It did send, so update our index
            Peripheral.sendDataIndex += amountToSend
            // Was it the last one?
            if Peripheral.sendDataIndex >= Peripheral.dataToSend.count {
                // It was - send an EOM
                
                // Set this so if the send fails, we'll send it next time
                Peripheral.sendingEOM = true
                
                //Send it
                let eomSent = peripheralManager.updateValue(Peripheral.EOM,
                                                             for: messageCharacteristic, onSubscribedCentrals: nil)
                
                if eomSent {
                    // It sent; we're all done
                    Peripheral.sendingEOM = false
                    delegate?.Report(status: "Sent: EOM")
                    Peripheral.dataToSend = Data()
                    Peripheral.sendDataIndex = 0
                }
                return
            }
        }
    }
}


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

struct MailboxService {
    static let serviceUUID = CBUUID(string: "E20A39F4-73F5-4BC4-A12F-17D1AD07A961")
    static let characteristicUUID = CBUUID(string: "08590F7E-DB05-467E-8757-72F6FAEB13D4")
    static let mailboxID = CBUUID(string: "11111111-DB05-467E-8757-72F6FAEB13D4")
}

var myKey: Box.KeyPair?
var theirPublicKey: Box.PublicKey?

class PeripheralViewController: UIViewController, PeripheralBlueToothEvent {

    @IBOutlet weak var textView: UITextView!
    var isLocked = false
    var peripheral = Peripheral()
    var sodium = Sodium()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        peripheral.delegate = self
    }
    
    func addStatus(status: String) {
        textView.text.append("\(status)\n")
    }
    
    func Report(status: String) {
        addStatus(status: status)
    }
    
    func Event(message: Message) -> MessageStruct {
        var response: MessageStruct
        switch message {
        case .SendMyPublicKey(let publicKey, let UserID):
            theirPublicKey = publicKey
            
            UserDefaults.standard.reset()
            myKey = sodium.box.keyPair()
            UserDefaults.standard.set(myKey?.publicKey, forKey: "publicKey")
            UserDefaults.standard.set(myKey?.secretKey, forKey: "secretKey")
            UserDefaults.standard.set(publicKey, forKey: UserID)

            addStatus(status: "Registered Public Keys")
            addStatus(status: "   My Public Key: \(String(describing: myKey?.publicKey))")
            addStatus(status: "   My Secret Key: \(String(describing: myKey?.secretKey))")
            addStatus(status: "   Their Public Key: \(theirPublicKey!)")

            response = MessageStruct(encryptionType: .NotEncrypted, message: Message.SendMyPublicKey(publicKey: myKey!.publicKey, userID: ""))
        case .PhoneID(let id):
            addStatus(status: "Phone ID = \(id)")
            if let key = UserDefaults.standard.object(forKey: id) as? Box.PublicKey {
                theirPublicKey = key
                response = MessageStruct(encryptionType: .NotEncrypted, message: Message.connectionStatus(sucessful: true))
            } else {
                response = MessageStruct(encryptionType: .NotEncrypted, message: Message.connectionStatus(sucessful: false))
            }
        case .PhoneMessage(let command):
            var cmd = ""
            switch command {
            case .Lock:
                cmd = "Lock"
                isLocked = true
                response = MessageStruct(encryptionType: .PublicPrivateKey, message: Message.LockMessage(status: LockStatus.Locked))
            case .Unlock:
                cmd = "Unlock"
                isLocked = false
                response = MessageStruct(encryptionType: .PublicPrivateKey, message: Message.LockMessage(status: LockStatus.Unlocked))
            }
            addStatus(status: "Command = \(cmd)")
        default:
            addStatus(status: "Unknown Command")
            response = MessageStruct(encryptionType: .NotEncrypted, message: Message.Error(errorType: .UnknownCommand))
        }
        return response
    }
}

extension UserDefaults {

    enum Keys: String, CaseIterable {

        case publicKey
        case secretKey

    }

    func reset() {
        Keys.allCases.forEach { removeObject(forKey: $0.rawValue) }
    }

}

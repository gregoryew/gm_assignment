//
//  MessageProtocol.swift
//  MailBox
//
//  Created by Gregory Williams on 12/23/20.
//

import Foundation
import Sodium

enum EncryptionType: UInt8, Codable {
    typealias RawValue = UInt8
    case NotEncrypted
    case PublicPrivateKey
}

enum Command: UInt8, Codable {
    typealias RawValue = UInt8
    case Lock
    case Unlock
}

enum LockStatus: UInt8, Codable {
    typealias RawValue = UInt8
    case Locking
    case Locked
    case Unlocking
    case Unlocked
    case Error
}

enum ErrorType: UInt8, Codable {
    typealias RawValue = UInt8
    case DecodeError
    case UnknownCommand
    case CantDecrypt
}

struct MessageStruct: Codable {
    let encryptionType: EncryptionType
    var messageType: Message?
    var messageBytes: Bytes?
    
    init (encryptionType: EncryptionType, message: Message) {
        self.encryptionType = encryptionType
        self.messageType = message
        self.messageBytes = nil
    }

    init (encryptionType: EncryptionType, message: Bytes) {
        self.encryptionType = encryptionType
        self.messageBytes = message
        self.messageType = nil
    }
}

enum Message: Encodable {
    
    case SendMyPublicKey(publicKey: Box.PublicKey, userID: String)
    case PhoneID(id: String)
    case connectionStatus(sucessful: Bool)
    case PhoneMessage(command: Command)
    case LockMessage(status: LockStatus)
    case Error(errorType: ErrorType)
    
    enum CodingKeys: CodingKey {
      case id, command, status, key, errorType, publicKey, userID, successful
    }

    func encode(to encoder: Encoder) throws {
       var container = encoder.container(keyedBy: CodingKeys.self)
       
       switch self {
       case .SendMyPublicKey(let publicKey, let userID):
          try container.encode(publicKey, forKey: .publicKey)
          try container.encode(userID, forKey: .userID)
       case .PhoneID(let id):
          try container.encode(id, forKey: .id)
       case .connectionStatus(let sucessful):
          try container.encode(sucessful, forKey: .successful)
       case .PhoneMessage(let command):
          try container.encode(command, forKey: .command)
       case .LockMessage(let status):
          try container.encode(status, forKey: .status)
       case .Error(let errorType):
          try container.encode(errorType, forKey: .errorType)
       }
    }
}

extension Message: Decodable {
   init(from decoder: Decoder) throws {
     let container = try decoder.container(keyedBy: CodingKeys.self)
     let containerKeys = Set(container.allKeys)
     let MyPublicKeys = Set<CodingKeys>([.publicKey, .userID])
     let PhoneIDKeys = Set<CodingKeys>([.id])
     let ConnectionStatusKeys = Set<CodingKeys>([.successful])
     let PhoneMessageKeys = Set<CodingKeys>([.command])
     let LockMessageKeys = Set<CodingKeys>([.status])
     let ErrorKeys = Set<CodingKeys>([.errorType])
    
     switch containerKeys {
     case MyPublicKeys:
        let phoneKey = try container.decode(Box.PublicKey.self, forKey: .publicKey)
        let userID = try container.decode(String.self, forKey: .userID)
        self = .SendMyPublicKey(publicKey: phoneKey, userID: userID)
     case PhoneIDKeys:
        let id = try container.decode(String.self, forKey: .id)
        self = .PhoneID(id: id)
     case ConnectionStatusKeys:
        let successful = try container.decode(Bool.self, forKey: .successful)
        self = .connectionStatus(sucessful: successful)
     case PhoneMessageKeys:
        let command = try container.decode(Command.self, forKey: .command)
        self = .PhoneMessage(command: command)
     case LockMessageKeys:
        let status = try container.decode(LockStatus.self, forKey: .status)
        self = .LockMessage(status: status)
     case ErrorKeys:
        let errorType = try container.decode(ErrorType.self, forKey: .errorType)
        self = .Error(errorType: errorType)
     default:
        fatalError("Unknown message type")
     }
   }
}


//
//  CentralViewController.swift
//  Central
//
//  Created by Gregory Williams on 12/24/20.
//

import UIKit

//
//  CentralViewController.swift
//  Central
//
//  Created by Gregory Williams on 12/24/20.
//

import UIKit
import Sodium
import CoreLocation
import UserNotifications

var myKey: Box.KeyPair?
var theirPublicKey: Box.PublicKey?
var allownotifications = false

class CentralViewController: UIViewController, CentralBlueToothEvent, CLLocationManagerDelegate {

    var central = Central()
    var locationNotificaton = LocationLocationNotifications()
    var locationManager: CLLocationManager?
    var userCoordinates: CLLocationCoordinate2D?
    
    var isLocked = true
    var isOpen = false
    var isFlagUp = true
    var hasPackage = true
    var authenicated = false
    var connected = false
    var userID = ""
    
    @IBOutlet weak var statusLbl: UILabel!
    @IBOutlet weak var statusLog: UITextView!
    @IBOutlet weak var mailbox: UIImageView!
    @IBOutlet weak var lockedBtn: UIButton!
    @IBOutlet weak var bluetoothConnection: UIButton!
    @IBOutlet weak var flagUp: UIButton!
    @IBOutlet weak var flagDown: UIButton!
    @IBOutlet weak var mailboxDoor: UIButton!
    @IBOutlet weak var package: UIButton!
    @IBOutlet weak var Register: UIButton!
    
    override func viewDidLoad() {
        central = Central()
        
        super.viewDidLoad()
        
        if #available(iOS 13.0, *) {
            NotificationCenter.default.addObserver(self, selector: #selector(willResignActive), name: UIScene.willDeactivateNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(willBecomeActive), name: UIScene.willEnterForegroundNotification, object: nil)
        } else {
            NotificationCenter.default.addObserver(self, selector: #selector(willResignActive), name: UIApplication.willResignActiveNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(willBecomeActive), name: UIApplication.willEnterForegroundNotification, object: nil)
        }
        
        setupApp()
    }

    func setupApp() {
        updateView()
        Register.setTitle("Get Loc", for: .normal)
        locationManager = CLLocationManager()
        locationManager?.delegate = self
        locationManager?.desiredAccuracy = kCLLocationAccuracyBest
        locationManager?.requestAlwaysAuthorization()
        locationNotificaton.requestPermissions()
        central.delegate = self
        central.RSSIDistance = -50
        statusLbl.text = "Peripheral Is Not Connected"
        lockedBtn.isEnabled = false
    }
    
    func Report(status: String) {
        statusLog.text.append("\(status)\n")
        let bottom = NSMakeRange(statusLog.text.count - 1, 1)
        statusLog.scrollRangeToVisible(bottom)
    }
        
    func Authenicate() {
        if !connected {
                        
            connected = true
            
            if let publicKeyArr = UserDefaults.standard.object(forKey: "publicKey") as? Box.PublicKey,
               let secretKeyArr = UserDefaults.standard.object(forKey: "secretKey") as? Box.SecretKey,
               let doorPublicKey = UserDefaults.standard.object(forKey: "doorPublicKey") as? Box.PublicKey,
               let userID = UserDefaults.standard.string(forKey: "userID")
            {
                myKey = Box.KeyPair.init(publicKey: publicKeyArr, secretKey: secretKeyArr)
                theirPublicKey = doorPublicKey
                self.userID = userID
                if !authenicated {central.sendMessage(message: Message.PhoneID(id: userID), encrpytion: .NotEncrypted)}
            } else {
                view.shake()
                Report(status: "Please press register button")
                authenicated = false
            }
            
            updateView()
        }
    }
    
    @objc func willResignActive(_ notification: Notification) {
        if authenicated {
            Report(status: "Went to background")
            central.cleanup()
            authenicated = false
            connected = false
        }
    }

    @objc func willBecomeActive(_ notification: Notification) {
        self.central = Central()
        setupApp()
    }
    
    func updateView() {
        Register.isEnabled = !authenicated
        package.isHidden = !(hasPackage && isOpen)
        flagUp.isHidden = !isFlagUp
        flagDown.isHidden = isFlagUp
        mailbox.image = UIImage(named: isOpen ? "openMailbox" : "closedMailbox")
        bluetoothConnection.setImage(UIImage(named: authenicated ? "bluetooth" : "bluetoothNotConnected"), for: .normal)
        lockedBtn.setImage(UIImage(named: isLocked ? "locked": "unlocked"), for: .normal)
        lockedBtn.isEnabled = authenicated
        
        if !connected {
            statusLbl.text = "Not connected"
        } else if !authenicated {
            statusLbl.text = "Please Register"
        } else if authenicated && isLocked {
            statusLbl.text = "Connected and locked"
        } else if authenicated  && !isLocked {
            statusLbl.text = "Connected and unlocked"
        } else if !isOpen {
            statusLbl.text = "Mailbox connected, unlocked and closed"
        } else if isOpen {
            statusLbl.text = "Mailbox connected, unlocked and open"
        }
    }
    
    func Event(message: Message) {
        switch message {
        case .SendMyPublicKey(let publicKey, let s):
            theirPublicKey = publicKey
            UserDefaults.standard.set(theirPublicKey, forKey: "doorPublicKey")
            Report(status: "Registered Public Keys")
            Report(status: "   My Public Key: \(String(describing: myKey?.publicKey))")
            Report(status: "   My Secret Key: \(String(describing: myKey?.secretKey))")
            Report(status: "   Their Public Key: \(theirPublicKey!)")
            statusLbl.text = "Peripheral Is Connected"
            Authenicate()
        case .connectionStatus(let successful):
            if successful {
                Report(status: "Successfully authenicated")
                authenicated = true
            } else {
                view.shake()
                Report(status: "Introdure Alert")
                authenicated = false
            }
        case .LockMessage(let status):
            Report(status: "Received status of \(status)")
            isLocked = status == .Locked
        case .Error(let errorType):
            Report(status: "Error = \(errorType.rawValue)")
        default:
            Report(status:"Unknown response")
        }
        updateView()
    }
    
    @IBAction func lockButtonTapped(_ sender: Any) {
        if isOpen {
            mailbox.shake()
            flagUp.shake()
            flagDown.shake()
        } else {
            if self.isLocked {
                central.sendMessage(message: Message.PhoneMessage(command: .Unlock), encrpytion: .PublicPrivateKey)
            } else {
                central.sendMessage(message: Message.PhoneMessage(command: .Lock), encrpytion: .PublicPrivateKey)
            }
        }
    }
    
    @IBAction func packageTapped(_ sender: Any) {
        hasPackage = false
        isFlagUp = false
        updateView()
    }
    
    @IBAction func mailboxDoorTapped(_ sender: Any) {
        if !isLocked {
            isOpen = !isOpen
        } else {
            mailbox.shake()
            flagUp.shake()
            flagDown.shake()
        }
        updateView()
    }
    
    @IBAction func upFlagTapped(_ sender: Any) {
        isFlagUp = false
        updateView()
    }
    
    @IBAction func downFlagTapped(_ sender: Any) {
        if isOpen {
            mailbox.shake()
            flagUp.shake()
            flagDown.shake()
        } else {
            isFlagUp = true
            hasPackage = true
        }
        updateView()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let userLocation :CLLocation = locations[0] as CLLocation
        self.userCoordinates = userLocation.coordinate
        locationManager?.stopUpdatingLocation()
        locationManager?.delegate = nil
        Register.setTitle("Register", for: .normal)
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let alert = UIAlertController(title: "Alert",
                                      message: "An error occured while trying to get location information.  The error is \(error)",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Ok", style: .default, handler: nil))
        self.present(alert, animated: true)
    }
    
    func getCooridates() {
        if CLLocationManager.locationServicesEnabled(){
            locationManager?.startUpdatingLocation()
        }
    }
    
    func register() {
        UserDefaults.standard.reset()
        myKey = sodium.box.keyPair()
        UserDefaults.standard.set(myKey?.publicKey, forKey: "publicKey")
        UserDefaults.standard.set(myKey?.secretKey, forKey: "secretKey")
        userID = UUID().uuidString
        UserDefaults.standard.set(userID, forKey: "userID")
        connected = false
        
        if !allownotifications || !CLLocationManager.locationServicesEnabled() {
            let alert = UIAlertController(title: "Alert",
                                          message: "To be notified when you are close to a mailbox turn on notifications and location services in the app settings and press register again.",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Ok", style: .default, handler: nil))
            self.present(alert, animated: true)
        } else {
            locationNotificaton.scheduleLocationNoifications(title: "The mailbox was detected.", subtitle: "Tap to connect", coordinate: userCoordinates!)
        }
        
        central.sendMessage(message: Message.SendMyPublicKey(publicKey: myKey?.publicKey ?? [UInt8](), userID: userID), encrpytion: .NotEncrypted)
    }
    
    @IBAction func RegisterTapped(_ sender: Any) {
        if Register.title(for: .normal) == "Get Loc" {
            getCooridates()
        } else {
            register()
        }
    }
}

public extension UIView {

    func shake(count : Float = 4,for duration : TimeInterval = 0.5,withTranslation translation : Float = 5) {

        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.linear)
        animation.repeatCount = count
        animation.duration = duration/TimeInterval(animation.repeatCount)
        animation.autoreverses = true
        animation.values = [translation, -translation]
        layer.add(animation, forKey: "shake")
    }
}

extension UserDefaults {

    enum Keys: String, CaseIterable {

        case publicKey
        case secretKey
        case doorPublicKey
        case userID

    }

    func reset() {
        Keys.allCases.forEach { removeObject(forKey: $0.rawValue) }
    }

}


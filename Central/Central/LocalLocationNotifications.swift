//
//  LocalLocationNotifications.swift
//  MailBox
//
//  Created by Gregory Williams on 12/29/20.
//

import Foundation
import UserNotifications
import CoreLocation
import UIKit

let CENTRAL_LOCATION_NOTIFICATION_NAME = "central location request name"

class LocationLocationNotifications: NSObject {
    func requestPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { success, error in
            if success {
                allownotifications = true
                print("All set!")
            } else if let error = error {
                allownotifications = false
                print(error.localizedDescription)
            }
        }
    }
    
    func scheduleLocationNoifications(title: String, subtitle: String, coordinate: CLLocationCoordinate2D) {
        
        guard allownotifications else {return}
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = subtitle
        content.sound = UNNotificationSound.default

        let oneMile = Measurement(value: 1, unit: UnitLength.miles)
        let radius = oneMile.converted(to: .meters).value
        let region = CLCircularRegion(center: coordinate,
                                      radius: radius,
                                      identifier: UUID().uuidString)

        region.notifyOnExit = false
        region.notifyOnEntry = true

        let trigger = UNLocationNotificationTrigger(region: region,
                                                    repeats: true)

        let request = UNNotificationRequest(identifier: CENTRAL_LOCATION_NOTIFICATION_NAME, content: content, trigger: trigger)

        // add our notification request
        UNUserNotificationCenter.current().add(request)
    }
}


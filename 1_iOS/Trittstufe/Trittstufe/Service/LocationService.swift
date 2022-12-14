//
//  LocationService.swift
//  Trittstufe
//
//  Created by Niklas Schildhauer on 17.04.22.
//

import Foundation
import CoreLocation
import UIKit

/// Delegate which informs when the user has granted or denied the location permissions.
protocol LocationServiceStatusDelegate {
    func didChangeStatus(in service: LocationService)
}

/// Delegate which informs about beacons in the area
protocol LocationServiceDelegate {
    func didFail(with error: String, in service: LocationService)
    func didRangeNothing(in service: LocationService)
    func didRangeCar(car: CarIdentification, step: CarStepIdentification, with proximity: CLProximity, meters: Double, in service: LocationService)
}

/// LocationService
/// Uses the CLLocationManager to locate iBeacons. If permissions are granted it starts monitoring. If
class LocationService: NSObject {
    
    private let locationManager = CLLocationManager()
    
    private var beaconConstraints = [CLBeaconIdentityConstraint: [CLBeacon]]()
    private var beacons = [CLProximity: [CLBeacon]]()
    private var nothingRangedCount = 0
    
    var statusDelegate: LocationServiceStatusDelegate?
    var delegate: LocationServiceDelegate?
    
    var clientConfiguration: ClientConfiguration?
    
    enum LocationPermission {
        case granted
        case denied
        case notDetermined
    }
    
    override init() {
        super.init()
        
        locationManager.delegate = self
    }
    
    func startMonitoring() {
        guard let clientConfiguration = clientConfiguration,
        let carUUID = clientConfiguration.carIdentification.uuid else {
            return
        }
        
        /// Create beacon regions for every step in the client configuration
        for step in clientConfiguration.carIdentification.stepIdentifications {
            /// Create a new constraint and add it to the dictionary.
            let constraint = CLBeaconIdentityConstraint(uuid: carUUID, major: CLBeaconMajorValue(step.rawValue))
            self.beaconConstraints[constraint] = []
            
            
            ///By monitoring for the beacon before ranging, the app is more energy efficient if the beacon is not immediately observable.
            let beaconRegion = CLBeaconRegion(beaconIdentityConstraint: constraint, identifier: "\(clientConfiguration.carIdentification.id)\(step.rawValue)")
            self.locationManager.startMonitoring(for: beaconRegion)
        }
    }
    
    func stopMonitoring() {
        /// Stop monitoring when the view disappears.
        for region in locationManager.monitoredRegions {
            locationManager.stopMonitoring(for: region)
        }
        
        /// Stop ranging when the view disappears.
        for constraint in beaconConstraints.keys {
            locationManager.stopRangingBeacons(satisfying: constraint)
        }
    }
    
    func requestAuthorization() {
        locationManager.requestAlwaysAuthorization()
    }
    
    func permissionStatus() -> LocationPermission {
        if CLLocationManager.locationServicesEnabled() {
            switch locationManager.authorizationStatus {
            case .notDetermined:
                return .notDetermined
            case .restricted, .denied:
                return .denied
            case .authorizedAlways, .authorizedWhenInUse:
                return .granted
            @unknown default:
                break
            }
        }
        return .notDetermined
    }
    
}

/// Implements the CLLocationManagerDelegate
extension LocationService: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        statusDelegate?.didChangeStatus(in: self)
    }
    
    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        delegate?.didFail(with: "Failed monitoring region: \(error.localizedDescription)", in: self)
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        delegate?.didFail(with:"Location manager failed: \(error.localizedDescription)", in: self)
    }
    
    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        let beaconRegion = region as? CLBeaconRegion
        if state == .inside {
            /// Start ranging when inside a region.
            manager.startRangingBeacons(satisfying: beaconRegion!.beaconIdentityConstraint)
        } else {
            /// Stop ranging when not inside a region.
            manager.stopRangingBeacons(satisfying: beaconRegion!.beaconIdentityConstraint)
        }
    }
    
    /// Is called when a iBeacon is ranged
    func locationManager(_ manager: CLLocationManager, didRange beacons: [CLBeacon], satisfying beaconConstraint: CLBeaconIdentityConstraint) {
        
        ///Beacons are categorized by proximity. A beacon can satisfy multiple constraints and can be displayed multiple times.
        beaconConstraints[beaconConstraint] = beacons
        
        self.beacons.removeAll()
        
        var allBeacons = [CLBeacon]()
        
        for regionResult in beaconConstraints.values {
            allBeacons.append(contentsOf: regionResult)
        }
        
        /// Sort the beacons which are ranged and add them to the beacons collection
        for range in [CLProximity.unknown, .immediate, .near, .far] {
            let proximityBeacons = allBeacons.filter { $0.proximity == range }
            if !proximityBeacons.isEmpty {
                self.beacons[range] = proximityBeacons
            }
        }
        
        /// Returns the clossest beacon and informs the delegate about it.
        if let closestBeacon = getClosestBeacon(beacons: allBeacons),
           let car = clientConfiguration?.carIdentification,
           let step = getCarStepFor(beacon: closestBeacon, car: car) {
            nothingRangedCount = 0
            delegate?.didRangeCar(car: car, step: step, with: closestBeacon.proximity, meters: closestBeacon.accuracy, in: self)
        } else {
            /// No suiteable iBeacon was ranged. Then a coutner is counted up. Should it come to the point that 10 times nothing was found, via the delegate it will be informed that the previous results have become invalid.
            nothingRangedCount = nothingRangedCount + 1
            if nothingRangedCount > 10 {
                delegate?.didRangeNothing(in: self)
            }
        }
    }
    
    private func getClosestBeacon(beacons: [CLBeacon]) -> CLBeacon? {
        beacons.sorted { $0.accuracy < $1.accuracy }.first
    }
    
    private func getCarStepFor(beacon: CLBeacon, car: CarIdentification) -> CarStepIdentification? {
        let beaconId = beacon.uuid
        print(beaconId)
        let stepId: Int = Int(truncating: beacon.major)
        if beaconId == car.uuid,
           let stepId = car.stepIdentifications.first(where: { $0.rawValue == stepId }) {
            return stepId
        } else {
            print("step could not be found")
            return nil
        }
    }
}

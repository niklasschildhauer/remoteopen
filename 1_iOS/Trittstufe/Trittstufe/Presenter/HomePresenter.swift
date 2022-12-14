//
//  HomePresenter.swift
//  Trittstufe
//
//  Created by Niklas Schildhauer on 02.04.22.
//

import Foundation
import UIKit
import CoreLocation
import CoreNFC

protocol HomeView: AnyObject, ErrorAlert {
    var presenter: HomePresenter! { get set }
    
    func show(reconnectButton: Bool)
    func display(carHeaderView viewModel: CarHeaderView.ViewModel?)
    func display(actionButton viewModel: UIButton.ViewModel?)
    func display(distanceView viewModel: DistanceView.ViewModel?, animated: Bool)
    func display(stepStatusView viewModel: StepStatusView.ViewModel?)
    func display(informationView viewModel: InformationView.ViewModel?)
}

protocol HomePresenterDelegate: AnyObject {
    func didTapLogout(in presenter: HomePresenter)
    func didChangePermissionStatus(in presenter: HomePresenter)
}

/// HomePresenter
/// The HomePresenter coordinates the services: StepEngineControlService, NFCReaderService and LocationService. It is responsible for keeping the CarStatus Model up to date. It implements the delegate methods of the services and then decides what to do when certain events occur. Mostly the CarStatus Model is updated and then the View is updated by creating the ViewModels for StepStatusView, InformationView, DistanceView & CarHeaderView and passing them from the HomePresenter to the View.
/// Furthermore, the HomePresenter is responsible for retracting and extending the Step.
class HomePresenter: NSObject, Presenter {
    
    weak var view: HomeView?
    var delegate: HomePresenterDelegate?
    
    private var stepEngineControlService: StepEngineControlService
    private let locationService: LocationService
    private var carStatus: CarStatus
    private let nfcReaderService = NFCReaderService()
    
    init(stepEngineControlService: StepEngineControlService, locationService: LocationService, carIdentification: CarIdentification) {
        self.stepEngineControlService = stepEngineControlService
        self.locationService = locationService
        self.carStatus = CarStatus(car: carIdentification)
    }
    
    func reloadServices() {
        if locationService.permissionStatus() == .granted {
            startLocationService()
            startEngineControlService()
        } else {
            delegate?.didChangePermissionStatus(in: self)
        }
    }
    
    func viewWillAppear() {
        reloadServices()
        reloadView()
    }
    
    private func startLocationService() {
        locationService.statusDelegate = self
        locationService.delegate = self
        
        locationService.startMonitoring()
    }
    
    private func startEngineControlService() {
        stepEngineControlService.connect() { _ in }
        stepEngineControlService.statusDelegate = self
    }
    
    private func stopLocationService() {
        locationService.stopMonitoring()
    }
    
    func extendStep() {
        let step = carStatus.selectedStep.step
        stepEngineControlService.extend(step: step)
    }
    
    func shrinkStep() {
        let step = carStatus.selectedStep.step
        stepEngineControlService.shrink(step: step)
    }
    
    func logout() {
        delegate?.didTapLogout(in: self)
    }
    
    func didTapActionButton() {
        switch carStatus.currentState {
        case .notConnected:
            carStatus.connected = true
            reloadView()
            print("Konfiguration")
        case .inLocalization, .readyToUnlock:
            nfcReaderService.delegate = self
            nfcReaderService.startReader(toLocate: carStatus.car.id) { success in
                if !success {
                    view?.showErrorAlert(with: NSLocalizedString("HomePresenter_NFCReaderFail", comment: ""), title: NSLocalizedString("HomePresenter_NFCReaderFailTitle", comment: ""))
                }
            }
        }
    }
    
    private func reloadView(animated: Bool = false) {
        view?.display(carHeaderView: carStatus.carHeaderViewModel)
        view?.display(stepStatusView: carStatus.stepStatusViewModel)
        view?.display(actionButton: carStatus.actionButtonViewModel)
        view?.display(informationView: carStatus.informationViewModel)
        view?.display(distanceView: carStatus.distanceViewModel, animated: animated)
        view?.show(reconnectButton: carStatus.currentState == .notConnected)
    }
}

/// Implements the LocationServiceStatusDelegate
extension HomePresenter: LocationServiceStatusDelegate {
    func didChangeStatus(in service: LocationService) {
        switch service.permissionStatus() {
        case .granted:
            startLocationService()
        case .denied, .notDetermined:
            stopLocationService()
            DispatchQueue.performUIOperation {
                self.delegate?.didChangePermissionStatus(in: self)
            }
        }
    }
}

/// Implements the LocationServiceDelegate to get the information if an iBeacon is near
extension HomePresenter: LocationServiceDelegate {
    /// Reset if there is nothing
    func didRangeNothing(in service: LocationService) {
        guard !carStatus.selectedStep.forceLocated else { return }

        print("Reset findings")
        carStatus.distance = (proximity: .unknown, meters: nil, count: 0)
        carStatus.selectedStep = (step: .unknown, forceLocated: false)
        
        DispatchQueue.performUIOperation {
            self.reloadView()
        }
    }
    
    /// This method balances the found cars in the proximity. Due to the inaccuracy of iBeacons this method was implemented. It allows a certain degree of inaccuracy.
    func didRangeCar(car: CarIdentification, step: CarStepIdentification, with proximity: CLProximity, meters: Double, in service: LocationService) {
        guard !carStatus.selectedStep.forceLocated else { return }
        let currentCarState = carStatus.currentState
    
        print("Find: \(car.model), \(step), \(meters)m - \(proximity.rawValue)")
        
        let distanceCount: Int
        switch carStatus.distance.proximity {
        case .near, .immediate:
            if (proximity == .immediate || proximity == .near) {
                distanceCount = carStatus.distance.count + 1
            } else {
                distanceCount = 0
            }
        case .far, .unknown:
            if proximity == .far || proximity == .unknown {
                distanceCount = carStatus.distance.count + 1
            } else {
                distanceCount = 0
            }
        @unknown default:
            fatalError()
        }

        carStatus.distance = (proximity: proximity, meters: meters > 0 ? meters : nil, count: distanceCount)

        if proximity == .immediate || proximity == .near,
           meters < 1,
           carStatus.distance.count > 3 {
            let oldStep = carStatus.selectedStep.step
            carStatus.selectedStep = (step: step, forceLocated: false)
            if oldStep != step {
                DispatchQueue.performUIOperation {
                    self.reloadView(animated: true)
                }
                return
            }
        }

        if proximity == .far && carStatus.distance.count > 6 {
            carStatus.selectedStep = (step: .unknown, forceLocated: false)
        }
        
        
        DispatchQueue.performUIOperation {
            if currentCarState != self.carStatus.currentState {
                self.reloadView(animated: true)
            } else {
                self.view?.display(distanceView: self.carStatus.distanceViewModel, animated: true)
                self.view?.display(carHeaderView: self.carStatus.carHeaderViewModel)
            }
        }
    }
        
    func didFail(with error: String, in service: LocationService) {
        carStatus.distance = (proximity: .unknown, meters: nil, count: 0)
        print(error)
        DispatchQueue.performUIOperation {
            self.reloadView()
        }
    }
}

/// Implements the StepEngineControlServiceDelegate to get status updates about the step position or the network status.
extension HomePresenter: StepEngineControlServiceDelegate {
    func didReceive(stepStatus: CarStepStatus, in service: StepEngineControlService) {
        carStatus.update(stepStatus: stepStatus)
        DispatchQueue.performUIOperation {
            self.reloadView()
        }
    }
    
    func didConnectToCar(in service: StepEngineControlService) {
        carStatus.connected = true
        DispatchQueue.performUIOperation {
            self.reloadView()
        }
    }
    
    func didDisconnectToCar(in service: StepEngineControlService) {
        carStatus.connected = false
        DispatchQueue.performUIOperation {
            self.reloadView()
        }
    }
}

/// Implements the NFCReaderServiceDelegate 
extension HomePresenter: NFCReaderServiceDelegate {
    /// If the NFCReaderService did range a step, the home presenter force locate it, so that the locationservice is not longer needed and stops it.
    func didLocate(step: CarStepIdentification, in service: NFCReaderService) {
        carStatus.selectedStep = (step: step, forceLocated: true)
        stopLocationService()
        
        DispatchQueue.performUIOperation {
            self.reloadView()
        }
    }
}

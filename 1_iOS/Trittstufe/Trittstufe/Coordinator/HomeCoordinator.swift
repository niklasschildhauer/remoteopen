//
//  HomeCoordinator.swift
//  Trittstufe
//
//  Created by Niklas Schildhauer on 02.04.22.
//

import Foundation
import UIKit

protocol HomeCoordinatorDelegate: AnyObject {
    func didLogout(in coordinator: HomeCoordinator)
}

/// Is responsible for creating the Home View Controller
class HomeCoordinator: Coordinator {
    var rootViewController: UIViewController! {
        navigationController
    }
    
    var delegate: HomeCoordinatorDelegate?
    private let navigationController = UINavigationController()
    private let stepEngineControlService: StepEngineControlService
    private let locationService: LocationService
    private let clientConfiguration: ClientConfiguration
    
    init(clientConfiguration: ClientConfiguration, locationService: LocationService) {
        locationService.clientConfiguration = clientConfiguration
        self.locationService = locationService
        self.clientConfiguration = clientConfiguration
        self.stepEngineControlService = MQTTClientService(clientConfiguration: clientConfiguration)

        navigationController.setViewControllers([createHomeViewController()], animated: false)
    }
    
    private func createHomeViewController() -> UIViewController {
        let homeViewController = HomeViewController()
        let homePresenter = HomePresenter(stepEngineControlService: stepEngineControlService, locationService: locationService, carIdentification: clientConfiguration.carIdentification)

        homePresenter.delegate = self
        homeViewController.presenter = homePresenter
        
        return homeViewController
    }
    
    private func createRequestLocationPermissionViewController() -> UIViewController {
        let viewController = RequestLocationPermissionViewController()
        let presenter = RequestLocationPermissionPresenter(locationService: locationService)
        
        viewController.presenter = presenter
        presenter.delegate = self
        
        return viewController
    }
}

extension HomeCoordinator: HomePresenterDelegate {
    func didChangePermissionStatus(in presenter: HomePresenter) {
        let requestPermissionViewController = self.createRequestLocationPermissionViewController()
        requestPermissionViewController.isModalInPresentation = true
        requestPermissionViewController.sheetPresentationController?.detents = [.medium()]
        
        DispatchQueue.performUIOperation {
            self.rootViewController.present(requestPermissionViewController, animated: true, completion: nil)
        }
    }
    
    func didTapLogout(in presenter: HomePresenter) {
        delegate?.didLogout(in: self)
    }
}

extension HomeCoordinator: RequestLocationPermissionPresenterDelegate {
    func didGrantedPermission(in presenter: RequestLocationPermissionPresenter) {
        DispatchQueue.performUIOperation {
            self.navigationController.setViewControllers([self.createHomeViewController()], animated: false)
            self.rootViewController.dismiss(animated: true)
        }
    }
}

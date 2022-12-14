//
//  LoginPresenter.swift
//  Trittstufe
//
//  Created by Niklas Schildhauer on 10.04.22.
//

import Foundation
import UIKit
import LocalAuthentication

protocol AuthenticationView: AnyObject, ErrorAlert {
    var presenter: AuthenticationPresenter! { get set }
    
    func setLoginFieldsHiddenStatus(isHidden: Bool, animated: Bool)
    func showLoginSpinner()
    func hideLoginSpinner()
    
    var passwordValue: String? { get set }
    var accountNameValue: String? { get set }
    var rememberMeValue: Bool { get set }
}

protocol AuthenticationPresenterDelegate: AnyObject {
    func didCompleteAuthentication(with clientConfiguration: ClientConfiguration, in presenter: AuthenticationPresenter)
    func didTapEditConfiguration(in presenter: AuthenticationPresenter)

}

/// AuthenticationPresenter
/// Uses the AuthenticationService to authenticate the user. The user logs in with his credentials and can also use FaceID for unlocking if desired.
class AuthenticationPresenter {
    weak var view: AuthenticationView?
    var delegate: AuthenticationPresenterDelegate?
    
    private let authenticationService: AuthenticationService
        
    init(authenticationService: AuthenticationService) {
        self.authenticationService = authenticationService
    }
    
    /// Checks if FaceID is activated. Then it tries to authenticate via the rememberMe authentication.
    func viewDidLoad() {
        if authenticationService.rememberMe {
            view?.setLoginFieldsHiddenStatus(isHidden: true, animated: false)
            startRememberMeAuthentication()
        } else {
            view?.setLoginFieldsHiddenStatus(isHidden: false, animated: false)
        }
        
        view?.rememberMeValue = authenticationService.rememberMe
    }
    
    func didChangeRememberMeValue(newValue: Bool) {
        if newValue {
            checkDeviceOwnerAuthenticationWithBiometrics { result in
                if !result {
                    self.view?.rememberMeValue = false
                }
            }
        }
    }
    
    func didTapEditConfiguration() {
        delegate?.didTapEditConfiguration(in: self)
    }
        
    func didTapLogin() {
        guard let password = view?.passwordValue,
              let accountName = view?.accountNameValue,
              let rememberMe = view?.rememberMeValue else { return }
            
        self.view?.showLoginSpinner()
        authenticationService.login(accountName: accountName, password: password, rememberMe: rememberMe) { [weak self] result in
            self?.handleAuthentication(result: result)
        }
    }
    
    private func startRememberMeAuthentication() {
        self.checkDeviceOwnerAuthenticationWithBiometrics { [weak self] isDeviceOwner in
            guard let self = self else { return }
            if isDeviceOwner {
                self.authenticationService.loginWithRememberMe { [weak self] result in
                    guard let self = self else { return }
                    self.handleAuthentication(result: result)
                }
            } else {
                DispatchQueue.performUIOperation {
                    self.view?.setLoginFieldsHiddenStatus(isHidden: false, animated: true)
                }
            }
        }
    }
    
    private func handleAuthentication(result: Result<ClientConfiguration, AuthenticationError>) {
        switch result {
        case .success(let clientConfiguration):
            delegate?.didCompleteAuthentication(with: clientConfiguration, in: self)
        case .failure(let error):
            DispatchQueue.performUIOperation {
                switch error {
                case .invalidLoginCredentials:
                    self.view?.showErrorAlert(with: NSLocalizedString("AuthenticationPresenter_wrongCredentials", comment: ""), title: NSLocalizedString("AuthenticationPresenter_wrongCredentialsTitle", comment: ""))
                case .noNetwork:
                    self.view?.showErrorAlert(with: NSLocalizedString("AuthenticationPresenter_noNetwork", comment: ""), title: NSLocalizedString("AuthenticationPresenter_noNetworkTitle", comment: ""))
                case .serverError:
                    self.view?.showErrorAlert(with: NSLocalizedString("ConfigurationPresenter_internalError", comment: ""), title: NSLocalizedString("ConfigurationPresenter_internalErrorTitle", comment: ""))
                case .internalError:
                    self.view?.showErrorAlert(with: NSLocalizedString("ConfigurationPresenter_internalError", comment: ""), title: NSLocalizedString("ConfigurationPresenter_internalErrorTitle", comment: ""))
                }
                self.view?.setLoginFieldsHiddenStatus(isHidden: false, animated: true)
                self.view?.hideLoginSpinner()
            }
        }
    }
    
    private func checkDeviceOwnerAuthenticationWithBiometrics(completion: @escaping (Bool) -> Void) {
        let context = LAContext()
        var error: NSError?

        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            let reason = NSLocalizedString("AuthenticationPresenter_identifiy", comment: "")

            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, authenticationError in
                if success {
                    completion(true)
                } else {
                    completion(false)
                }
            }
        } else {
            completion(false)
        }
    }
}

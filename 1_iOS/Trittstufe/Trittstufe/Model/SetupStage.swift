//
//  SetupStage.swift
//  Trittstufe
//
//  Created by Niklas Schildhauer on 10.04.22.
//

import Foundation

enum SetupStage {
    case configurationMissing
    case authenticationRequired
    case setupCompleted(clientConfiguration: ClientConfiguration)
}
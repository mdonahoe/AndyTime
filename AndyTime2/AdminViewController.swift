//
//  AdminViewController.swift
//  AndyTime2
//
//  Created by Matt Donahoe on 12/17/24.
//

import Foundation
import UIKit


// This class provides info on what the app is doing
// There are is a label for the current playback time.
// There is also buttons that:
// 1. advances playback time by 10 minutes
// 2. rewinds playback time by 10 minutes
// 3. resets playback time to 0
class AdminViewController: UIViewController {
    
    private let timeLabel = UILabel()
    private let advanceButton = UIButton()
    private let rewindButton = UIButton()
    private let resetButton = UIButton()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    private func setupUI() {
        let adminLabel = UILabel()
        adminLabel.text = "admin view"
        adminLabel.textColor = .white
        adminLabel.textAlignment = .center
        adminLabel.font = .systemFont(ofSize: 24)
        view.addSubview(adminLabel)
        adminLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            adminLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            adminLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20)
        ])
        view.backgroundColor = .black
        
        // Configure time label
        timeLabel.textColor = .white
        timeLabel.textAlignment = .center
        timeLabel.font = .systemFont(ofSize: 24)
        view.addSubview(timeLabel)
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            timeLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            timeLabel.topAnchor.constraint(equalTo: adminLabel.bottomAnchor, constant: 20)
        ])
        timeLabel.text = "00:00:00" // TODO
        
        // Configure buttons
        let buttonConfig = UIButton.Configuration.filled()
        var highlightedConfig = UIButton.Configuration.filled()
        highlightedConfig.baseBackgroundColor = .lightGray
        let buttonStack = UIStackView()
        buttonStack.axis = .horizontal
        buttonStack.spacing = 20
        buttonStack.distribution = .fillEqually
        view.addSubview(buttonStack)
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        
        [rewindButton, resetButton, advanceButton].forEach { button in
            button.backgroundColor = .darkGray
            button.layer.cornerRadius = 8
            buttonStack.addArrangedSubview(button)
            button.configuration = buttonConfig
            button.configurationUpdateHandler = { button in
                button.configuration?.baseBackgroundColor = button.isHighlighted ? .lightGray : .darkGray
            }
        }
        
        rewindButton.setTitle("-10m", for: .normal)
        resetButton.setTitle("Reset", for: .normal)
        advanceButton.setTitle("+10m", for: .normal)
        
        NSLayoutConstraint.activate([
            buttonStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            buttonStack.topAnchor.constraint(equalTo: timeLabel.bottomAnchor, constant: 20),
            buttonStack.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.8)
        ])
        
        // Add button targets
        advanceButton.addTarget(self, action: #selector(advanceTime), for: .touchUpInside)
        rewindButton.addTarget(self, action: #selector(rewindTime), for: .touchUpInside)
        resetButton.addTarget(self, action: #selector(resetTime), for: .touchUpInside)
        
        // Update time label initially
        updateTimeLabel()
        
        // Observe time changes
        NotificationCenter.default.addObserver(self, 
            selector: #selector(handleTimeUpdate), 
            name: PlaybackManager.playbackTimeDidChange, 
            object: nil)
    }
    
    private func updateTimeLabel() {
        let time = PlaybackManager.shared.currentPlaybackTime
        let hours = Int(time) / 3600
        let minutes = Int(time) / 60 % 60
        let seconds = Int(time) % 60
        timeLabel.text = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
    
    @objc private func handleTimeUpdate(_ notification: Notification) {
        print("handleTimeUpdate admin")
        // TODO(matt): we probably want to update the time label once a second.
        updateTimeLabel()
    }
    
    @objc private func advanceTime() {
        PlaybackManager.shared.adjustTime(by: 600) // 10 minutes in seconds
    }
    
    @objc private func rewindTime() {
        PlaybackManager.shared.adjustTime(by: -600) // -10 minutes in seconds
    }
    
    @objc private func resetTime() {
        PlaybackManager.shared.resetTime()
    }
}

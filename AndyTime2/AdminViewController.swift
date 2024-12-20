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
    private let stateLabel = UILabel()
    private let advanceButton = UIButton()
    private let rewindButton = UIButton()
    private let resetButton = UIButton()
    private let nextChannelButton = UIButton()
    private let prevChannelButton = UIButton()
    
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
        
        // Configure state label
        stateLabel.textColor = .white
        stateLabel.textAlignment = .center
        stateLabel.font = .systemFont(ofSize: 18)
        stateLabel.numberOfLines = 0 // Allow multiple lines
        view.addSubview(stateLabel)
        stateLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stateLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stateLabel.topAnchor.constraint(equalTo: timeLabel.bottomAnchor, constant: 20),
            stateLabel.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.9)
        ])
        updateStateLabel() // Initial update
        
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
            buttonStack.topAnchor.constraint(equalTo: stateLabel.bottomAnchor, constant: 20),
            buttonStack.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.8)
        ])
        
        // Add button targets
        advanceButton.addTarget(self, action: #selector(advanceTime), for: .touchUpInside)
        rewindButton.addTarget(self, action: #selector(rewindTime), for: .touchUpInside)
        resetButton.addTarget(self, action: #selector(resetTime), for: .touchUpInside)
        
        // Update time label initially
        updateTimeLabel()
        
        // Observe time changes
        NotificationCenter.default.addObserver(forName: PlaybackManager.playbackTimeDidChange, object: nil, queue: .main) { [weak self] notification in
            self?.handleTimeUpdate(notification)
        }
        
        // Create channel button stack
        let channelButtonStack = UIStackView()
        channelButtonStack.axis = .horizontal
        channelButtonStack.spacing = 20
        channelButtonStack.distribution = .fillEqually
        view.addSubview(channelButtonStack)
        channelButtonStack.translatesAutoresizingMaskIntoConstraints = false
        
        // Configure channel buttons
        [prevChannelButton, nextChannelButton].forEach { button in
            button.backgroundColor = .darkGray
            button.layer.cornerRadius = 8
            channelButtonStack.addArrangedSubview(button)
            button.configuration = buttonConfig
            button.configurationUpdateHandler = { button in
                button.configuration?.baseBackgroundColor = button.isHighlighted ? .lightGray : .darkGray
            }
        }
        
        prevChannelButton.setTitle("Prev Channel", for: .normal)
        nextChannelButton.setTitle("Next Channel", for: .normal)
        
        NSLayoutConstraint.activate([
            channelButtonStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            channelButtonStack.topAnchor.constraint(equalTo: buttonStack.bottomAnchor, constant: 20),
            channelButtonStack.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.8)
        ])
        
        // Add button targets
        nextChannelButton.addTarget(self, action: #selector(nextChannel), for: .touchUpInside)
        prevChannelButton.addTarget(self, action: #selector(prevChannel), for: .touchUpInside)
    }
    
    private func updateTimeLabel() {
        let time = PlaybackManager.shared.currentPlaybackTime
        
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.year, .month, .day, .hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 6
        
        timeLabel.text = formatter.string(from: time)
    }
    
    private func updateStateLabel() {
        let state = PlaybackManager.shared.getState()
        let progressString = String(format: "%.2f%%", state.playlistPosition.seekTime / state.playlistPosition.videoDuration * 100)
        let minutesRemaining = String(format: "%d:%02d", Int(state.playlistPosition.videoDuration - state.playlistPosition.seekTime) / 60, Int(state.playlistPosition.videoDuration - state.playlistPosition.seekTime) % 60)
        stateLabel.text = "Channel: \(state.channelName)\nVideo: \(state.videoTitle) \(progressString) \(minutesRemaining) remaining"
    }
    
    @objc private func handleTimeUpdate(_ notification: Notification) {
        print("handleTimeUpdate admin")
        updateTimeLabel()
        updateStateLabel() // Update state label when time changes
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
    
    @objc private func nextChannel() {
        let state = PlaybackManager.shared.getState()
        PlaybackManager.shared.setChannelIndex(index:state.channelIndex + 1)
    }
    
    @objc private func prevChannel() {
        let state = PlaybackManager.shared.getState()
        PlaybackManager.shared.setChannelIndex(index:state.channelIndex - 1)
    }
}

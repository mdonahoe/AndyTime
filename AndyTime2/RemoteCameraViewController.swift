import UIKit
import LiveKit

/// Displays a single remote participant's camera feed as a swipeable page.
/// Audio from this participant plays only while this page is visible.
class RemoteCameraViewController: UIViewController {

    let participantIdentity: String

    private let videoView    = VideoView()
    private let nameLabel    = UILabel()
    private let noVideoLabel = UILabel()

    private var videoTrack: RemoteVideoTrack?

    init(participant: RemoteParticipant) {
        participantIdentity = participant.identity?.description ?? "unknown"
        super.init(nibName: nil, bundle: nil)
        LiveKitManager.shared.room.add(delegate: self)
        attachExistingTracks(from: participant)
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        LiveKitManager.shared.room.remove(delegate: self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        if let track = videoTrack {
            videoView.track = track
            noVideoLabel.isHidden = true
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        LiveKitManager.shared.setActiveAudioParticipant(participantIdentity)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        LiveKitManager.shared.clearActiveAudioParticipantIfMatches(participantIdentity)
    }

    // MARK: - Private

    private func attachExistingTracks(from participant: RemoteParticipant) {
        for pub in participant.trackPublications.values {
            if let track = pub.track as? RemoteVideoTrack {
                videoTrack = track
            }
        }
    }

    private func setupUI() {
        view.backgroundColor = .black

        nameLabel.text = participantIdentity
        nameLabel.textColor = .white
        nameLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        nameLabel.textAlignment = .center
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(nameLabel)

        videoView.layoutMode = .fit
        videoView.backgroundColor = .black
        videoView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(videoView)

        noVideoLabel.text = "Waiting for video…"
        noVideoLabel.textColor = UIColor(white: 0.4, alpha: 1)
        noVideoLabel.font = .systemFont(ofSize: 14)
        noVideoLabel.textAlignment = .center
        noVideoLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(noVideoLabel)

        NSLayoutConstraint.activate([
            nameLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            nameLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            videoView.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 8),
            videoView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            videoView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            videoView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            noVideoLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            noVideoLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }
}

// MARK: - RoomDelegate

extension RemoteCameraViewController: RoomDelegate {
    func room(_ room: Room, participant: RemoteParticipant, didSubscribeTrack publication: RemoteTrackPublication) {
        guard participant.identity?.description == participantIdentity else { return }
        if let track = publication.track as? RemoteVideoTrack {
            videoTrack = track
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if isViewLoaded {
                    videoView.track = track
                    noVideoLabel.isHidden = true
                }
            }
        }
        // Audio policy is owned by LiveKitManager via active-participant tracking;
        // it applies the right volume to this track in its own delegate handler.
    }

    func room(_ room: Room, participant: RemoteParticipant, didUnsubscribeTrack publication: RemoteTrackPublication) {
        guard participant.identity?.description == participantIdentity else { return }
        if publication.kind == .video {
            videoTrack = nil
            DispatchQueue.main.async { [weak self] in
                guard let self, isViewLoaded else { return }
                videoView.track = nil
                noVideoLabel.isHidden = false
            }
        }
    }
}

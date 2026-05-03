import Foundation
import LiveKit

/// Shared Room instance. Owns the WebRTC connection; all VCs use this room.
///
/// Audio policy: only the participant currently being viewed
/// (`activeAudioParticipant`) is audible. All other remote audio tracks are
/// volume-zeroed. This prevents feedback loops between devices in the same room.
class LiveKitManager: NSObject {
    static let shared = LiveKitManager()

    let room = Room()

    static let participantConnectedNotification    = Notification.Name("LKParticipantConnected")
    static let participantDisconnectedNotification = Notification.Name("LKParticipantDisconnected")

    /// Identity of the participant whose audio should currently play.
    /// `nil` means all remote audio is muted.
    private(set) var activeAudioParticipant: String?

    private override init() {
        super.init()
        room.add(delegate: self)
    }

    /// The currently visible participant. Their audio plays at full volume,
    /// every other remote participant is zeroed.
    func setActiveAudioParticipant(_ identity: String?) {
        activeAudioParticipant = identity
        applyAudioVolumes()
    }

    /// If the currently active participant matches `identity`, clear it.
    /// Used by RemoteCameraVC.viewWillDisappear to avoid clobbering the
    /// next page's viewDidAppear during swipe transitions.
    func clearActiveAudioParticipantIfMatches(_ identity: String) {
        if activeAudioParticipant == identity {
            activeAudioParticipant = nil
            applyAudioVolumes()
        }
    }

    private func applyAudioVolumes() {
        let active = activeAudioParticipant
        for participant in room.remoteParticipants.values {
            let pid = participant.identity?.description
            for pub in participant.trackPublications.values {
                if let audio = pub.track as? RemoteAudioTrack {
                    audio.volume = (pid == active) ? 1.0 : 0.0
                }
            }
        }
    }
}

extension LiveKitManager: RoomDelegate {
    func room(_ room: Room, didUpdateConnectionState connectionState: ConnectionState, from oldValue: ConnectionState) {
        // participantDidConnect doesn't fire for participants already in the room when we join.
        // Emit synthetic connect notifications for them once the connection is established.
        guard connectionState == .connected, oldValue != .connected else { return }
        for participant in room.remoteParticipants.values {
            NotificationCenter.default.post(name: LiveKitManager.participantConnectedNotification,
                                            object: participant)
        }
    }

    func room(_ room: Room, participantDidConnect participant: RemoteParticipant) {
        NotificationCenter.default.post(name: LiveKitManager.participantConnectedNotification,
                                        object: participant)
    }

    func room(_ room: Room, participantDidDisconnect participant: RemoteParticipant) {
        NotificationCenter.default.post(name: LiveKitManager.participantDisconnectedNotification,
                                        object: participant)
    }

    func room(_ room: Room, participant: RemoteParticipant, didSubscribeTrack publication: RemoteTrackPublication) {
        // Apply current audio policy to any newly subscribed audio track.
        if let audio = publication.track as? RemoteAudioTrack {
            let pid = participant.identity?.description
            audio.volume = (pid == activeAudioParticipant) ? 1.0 : 0.0
        }
    }
}

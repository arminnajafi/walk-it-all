import CoreLocation
import Foundation
import Observation
import OSLog
import WalkItAllCore

enum LocationAccessState: Equatable {
    case notDetermined
    case authorized
    case denied
    case restricted

    var canShowLocation: Bool { self == .authorized }
}

@MainActor
@Observable
final class LiveTrailController: NSObject, @preconcurrency CLLocationManagerDelegate {
    static let maximumSessionDuration: TimeInterval = 12 * 60 * 60
    static let pendingRetentionDuration: TimeInterval = 7 * 24 * 60 * 60
    private static let expiredNoticeKey = "lastExpiredLiveTrailDate"
    private static let persistenceInterval: TimeInterval = 15
    private static let persistencePointInterval = 25
    private static let renderInterval: TimeInterval = 2

    var session: LiveTrailSession?
    var accessState: LocationAccessState
    var issueMessage: String?
    var renderRevision = 0
    var lastExpiredTrailDate: Date?

    @ObservationIgnored var onDidFinish: (() -> Void)?
    @ObservationIgnored private let repository: any LiveTrailRepository
    @ObservationIgnored private let processor: LiveTrailProcessor
    @ObservationIgnored private let locationManager: CLLocationManager
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let logger = Logger(
        subsystem: "com.arminnajafi.walkitall",
        category: "LiveTrail"
    )
    @ObservationIgnored private var updateTask: Task<Void, Never>?
    @ObservationIgnored private var timeoutTask: Task<Void, Never>?
    @ObservationIgnored private var backgroundSession: CLBackgroundActivitySession?
    @ObservationIgnored private var pendingStart = false
    @ObservationIgnored private var requiresNewPart = true
    @ObservationIgnored private var acceptedSincePersistence = 0
    @ObservationIgnored private var lastPersistenceDate: Date?
    @ObservationIgnored private var lastRenderDate: Date?
    @ObservationIgnored private var persistenceTask: Task<Void, Never>?

    init(
        repository: any LiveTrailRepository,
        processor: LiveTrailProcessor = LiveTrailProcessor(),
        locationManager: CLLocationManager = CLLocationManager(),
        defaults: UserDefaults = .standard
    ) {
        self.repository = repository
        self.processor = processor
        self.locationManager = locationManager
        self.defaults = defaults
        accessState = Self.accessState(for: locationManager.authorizationStatus)
        lastExpiredTrailDate = defaults.object(forKey: Self.expiredNoticeKey) as? Date
        super.init()
        locationManager.delegate = self
    }

    var isActive: Bool { session?.state == .active }
    var isWaitingForHealth: Bool { session?.state == .waitingForHealth }

    func bootstrap(now: Date = Date()) async {
        do {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-uiTestResetLiveTrail") {
                try await repository.delete()
            }
            #endif
            guard let stored = try await repository.load() else { return }
            session = stored
            renderRevision &+= 1
            switch stored.state {
            case .active:
                if now.timeIntervalSince(stored.start) >= Self.maximumSessionDuration {
                    await finish(at: stored.start.addingTimeInterval(Self.maximumSessionDuration))
                } else if accessState == .authorized {
                    requiresNewPart = true
                    beginLocationDelivery()
                } else {
                    issueMessage = "Live Trail could not resume because location access is unavailable. You can finish it safely."
                }
            case .waitingForHealth:
                await expirePendingTrailIfNeeded(now: now)
            }
        } catch {
            logger.error("Temporary trail recovery failed: \(error.localizedDescription, privacy: .private)")
            issueMessage = "The temporary Live Trail could not be recovered. Your Apple Health history is unaffected."
        }
    }

    func requestCurrentLocation() {
        pendingStart = false
        requestAuthorizationIfNeeded()
    }

    func start(now: Date = Date()) {
        guard session == nil else { return }
        pendingStart = true
        switch accessState {
        case .authorized:
            beginNewSession(at: now)
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .denied:
            pendingStart = false
            issueMessage = "Location access is off. Allow it in Settings to use Live Trail."
        case .restricted:
            pendingStart = false
            issueMessage = "Location access is restricted on this iPhone."
        }
    }

    func finish(at date: Date = Date()) async {
        guard let session, session.state == .active else { return }
        stopLocationDelivery()
        await persistenceTask?.value
        persistenceTask = nil
        let processor = processor
        let pending = await Task.detached(priority: .userInitiated) {
            processor.finishing(session, at: date)
        }.value
        self.session = pending
        renderRevision &+= 1
        do {
            try await repository.save(pending)
        } catch {
            logger.error("Temporary trail finish save failed: \(error.localizedDescription, privacy: .private)")
            issueMessage = "Live Trail stopped, but its temporary route could not be saved."
        }
        onDidFinish?()
    }

    func reconcile(with records: [WorkoutRouteRecord], now: Date = Date()) async {
        guard let session, session.state == .waitingForHealth else { return }
        if LiveTrailHealthAssociator.matchingWorkoutID(for: session, among: records) != nil {
            do {
                try await repository.delete()
                self.session = nil
                renderRevision &+= 1
            } catch {
                logger.error("Matched temporary trail cleanup failed: \(error.localizedDescription, privacy: .private)")
            }
            return
        }
        await expirePendingTrailIfNeeded(now: now)
    }

    func clearIssue() {
        issueMessage = nil
    }

    func resumeIfNeeded() {
        guard isActive, accessState == .authorized, updateTask == nil else { return }
        requiresNewPart = true
        beginLocationDelivery()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        accessState = Self.accessState(for: manager.authorizationStatus)
        if isActive, accessState != .authorized {
            stopLocationDelivery()
            issueMessage = "Live Trail paused because location access is unavailable. You can finish it safely."
        }
        guard pendingStart else { return }
        switch accessState {
        case .authorized:
            beginNewSession(at: Date())
        case .denied:
            pendingStart = false
            issueMessage = "Location access is off. Allow it in Settings to use Live Trail."
        case .restricted:
            pendingStart = false
            issueMessage = "Location access is restricted on this iPhone."
        case .notDetermined:
            break
        }
    }

    private func beginNewSession(at date: Date) {
        pendingStart = false
        requiresNewPart = true
        acceptedSincePersistence = 0
        lastPersistenceDate = date
        lastRenderDate = nil
        session = LiveTrailSession(state: .active, start: date, lastUpdate: date)
        renderRevision &+= 1
        beginLocationDelivery()
        persistenceTask = Task { [weak self] in
            guard let self, let session = self.session else { return }
            do {
                try await repository.save(session)
            } catch {
                logger.error("Temporary trail start save failed: \(error.localizedDescription, privacy: .private)")
                issueMessage = "Live Trail started, but its recovery file could not be saved."
            }
        }
    }

    private func beginLocationDelivery() {
        guard updateTask == nil, session?.state == .active else { return }
        backgroundSession = CLBackgroundActivitySession()
        scheduleTimeout()
        updateTask = Task { [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates(.fitness) {
                    guard let self, !Task.isCancelled else { return }
                    if let location = update.location {
                        await self.consume(location)
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                guard let self else { return }
                self.logger.error("Live location delivery failed: \(error.localizedDescription, privacy: .private)")
                self.issueMessage = "Live Trail location updates stopped unexpectedly. Reopen the app to resume."
                self.stopLocationDelivery()
            }
        }
    }

    private func consume(_ location: CLLocation) async {
        guard let session, session.state == .active else { return }
        if location.timestamp.timeIntervalSince(session.start) >= Self.maximumSessionDuration {
            await finish(at: session.start.addingTimeInterval(Self.maximumSessionDuration))
            issueMessage = "Live Trail finished automatically after 12 hours."
            return
        }
        let point = RoutePoint(
            coordinate: GeoCoordinate(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            ),
            timestamp: location.timestamp,
            horizontalAccuracy: location.horizontalAccuracy
        )
        let result = processor.appending(point, to: session, forceNewPart: requiresNewPart)
        requiresNewPart = result.requiresNewPart
        guard result.accepted else { return }
        self.session = result.session
        acceptedSincePersistence += 1

        let now = Date()
        if lastRenderDate.map({ now.timeIntervalSince($0) >= Self.renderInterval }) ?? true {
            renderRevision &+= 1
            lastRenderDate = now
        }
        if acceptedSincePersistence >= Self.persistencePointInterval
            || lastPersistenceDate.map({ now.timeIntervalSince($0) >= Self.persistenceInterval }) ?? true
        {
            let processor = processor
            let compacted = await Task.detached(priority: .utility) {
                processor.compacting(result.session)
            }.value
            guard !Task.isCancelled,
                  self.session?.id == compacted.id,
                  self.session?.state == .active
            else { return }
            self.session = compacted
            acceptedSincePersistence = 0
            lastPersistenceDate = now
            do {
                try await repository.save(compacted)
            } catch {
                logger.error("Temporary trail checkpoint failed: \(error.localizedDescription, privacy: .private)")
            }
        }
    }

    private func scheduleTimeout() {
        timeoutTask?.cancel()
        guard let session else { return }
        let remaining = max(0, Self.maximumSessionDuration - Date().timeIntervalSince(session.start))
        timeoutTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(remaining)) } catch { return }
            guard let self else { return }
            await self.finish(at: session.start.addingTimeInterval(Self.maximumSessionDuration))
            self.issueMessage = "Live Trail finished automatically after 12 hours."
        }
    }

    private func stopLocationDelivery() {
        updateTask?.cancel()
        updateTask = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        backgroundSession?.invalidate()
        backgroundSession = nil
    }

    private func requestAuthorizationIfNeeded() {
        switch accessState {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .denied:
            issueMessage = "Location access is off. Allow it in Settings to show your position."
        case .restricted:
            issueMessage = "Location access is restricted on this iPhone."
        case .authorized:
            break
        }
    }

    private func expirePendingTrailIfNeeded(now: Date) async {
        guard let session,
              session.state == .waitingForHealth,
              let end = session.end,
              now.timeIntervalSince(end) >= Self.pendingRetentionDuration
        else { return }
        do {
            try await repository.delete()
            self.session = nil
            renderRevision &+= 1
            lastExpiredTrailDate = now
            defaults.set(now, forKey: Self.expiredNoticeKey)
        } catch {
            logger.error("Expired temporary trail cleanup failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    private static func accessState(for status: CLAuthorizationStatus) -> LocationAccessState {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse: .authorized
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default: .restricted
        }
    }
}

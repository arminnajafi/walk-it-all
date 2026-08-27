#if DEBUG
import SwiftUI
import WalkItAllCore

#Preview("Coverage") {
    ZStack {
        Color.green.opacity(0.12).ignoresSafeArea()
        ProgressCard(
            coverage: CoverageSnapshot(
                packIdentifier: "preview",
                packVersion: 1,
                totalDistanceMeters: 1_600_000,
                coveredDistanceMeters: 358_000,
                completedSegmentIDs: [],
                coveredMetersBySegment: [:],
                coveredIntervalsBySegment: [:],
                averageConfidence: 0.94
            ),
            phase: .complete(imported: 37, unmatched: 3),
            selectedWorkoutName: nil,
            refresh: {},
            cancel: {},
            showDetails: {},
            clearSelection: {}
        )
        .padding()
    }
}

#Preview("Importing") {
    ProgressCard(
        coverage: CoverageSnapshot(
            packIdentifier: "preview",
            packVersion: 1,
            totalDistanceMeters: 1_600_000,
            coveredDistanceMeters: 0,
            completedSegmentIDs: [],
            coveredMetersBySegment: [:],
            coveredIntervalsBySegment: [:],
            averageConfidence: 0
        ),
        phase: .matching(completed: 18, total: 37),
        selectedWorkoutName: nil,
        refresh: {},
        cancel: {},
        showDetails: {},
        clearSelection: {}
    )
    .padding()
}
#endif


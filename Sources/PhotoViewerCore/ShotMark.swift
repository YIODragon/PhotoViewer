import Foundation

/// Local, non-destructive culling metadata for one shot.
///
/// This is intentionally independent of the original files: no EXIF/XMP is
/// written. Ratings live in Application Support until XMP export is added.
public struct ShotMark: Codable, Equatable, Sendable {
    public enum Flag: String, Codable, CaseIterable, Sendable {
        case none
        case pick
        case reject
    }

    public var rating: Int
    public var flag: Flag

    public init(rating: Int = 0, flag: Flag = .none) {
        self.rating = min(max(rating, 0), 5)
        self.flag = flag
    }

    public var isUnmarked: Bool {
        rating == 0 && flag == .none
    }
}

public enum ShotFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case unrated
    case picked
    case rejected

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: return "全部"
        case .unrated: return "未评级"
        case .picked: return "保留"
        case .rejected: return "废片"
        }
    }

    public func matches(_ mark: ShotMark) -> Bool {
        switch self {
        case .all:
            return true
        case .unrated:
            return mark.rating == 0 && mark.flag == .none
        case .picked:
            return mark.flag == .pick
        case .rejected:
            return mark.flag == .reject
        }
    }
}

/// Pure index rules used after a rating/flag change so auto-advance can be
/// verified without a window.
public enum CullingMath {
    public static func nextIndexAfterMark(
        shotID: String,
        visible: [Shot],
        oldIndex: Int,
        autoAdvance: Bool
    ) -> Int? {
        guard !visible.isEmpty else { return nil }

        if let index = visible.firstIndex(where: { $0.id == shotID }) {
            if autoAdvance {
                return min(index + 1, visible.count - 1)
            }
            return index
        }

        // The shot left the current filter (for example it was rated while
        // viewing "未评级"). The next item has taken its old position.
        return min(max(oldIndex, 0), visible.count - 1)
    }
}

import SwiftUI
import UIKit

/// How a sideways drag on the text turns into a move to the neighbouring surah. Dragging toward
/// the right goes to the next one, which comes in from the left, the way a mushaf's pages turn.
nonisolated enum SurahSwipe {
    /// Letting go past this share of the text's width moves on.
    static let commitFraction: CGFloat = 0.28
    /// A quick flick moves on when its projected end passes this share.
    static let flickFraction: CGFloat = 0.5
    /// How far ahead the release velocity is projected, to tell a flick from a stop.
    static let flickProjection: CGFloat = 0.2
    /// With nothing further that way, the text follows this share of the drag.
    static let rubberBand: CGFloat = 0.3
    /// A drag must be this many times wider than tall to be a swipe, so scrolling stays vertical.
    static let horizontalDominance: CGFloat = 1.5
    /// How far the finger moves before the drag's direction is decided.
    static let decisionDistance: CGFloat = 10
    /// The arriving text starts this share of the width away, on the side it comes from.
    static let arrivalFraction: CGFloat = 0.25
    static let leavingDuration: TimeInterval = 0.2
    static let arrivalDuration: TimeInterval = 0.3
    /// How far the title moves as one name replaces the other.
    static let titleShift: CGFloat = 24

    static func side(for translationX: CGFloat) -> ReaderNeighbor { translationX > 0 ? .next : .previous }

    static func isHorizontal(dx: CGFloat, dy: CGFloat) -> Bool { abs(dx) >= abs(dy) * horizontalDominance }

    static func offset(for translationX: CGFloat, hasNeighbor: Bool) -> CGFloat {
        hasNeighbor ? translationX : translationX * rubberBand
    }

    /// 0 at rest, 1 once letting go would move on.
    static func progress(for translationX: CGFloat, width: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }
        return min(abs(translationX) / (width * commitFraction), 1)
    }

    static func projectedEnd(translationX: CGFloat, velocityX: CGFloat) -> CGFloat {
        translationX + velocityX * flickProjection
    }

    /// Where letting go leads: the neighbour on the dragged side, or nil to spring back. A drag
    /// past the threshold that's flung back toward the start springs back too.
    static func outcome(translationX: CGFloat, projectedEndX: CGFloat, width: CGFloat,
                        available: Set<ReaderNeighbor>) -> ReaderNeighbor? {
        guard width > 0, translationX != 0, projectedEndX != 0 else { return nil }
        let side = side(for: translationX)
        guard available.contains(side), self.side(for: projectedEndX) == side else { return nil }
        let threshold = width * commitFraction
        let dragged = abs(translationX) >= threshold && abs(projectedEndX) >= threshold
        let flicked = abs(projectedEndX) >= width * flickFraction
        return dragged || flicked ? side : nil
    }

    /// Where the arriving text starts, on the side it comes in from.
    static func arrivalOffset(from side: ReaderNeighbor, width: CGFloat) -> CGFloat {
        let distance = width * arrivalFraction
        return side == .next ? -distance : distance
    }

    /// Where the leaving text ends: just off screen on the side the finger moved to.
    static func leavingOffset(toward side: ReaderNeighbor, width: CGFloat) -> CGFloat {
        side == .next ? width : -width
    }
}

/// How far along a move to the neighbouring surah is.
enum SurahSwitchPhase: Equatable {
    case idle
    case dragging
    case leaving
    case arriving

    /// The text takes a new drag only when no switch is under way.
    var acceptsDrag: Bool { self == .idle || self == .dragging }
}

/// The surah screen's swipe, from the first sideways movement until the next surah has arrived.
struct SurahSwipeState {
    var phase = SurahSwitchPhase.idle
    /// How far the text is moved sideways.
    var offset: CGFloat = 0
    /// The neighbour being uncovered, or switched to; nil when there's none that way.
    var reveal: SurahReveal?
    /// Past the point where letting go moves on.
    var isPastThreshold = false
    /// Hidden as the next surah arrives.
    var showsReveal = true

    var side: ReaderNeighbor? { reveal?.side }
}

/// The neighbour's name beside the text. It's kept apart from the screen's surah, so while the
/// neighbour arrives the name fades where it is instead of becoming the next surah's neighbour.
struct SurahReveal {
    let side: ReaderNeighbor
    let destination: QuranDestination
    let caption: String
    /// Follows the text while dragging and leaving, and stays put while the neighbour arrives.
    var offset: CGFloat
    /// Middle of the text the sheet leaves in view.
    let centerY: CGFloat
}

/// A pan that claims only sideways drags. Scrolling waits for it to decide, and it gives up as
/// soon as the finger moves more down than across, so vertical scrolling feels untouched.
final class HorizontalPanGestureRecognizer: UIPanGestureRecognizer {
    private var start: CGPoint?
    private var isDecided = false

    /// How far the finger has moved across since it touched down. UIKit's own translation starts
    /// once the pan begins, which would drop the movement it took to decide, and all of a fast flick.
    var translationX: CGFloat {
        guard let start else { return 0 }
        return location(in: view).x - start.x
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if start == nil { start = touches.first?.location(in: view) }
        super.touchesBegan(touches, with: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard !isDecided else { super.touchesMoved(touches, with: event); return }
        guard state == .possible, let start, let point = touches.first?.location(in: view) else { return }
        let dx = point.x - start.x, dy = point.y - start.y
        // Held back until the direction is clear, so the pan can't begin on a diagonal.
        guard hypot(dx, dy) >= SurahSwipe.decisionDistance else { return }
        guard SurahSwipe.isHorizontal(dx: dx, dy: dy) else { state = .failed; return }
        isDecided = true
        super.touchesMoved(touches, with: event)
    }

    override func reset() {
        super.reset()
        start = nil
        isDecided = false
    }

    /// Scroll views wait for this pan to fail before scrolling.
    override func shouldBeRequiredToFail(by other: UIGestureRecognizer) -> Bool {
        other is UIPanGestureRecognizer && other.view is UIScrollView
    }
}

struct SurahSwipeGesture: UIGestureRecognizerRepresentable {
    var isEnabled: Bool
    var onChange: (_ translationX: CGFloat) -> Void
    var onEnd: (_ translationX: CGFloat, _ velocityX: CGFloat) -> Void
    var onCancel: () -> Void

    func makeUIGestureRecognizer(context: Context) -> HorizontalPanGestureRecognizer {
        let recognizer = HorizontalPanGestureRecognizer()
        recognizer.maximumNumberOfTouches = 1
        return recognizer
    }

    /// Turning it off mid-drag cancels the drag, which springs back.
    func updateUIGestureRecognizer(_ recognizer: HorizontalPanGestureRecognizer, context: Context) {
        recognizer.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: HorizontalPanGestureRecognizer, context: Context) {
        let translationX = recognizer.translationX
        switch recognizer.state {
        case .began, .changed: onChange(translationX)
        case .ended: onEnd(translationX, recognizer.velocity(in: recognizer.view).x)
        case .cancelled, .failed: onCancel()
        default: break
        }
    }
}

/// The neighbour's name, uncovered at the edge the text moves away from.
struct SurahNeighborReveal: View {
    static let width: CGFloat = 132

    let side: ReaderNeighbor
    let caption: String
    let title: String
    let arabicName: String?

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: side == .next ? "chevron.right" : "chevron.left")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.bronze)
            if let arabicName {
                Text(arabicName).font(.quran(.listName)).lineLimit(1)
            }
            Text(title).font(.subheadline.weight(.semibold)).lineLimit(2)
            Text(caption).font(.caption).foregroundStyle(Color.secondaryWarm)
        }
        .multilineTextAlignment(.center)
        .minimumScaleFactor(0.8)
        .foregroundStyle(Color.appBrownText)
        .frame(width: Self.width)
        .accessibilityHidden(true)
    }
}

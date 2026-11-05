import SwiftUI

/// Whole 15-line Madani pages, one per screen, turned by swiping. Pages run right to left like a
/// printed mushaf, so swiping right goes on to the next page.
struct MushafPagerView: View {
    var currentGlobalAyah: Int?
    var hiddenAyahs: Set<Int> = []
    var selectionEnabled: Bool
    var focusedAyah: Int? = nil
    /// The piece being memorized; everything else fades back.
    var focusRange: VerseRange? = nil
    var markedAyahs: Set<Int> = []
    /// False while the user has paged away during playback; the page then stays where they put it.
    var isFollowing = true
    /// The pages that can be turned to: the whole Quran, or just a piece's while memorizing.
    var pageRange: ClosedRange<Int>
    /// The ayah whose page opens first.
    var startAyah: Int?
    var onSelect: (Int) -> Void
    /// A swipe came to rest on a page, going the given way.
    var onPageSettled: (Int, ReaderNeighbor) -> Void = { _, _ in }

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page: Int?
    @State private var settledPage: Int?

    /// Playback wins over the ayah the user picked, as in continuous text.
    private var followTarget: Int? { currentGlobalAyah ?? focusedAyah }

    var body: some View {
        if let library = environment.mushafPages {
            pager(library)
        } else {
            ContentUnavailableView(
                String(localized: "Mushaf pages are unavailable"),
                systemImage: "book.closed",
                description: Text("Choose another reading layout from the options menu.")
            )
        }
    }

    /// The rows only look up what's already worked out, since this runs on every update while a
    /// page turns: each page's text is composed once, by the library.
    private func pager(_ library: MushafPageLibrary) -> some View {
        let layout = library.layout
        return ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(layout.pages(in: pageRange)) { mushafPage in
                    MushafPageView(
                        page: mushafPage,
                        lines: library.lines(for: mushafPage),
                        referenceWidth: library.referenceWidth,
                        highlight: highlight(on: mushafPage),
                        selectionEnabled: selectionEnabled,
                        onSelect: onSelect
                    )
                    .containerRelativeFrame([.horizontal, .vertical])
                    .id(mushafPage.number)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $page)
        .scrollIndicators(.hidden)
        .environment(\.layoutDirection, .rightToLeft)
        .onAppear {
            let opening = clamped(layout.page(containing: startAyah ?? followTarget ?? 1))
            page = opening
            settledPage = opening
        }
        .onChange(of: followTarget) { _, target in
            guard isFollowing, let target else { return }
            turn(to: layout.page(containing: target))
        }
        .onChange(of: isFollowing) { _, following in
            guard following, let target = followTarget else { return }
            turn(to: layout.page(containing: target))
        }
        .onChange(of: pageRange) { _, range in
            if let page, !range.contains(page) { self.page = clamped(page) }
        }
        .onScrollPhaseChange { _, phase in
            guard phase == .idle, let page, let settled = settledPage, page != settled else { return }
            settledPage = page
            onPageSettled(page, page > settled ? .next : .previous)
        }
    }

    /// Turns to the page with the ayah: one page over glides, anything further jumps.
    private func turn(to target: Int) {
        let target = clamped(target)
        guard target != page else { return }
        let glides = !reduceMotion && page.map { abs($0 - target) == 1 } == true
        settledPage = target
        if glides {
            withAnimation(.easeInOut(duration: 0.35)) { page = target }
        } else {
            page = target
        }
    }

    private func clamped(_ number: Int) -> Int {
        min(max(number, pageRange.lowerBound), pageRange.upperBound)
    }

    /// Only this page's ayahs, so a change elsewhere leaves the page's inputs equal and it isn't redrawn.
    private func highlight(on page: MushafPage) -> MushafHighlightState {
        let ayahs = page.ayahs
        return MushafHighlightState(
            highlightedAyah: currentGlobalAyah.flatMap { ayahs.contains($0) ? $0 : nil },
            dimmedAyahs: focusRange.map { range in ayahs.filter { !range.contains($0) } } ?? [],
            markedAyahs: markedAyahs.intersection(ayahs),
            hiddenAyahs: hiddenAyahs.intersection(ayahs)
        )
    }
}

/// One page, drawn by `MushafPageCanvas` with the hidden-ayah bars laid over it.
private struct MushafPageView: UIViewRepresentable {
    var page: MushafPage
    var lines: [MushafComposedLine]
    var referenceWidth: CGFloat
    var highlight: MushafHighlightState
    var selectionEnabled: Bool
    var onSelect: (Int) -> Void

    func makeUIView(context: Context) -> MushafPageHostView<MushafPageCanvas> {
        MushafPageHostView<MushafPageCanvas>()
    }

    func updateUIView(_ host: MushafPageHostView<MushafPageCanvas>, context: Context) {
        let canvas = host.textView
        canvas.selectionEnabled = selectionEnabled
        canvas.onSelect = onSelect
        canvas.configure(
            page: page.number,
            lines: lines,
            widestLine: page.widestJustifiedWidth,
            referenceWidth: referenceWidth,
            highlight: highlight
        )
    }
}

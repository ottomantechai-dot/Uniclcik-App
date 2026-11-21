import AVFAudio
import ImageIO
import SwiftUI

struct BoosterPacksView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("packTour.browseLearned") private var browseLearned = false
    @AppStorage("packTour.selectLearned") private var selectLearned = false
    @State private var position: Double
    @State private var gestureOrigin: Double?
    @State private var tilt = CGSize.zero
    @State private var inspectionReturn: Task<Void, Never>?
    @State private var snap: Task<Void, Never>?
    @State private var paging = false
    @State private var selected: BoosterPack?
    @State private var renderer: BoosterScene.Wheel?

    private static let packs = BoosterPack.library
    private static let logos = Dictionary(uniqueKeysWithValues: packs.compactMap { pack in
        pack.logo.map { (pack.id, $0) }
    })
    private static let previews: [String: UIImage] = Dictionary(uniqueKeysWithValues: packs.compactMap { pack in
        let url = BoosterResources.folder.appendingPathComponent(pack.front)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 800
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return (pack.id, UIImage(cgImage: image))
    })

    private var centeredIndex: Int { wrapped(Int(position.rounded())) }

    init(initialPackID: String? = nil) {
        let index = Self.packs.firstIndex { $0.id == initialPackID } ?? 0
        _position = State(initialValue: Double(index))
    }

    var body: some View {
        ZStack {
            if let selected {
                BoosterOpeningView(pack: selected) {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24)) {
                        self.selected = nil
                    }
                }
                .id(selected.id)
                .transition(.opacity)
            } else {
                picker
                    .transition(.opacity)
            }
        }
        .background { BoosterBackdrop() }
        .preferredColorScheme(.light)
        .task {
            guard renderer == nil else { return }
            renderer = try? BoosterScene.Wheel(library: Self.packs)
        }
        .onDisappear {
            inspectionReturn?.cancel()
            snap?.cancel()
        }
    }

    private var picker: some View {
        let pack = Self.packs[centeredIndex]
        return VStack(spacing: 0) {
            ZStack(alignment: .leading) {
                BoosterCollectionBadge(name: pack.name, logo: Self.logos[pack.id])
                    .accessibilityIdentifier("cards.booster.collection")

                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close packs")
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)

            wheel
                .frame(maxHeight: .infinity)
        }
        .foregroundStyle(.primary)
    }

    private var wheel: some View {
        GeometryReader { proxy in
            let layout = BoosterWheelLayout(size: proxy.size)
            ZStack {
                ForEach(Self.packs.indices, id: \.self) { index in
                    let placement = layout.placement(index: index, count: Self.packs.count, position: position)
                    if placement.isVisible {
                        let pack = Self.packs[index]
                        Button {
                            if index == centeredIndex && snap == nil {
                                inspectionReturn?.cancel()
                                tilt = .zero
                                selectLearned = true
                                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24)) {
                                    selected = pack
                                }
                            } else {
                                settle(at: (position + placement.distance).rounded())
                            }
                        } label: {
                            packSurface(pack, layout: layout)
                        }
                        .buttonStyle(.plain)
                        .scaleEffect(placement.scale)
                        .rotation3DEffect(.degrees(reduceMotion ? 0 : placement.yaw),
                                          axis: (x: 0, y: 1, z: 0), perspective: 0.40)
                        .offset(x: placement.x, y: placement.y)
                        .opacity(placement.opacity)
                        .zIndex(-placement.depth)
                        .accessibilityLabel(pack.name)
                        .accessibilityHint("Double-tap to select. Swipe horizontally to browse more packs.")
                        .accessibilityIdentifier("cards.booster.pack.\(pack.id)")
                        .accessibilityHidden(index != centeredIndex)
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .overlay {
                if let renderer {
                    BoosterWheelStage(renderer: renderer, packs: Self.packs, layout: layout,
                                      position: position, tilt: tilt, reduceMotion: reduceMotion)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .overlay {
                if gestureOrigin == nil && snap == nil && (!browseLearned || !selectLearned) {
                    let kind: BoosterGestureCoach.Kind = browseLearned ? .select : .browse
                    let center = layout.placement(index: centeredIndex, count: Self.packs.count, position: position)
                    BoosterGestureCoach(kind: kind, travel: layout.packWidth * 0.64, captionOffset: 59)
                        .position(x: proxy.size.width / 2,
                                  y: proxy.size.height / 2 + center.y + layout.packHeight * 0.26)
                }
            }
            .contentShape(Rectangle())
            .clipped()
            .highPriorityGesture(wheelGesture(layout))
            .accessibilityElement(children: .contain)
            .accessibilityAdjustableAction { action in
                switch action {
                case .increment: settle(by: 1)
                case .decrement: settle(by: -1)
                @unknown default: break
                }
            }
        }
        .sensoryFeedback(.selection, trigger: centeredIndex)
    }

    private func packSurface(_ pack: BoosterPack, layout: BoosterWheelLayout) -> some View {
        let shape = RoundedRectangle(cornerRadius: 5)
        return Color.clear
            .frame(width: layout.packWidth, height: layout.packHeight)
            .overlay {
                if let image = Self.previews[pack.id] {
                    if renderer == nil {
                        Image(uiImage: image).resizable().interpolation(.high).clipShape(shape)
                    }
                    Image(uiImage: image).resizable().interpolation(.high)
                        .clipShape(shape)
                        .scaleEffect(x: 1, y: -1)
                        .mask(alignment: .top) {
                            LinearGradient(colors: [.white.opacity(0.21), .clear],
                                           startPoint: .top, endPoint: .bottom)
                                .frame(height: layout.packWidth * 0.68)
                        }
                        .offset(y: layout.packHeight + 9)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(shape)
    }

    private func wheelGesture(_ layout: BoosterWheelLayout) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                if gestureOrigin == nil {
                    let interrupted = snap != nil
                    snap?.cancel()
                    snap = nil
                    inspectionReturn?.cancel()
                    inspectionReturn = nil
                    gestureOrigin = position
                    paging = interrupted
                }
                guard let gestureOrigin else { return }
                let movement = value.translation
                if paging || isBrowse(movement, spacing: layout.spacing) {
                    let threshold = paging && gestureOrigin != gestureOrigin.rounded() ? 0 : browseThreshold(layout.spacing)
                    paging = true
                    tilt = .zero
                    position = gestureOrigin + browseOffset(movement.width, spacing: layout.spacing, threshold: threshold)
                } else if !reduceMotion {
                    tilt = inspectionTilt(for: movement)
                }
            }
            .onEnded { value in
                let origin = gestureOrigin ?? position
                gestureOrigin = nil
                let movement = value.translation
                let shouldBrowse = paging || isBrowse(movement, spacing: layout.spacing)
                paging = false
                guard shouldBrowse else {
                    guard !reduceMotion else { return }
                    tilt = inspectionTilt(for: movement)
                    inspectionReturn = Task { @MainActor in
                        do {
                            try await Task.sleep(for: .milliseconds(75))
                        } catch {
                            return
                        }
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) { tilt = .zero }
                        inspectionReturn = nil
                    }
                    return
                }
                let threshold = origin == origin.rounded() ? browseThreshold(layout.spacing) : 0
                let offset = browseOffset(movement.width, spacing: layout.spacing, threshold: threshold)
                let fling = (movement.width - value.predictedEndTranslation.width) / layout.spacing
                let projected = offset + min(0.60, max(-0.60, fling * 0.5))
                let bias = abs(projected) >= 0.32 ? (projected > 0 ? 0.17 : -0.17) : 0
                let target = (origin + projected + bias).rounded()
                if target != origin.rounded() { browseLearned = true }
                settle(at: target)
            }
    }

    private func browseThreshold(_ spacing: CGFloat) -> CGFloat {
        min(32, spacing * 0.16)
    }

    private func isBrowse(_ movement: CGSize, spacing: CGFloat) -> Bool {
        abs(movement.width) > browseThreshold(spacing) && abs(movement.width) > abs(movement.height) * 1.15
    }

    private func browseOffset(_ horizontal: CGFloat, spacing: CGFloat, threshold: CGFloat) -> Double {
        min(2.25, max(0, abs(horizontal) - threshold) / spacing) * (horizontal < 0 ? 1 : -1)
    }

    private func inspectionTilt(for movement: CGSize) -> CGSize {
        CGSize(width: 18 * tanh(movement.width / 28),
               height: 15 * tanh(movement.height / 36))
    }

    private func wrapped(_ index: Int) -> Int {
        let count = Self.packs.count
        return (index % count + count) % count
    }

    private func settle(by step: Int) {
        settle(at: position.rounded() + Double(step))
    }

    private func settle(at target: Double) {
        inspectionReturn?.cancel()
        inspectionReturn = nil
        snap?.cancel()
        snap = nil
        tilt = .zero
        let start = position
        let distance = target - start
        guard !reduceMotion, abs(distance) > 0.001 else {
            position = target
            return
        }

        // The same position drives the foil, reflections, hit targets and logo throughout the snap.
        let duration = min(0.36, 0.20 + abs(distance) * 0.11)
        snap = Task { @MainActor in
            let clock = ContinuousClock()
            let began = clock.now
            while !Task.isCancelled {
                let elapsed = began.duration(to: clock.now).components
                let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
                let progress = min(1, seconds / duration)
                position = start + distance * (1 - pow(1 - progress, 3))
                if progress >= 1 {
                    position = target
                    snap = nil
                    return
                }
                try? await clock.sleep(for: .milliseconds(16))
            }
        }
    }
}

private struct BoosterGestureCoach: View {
    enum Kind: String {
        case browse, select, cut

        var title: LocalizedStringKey {
            switch self {
            case .browse: "Swipe to browse"
            case .select: "Tap the pack"
            case .cut: "Swipe along the seal"
            }
        }
    }

    let kind: Kind
    let travel: CGFloat
    let captionOffset: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Color.clear.frame(width: 1, height: 1)
            .overlay {
                TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
                    let cycle = reduceMotion ? 0.42 : context.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: 2.30) / 2.30
                    let progress = min(1, max(0, (cycle - 0.17) / 0.55))
                    let slide = progress * progress * (3 - 2 * progress)
                    let opacity = reduceMotion ? 1 : min(1, cycle / 0.12, (1 - cycle) / 0.22)
                    let x = kind == .select ? 0 : travel * (kind == .browse ? 0.5 - slide : slide - 0.5)
                    let pulse = max(0, 1 - abs(cycle - 0.43) / 0.17)
                    let hover = kind == .select ? 11 * (1 - pulse) : 0

                    ZStack {
                        Circle()
                            .strokeBorder(.white.opacity(kind == .select ? 0.9 * pulse : 0.76), lineWidth: 1.4)
                            .background(.cyan.opacity(0.25), in: .circle)
                            .frame(width: 13, height: 13)
                            .scaleEffect(kind == .select ? 1 + 1.1 * pulse : 1)
                            .shadow(color: .blue.opacity(0.45), radius: 4)
                        Image(systemName: "hand.point.up.left.fill")
                            .font(.system(size: 29, weight: .semibold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.60), radius: 1)
                            .shadow(color: .black.opacity(0.22), radius: 4, y: 2)
                            .offset(x: 12, y: 14 + hover)
                    }
                    .fixedSize()
                    .offset(x: x)
                    .opacity(opacity)
                }
                .accessibilityHidden(true)
            }
            .overlay {
                Text(kind.title)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .glassEffect(.regular, in: .capsule)
                    .fixedSize()
                    .offset(y: captionOffset)
                    .accessibilityIdentifier("cards.booster.coach.\(kind.rawValue)")
            }
            .allowsHitTesting(false)
    }
}

private struct BoosterBackdrop: View {
    var special = false
    private static let art = BoosterResources.image("opening-sky.png")

    var body: some View {
        ZStack {
            if special {
                BoosterSpecialSky()
            } else {
                GeometryReader { proxy in
                    if let art = Self.art {
                        Image(uiImage: art).resizable()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                    } else {
                        Color(red: 0.80, green: 0.90, blue: 0.96)
                    }
                }
            }
            BoosterBrandPattern()
            if special { BoosterSpecialSparkles() }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct BoosterBrandPattern: View {
    var body: some View {
        Canvas { context, size in
            let logo = context.resolve(Image("LoginBrandPattern"))
            let spacing = min(104, max(64, size.width / 4.7))
            let rowSpacing = spacing * 0.87
            let rows = Int(ceil(size.height / rowSpacing))
            let columns = Int(ceil(size.width / spacing))
            let opacities = [0.10, 0.17, 0.12, 0.20]
            let angles = [-11.0, 6.0, -4.0, 12.0]

            for row in 0..<rows {
                for column in 0..<columns {
                    let variation = (row * 3 + column) % opacities.count
                    let width = spacing * (0.38 + 0.04 * CGFloat(variation))
                    let height = width * 726 / 663
                    let stagger = row.isMultiple(of: 2) ? 0.32 : 0.74

                    var stamp = context
                    stamp.opacity = opacities[variation]
                    stamp.translateBy(x: (CGFloat(column) + stagger) * spacing,
                                      y: (CGFloat(row) + 0.45) * rowSpacing)
                    stamp.rotate(by: .degrees(angles[variation]))
                    stamp.draw(logo, in: CGRect(x: -width / 2, y: -height / 2, width: width, height: height))
                }
            }
        }
    }
}

private struct BoosterCollectionBadge: View {
    let name: String
    let logo: UIImage?

    var body: some View {
        Group {
            if let logo {
                Image(uiImage: logo).resizable().interpolation(.high).scaledToFit()
                    .frame(width: 102, height: 38)
            } else {
                Text(name).font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(height: 38)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 4)
        .glassEffect(.regular, in: .capsule)
        .accessibilityLabel(name)
        .accessibilityAddTraits(.isHeader)
        .padding(.horizontal, 56)
        .frame(maxWidth: .infinity)
    }
}

private struct BoosterOpeningView: View {
    let pack: BoosterPack
    let close: () -> Void
    private let packLogo: UIImage?

    init(pack: BoosterPack, close: @escaping () -> Void) {
        self.pack = pack
        self.close = close
        packLogo = pack.logo
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("packTour.cutLearned") private var cutLearned = false

    private enum Phase: Equatable { case sealed, positioning, ready, opening, cards, finished }
    @State private var phase: Phase = .sealed
    @State private var renderer: BoosterScene?
    @State private var hand: [BoosterCard] = []
    @State private var index = 0
    @State private var loadError = false
    @State private var loadAttempt = 0
    @State private var dragTilt = CGSize.zero
    @State private var dragShift = CGSize.zero
    @State private var cardSlide = 0.0
    @State private var openingSwipeConsumed = false
    @GestureState private var draggingStage = false
    @State private var reviewIndex: Int?
    @State private var reviewDrag = CGFloat.zero
    @State private var prices: [String: Double] = [:]
    @State private var positionDate = Date.distantPast
    @State private var openingDate = Date.distantPast
    @State private var guideDate = Date.distantPast
    @State private var animationTime = Date.distantPast
    @State private var slideAnimation: CardSlide?
    @State private var specialDate: Date?

    private struct CardSlide: Equatable {
        let start: Date
        let from: Double
        let target: Double
        let duration: Double

        func value(at date: Date) -> Double {
            let progress = min(1, max(0, date.timeIntervalSince(start) / duration))
            let eased = 1 - pow(1 - progress, 3)
            return from + (target - from) * eased
        }
    }

    private let focusDuration = 0.44
    private let guideDuration = 0.25
    private let cutDuration = 0.20
    private let openingDuration = 1.36
    private let sealRelease = 0.29
    private var card: BoosterCard? { hand.indices.contains(index) ? hand[index] : nil }
    private let specialDuration = 2.0
    /// La carta especial es la que está delante: fondo arcoíris, giro y brillo.
    private var specialActive: Bool { phase == .cards && card?.isHit == true }
    private var specialBusy: Bool {
        guard specialActive, !reduceMotion else { return false }
        guard let specialDate else { return true }
        return Date.now.timeIntervalSince(specialDate) < 1.55
    }

    private var specialFX: BoosterSpecialFX {
        guard let special = hand.firstIndex(where: \.isHit) else { return BoosterSpecialFX() }
        var fx = BoosterSpecialFX(index: special)
        if reduceMotion {
            fx.glow = specialActive ? 0.85 : 0
            return fx
        }
        guard specialActive else { return fx }
        func smooth(_ value: Double) -> Double {
            let t = min(1, max(0, value))
            return t * t * (3 - 2 * t)
        }
        // Empieza de frente como las demás, da una vuelta completa y vuelve a su sitio.
        let t = specialDate.map { max(0, animationTime.timeIntervalSince($0)) } ?? 0
        let turn = min(1, max(0, (t - 0.18) / 1.05))
        let eased = turn < 0.5 ? 4 * turn * turn * turn : 1 - pow(-2 * turn + 2, 3) / 2
        fx.spin = turn >= 1 ? 0 : 2 * .pi * eased
        fx.flash = t < 1.12 ? smooth((t - 0.86) / 0.24) : 1 - smooth((t - 1.18) / 0.40)
        fx.glow = smooth((t - 0.95) / 0.30)
        fx.scale = 1 + 0.07 * sin(.pi * min(1, max(0, (t - 0.18) / 1.25)))
        return fx
    }

    var body: some View {
        openingContent
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if specialActive {
                BoosterBackdrop(special: true)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.55), value: specialActive)
        .preferredColorScheme(.light)
        .task(id: loadAttempt) { load() }
        .task(id: hand.map(\.id)) {
            let quotes = await BoosterMarketPrices.load(hand)
            if !Task.isCancelled { prices = quotes }
        }
        .task(id: phase) {
            if phase == .positioning {
                await animate(from: positionDate, duration: focusDuration)
                if !Task.isCancelled {
                    guideDate = .now
                    phase = .ready
                }
                return
            }
            if phase == .ready {
                BoosterSounds.play(.ready)
                if !reduceMotion {
                    await animate(from: guideDate, duration: guideDuration)
                }
                return
            }
            guard phase == .opening else { return }
            let duration = reduceMotion ? 0.12 : cutDuration + openingDuration
            let revealTime = reduceMotion ? 0.08 : cutDuration + 0.81
            let reveal: BoosterSounds.Cue = hand.first?.isHit == true ? .special : .reveal
            let cues: [(time: Double, sound: BoosterSounds.Cue)] = reduceMotion
                ? [(revealTime, reveal)]
                : [(revealTime, reveal)]
            await animate(from: openingDate, duration: duration, cues: cues)
            guard !Task.isCancelled else { return }
            phase = .cards
        }
        .task(id: slideAnimation) {
            guard let slideAnimation else { return }
            await animate(from: slideAnimation.start, duration: slideAnimation.duration)
            guard !Task.isCancelled else { return }
            if slideAnimation.target > 0 {
                advanceCard()
            } else {
                cardSlide = 0
                self.slideAnimation = nil
            }
        }
        .onChange(of: specialActive) { _, active in
            specialDate = active ? .now : nil
            BoosterMusic.duck(active)
        }
        .onChange(of: scenePhase) { _, next in
            if next == .active { BoosterMusic.resume() } else { BoosterMusic.pause() }
        }
        .onDisappear { BoosterMusic.stop() }
        .task(id: specialDate) {
            guard let specialDate, !reduceMotion else { return }
            await animate(from: specialDate, duration: specialDuration)
        }
        .sensoryFeedback(.impact(weight: .heavy), trigger: specialDate) { _, next in next != nil }
        .onChange(of: draggingStage) { _, dragging in
            guard !dragging else { return }
            openingSwipeConsumed = false
            if phase == .cards, slideAnimation == nil {
                recenterDrag()
                cardSlide = 0
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: phase) { _, next in next == .opening }
        .sensoryFeedback(.selection, trigger: index)
    }

    private var openingContent: some View {
        ZStack {
            if phase == .finished {
                recap
            } else if let renderer, card != nil {
                stage(renderer)
                    .ignoresSafeArea(.container)
                    .overlay(alignment: .bottom) { controls }
            } else if loadError {
                ContentUnavailableView {
                    Label("Pack unavailable", systemImage: "rectangle.portrait.slash")
                } actions: {
                    Button("Try Again") { loadAttempt += 1 }
                        .buttonStyle(.bordered)
                }
            } else {
                ProgressView("Loading pack")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .top) { header }
    }

    private var recap: some View {
        Group {
            if let reviewIndex {
                carousel(index: reviewIndex)
            } else {
                GeometryReader { proxy in
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                            ForEach(hand.indices, id: \.self) { index in
                                let card = hand[index]
                                Button {
                                    reviewIndex = index
                                } label: {
                                    recapCard(card, cornerRadius: 10)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(cardLabel(card))
                                .accessibilityIdentifier("cards.booster.recap.\(card.id)")
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, proxy.safeAreaInsets.top + 66)
                        .padding(.bottom, proxy.safeAreaInsets.bottom + 80)
                    }
                    .scrollIndicators(.hidden)
                    .ignoresSafeArea(.container, edges: [.top, .bottom])
                }
            }
        }
        .overlay(alignment: .bottom) {
            Button(action: close) {
                Text("Save")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
            }
            .buttonStyle(.glass)
            .padding(.horizontal, 24)
            .padding(.vertical, 9)
            .accessibilityIdentifier("cards.booster.save")
            .background {
                Rectangle().fill(.ultraThinMaterial)
                    .mask {
                        LinearGradient(colors: [.clear, .black.opacity(0.75)],
                                       startPoint: .top, endPoint: .bottom)
                    }
                    .ignoresSafeArea(.container, edges: .bottom)
                    .allowsHitTesting(false)
            }
        }
    }

    private func carousel(index: Int) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let cardWidth = max(0, min(width - 48, proxy.size.height * 0.62))
            ZStack {
                ForEach(hand.indices, id: \.self) { position in
                    recapCard(hand[position], cornerRadius: 14)
                        .frame(width: cardWidth)
                        .offset(x: CGFloat(position - index) * width + reviewDrag)
                        .accessibilityHidden(position != index)
                }
            }
            .frame(width: width, height: proxy.size.height)
            .contentShape(Rectangle())
            .clipped()
            .gesture(DragGesture(minimumDistance: 9)
                .onChanged { value in
                    let horizontal = value.translation.width
                    guard abs(horizontal) > abs(value.translation.height) else { return }
                    let beyondEdge = (index == 0 && horizontal > 0) ||
                        (index == hand.count - 1 && horizontal < 0)
                    reviewDrag = beyondEdge ? horizontal * 0.22 : horizontal
                }
                .onEnded { value in
                    let horizontal = value.translation.width
                    let travel = value.predictedEndTranslation.width
                    let isSwipe = abs(horizontal) >= 12 && abs(horizontal) > abs(value.translation.height) &&
                        (abs(horizontal) > width * 0.16 || abs(travel) > width * 0.36)
                    moveReview(to: index + (isSwipe ? (horizontal < 0 ? 1 : -1) : 0))
                }
            )
            .accessibilityElement(children: .combine)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: moveReview(to: index + 1)
                case .decrement: moveReview(to: index - 1)
                @unknown default: break
                }
            }
        }
        .padding(.vertical, 66)
        .accessibilityIdentifier("cards.booster.carousel")
    }

    private func moveReview(to index: Int) {
        let newIndex = min(hand.count - 1, max(0, index))
        if reviewIndex != newIndex { BoosterSounds.swipe(cardIndex: newIndex) }
        withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86)) {
            reviewIndex = newIndex
            reviewDrag = 0
        }
    }

    private func recapCard(_ card: BoosterCard, cornerRadius: CGFloat) -> some View {
        Color.clear
            .aspectRatio(5.0 / 7.0, contentMode: .fit)
            .overlay {
                if let image = card.image() {
                    Image(uiImage: image).resizable()
                }
            }
            .clipShape(.rect(cornerRadius: cornerRadius))
            .overlay(alignment: .bottomTrailing) {
                if let price = prices[card.id] {
                    Text(price, format: .currency(code: "USD"))
                        .font(.footnote.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .glassEffect(.regular, in: .capsule)
                        .padding(7)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(cardLabel(card))
    }

    private func cardLabel(_ card: BoosterCard) -> String {
        guard let price = prices[card.id] else { return card.name }
        return "\(card.name), \(price.formatted(.currency(code: "USD")))"
    }

    private var header: some View {
        ZStack(alignment: .leading) {
            BoosterCollectionBadge(name: pack.name, logo: packLogo)

            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 16, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close pack")

            if reviewIndex != nil {
                Button {
                    reviewIndex = nil
                    reviewDrag = 0
                } label: {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("All cards")
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 5)
    }

    private func stage(_ renderer: BoosterScene) -> some View {
        GeometryReader { proxy in
            let size = proxy.size
            let seal = renderer.focusedSeal(in: size)
            let opening = phase == .opening && !reduceMotion
            let elapsed = max(0, animationTime.timeIntervalSince(openingDate))
            let releaseTime = elapsed - cutDuration
            let frame: Double = switch phase {
            case .sealed, .positioning, .ready: 0
            case .opening where reduceMotion: renderer.finalFrame
            case .opening where releaseTime < 0: 0
            case .opening: openingFrame(at: releaseTime, end: renderer.finalFrame)
            case .cards, .finished: renderer.finalFrame
            }
            let slide = slideAnimation?.value(at: animationTime) ?? cardSlide
            let approach = min(1, max(0, animationTime.timeIntervalSince(positionDate) / focusDuration))
            let focus = switch phase {
            case .sealed: 0.0
            case .positioning: approach * approach * (3 - 2 * approach)
            case .ready, .opening, .cards, .finished: 1.0
            }
            let progress = opening ? min(1, elapsed / cutDuration) : 0
            let trace = progress * (2 - progress)
            let release = opening ? 1 - min(1, max(0, releaseTime / sealRelease)) : 0
            let flash = opening && releaseTime >= 0 ? max(0, min(1, releaseTime / sealRelease)) : 0
            let guide = min(1, max(0, animationTime.timeIntervalSince(guideDate) / guideDuration))
            let special = specialFX
            BoosterStage(renderer: renderer, hand: hand, firstCard: index, frame: frame,
                         tilt: dragTilt, shift: dragShift,
                         viewport: size, focus: focus, slide: slide, cut: trace, cutWeight: release,
                         sealGuideProgress: phase == .ready ? (reduceMotion ? 1 : guide * (2 - guide)) : 0,
                         animateSealGuide: !reduceMotion && scenePhase == .active, special: special)
                .overlay(alignment: .topLeading) {
                    if phase == .cards, let card, let price = prices[card.id] {
                        let frame = renderer.settledCardFrame(in: size)
                        let settled = special.index == index && !reduceMotion
                            ? min(1, max(0, (max(0, animationTime.timeIntervalSince(specialDate ?? .now)) - 1.35) / 0.35))
                            : 1.0
                        Text(price, format: .currency(code: "USD"))
                            .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.black)
                            .contentTransition(.numericText())
                            .frame(width: frame.width, height: 62)
                            .glassEffect(.regular, in: .rect(cornerRadius: 22))
                            .offset(x: frame.minX, y: frame.maxY + 16)
                            .opacity(settled * max(0, 1 - slide * 4))
                            .allowsHitTesting(false)
                            .accessibilityLabel("Market price \(price.formatted(.currency(code: "USD")))")
                            .id(card.id)
                            .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.25), value: index)
                .overlay {
                    if special.flash > 0.01 {
                        RadialGradient(colors: [.white.opacity(0.5 * special.flash), .white.opacity(0)],
                                       center: .center, startRadius: 20, endRadius: size.height * 0.62)
                            .blendMode(.plusLighter)
                            .allowsHitTesting(false)
                    }
                }
                .overlay {
                    if trace > 0 && release > 0 {
                        Rectangle().fill(.black.opacity(0.19 * min(1, trace * 3) * pow(release, 2)))
                        tearLight(across: seal, progress: trace, strength: release, flash: flash)
                    }
                }
            .accessibilityHidden(true)
            .overlay {
                if phase == .ready && !cutLearned {
                    BoosterGestureCoach(kind: .cut, travel: seal.width * 0.84, captionOffset: -42)
                        .position(x: seal.midX, y: seal.midY)
                }
            }
            .overlay {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(interaction(in: size, seal: seal))
                    .simultaneousGesture(SpatialTapGesture().onEnded { tap in
                        if renderer.containsSealedPack(tap.location, in: size) { positionPack() }
                    })
            }
        }
        .clipped()
    }

    private var controls: some View {
        VStack(spacing: 7) {
            switch phase {
            case .sealed:
                gestureHint("Tap the pack", icon: "hand.tap")
                    .accessibilityAction(named: Text("Position pack")) { positionPack() }
            case .ready:
                Color.clear.frame(width: 1, height: 1)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Pack seal")
                    .accessibilityAction(named: Text("Open pack")) { begin() }
            case .positioning, .opening, .finished:
                EmptyView()
            case .cards:
                if let card {
                    Color.clear.frame(width: 1, height: 1)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Card \(index + 1) of \(hand.count), \(card.name), \(card.rarity)")
                        .accessibilityAction(named: Text(index < hand.count - 1 ? "Next card" : "Finish pack")) {
                            finishSwipe(toward: 1.2)
                        }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 32)
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
    }

    private func gestureHint(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 15)
            .padding(.vertical, 9)
            .glassEffect(.regular, in: .capsule)
    }

    private func animate(from start: Date, duration: Double,
                         cues: [(time: Double, sound: BoosterSounds.Cue)] = []) async {
        let deadline = start.addingTimeInterval(duration)
        var nextCue = 0
        while !Task.isCancelled {
            let now = Date.now
            animationTime = min(now, deadline)
            let elapsed = now.timeIntervalSince(start)
            while nextCue < cues.count, elapsed >= cues[nextCue].time {
                let cue = cues[nextCue]
                if scenePhase == .active, elapsed - cue.time < 0.15 {
                    BoosterSounds.play(cue.sound)
                }
                nextCue += 1
            }
            guard now < deadline else { return }
            try? await Task.sleep(for: .milliseconds(16))
        }
    }

    private func openingFrame(at time: Double, end: Double) -> Double {
        if time < sealRelease {
            let t = time / sealRelease
            return 12 + 18 * t * t
        }
        if time < 0.73 { return 30 + 25 * (time - sealRelease) / (0.73 - sealRelease) }
        if time < 1.10 { return 55 + 33 * (time - 0.73) / 0.37 }
        return 88 + (end - 88) * min(1, (time - 1.10) / (openingDuration - 1.10))
    }

    private func tearLight(across seal: CGRect, progress: Double, strength: Double, flash: Double) -> some View {
        Canvas { context, size in
            let x = seal.minX + seal.width * progress
            let head = CGPoint(x: x, y: seal.midY)
            let tail = CGPoint(x: max(seal.minX, x - 48), y: seal.midY)
            let path = Path { path in
                path.move(to: CGPoint(x: seal.minX, y: seal.midY))
                path.addQuadCurve(to: head, control: CGPoint(x: seal.minX + (x - seal.minX) * 0.55,
                                                             y: seal.midY - 2.5))
            }
            var glow = context
            glow.addFilter(.blur(radius: 8))
            glow.stroke(path, with: .color(Color(red: 0.22, green: 0.74, blue: 1).opacity(0.78 * strength)),
                        style: StrokeStyle(lineWidth: 11, lineCap: .round))
            glow.fill(Path(ellipseIn: CGRect(x: x - 17, y: head.y - 12, width: 34, height: 24)),
                      with: .color(Color(red: 0.56, green: 0.57, blue: 1).opacity(0.86 * strength)))
            context.stroke(path, with: .color(Color(red: 0.30, green: 0.78, blue: 1).opacity(0.82 * strength)),
                           style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            if head.x - tail.x > 1 {
                var tip = Path()
                tip.move(to: tail)
                tip.addLine(to: head)
                context.stroke(tip, with: .linearGradient(
                    Gradient(colors: [.clear, .white.opacity(0.98 * strength)]), startPoint: tail, endPoint: head
                ), style: StrokeStyle(lineWidth: BoosterScene.sealBeamWidth, lineCap: .round))
            }
            context.fill(Path(ellipseIn: CGRect(x: x - 3, y: head.y - 3, width: 6, height: 6)),
                         with: .color(.white.opacity(strength)))
            if flash > 0 && flash < 1 {
                drawSealFlash(in: context, across: seal, screenWidth: size.width, progress: flash)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawSealFlash(in context: GraphicsContext, across seal: CGRect,
                               screenWidth: CGFloat, progress: Double) {
        let rise = min(1, progress / 0.20)
        let fall = min(1, (1 - progress) / 0.64)
        let swell = pow(rise * fall, 1.18)
        let width = seal.width + max(0, screenWidth - seal.width + 16) * swell
        let core = CGRect(x: seal.midX - width / 2, y: seal.midY - 2 - 16 * swell,
                          width: width, height: 4 + 32 * swell)
        let aura = core.insetBy(dx: -10 * swell, dy: -10 * swell)
        let colors = Gradient(stops: [
            .init(color: .clear, location: 0),
            .init(color: Color(red: 0.75, green: 0.43, blue: 1), location: 0.08),
            .init(color: Color(red: 0.28, green: 0.89, blue: 1), location: 0.22),
            .init(color: Color(red: 1, green: 0.77, blue: 0.42), location: 0.32),
            .init(color: .white, location: 0.43),
            .init(color: .white, location: 0.57),
            .init(color: Color(red: 0.48, green: 0.96, blue: 0.68), location: 0.72),
            .init(color: Color(red: 0.20, green: 0.67, blue: 1), location: 0.87),
            .init(color: .clear, location: 1)
        ])
        let shape = Path(roundedRect: aura, cornerRadius: min(18, aura.height * 0.45))
        let spectrum = GraphicsContext.Shading.linearGradient(colors,
            startPoint: CGPoint(x: seal.midX, y: aura.minY),
            endPoint: CGPoint(x: seal.midX, y: aura.maxY))

        var bloom = context
        bloom.opacity = 0.65 * swell
        bloom.addFilter(.blur(radius: 4 + 6 * swell))
        bloom.fill(shape, with: spectrum)

        var fringe = context
        fringe.opacity = 0.92 * swell
        fringe.addFilter(.blur(radius: 0.8))
        fringe.fill(shape, with: spectrum)

        var white = context
        white.opacity = min(1, swell * 1.55)
        white.addFilter(.blur(radius: 0.8 + 1.3 * swell))
        white.fill(Path(roundedRect: core, cornerRadius: min(12, core.height * 0.45)), with: .color(.white))
    }

    private func interaction(in size: CGSize, seal: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .updating($draggingStage) { _, dragging, _ in dragging = true }
            .onChanged { value in
                guard !openingSwipeConsumed else { return }
                let movement = value.translation
                if phase == .cards {
                    guard slideAnimation == nil, !specialBusy, startsOnCard(value, in: size) else { return }
                    if isCardSwipe(movement, in: size) {
                        if cardSlide == 0 { recenterDrag() }
                        cardSlide = Double((movement.width - size.width * 0.23) / max(1, size.width))
                    } else {
                        cardSlide = 0
                        if !reduceMotion { tiltObject(by: movement, in: size) }
                    }
                    return
                }
                guard phase == .sealed || phase == .ready else { return }
                let nearSeal = abs(value.startLocation.y - seal.midY) < max(25, size.width * 0.073)
                let overSeal = value.startLocation.x >= seal.minX - 14 && value.startLocation.x <= seal.maxX + 14
                let shortSwipe = movement.width > max(10, abs(movement.height) * 1.25)
                if phase == .ready && nearSeal && overSeal && shortSwipe {
                    openingSwipeConsumed = true
                    begin()
                } else if !reduceMotion {
                    tiltObject(by: movement, in: size)
                }
            }
            .onEnded { value in
                recenterDrag()
                guard phase == .cards, !openingSwipeConsumed, startsOnCard(value, in: size) else { return }
                finishSwipe(toward: isCardSwipe(value.translation, in: size) ? 1.2 : 0)
            }
    }

    private func startsOnCard(_ value: DragGesture.Value, in size: CGSize) -> Bool {
        abs(value.startLocation.x - size.width / 2) < size.width * 0.41 &&
            abs(value.startLocation.y - size.height / 2) < size.width * 0.54
    }

    private func isCardSwipe(_ movement: CGSize, in size: CGSize) -> Bool {
        movement.width > size.width * 0.23 && movement.width > abs(movement.height) * 1.55
    }

    private func tiltObject(by movement: CGSize, in size: CGSize) {
        dragTilt = CGSize(
            width: 13 * tanh(movement.width / (size.width * 0.25)),
            height: 10 * tanh(movement.height / (size.height * 0.15))
        )
        dragShift = CGSize(width: 0.094 * tanh(movement.width / (size.width * 0.34)),
                           height: -0.087 * tanh(movement.height / (size.height * 0.23)))
    }

    private func recenterDrag() {
        withAnimation(.spring(response: 0.30, dampingFraction: 0.75)) {
            dragTilt = .zero
            dragShift = .zero
        }
    }

    private func load() {
        guard renderer == nil else { return }
        loadError = false
        do {
            let available: [BoosterCard] = try BoosterResources.load(pack.catalog)
            let cards = try BoosterResources.draw(from: available)
            let scene = try BoosterScene(pack: pack)
            hand = cards
            prices = Dictionary(uniqueKeysWithValues: cards.compactMap { card in
                card.referencePrice.map { (card.id, $0) }
            })
            renderer = scene
            BoosterSounds.prepare()
            BoosterSounds.play(.appear)
            BoosterMusic.start()
            positionPack()
        } catch {
            print("[Booster] Could not load \(pack.name): \(error)")
            loadError = true
        }
    }

    private func positionPack() {
        guard phase == .sealed, renderer != nil else { return }
        BoosterSounds.play(.select)
        dragTilt = .zero
        dragShift = .zero
        positionDate = .now
        phase = reduceMotion ? .ready : .positioning
    }

    private func begin() {
        guard phase == .ready, renderer != nil else { return }
        cutLearned = true
        BoosterSounds.play(.cut)
        dragTilt = .zero
        dragShift = .zero
        openingDate = .now
        phase = .opening
    }

    private func finishSwipe(toward target: Double) {
        guard phase == .cards, slideAnimation == nil, !specialBusy, target > 0 || cardSlide > 0 else { return }
        if target > 0 {
            if index == hand.count - 1 { BoosterSounds.play(.last) }
            else { BoosterSounds.swipe(cardIndex: index) }
        }
        if reduceMotion {
            if target > 0 { advanceCard() }
            else { cardSlide = 0 }
            return
        }

        let duration = target > 0 ? 0.11 + 0.09 * (1 - min(1, cardSlide)) : 0.20
        slideAnimation = CardSlide(start: .now, from: cardSlide, target: target, duration: duration)
    }

    private func advanceCard() {
        cardSlide = 0
        slideAnimation = nil
        if index < hand.count - 1 {
            index += 1
            if hand[index].isHit { BoosterSounds.play(.specialNext) }
        } else {
            BoosterSounds.play(.recap)
            phase = .finished
        }
    }
}

/// Fondo arcoíris suave que va cambiando de color mientras se muestra la carta especial.
private struct BoosterSpecialSky: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let drift = Float(sin(t * 0.45)) * 0.10
            let lift = Float(cos(t * 0.38)) * 0.10
            let hues: [Double] = [0.92, 0.02, 0.08, 0.84, 0.95, 0.04, 0.68, 0.76, 0.58]
            MeshGradient(width: 3, height: 3, points: [
                [0, 0], [0.5 + drift, 0], [1, 0],
                [0, 0.5 + lift], [0.5 - drift, 0.5 - lift], [1, 0.5 - lift],
                [0, 1], [0.5 - drift, 1], [1, 1]
            ], colors: hues.enumerated().map { offset, hue in
                let shifted = (hue + 1 + 0.075 * sin(t * 0.42 + Double(offset) * 0.9)).truncatingRemainder(dividingBy: 1)
                return Color(hue: shifted < 0 ? shifted + 1 : shifted,
                             saturation: offset == 4 ? 0.34 : 0.50, brightness: 1)
            })
        }
    }
}

/// Partículas blancas suaves que suben y parpadean sobre el fondo de la carta especial.
private struct BoosterSpecialSparkles: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                var soft = context
                soft.addFilter(.blur(radius: 5))
                for particle in 0..<42 {
                    let seed = Double(particle)
                    func noise(_ salt: Double) -> Double {
                        let value = sin(seed * 12.9898 + salt * 78.233) * 43758.5453
                        return value - floor(value)
                    }
                    let speed = 0.012 + 0.030 * noise(1)
                    let rise = (noise(2) - t * speed).truncatingRemainder(dividingBy: 1)
                    let y = (rise < 0 ? rise + 1 : rise) * (size.height + 40) - 20
                    let x = noise(3) * size.width + sin(t * (0.3 + noise(4) * 0.5) + seed) * 10
                    let radius = 1.2 + 3.4 * pow(noise(5), 2.2)
                    let twinkle = 0.30 + 0.70 * pow(abs(sin(t * (0.6 + 1.5 * noise(6)) + seed * 1.7)), 2)
                    let dot = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                    soft.fill(Path(ellipseIn: dot.insetBy(dx: -radius * 1.6, dy: -radius * 1.6)),
                              with: .color(.white.opacity(0.42 * twinkle)))
                    context.fill(Path(ellipseIn: dot), with: .color(.white.opacity(0.92 * twinkle)))
                    if particle.isMultiple(of: 7) {
                        let reach = radius * 4.2 * twinkle
                        var star = Path()
                        star.move(to: CGPoint(x: x - reach, y: y))
                        star.addLine(to: CGPoint(x: x + reach, y: y))
                        star.move(to: CGPoint(x: x, y: y - reach))
                        star.addLine(to: CGPoint(x: x, y: y + reach))
                        context.stroke(star, with: .color(.white.opacity(0.75 * twinkle)),
                                       style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
                    }
                }
            }
        }
        .blendMode(.plusLighter)
    }
}

/// Música de fondo, solo mientras la pantalla de sobres está abierta.
@MainActor
private enum BoosterMusic {
    private static let level: Float = 0.30
    private static let player: AVAudioPlayer? = {
        let url = BoosterResources.folder.appendingPathComponent("Audio/music-loop.m4a")
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.numberOfLoops = -1
        player.volume = 0
        return player
    }()
    private static var wanted = false

    static func start() {
        guard let player else { return }
        wanted = true
        player.currentTime = 0
        player.volume = 0
        player.play()
        player.setVolume(level, fadeDuration: 1.2)
    }

    /// Baja la música un momento para que se oiga el sonido de la carta especial.
    static func duck(_ lowered: Bool) {
        guard wanted else { return }
        player?.setVolume(lowered ? level * 0.45 : level, fadeDuration: 0.5)
    }

    static func pause() { player?.pause() }

    static func resume() {
        guard wanted, let player, !player.isPlaying else { return }
        player.play()
    }

    static func stop() {
        wanted = false
        guard let player else { return }
        player.setVolume(0, fadeDuration: 0.35)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            if !wanted { player.stop() }
        }
    }
}

@MainActor
private enum BoosterSounds {
    enum Cue: String, CaseIterable {
        case appear = "pocket-appear"
        case select = "pocket-select"
        case ready = "pocket-ready"
        case cut = "pocket-cut"
        case reveal = "pocket-reveal"
        case special = "pocket-special"
        case specialNext = "pocket-special-next"
        case swipe1 = "pocket-swipe-1"
        case swipe2 = "pocket-swipe-2"
        case swipe3 = "pocket-swipe-3"
        case last = "pocket-last"
        case recap = "pocket-recap"

        var fallback: String {
            switch self {
            case .appear: "approach"
            case .select: "select"
            case .ready: "ready"
            case .cut: "cut"
            case .reveal: "reveal"
            case .special, .specialNext: "special"
            case .swipe1, .swipe3, .last: "swipe"
            case .swipe2: "swipe-alt"
            case .recap: "recap"
            }
        }
    }

    private static let players: [Cue: AVAudioPlayer] = Dictionary(uniqueKeysWithValues: Cue.allCases.compactMap { cue in
        // Si falta el sonido nuevo en la copia del proyecto, suena el original de la app.
        for name in [cue.rawValue, cue.fallback] {
            let url = BoosterResources.folder.appendingPathComponent("Audio/\(name).wav")
            if let player = try? AVAudioPlayer(contentsOf: url) { return (cue, player) }
        }
        return nil
    })

    static func prepare() {
        let session = AVAudioSession.sharedInstance()
        if session.category == .soloAmbient {
            try? session.setCategory(.ambient)
        }
        for player in players.values { player.prepareToPlay() }
    }

    static func play(_ cue: Cue) {
        guard let player = players[cue] else { return }
        player.currentTime = 0
        player.play()
    }

    static func swipe(cardIndex: Int) {
        play([Cue.swipe1, .swipe2, .swipe3][abs(cardIndex) % 3])
    }
}

private enum BoosterMarketPrices {
    private struct Listing: Decodable {
        struct Pricing: Decodable {
            let tcgplayer: Market?
        }

        struct Market: Decodable {
            struct Variant: Decodable { let marketPrice: Double? }

            let unit: String
            let normal: Variant?
            let holofoil: Variant?
            let reverseHolofoil: Variant?

            enum CodingKeys: String, CodingKey {
                case unit, normal, holofoil
                case reverseHolofoil = "reverse-holofoil"
            }

            var amount: Double? {
                guard unit == "USD" else { return nil }
                return normal?.marketPrice ?? holofoil?.marketPrice ?? reverseHolofoil?.marketPrice
            }
        }

        let id: String
        let pricing: Pricing?
    }

    static func load(_ cards: [BoosterCard]) async -> [String: Double] {
        await withTaskGroup(of: (String, Double?).self) { group in
            for card in cards {
                group.addTask { (card.id, await quote(for: card) ?? card.referencePrice) }
            }

            var quotes: [String: Double] = [:]
            for await (id, amount) in group {
                quotes[id] = amount
            }
            return quotes
        }
    }

    private static func quote(for card: BoosterCard) async -> Double? {
        let catalogID: String
        if let marketID = card.marketID {
            catalogID = marketID
        } else if card.id.hasPrefix("sv4-"), let number = Int(card.id.dropFirst(4)), (1...266).contains(number) {
            catalogID = String(format: "sv04-%03d", number)
        } else {
            return nil
        }

        guard let url = URL(string: "https://api.tcgdex.net/v2/en/cards/\(catalogID)"),
              let (data, response) = try? await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 8)),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let listing = try? JSONDecoder().decode(Listing.self, from: data),
              listing.id == catalogID, let amount = listing.pricing?.tcgplayer?.amount,
              amount.isFinite, amount > 0 else { return nil }
        return amount
    }
}

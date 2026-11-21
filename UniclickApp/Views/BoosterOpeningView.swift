import AVFAudio
import SwiftUI

struct BoosterOpeningView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

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
    private static let setLogo = UIImage(contentsOfFile: BoosterResources.folder
        .appendingPathComponent("paradox-rift-logo.png").path)
    private let sky = Color(red: 0.80, green: 0.90, blue: 0.96)
    private static let backgroundArt = UIImage(contentsOfFile: BoosterResources.folder
        .appendingPathComponent("opening-sky.png").path)
    private var card: BoosterCard? { hand.indices.contains(index) ? hand[index] : nil }

    var body: some View {
        openingContent
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                GeometryReader { proxy in
                    if let art = Self.backgroundArt {
                        Image(uiImage: art)
                            .resizable()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                    } else {
                        sky
                    }
                }
                brandPattern
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .preferredColorScheme(.light)
        .task(id: loadAttempt) { load() }
        .task(id: hand.map(\.id)) {
            let quotes = await BoosterMarketPrices.load(hand.map(\.id))
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
            let reveal: BoosterSounds.Cue = hand.first?.special == true ? .special : .reveal
            let cues: [(time: Double, sound: BoosterSounds.Cue)] = reduceMotion
                ? [(revealTime, reveal)]
                : [(cutDuration + sealRelease, .flap), (revealTime, reveal)]
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

    private var brandPattern: some View {
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
            Button(action: { dismiss() }) {
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
            if let logo = Self.setLogo {
                Image(uiImage: logo)
                    .resizable().scaledToFit()
                    .frame(width: 96, height: 38)
                    .padding(.horizontal, 14).padding(.vertical, 4)
                    .glassEffect(.regular, in: .capsule)
                    .accessibilityLabel("Paradox Rift")
                    .accessibilityAddTraits(.isHeader)
                    .frame(maxWidth: .infinity)
            }

            Button { dismiss() } label: {
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
            BoosterStage(renderer: renderer, hand: hand, firstCard: index, frame: frame,
                         tilt: dragTilt, shift: dragShift,
                         viewport: size, focus: focus, slide: slide, cut: trace, cutWeight: release,
                         sealGuideProgress: phase == .ready ? (reduceMotion ? 1 : guide * (2 - guide)) : 0,
                         animateSealGuide: !reduceMotion && scenePhase == .active)
                .overlay {
                    if trace > 0 && release > 0 {
                        Rectangle().fill(.black.opacity(0.19 * min(1, trace * 3) * pow(release, 2)))
                        tearLight(across: seal, progress: trace, strength: release, flash: flash)
                    }
                }
            .accessibilityHidden(true)
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
                gestureHint("Swipe across the seal", icon: "hand.draw")
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
                    guard slideAnimation == nil, startsOnCard(value, in: size) else { return }
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
            let available: [BoosterCard] = try BoosterResources.load("paradox-rift.json")
            let cards = try BoosterResources.draw(from: available)
            let scene = try BoosterScene()
            hand = cards
            renderer = scene
            BoosterSounds.prepare()
        } catch {
            print("[Booster] Could not load Paradox Rift: \(error)")
            loadError = true
        }
    }

    private func positionPack() {
        guard phase == .sealed, renderer != nil else { return }
        BoosterSounds.play(.select)
        if !reduceMotion { BoosterSounds.play(.approach) }
        dragTilt = .zero
        dragShift = .zero
        positionDate = .now
        phase = reduceMotion ? .ready : .positioning
    }

    private func begin() {
        guard phase == .ready, renderer != nil else { return }
        BoosterSounds.play(.cut)
        dragTilt = .zero
        dragShift = .zero
        openingDate = .now
        phase = .opening
    }

    private func finishSwipe(toward target: Double) {
        guard phase == .cards, slideAnimation == nil, target > 0 || cardSlide > 0 else { return }
        if target > 0 { BoosterSounds.swipe(cardIndex: index) }
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
            if hand[index].special { BoosterSounds.play(.special) }
        } else {
            BoosterSounds.play(.recap)
            phase = .finished
        }
    }
}

@MainActor
private enum BoosterSounds {
    enum Cue: String, CaseIterable {
        case select, approach, ready, cut, flap, reveal, special, swipe, recap
        case swipeAlternate = "swipe-alt"
    }

    private static let players: [Cue: AVAudioPlayer] = Dictionary(uniqueKeysWithValues: Cue.allCases.compactMap { cue in
        let url = BoosterResources.folder.appendingPathComponent("Audio/\(cue.rawValue).wav")
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        return (cue, player)
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
        play(cardIndex.isMultiple(of: 2) ? .swipe : .swipeAlternate)
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

    static func load(_ ids: [String]) async -> [String: Double] {
        await withTaskGroup(of: (String, Double?).self) { group in
            for id in ids {
                group.addTask { (id, await quote(for: id)) }
            }

            var quotes: [String: Double] = [:]
            for await (id, amount) in group {
                quotes[id] = amount
            }
            return quotes
        }
    }

    private static func quote(for id: String) async -> Double? {
        guard id.hasPrefix("sv4-"), let number = Int(id.dropFirst(4)), (1...266).contains(number) else {
            return nil
        }

        let catalogID = String(format: "sv04-%03d", number)
        guard let url = URL(string: "https://api.tcgdex.net/v2/en/cards/\(catalogID)"),
              let (data, response) = try? await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 8)),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let listing = try? JSONDecoder().decode(Listing.self, from: data),
              listing.id == catalogID, let amount = listing.pricing?.tcgplayer?.amount,
              amount.isFinite, amount > 0 else { return nil }
        return amount
    }
}

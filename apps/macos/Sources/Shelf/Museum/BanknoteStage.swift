import SwiftUI
import CoreImage
import QuartzCore

/// A banknote held up to the light. It's paper, not a card: drag it and
/// it turns with a give, the far side trailing behind the near one, then
/// settles with a little flutter. Turned far enough, it shows its back.
struct BanknoteStage: View {
    let note: Banknote
    /// The face to come to rest on, in degrees: 0 is the front, 180 the back.
    @Binding var angle: Double
    @State private var front: NSImage?
    @State private var back: NSImage?
    @State private var paper = PaperMotion()
    @State private var tilt: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            let size = fitted(in: geo.size)
            TimelineView(.animation(minimumInterval: 1.0 / 60)) { timeline in
                let pose = paper.pose(at: timeline.date, hover: tilt)
                ZStack {
                    floorShadow(width: size.width, pose: pose)
                        .offset(y: size.height / 2 + 34)
                    FoldingPaper(size: size, pose: pose, front: face(front), back: face(back))
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .contentShape(Rectangle())
            // Double-tap a side to turn the note over that way, as if
            // flicking that edge of the paper.
            .onTapGesture(count: 2, coordinateSpace: .local) { location in
                angle += location.x < geo.size.width / 2 ? -180 : 180
            }
            .gesture(drag(width: size.width))
            .onContinuousHover { phase in
                // The note leans a little toward the pointer, as if being looked at.
                switch phase {
                case .active(let p):
                    tilt = CGSize(width: (p.x / geo.size.width - 0.5) * 2, height: (p.y / geo.size.height - 0.5) * 2)
                case .ended:
                    tilt = .zero
                }
            }
        }
        .task(id: note.id) { await load() }
        .onAppear { paper.target = angle; paper.angle = angle }
        .onChange(of: angle) { _, target in paper.target = target }
        .accessibilityElement()
        .accessibilityLabel("\(note.denomination) note from \(note.country), \(showingFront ? "front" : "back")")
        .accessibilityAction(named: "Turn over") { angle += 180 }
    }

    private var showingFront: Bool { cos(angle * .pi / 180) >= 0 }

    /// One face, fitted exactly to the paper: stretched by at most a hair
    /// when front and back scans differ, never cropped.
    @ViewBuilder private func face(_ image: NSImage?) -> some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .overlay { PaperGrain() }
        } else {
            ZStack {
                Rectangle().fill(Color(white: 0.5, opacity: 0.25))
                ProgressView().controlSize(.small)
            }
        }
    }

    private func floorShadow(width: CGFloat, pose: PaperPose) -> some View {
        Ellipse()
            .fill(.black.opacity(0.22))
            .frame(width: width * (0.5 + 0.4 * abs(cos(pose.angle * .pi / 180))), height: 18)
            .blur(radius: 14)
            .scaleEffect(1 + pose.lift * 0.02)
    }

    // MARK: Sizing

    /// The note's own proportions, from its scan, fit to the stage.
    private func fitted(in space: CGSize) -> CGSize {
        let image = front ?? back
        // Pixel proportions, not points: some scans carry odd DPI metadata.
        var aspect: Double = 2.2
        if let rep = image?.representations.first, rep.pixelsWide > 0, rep.pixelsHigh > 0 {
            aspect = Double(rep.pixelsWide) / Double(rep.pixelsHigh)
        } else if let image, image.size.height > 0 {
            aspect = Double(image.size.width / image.size.height)
        }
        let maxW = space.width * 0.74, maxH = space.height * 0.68
        var w = maxW, h = maxW / aspect
        if h > maxH { h = maxH; w = maxH * aspect }
        return CGSize(width: w, height: h)
    }

    // MARK: Turning

    private func drag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                paper.drag(to: value.translation.width, grabbedAt: value.startLocation.x, time: value.time)
            }
            .onEnded { value in
                // Settle on whichever face the flick was heading for.
                angle = paper.release(predicted: value.predictedEndTranslation.width)
            }
    }

    private func load() async {
        let images = BanknoteImages.shared
        front = images.cached(note.front.image)
        back = images.cached(note.back.image)
        async let f = images.image(note.front.image)
        async let b = images.image(note.back.image)
        let (loadedFront, loadedBack) = await (f, b)
        withAnimation(.easeOut(duration: 0.35)) { front = loadedFront; back = loadedBack }
    }
}

// MARK: - Motion

/// Where the paper is at one instant.
struct PaperPose {
    /// The middle of the note's turn, in degrees.
    var angle: Double
    /// How much the paper gives, in degrees: positive bends the right side
    /// back, negative the left. Comes from how fast it's turning.
    var flex: Double
    /// A slight bow it keeps even at rest.
    var bow: Double
    /// Lean toward the pointer, in degrees around the horizontal axis.
    var pitch: Double
    /// 0…1, how lifted the paper is (for the shadow).
    var lift: Double
}

/// A tiny physics model: the turn springs toward its resting face, and the
/// paper's give springs after the turn, so it trails, overshoots and
/// flutters the way a real note does.
/// Not observed: the timeline redraws every frame and reads it as it goes.
final class PaperMotion {
    var target: Double = 0
    var angle: Double = 0
    private var velocity: Double = 0
    private var flex: Double = 0
    private var flexVelocity: Double = 0
    private var last: Date?
    private var dragging: (start: Double, lastX: CGFloat, lastTime: Date)?
    private let born = Date()

    func pose(at date: Date, hover: CGSize) -> PaperPose {
        let dt = min(max(date.timeIntervalSince(last ?? date), 0), 1.0 / 30)
        last = date
        if dragging == nil {
            // Underdamped spring toward the resting face.
            velocity += (60 * (target - angle) - 11 * velocity) * dt
            angle += velocity * dt
        }
        // The paper's give lags the turn and wobbles as it catches up.
        let wanted = max(-55, min(55, -velocity * 0.07))
        flexVelocity += (140 * (wanted - flex) - 7 * flexVelocity) * dt
        flex += flexVelocity * dt

        let t = date.timeIntervalSince(born)
        let breathe = sin(t * 2 * .pi / 9)
        return PaperPose(
            angle: angle + Double(hover.width) * 9 + breathe * 3,
            flex: flex,
            bow: 7 + breathe * 2,
            pitch: Double(-hover.height) * 5 + sin(t * 2 * .pi / 13) * 1.5,
            lift: min(1, abs(velocity) / 400 + abs(flex) / 40)
        )
    }

    func drag(to dx: CGFloat, grabbedAt x: CGFloat, time: Date) {
        if dragging == nil {
            dragging = (angle, dx, time)
        }
        guard let d = dragging else { return }
        let next = d.start + Double(dx) * 0.6
        let dt = time.timeIntervalSince(d.lastTime)
        if dt > 0.001 {
            // Smoothed angular speed, so the paper's give follows the hand.
            velocity = velocity * 0.6 + ((next - angle) / dt) * 0.4
        }
        angle = next
        dragging = (d.start, dx, time)
    }

    func release(predicted: CGFloat) -> Double {
        let start = dragging?.start ?? angle
        dragging = nil
        let projected = start + Double(predicted) * 0.6
        target = (projected / 180).rounded() * 180
        return target
    }
}

// MARK: - The paper

/// The note as thin columns of paper joined edge to edge. Each column turns
/// a little more or less than its neighbour, so the sheet bends as a whole;
/// a column turned past edge-on shows the back of the note.
private struct FoldingPaper<Front: View, Back: View>: View {
    let size: CGSize
    let pose: PaperPose
    let front: Front
    let back: Back

    private let columns = 32

    var body: some View {
        let layout = columnLayout()
        let radius = size.width * 0.012
        let frontFace = front
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        // Seen from behind, the back runs right to left.
        let backFace = back
            .frame(width: size.width, height: size.height)
            .scaleEffect(x: -1)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))

        ZStack(alignment: .topLeading) {
            ForEach(0..<columns, id: \.self) { i in
                let c = layout[i]
                Group {
                    if c.facingUs { frontFace } else { backFace }
                }
                .overlay { shade(c) }
                .mask(alignment: .topLeading) {
                    // A little of the neighbours' picture on each side, so
                    // the joins fall on matching pixels and never show.
                    Rectangle()
                        .frame(width: c.width + c.pad * 2, height: size.height)
                        .offset(x: c.x0 - c.pad)
                }
                .projectionEffect(ProjectionTransform(c.transform))
                .zIndex(c.depth)
            }
        }
        .frame(width: size.width, height: size.height)
        .compositingGroup()
        .shadow(color: .black.opacity(0.28), radius: 16, y: 12)
    }

    /// Light falling on one column: dimmer as it turns from the light, with
    /// a soft glint where it faces it squarely.
    private func shade(_ c: Column) -> some View {
        ZStack {
            Color.black.opacity(c.dim)
            Color.white.opacity(c.glint).blendMode(.plusLighter)
        }
        .allowsHitTesting(false)
    }

    struct Column {
        var x0: CGFloat
        var width: CGFloat
        var pad: CGFloat
        var transform: CATransform3D
        var facingUs: Bool
        var depth: Double
        var dim: Double
        var glint: Double
    }

    private func columnLayout() -> [Column] {
        let n = columns
        let w = Double(size.width) / Double(n)
        let center = Double(size.width) / 2, middle = Double(size.height) / 2
        let base = pose.angle * .pi / 180
        let pitch = pose.pitch * .pi / 180

        // Each column's turn: the overall angle, a gentle bow across the
        // note, and the give: the half pushed through the air bends back.
        func turn(_ k: Int) -> Double {
            let s = (Double(k) + 0.5) / Double(n) * 2 - 1   // -1…1 across the note
            let bow = pose.bow * s
            // Both edges trail the middle; the side you're pushing a bit more.
            let give = pose.flex * pow(abs(s), 1.6) * (s > 0 ? 1 : 0.7)
            return base + (bow + give) * .pi / 180
        }

        // Lay the columns end to end in 3D, then centre the chain so the
        // note turns about its middle.
        var joints: [(x: Double, z: Double)] = [(0, 0)]
        for k in 0..<n {
            let a = turn(k)
            let j = joints[k]
            joints.append((j.x + w * cos(a), j.z - w * sin(a)))
        }
        let mid = joints[n / 2]

        let eye = Double(size.width) * 2.4
        var perspective = CATransform3DIdentity
        perspective.m34 = CGFloat(-1 / eye)
        let light = normalize((-0.35, 0.25, 1.0))

        return (0..<n).map { k in
            let a = turn(k)
            let j = joints[k]
            let x0 = Double(k) * w
            var t = CATransform3DMakeTranslation(CGFloat(-x0), CGFloat(-middle), 0)
            t = CATransform3DConcat(t, CATransform3DMakeRotation(CGFloat(a), 0, 1, 0))
            t = CATransform3DConcat(t, CATransform3DMakeTranslation(CGFloat(j.x - mid.x), 0, CGFloat(j.z - mid.z)))
            t = CATransform3DConcat(t, CATransform3DMakeRotation(CGFloat(pitch), 1, 0, 0))
            t = CATransform3DConcat(t, perspective)
            t = CATransform3DConcat(t, CATransform3DMakeTranslation(CGFloat(center), CGFloat(middle), 0))

            // The column's face direction after turning (and the lean).
            let normal = normalize((sin(a), -sin(pitch) * cos(a), cos(a) * cos(pitch)))
            let facing = normal.2 >= 0
            let n2 = facing ? normal : (-normal.0, -normal.1, -normal.2)
            let lit = max(0, dot(n2, light))
            let halfway = normalize((light.0, light.1, light.2 + 1))
            let glint = pow(max(0, dot(n2, halfway)), 60) * 0.22

            let midZ = (j.z - mid.z) - w / 2 * sin(a)
            return Column(
                x0: CGFloat(x0), width: CGFloat(w), pad: CGFloat(w * 0.6),
                transform: t, facingUs: facing, depth: midZ,
                dim: (1 - lit) * 0.6, glint: glint
            )
        }
    }

    private func normalize(_ v: (Double, Double, Double)) -> (Double, Double, Double) {
        let l = max(sqrt(v.0 * v.0 + v.1 * v.1 + v.2 * v.2), 1e-9)
        return (v.0 / l, v.1 / l, v.2 / l)
    }

    private func dot(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
        a.0 * b.0 + a.1 * b.1 + a.2 * b.2
    }
}

/// The faint tooth of banknote paper: fibres you feel more than see.
private struct PaperGrain: View {
    private static let texture: NSImage? = {
        guard let noise = CIFilter(name: "CIRandomGenerator")?.outputImage else { return nil }
        let mono = noise
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0, kCIInputContrastKey: 1.1])
            // Stretch the speckle sideways into short fibres.
            .applyingFilter("CIMotionBlur", parameters: [kCIInputRadiusKey: 3, kCIInputAngleKey: 0.3])
            .cropped(to: CGRect(x: 0, y: 0, width: 512, height: 512))
        let context = CIContext()
        guard let cg = context.createCGImage(mono, from: CGRect(x: 0, y: 0, width: 512, height: 512)) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: 512, height: 512))
    }()

    var body: some View {
        if let texture = Self.texture {
            Image(nsImage: texture)
                .resizable(resizingMode: .tile)
                .blendMode(.overlay)
                .opacity(0.10)
                .allowsHitTesting(false)
        }
    }
}

import SwiftUI
import SceneKit

/// A flag hung in the middle of the wall, made of real cloth: a finely
/// divided surface rippled by a small shader and lit like fabric. Left
/// alone it barely stirs; drag across it or click it and it ripples, then
/// settles again. Its anthem stirs it a little too.
struct FlagStage: View {
    let flag: NationalFlag
    @State private var image: NSImage?
    @State private var cloth = ClothMotion()

    var body: some View {
        GeometryReader { geo in
            ClothView(image: image, aspect: max(0.8, min(flag.flag.aspect, 3)), motion: cloth)
                .frame(width: geo.size.width, height: geo.size.height)
                // SceneKit's view takes the mouse for itself, so a clear
                // layer on top catches the drags and clicks.
                .overlay {
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 2)
                                .onChanged { value in cloth.blow(Double(value.velocity.width), at: value.location.x / geo.size.width) }
                        )
                        .onTapGesture { location in cloth.flick(at: location.x / geo.size.width) }
                }
                .task {
                    // The renderer runs on its own thread; hand it the music level from here.
                    while !Task.isCancelled {
                        cloth.music = AnthemPlayer.shared.level()
                        try? await Task.sleep(for: .milliseconds(33))
                    }
                }
        }
        .task(id: flag.id) {
            image = BanknoteImages.shared.cached(flag.flag.image)
            let loaded = await BanknoteImages.shared.image(flag.flag.image)
            image = loaded
            cloth.flick(at: 0.5, strength: 0.35)   // it settles into place when it arrives
        }
        .accessibilityElement()
        .accessibilityLabel("Flag of \(flag.country)")
        .accessibilityAction(named: "Ripple") { cloth.flick(at: 0.5) }
    }
}

// MARK: - Motion

/// How much the cloth is moving: a whisper at rest, a ripple that rises
/// with a drag or click and dies away, a little more while music plays.
final class ClothMotion: @unchecked Sendable {
    private let lock = NSLock()
    private var energy: Double = 0
    private var phase: Double = 0
    private var direction: Double = 1
    private var last: TimeInterval?
    private var _music: Double = 0

    /// 0…1, how loud the anthem is right now.
    var music: Double {
        get { lock.withLock { _music } }
        set { lock.withLock { _music = newValue } }
    }

    /// Advances the motion; returns (amplitude, phase) for the shader.
    func step(at time: TimeInterval) -> (amplitude: Double, phase: Double) {
        lock.lock(); defer { lock.unlock() }
        let music = _music
        let dt = min(max(time - (last ?? time), 0), 1.0 / 20)
        last = time
        energy *= exp(-dt * 1.1)                       // ripples die away over a couple of seconds
        let calm = 0.012 + 0.006 * sin(time * 0.6)     // a breath of air, nothing more
        let amplitude = calm + 0.11 * energy + 0.03 * music
        // Waves run faster while it's been stirred.
        phase += dt * (0.5 + 4.0 * energy + 1.0 * music) * direction
        return (amplitude, phase)
    }

    func blow(_ velocity: Double, at x: Double) {
        lock.lock(); defer { lock.unlock() }
        direction = velocity >= 0 ? 1 : -1
        energy = min(1, energy + abs(velocity) / 9000)
    }

    func flick(at x: Double, strength: Double = 0.6) {
        lock.lock(); defer { lock.unlock() }
        energy = min(1, energy + strength)
    }
}

// MARK: - SceneKit cloth

private struct ClothView: NSViewRepresentable {
    let image: NSImage?
    let aspect: Double
    let motion: ClothMotion

    func makeCoordinator() -> Coordinator { Coordinator(motion: motion) }

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.rendersContinuously = true
        view.allowsCameraControl = false
        view.scene = context.coordinator.scene
        view.delegate = context.coordinator
        view.isPlaying = true
        context.coordinator.update(image: image, aspect: aspect)
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        context.coordinator.motion = motion
        context.coordinator.update(image: image, aspect: aspect)
    }

    final class Coordinator: NSObject, SCNSceneRendererDelegate {
        var motion: ClothMotion
        let scene = SCNScene()
        private let node = SCNNode()
        private let camera = SCNNode()
        private var currentImage: NSImage?
        private var currentAspect: Double = 0

        init(motion: ClothMotion) {
            self.motion = motion
            super.init()
            scene.background.contents = NSColor.clear

            camera.camera = SCNCamera()
            camera.camera?.fieldOfView = 30
            camera.position = SCNVector3(0, 0, 4.2)
            scene.rootNode.addChildNode(camera)

            // Soft light from the upper left, plus a gentle fill, like a gallery.
            let key = SCNNode()
            key.light = SCNLight()
            key.light?.type = .directional
            key.light?.intensity = 900
            key.eulerAngles = SCNVector3(-0.5, -0.45, 0)
            scene.rootNode.addChildNode(key)
            let fill = SCNNode()
            fill.light = SCNLight()
            fill.light?.type = .ambient
            fill.light?.intensity = 420
            scene.rootNode.addChildNode(fill)

            node.eulerAngles = SCNVector3(0, -0.12, 0)   // turned just enough to read as cloth
            scene.rootNode.addChildNode(node)
        }

        func update(image: NSImage?, aspect: Double) {
            if aspect != currentAspect {
                currentAspect = aspect
                rebuild(aspect: aspect)
            }
            if image !== currentImage {
                currentImage = image
                node.geometry?.firstMaterial?.diffuse.contents = image ?? NSColor(white: 0.5, alpha: 0.3)
            }
        }

        private func rebuild(aspect: Double) {
            // The flag fills about two thirds of the stage, whatever its shape.
            let height = aspect >= 1.4 ? 1.5 / aspect * 1.4 : 1.15
            let width = height * aspect
            let plane = SCNPlane(width: width, height: height)
            plane.widthSegmentCount = 90
            plane.heightSegmentCount = 45

            let material = SCNMaterial()
            material.lightingModel = .blinn
            material.isDoubleSided = true
            material.specular.contents = NSColor(white: 0.18, alpha: 1)
            material.shininess = 0.15
            material.diffuse.contents = currentImage ?? NSColor(white: 0.5, alpha: 0.3)
            material.diffuse.mipFilter = .linear
            // Woven cloth: fine threads that catch the light, and a faint shade
            // between them. Each tile holds 32 threads, so about 160 run up the flag.
            let threads = Float(height * 5)
            for property in [material.normal, material.multiply] {
                property.wrapS = .repeat
                property.wrapT = .repeat
                property.mipFilter = .linear
                property.contentsTransform = SCNMatrix4MakeScale(CGFloat(threads * Float(aspect)), CGFloat(threads), 1)
            }
            material.normal.contents = Weave.normalMap
            material.normal.intensity = 0.6
            material.multiply.contents = Weave.shade
            material.shaderModifiers = [.geometry: Self.ripple]
            material.setValue(NSNumber(value: Float(width / 2)), forKey: "halfWidth")
            material.setValue(NSNumber(value: Float(0.01)), forKey: "amplitude")
            material.setValue(NSNumber(value: Float(0)), forKey: "phase")
            plane.materials = [material]
            node.geometry = plane
        }

        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            let (amplitude, phase) = motion.step(at: time)
            let material = node.geometry?.firstMaterial
            material?.setValue(NSNumber(value: Float(amplitude)), forKey: "amplitude")
            material?.setValue(NSNumber(value: Float(phase)), forKey: "phase")
        }

        /// Waves that start at the hoist (left) and grow toward the fly,
        /// with a slower crosswise wave so it never looks like slats.
        static let ripple = """
        #pragma arguments
        float halfWidth;
        float amplitude;
        float phase;
        #pragma body
        float3 p = _geometry.position.xyz;
        float u = clamp((p.x / halfWidth + 1.0) * 0.5, 0.0, 1.0);
        float reach = pow(u, 1.3);
        float k = 2.0 * 3.14159 * 1.25 / (2.0 * halfWidth);
        float a1 = k * p.x - phase * 6.2832;
        float a2 = 0.6 * k * p.x + 2.3 * p.y - phase * 4.1;
        float z = amplitude * reach * (sin(a1) + 0.45 * sin(a2));
        float dzdx = amplitude * (reach * (k * cos(a1) + 0.45 * 0.6 * k * cos(a2))
                     + 1.3 * pow(max(u, 0.0001), 0.3) / (2.0 * halfWidth) * (sin(a1) + 0.45 * sin(a2)));
        float dzdy = amplitude * reach * 0.45 * 2.3 * cos(a2);
        // Cloth that billows out also draws in a little at the fly.
        p.x -= amplitude * reach * 0.35 * (1.0 - cos(a1));
        p.z += z;
        _geometry.position.xyz = p;
        _geometry.normal = normalize(float3(-dzdx, -dzdy, 1.0));
        """
    }
}

/// Flag cloth, generated once: fine woven threads, the weft (across)
/// a touch stronger than the warp, each thread a little uneven, with the
/// odd thicker slub, so it reads as grain rather than a printed pattern.
/// One tile holds 32 threads each way.
private enum Weave {
    static let size = 256
    private static let threads = 32

    /// A steady pseudo-random number per thread, 0…1.
    private static func jitter(_ i: Int, _ salt: Int) -> Double {
        var h = UInt32(truncatingIfNeeded: i &* 374761393 &+ salt &* 668265263)
        h = (h ^ (h >> 13)) &* 1274126177
        return Double(h & 0xFFFF) / 65535.0
    }

    /// Thread height at a pixel, 0…1.
    private static func height(_ x: Int, _ y: Int) -> Double {
        let cell = Double(size) / Double(threads)
        let i = Int(Double(x) / cell), j = Int(Double(y) / cell)
        let fx = Double(x).truncatingRemainder(dividingBy: cell) / cell
        let fy = Double(y).truncatingRemainder(dividingBy: cell) / cell
        // Each thread its own thickness; now and then a slub.
        let warpWidth = 0.8 + 0.3 * jitter(i, 1) + (jitter(i, 7) > 0.93 ? 0.25 : 0)
        let weftWidth = 0.8 + 0.3 * jitter(j, 2) + (jitter(j, 9) > 0.93 ? 0.3 : 0)
        let warp = pow(max(sin(.pi * fx), 0), 0.7) * warpWidth
        let weft = pow(max(sin(.pi * fy), 0), 0.7) * weftWidth
        // Over and under, gently: whichever thread is on top shows a little more.
        let weftOnTop = (i + j) % 2 == 0
        let h = weftOnTop ? 0.62 * weft + 0.38 * warp : 0.48 * weft + 0.52 * warp
        return min(h, 1)
    }

    private static func image(_ pixel: (Int, Int) -> (UInt8, UInt8, UInt8)) -> NSImage {
        var bytes = [UInt8](repeating: 255, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let (r, g, b) = pixel(x, y)
                let o = (y * size + x) * 4
                bytes[o] = r; bytes[o + 1] = g; bytes[o + 2] = b
            }
        }
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: size * 4, bitsPerPixel: 32)!
        bytes.withUnsafeBufferPointer { memcpy(rep.bitmapData!, $0.baseAddress!, bytes.count) }
        let image = NSImage(size: NSSize(width: size, height: size))
        image.addRepresentation(rep)
        return image
    }

    /// Normals from the thread heights, wrapping at the edges so it tiles.
    static let normalMap: NSImage = image { x, y in
        let s = size
        let dx = height((x + 1) % s, y) - height((x - 1 + s) % s, y)
        let dy = height(x, (y + 1) % s) - height(x, (y - 1 + s) % s)
        let strength = 1.4
        var n = (-dx * strength, -dy * strength, 1.0)
        let l = (n.0 * n.0 + n.1 * n.1 + n.2 * n.2).squareRoot()
        n = (n.0 / l, n.1 / l, n.2 / l)
        return (UInt8((n.0 * 0.5 + 0.5) * 255), UInt8((n.1 * 0.5 + 0.5) * 255), UInt8((n.2 * 0.5 + 0.5) * 255))
    }

    /// Gaps between threads sit a touch darker.
    static let shade: NSImage = image { x, y in
        let v = UInt8(255 * (0.9 + 0.1 * height(x, y)))
        return (v, v, v)
    }
}

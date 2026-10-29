import AppKit
import SceneKit
import Testing

@testable import Brim

@Suite("AirPods 3D model")
struct AirPods3DTests {
  private func names(_ node: SCNNode) -> Set<String> {
    var result = Set<String>()
    node.enumerateHierarchy { child, _ in if let name = child.name { result.insert(name) } }
    return result
  }

  private func triangles(_ node: SCNNode) -> Int {
    var total = 0
    node.enumerateHierarchy { child, _ in total += child.geometry?.elements.reduce(0) { $0 + $1.primitiveCount } ?? 0 }
    return total
  }

  @Test func kindFollowsTheAccessoryModel() {
    #expect(AirPodsDeviceKind(model: .airPodsPro) == .pro)
    #expect(AirPodsDeviceKind(model: .airPodsMax) == .max)
    #expect(AirPodsDeviceKind(model: .airPods3) == .gen3)
    #expect(AirPodsDeviceKind(model: .airPods4) == .gen4)
    #expect(AirPodsDeviceKind(model: .airPods) == .original)
    #expect(AirPodsDeviceKind(model: .beats(.headphones)) == nil)
    #expect(AirPodsDeviceKind(model: .headphones) == nil)
    #expect(AirPodsDeviceKind(symbol: "airpodspro") == .pro)
    #expect(AirPodsDeviceKind(symbol: "headphones") == nil)
  }

  @Test func batteriesCarryTheModelForTheCard() {
    let parts = [DeviceBattery(id: "max", name: "n", symbol: "airpodsmax", percent: 50, charging: nil,
                               accessoryID: "bluetooth:9", accessoryName: "AirPods Max", part: nil, model: .airPodsMax,
                               onPower: nil, minutesToEmpty: nil, minutesToFull: nil)]
    let pods = AirPodsBatteries.from(parts, accessoryID: "bluetooth:9")
    #expect(pods?.model == .airPodsMax)
    #expect(pods?.kind == .max)
    #expect(pods?.left == 50 && pods?.isSingleLevel == true)
    // Cards built from a symbol alone (older call sites) still pick a model.
    #expect(AirPodsBatteries(name: "x", symbol: "airpods.gen3").kind == .gen3)
    #expect(AirPodsBatteries(name: "x", symbol: "airpods", left: 40).isSingleLevel)
  }

  @Test func earbudsHaveEveryPart() {
    let pro = names(AirPods3DScene.makeModel(.pro))
    for part in ["pair", "bud.left", "bud.right", "stem", "foot", "head", "shell", "tip", "mesh", "vent", "sensor"] {
      #expect(pro.contains(part), "pro is missing \(part)")
    }
    #expect(!pro.contains("nozzle"))
    for kind in [AirPodsDeviceKind.original, .gen3, .gen4] {
      let parts = names(AirPods3DScene.makeModel(kind))
      #expect(parts.contains("nozzle") && !parts.contains("tip"), "\(kind)")
    }
  }

  @Test func maxHasBandCupsAndCushions() {
    let parts = names(AirPods3DScene.makeModel(.max))
    for part in ["max", "max.frame", "max.canopy", "max.arm.left", "max.arm.right", "max.cup.left", "max.cup.right",
                 "max.cushion.left", "max.cushion.right", "max.crown"] {
      #expect(parts.contains(part), "max is missing \(part)")
    }
  }

  @Test(arguments: AirPodsDeviceKind.allCases)
  func modelsAreSymmetricAndSensiblySized(kind: AirPodsDeviceKind) {
    let model = AirPods3DScene.makeModel(kind)
    let box = AirPods3DScene.bounds(of: model)
    let width = box.max.x - box.min.x, height = box.max.y - box.min.y
    #expect(abs(box.max.x + box.min.x) < 0.15, "\(kind) is off center")
    #expect((1.5...4).contains(width), "\(kind) width \(width)")
    #expect((1.5...2.6).contains(height), "\(kind) height \(height)")
    #expect(triangles(model) < 40_000, "\(kind) is too heavy: \(triangles(model)) triangles")
  }

  @Test func budsFaceEachOther() throws {
    let pair = AirPods3DScene.makeModel(.pro)
    for (name, inward) in [("bud.left", CGFloat(1)), ("bud.right", -1)] {
      let bud = try #require(pair.childNode(withName: name, recursively: false))
      let tip = try #require(bud.childNode(withName: "tip", recursively: true))
      let stem = try #require(bud.childNode(withName: "stem", recursively: false))
      let tipX = pair.convertPosition(SCNVector3Zero, from: tip).x
      let stemX = pair.convertPosition(SCNVector3Zero, from: stem).x
      #expect((tipX - stemX) * inward > 0.2, "\(name) tip should point at the other bud")
      #expect(pair.convertPosition(SCNVector3Zero, from: tip).z > 0, "\(name) tip should face the camera")
    }
  }

  @Test func latheBuildsAClosedOutwardSurface() throws {
    let profile = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 2), CGPoint(x: 0, y: 2)]
    let geometry = LatheGeometry.make(profile: profile, segments: 8)
    let vertices = try #require(geometry.sources(for: .vertex).first)
    #expect(vertices.vectorCount == 4 * 9)
    #expect(geometry.elements.first?.primitiveCount == 3 * 8 * 2)
    let normals = LatheGeometry.profileNormals([CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 1, y: 2)])
    #expect(normals.allSatisfy { abs($0.x - 1) < 1e-6 && abs($0.y) < 1e-6 })
    #expect(LatheGeometry.make(profile: [CGPoint(x: 1, y: 0)], segments: 8).elements.isEmpty)
  }

  @Test func surfaceMathLandsOnTheEllipsoid() {
    let radii = SCNVector3(2, 1, 1)
    let point = AirPods3DMath.ellipsoidPoint(radii: radii, direction: SCNVector3(1, 0, 0))
    #expect(abs(point.x - 2) < 1e-6)
    let diagonal = AirPods3DMath.ellipsoidPoint(radii: radii, direction: SCNVector3(1, 1, 0))
    #expect(abs(pow(diagonal.x / 2, 2) + pow(diagonal.y, 2) - 1) < 1e-6)
    let normal = AirPods3DMath.ellipsoidNormal(radii: radii, at: SCNVector3(0, 1, 0))
    #expect(abs(normal.y - 1) < 1e-6)
  }

  @Test func springSettlesWithOneOvershoot() {
    #expect(AirPods3DMotion.spring(0) == 0)
    #expect(AirPods3DMotion.spring(1) == 1)
    let samples = stride(from: 0.0, through: 1, by: 0.01).map(AirPods3DMotion.spring)
    #expect(samples.max()! > 1.05 && samples.max()! < 1.2)
    #expect(abs(AirPods3DMotion.spring(0.999) - 1) < 0.01, "no visible jump when the intro ends")
  }

  @Test func motionArrivesAtTheRestPoseThenTurnsSmoothly() {
    let start = AirPods3DMotion.pose(at: 0)
    #expect(start.scale == AirPods3DMotion.introScale)
    let settled = AirPods3DMotion.pose(at: AirPods3DMotion.introDuration)
    #expect(abs(settled.scale - 1) < 1e-9 && abs(settled.yaw - AirPods3DMotion.restPose.yaw) < 1e-9 && settled.pitch == 0)
    // The turn eases in: no jump across the ramp and full speed afterwards.
    let ramp = AirPods3DMotion.turnRamp
    #expect(abs(AirPods3DMotion.turnDistance(after: ramp - 1e-6) - AirPods3DMotion.turnDistance(after: ramp + 1e-6)) < 1e-4)
    let later = AirPods3DMotion.pose(at: 20), laterStill = AirPods3DMotion.pose(at: 20 + AirPods3DMotion.turnPeriod)
    #expect(abs(laterStill.yaw - later.yaw - 2 * .pi) < 1e-6)
    #expect(AirPods3DMotion.pose(at: 3, reduceMotion: true) == AirPods3DMotion.restPose)
  }

  @Test func sceneIsFramedAndLit() throws {
    let scene = AirPods3DScene.make(kind: .pro)
    let camera = try #require(scene.rootNode.childNode(withName: "camera", recursively: false))
    #expect(camera.camera != nil && camera.position.z > 0)
    #expect(scene.lightingEnvironment.contents != nil)
    #expect(scene.rootNode.childNode(withName: "light.key", recursively: false)?.light != nil)
    let turntable = try #require(scene.rootNode.childNode(withName: "turntable", recursively: false))
    AirPods3DScene.apply(.init(scale: 0.5, yaw: 1, pitch: 0.2), to: scene)
    #expect(abs(turntable.eulerAngles.y - 1) < 1e-6)
    #expect(abs((turntable.childNode(withName: "pose", recursively: false)?.scale.x ?? 0) - 0.5) < 1e-6)
  }

  @Test func studioEnvironmentIsAnEquirectangularImage() throws {
    let image = try #require(AirPods3DStudio.environmentImage())
    #expect(image.width == 2 * image.height)
  }

  /// The live view renders only while the card is showing; hidden, it stops and rests.
  @MainActor @Test func liveViewStopsWhenInactive() {
    let view = SCNView(frame: CGRect(x: 0, y: 0, width: 60, height: 60))
    let animator = AirPods3DAnimator()
    animator.attach(scene: AirPods3DScene.make(kind: .gen4), kind: .gen4, to: view)
    animator.setAnimating(true, in: view)
    #expect(view.isPlaying && view.scene?.isPaused == false)
    animator.setAnimating(false, in: view)
    #expect(!view.isPlaying && view.scene?.isPaused == true)
    let turntable = view.scene?.rootNode.childNode(withName: "turntable", recursively: false)
    #expect(abs((turntable?.eulerAngles.y ?? 0) - AirPods3DMotion.restPose.yaw) < 1e-6)
  }
}

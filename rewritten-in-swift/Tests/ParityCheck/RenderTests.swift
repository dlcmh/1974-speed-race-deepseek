import Foundation
import Metal
import SpeedRace

let renderTests: [TestCase] = [
    TestCase("render::rect") {
        let renderer = try MetalRenderer()
        let cabinet = DrawList(aaScale: 1)
        cabinet.begin()
        cabinet.rectangle(380, 310, 200, 100, RGBAColor.rgb(255, 255, 255))
        let out = try renderer.render(
            crt: DrawList(aaScale: 1), cabinet: cabinet, drawable: nil, viewport: nil)!
        var covered = 0
        for y in 0..<720 {
            for x in 0..<960 {
                let i = ((y * 960) + x) * 4
                if out.pixels[i] > 128 { covered += 1 }
            }
        }
        let c = ((360 * 960) + 480) * 4
        print(
            "RENDER covered=\(covered) centre=\(out.pixels[c]),\(out.pixels[c+1]),\(out.pixels[c+2]) (want ~20000, 255)"
        )
    }
]

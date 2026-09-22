import Foundation

// ⚠️ 已被取代（保留作历史参考）。当前 App 使用的 turn_a/b/c.wav 不是本脚本生成的：
// 那三条取自真实磁吸魔方录音（commit "转动音效改用真实磁吸魔方采样"），
// 声学特征与本脚本产物完全不同——本脚本是"起始冲击 + 快速归零"的干净合成音，
// 现行音效是峰值在中后段、过零率 0.33~0.37 的宽带噪声。
// 若要改音效，请以 iCube/Resources/Sounds/ 下已入库的 wav 为准，
// 或在 build/sound_work/ 的原始录音上重新取段。
//
// 用法：swift Tools/make_sounds.swift <输出目录>
//
// 转动音效合成脚本：生成 3 条变体 WAV（44.1kHz / 16bit / 单声道）。
// 声音模型：磁吸魔方的"喀啦"——模态合成（modal synthesis）：撞击脉冲（~1.3ms 噪声
// 冲击）打进 3 个带通共振器（塑料件撞击的固有模态）。无正弦+包络的音调分量，
// 干脆无余韵，听感是"啪嗒"而不是鼓。

let sampleRate = 44100.0

struct Variant {
    let name: String
    let freqScale: Double    // 全部模态频率缩放
    let burst: Double        // 冲击噪声时长（秒）
    let seed: UInt64
}

let variants = [
    Variant(name: "turn_a", freqScale: 0.90, burst: 0.0014, seed: 1),
    Variant(name: "turn_b", freqScale: 1.00, burst: 0.0016, seed: 7),
    Variant(name: "turn_c", freqScale: 1.10, burst: 0.0012, seed: 13),
]

// 简易可复现噪声（xorshift）
var noiseState: UInt64 = 0
func noise() -> Double {
    noiseState ^= noiseState << 13
    noiseState ^= noiseState >> 7
    noiseState ^= noiseState << 17
    return Double(Int64(bitPattern: noiseState % 20000) - 10000) / 10000.0
}

// RBJ 带通滤波器（峰值增益恒定）
struct Bandpass {
    var b0: Double = 0, a1: Double = 0, a2: Double = 0
    var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

    init(freq: Double, q: Double, sampleRate: Double) {
        let w0 = 2 * .pi * freq / sampleRate
        let alpha = sin(w0) / (2 * q)
        let a0 = 1 + alpha
        b0 = alpha / a0
        a1 = -2 * cos(w0) / a0
        a2 = (1 - alpha) / a0
    }

    mutating func process(_ x: Double) -> Double {
        let y = b0 * (x - x2) - a1 * y1 - a2 * y2
        x2 = x1; x1 = x
        y2 = y1; y1 = y
        return y
    }
}

func render(_ v: Variant) -> [Double] {
    noiseState = v.seed &+ 0x9E3779B97F4A7C15
    let f = { (base: Double) in base * v.freqScale }
    // 模态：塑料件撞击的固有频率（Q 越高余韵越短促清脆）
    var modes = [
        Bandpass(freq: f(1200), q: 1.0, sampleRate: sampleRate),  // 塑料"喀"的实体感（加量，柔）
        Bandpass(freq: f(2150), q: 1.4, sampleRate: sampleRate),  // 咔啦主体
        Bandpass(freq: f(3300), q: 1.4, sampleRate: sampleRate),  // 亮色收敛：降频、降压、放软 Q
    ]
    let gains: [Double] = [0.75, 0.85, 0.25]

    let burstLen = Int(v.burst * sampleRate)
    let n = Int(0.032 * sampleRate)
    var samples = [Double](repeating: 0, count: n)
    for i in 0..<n {
        // 激励：极短噪声冲击（撞击那一瞬），之后输入为零，只剩模态余音
        var exciter = 0.0
        if i < burstLen {
            let t = Double(i) / sampleRate
            exciter = noise() * exp(-t / 0.00055) * 1.2
        }
        var s = 0.0
        for k in modes.indices {
            s += gains[k] * modes[k].process(exciter)
        }
        samples[i] = s
    }
    // 归一化到 0.78 峰值 + 末尾 1.5ms 淡出防爆音
    let peak = samples.map(abs).max() ?? 1
    let fadeN = Int(0.0015 * sampleRate)
    for i in 0..<n {
        var s = samples[i] / peak * 0.78
        let remain = n - i
        if remain < fadeN { s *= Double(remain) / Double(fadeN) }
        samples[i] = s
    }
    return samples
}

func writeWav(_ samples: [Double], to path: String) throws {
    var data = Data()
    let n = samples.count
    func append(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
    func append(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
    let byteCount = UInt32(n * 2)
    data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + byteCount))
    data.append(contentsOf: Array("WAVE".utf8))
    data.append(contentsOf: Array("fmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
    append(UInt32(sampleRate)); append(UInt32(sampleRate * 2)); append(UInt16(2)); append(UInt16(16))
    data.append(contentsOf: Array("data".utf8)); append(byteCount)
    for s in samples {
        let v = Int16(max(-1, min(1, s)) * Double(Int16.max))
        withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) }
    }
    try data.write(to: URL(fileURLWithPath: path))
}

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
for v in variants {
    let path = outDir + "/\(v.name).wav"
    try writeWav(render(v), to: path)
    print("written: \(path)")
}

// DigUp: remember everything you've seen on screen.
// https://github.com/sryo/Spoons/blob/main/DigUp/digup_ocr_helper.swift - reads an image, runs Vision OCR, outputs JSON
// Compile: swiftc -O -o ocr_helper digup_ocr_helper.swift
import AppKit
import Vision
import Foundation

guard CommandLine.arguments.count > 1 else {
    fputs("Usage: ocr_helper <image_path>\n", stderr)
    exit(1)
}

let imagePath = CommandLine.arguments[1]
guard let image = NSImage(contentsOfFile: imagePath),
      let tiffData = image.tiffRepresentation,
      let cgImage = NSBitmapImageRep(data: tiffData)?.cgImage else {
    fputs("Error: cannot load image at \(imagePath)\n", stderr)
    print("[]")
    exit(0)
}

let request = VNRecognizeTextRequest()
request.recognitionLevel = .fast
request.usesLanguageCorrection = false

let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
do {
    try handler.perform([request])
} catch {
    fputs("Vision error: \(error)\n", stderr)
    print("[]")
    exit(0)
}

var results: [[String: Any]] = []
if let observations = request.results {
    let imageHeight = CGFloat(cgImage.height)
    let imageWidth  = CGFloat(cgImage.width)
    for obs in observations {
        let box = obs.boundingBox
        let entry: [String: Any] = [
            "text":       obs.topCandidates(1).first?.string ?? "",
            "confidence": obs.confidence,
            "x":          box.origin.x * imageWidth,
            "y":          (1.0 - box.origin.y - box.size.height) * imageHeight,
            "width":      box.size.width * imageWidth,
            "height":     box.size.height * imageHeight,
        ]
        results.append(entry)
    }
}

if let jsonData = try? JSONSerialization.data(withJSONObject: results, options: []),
   let jsonString = String(data: jsonData, encoding: .utf8) {
    print(jsonString)
} else {
    print("[]")
}

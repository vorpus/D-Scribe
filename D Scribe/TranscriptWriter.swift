//
//  TranscriptWriter.swift
//  D Scribe
//
//  Created by li on 4/4/26.
//

import Foundation

/// Writes a live markdown transcript to disk, appending lines in real time.
final class TranscriptWriter {

    let outputPath: URL
    private let modelName: String
    private var fileHandle: FileHandle?
    private var startTime: Date?
    private(set) var lineCount = 0

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    init(outputDir: URL? = nil, modelName: String = "distil-large-v3") {
        let dir = outputDir ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("transcripts")

        let now = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm"
        let filename = "\(formatter.string(from: now)).md"

        self.outputPath = dir.appendingPathComponent(filename)
        self.modelName = modelName
    }

    /// Create the file and write the header.
    func start() throws {
        let dir = outputPath.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        startTime = Date()

        let header = """
        # Meeting Transcript
        Date: \(Self.dateFormatter.string(from: startTime!))
        Start: \(Self.timeFormatter.string(from: startTime!))
        Model: \(modelName) (local)

        ---


        """

        try header.write(to: outputPath, atomically: true, encoding: .utf8)
        fileHandle = try FileHandle(forWritingTo: outputPath)
        fileHandle?.seekToEndOfFile()

        print("[TranscriptWriter] Writing to \(outputPath.path)")
    }

    /// Append a transcript line and flush immediately.
    func writeLine(label: String, timestamp: Date, text: String) {
        let timeStr = Self.timeFormatter.string(from: timestamp)
        let line = "[\(timeStr)] \(label): \(text)\n"

        if let data = line.data(using: .utf8) {
            fileHandle?.write(data)
            fileHandle?.synchronizeFile()
        }

        lineCount += 1
    }

    /// Write footer and close the file.
    func finalize() {
        guard let start = startTime else { return }
        let end = Date()
        let duration = Int(end.timeIntervalSince(start))
        let minutes = duration / 60
        let seconds = duration % 60

        let footer = """

        ---

        End: \(Self.timeFormatter.string(from: end))
        Duration: \(minutes)m \(seconds)s

        """

        if let data = footer.data(using: .utf8) {
            fileHandle?.write(data)
        }

        fileHandle?.closeFile()
        fileHandle = nil

        print("[TranscriptWriter] Finalized — \(lineCount) lines, \(minutes)m \(seconds)s")
    }
}

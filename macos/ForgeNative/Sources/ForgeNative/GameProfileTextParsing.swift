import Foundation

extension ForgeStore {
    nonisolated static func parseLaunchArgs(_ text: String) throws -> [String] {
        var args: [String] = []
        var current = ""
        var argStarted = false
        var quote: Character?
        let characters = Array(text)
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if character == "\\" {
                let nextIndex = index + 1
                if nextIndex < characters.count, isEscapableLaunchArgCharacter(characters[nextIndex]) {
                    current.append(characters[nextIndex])
                    argStarted = true
                    index += 2
                } else {
                    current.append(character)
                    argStarted = true
                    index += 1
                }
                continue
            }

            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else {
                    current.append(character)
                    argStarted = true
                }
                index += 1
                continue
            }

            if character == "\"" || character == "'" {
                quote = character
                argStarted = true
            } else if character.unicodeScalars.allSatisfy({ CharacterSet.whitespacesAndNewlines.contains($0) }) {
                if argStarted {
                    args.append(current)
                    current = ""
                    argStarted = false
                }
            } else {
                current.append(character)
                argStarted = true
            }

            index += 1
        }

        if let quote {
            throw ForgeError.message("Unclosed \(quote) quote in launch args.")
        }

        if argStarted {
            args.append(current)
        }

        return args
    }

    nonisolated private static func isEscapableLaunchArgCharacter(_ character: Character) -> Bool {
        character == "\\"
            || character == "\""
            || character == "'"
            || character.unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
    }

    nonisolated static func formatLaunchArgs(_ args: [String]) -> String {
        args.map { arg in
            if arg.isEmpty { return "\"\"" }
            let needsQuoting = arg.rangeOfCharacter(from: .whitespacesAndNewlines) != nil
                || arg.contains("\"")
                || arg.contains("'")
                || arg.contains("\\")
            guard needsQuoting else { return arg }
            return "\"\(escapedLaunchArg(arg))\""
        }
        .joined(separator: " ")
    }

    nonisolated private static func escapedLaunchArg(_ arg: String) -> String {
        arg
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    nonisolated static func parseEnvOverrides(_ text: String) throws -> [String: String] {
        var env: [String: String] = [:]
        let invalidKeyCharacters = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "="))

        for (index, rawLine) in text.components(separatedBy: .newlines).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") { continue }

            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else {
                throw ForgeError.message("Environment line \(index + 1) must use KEY=value.")
            }

            let key = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else {
                throw ForgeError.message("Environment line \(index + 1) is missing a key.")
            }
            guard key.rangeOfCharacter(from: invalidKeyCharacters) == nil else {
                throw ForgeError.message("Environment key \(key) cannot contain spaces or '='.")
            }

            env[key] = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return env
    }

    nonisolated static func formatEnvOverrides(_ env: [String: String]) -> String {
        env.keys.sorted().map { "\($0)=\(env[$0] ?? "")" }.joined(separator: "\n")
    }

    nonisolated static func cleanedProfileNotes(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

import Foundation

/// Parses raw LLM output into `ParsedRecipeDTO` with tolerant JSON extraction
/// and decoding (small models often omit optional keys or truncate output).
enum RecipeJSONParser {

    static func parseRecipeDTO(from modelOutput: String) throws -> ParsedRecipeDTO {
        guard let jsonString = modelOutput.extractedJSONObject() else {
            throw InferenceError.noJSONInResponse(modelOutput)
        }
        guard let data = jsonString.data(using: .utf8) else {
            throw InferenceError.malformedResponse
        }
        do {
            return try JSONDecoder().decode(ParsedRecipeDTO.self, from: data)
        } catch {
            throw InferenceError.decodingFailed(error)
        }
    }
}

extension String {

    /// Extracts the first balanced `{ ... }` JSON object from LLM output.
    /// Falls back to repairing truncated JSON when the model hits its token limit.
    func extractedJSONObject() -> String? {
        if let balanced = balancedJSONObject() {
            return balanced
        }
        return repairedTruncatedJSONObject()
    }

    /// Returns a complete JSON object when braces are balanced.
    private func balancedJSONObject() -> String? {
        guard let start = firstIndex(of: "{") else { return nil }

        var depth = 0
        var inString = false
        var isEscaped = false

        for index in self.indices[start...] {
            let character = self[index]

            if inString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    inString = false
                }
                continue
            }

            switch character {
            case "\"":
                inString = true
            case "{":
                depth += 1
            case "}":
                depth -= 1
                if depth == 0 {
                    return String(self[start...index])
                }
            default:
                break
            }
        }

        return nil
    }

    /// Closes truncated JSON objects produced when generation stops mid-response.
    private func repairedTruncatedJSONObject() -> String? {
        guard let start = firstIndex(of: "{") else { return nil }

        var fragment = String(self[start...])
        fragment.closeUnterminatedJSONString()
        fragment.trimIncompleteJSONTail()

        var stack: [Character] = []
        var inString = false
        var isEscaped = false

        for character in fragment {
            if inString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    inString = false
                }
                continue
            }

            switch character {
            case "\"":
                inString = true
            case "{":
                stack.append("}")
            case "[":
                stack.append("]")
            case "}", "]":
                if stack.last == character {
                    stack.removeLast()
                }
            default:
                break
            }
        }

        guard !fragment.isEmpty else { return nil }

        while let closer = stack.popLast() {
            fragment.append(closer)
        }

        return fragment
    }
}

private extension String {

    mutating func closeUnterminatedJSONString() {
        var inString = false
        var isEscaped = false

        for character in self {
            if inString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    inString = false
                }
                continue
            }

            if character == "\"" {
                inString = true
            }
        }

        if inString {
            append("\"")
        }
    }

    mutating func trimIncompleteJSONTail() {
        self = trimmingCharacters(in: .whitespacesAndNewlines)

        while let last = last, last == "," || last == ":" {
            removeLast()
            self = trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Drop a dangling partial key/value such as `,"originalText":"1 lb`.
        while let lastQuote = lastIndex(of: "\"") {
            let tail = self[index(after: lastQuote)...]
            if tail.contains(where: { $0 == "}" || $0 == "]" || $0 == "," }) {
                break
            }
            if tail.contains(":") {
                break
            }
            if let comma = self[..<lastQuote].lastIndex(of: ",") {
                self = String(self[..<comma])
            } else if let brace = self[..<lastQuote].lastIndex(of: "{") {
                self = String(self[...brace])
            } else if let bracket = self[..<lastQuote].lastIndex(of: "[") {
                self = String(self[...bracket])
            } else {
                break
            }
            self = trimmingCharacters(in: .whitespacesAndNewlines)
            while let last = last, last == "," || last == ":" {
                removeLast()
            }
        }
    }
}

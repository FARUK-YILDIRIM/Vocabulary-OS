import Foundation
import FoundationModels

/// Turns `GenerationSchema` into JSON Schema for cloud providers, and cloud replies back into
/// `GeneratedContent` (ADR-003).
enum JSONSchemaAdapter {
    /// The schema as a JSON object, cleaned for providers' structured-output modes:
    /// - `title` and `x-order` are removed (strict modes reject unknown keywords);
    /// - every object gets `additionalProperties: false` and lists all its properties as required;
    /// - `dropArrayBounds` removes `minItems`/`maxItems` for providers that reject them (Anthropic);
    ///   validators enforce the counts instead;
    /// - named sub-schemas (`$defs`/`$ref`) are inlined, since our schemas are never recursive;
    /// - `anyOf` lists of single string values become one `enum`.
    static func jsonObject(for schema: GenerationSchema, dropArrayBounds: Bool) throws(AIError) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(schema),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw .unknown("The output schema could not be encoded")
        }
        let definitions = object["$defs"] as? [String: Any] ?? [:]
        return clean(object, definitions: definitions, dropArrayBounds: dropArrayBounds, depth: 0)
    }

    private static func clean(_ node: [String: Any], definitions: [String: Any], dropArrayBounds: Bool, depth: Int) -> [String: Any] {
        if let reference = node["$ref"] as? String, depth < 16,
           let name = reference.split(separator: "/").last,
           let definition = definitions[String(name)] as? [String: Any] {
            var merged = definition
            if let description = node["description"] { merged["description"] = description }
            return clean(merged, definitions: definitions, dropArrayBounds: dropArrayBounds, depth: depth + 1)
        }
        if let choices = node["anyOf"] as? [[String: Any]], !choices.isEmpty,
           choices.allSatisfy({ $0["type"] as? String == "string" && ($0["enum"] as? [Any])?.count == 1 }) {
            var collapsed: [String: Any] = ["type": "string", "enum": choices.compactMap { ($0["enum"] as? [Any])?.first }]
            if let description = node["description"] { collapsed["description"] = description }
            return collapsed
        }
        var result: [String: Any] = [:]
        for (key, value) in node {
            if key == "title" || key == "x-order" || key == "$defs" { continue }
            if dropArrayBounds && (key == "minItems" || key == "maxItems") { continue }
            result[key] = cleanValue(value, definitions: definitions, dropArrayBounds: dropArrayBounds, depth: depth + 1)
        }
        if result["type"] as? String == "object", let properties = result["properties"] as? [String: Any] {
            result["additionalProperties"] = false
            let order = (node["x-order"] as? [String]) ?? properties.keys.sorted()
            result["required"] = order.filter { properties[$0] != nil }
        }
        return result
    }

    private static func cleanValue(_ value: Any, definitions: [String: Any], dropArrayBounds: Bool, depth: Int) -> Any {
        if let object = value as? [String: Any] {
            return clean(object, definitions: definitions, dropArrayBounds: dropArrayBounds, depth: depth)
        }
        if let array = value as? [Any] {
            return array.map { cleanValue($0, definitions: definitions, dropArrayBounds: dropArrayBounds, depth: depth) }
        }
        return value
    }

    /// A placeholder answer with the schema's shape, for providers whose JSON mode needs an example.
    static func example(for schema: [String: Any]) -> Any {
        if let choices = schema["enum"] as? [Any], let first = choices.first {
            return first
        }
        switch schema["type"] as? String {
        case "object":
            let properties = schema["properties"] as? [String: Any] ?? [:]
            var result: [String: Any] = [:]
            for (key, value) in properties {
                result[key] = example(for: value as? [String: Any] ?? [:])
            }
            return result
        case "array":
            let count = max(schema["minItems"] as? Int ?? 1, 1)
            let item = example(for: schema["items"] as? [String: Any] ?? [:])
            return Array(repeating: item, count: count)
        case "integer", "number":
            return 0
        case "boolean":
            return false
        default:
            return "…"
        }
    }

    static func jsonString(_ object: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]) else {
            return "{}"
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// The first complete JSON object in a model reply, ignoring code fences and surrounding prose.
    static func extractJSONObject(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var isInString = false
        var isEscaped = false
        var index = start
        while index < text.endIndex {
            let character = text[index]
            if isInString {
                if isEscaped { isEscaped = false }
                else if character == "\\" { isEscaped = true }
                else if character == "\"" { isInString = false }
            } else if character == "\"" {
                isInString = true
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 { return String(text[start...index]) }
            }
            index = text.index(after: index)
        }
        return nil
    }

    /// Parses a reply into content that a `Generable` type or a validator can read.
    static func content(fromReply text: String) throws(AIError) -> GeneratedContent {
        guard let json = extractJSONObject(from: text) else {
            throw .invalidOutput("The answer contained no JSON object.")
        }
        do {
            return try GeneratedContent(json: json)
        } catch {
            throw .invalidOutput("The answer's JSON could not be read.")
        }
    }
}

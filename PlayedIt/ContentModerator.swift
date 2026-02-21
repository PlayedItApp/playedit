// ContentModerator.swift
// Client-side text moderation for PlayedIt
// Provides instant feedback before server-side validation

import Foundation

// MARK: - Moderation Result

struct ModerationResult {
    let allowed: Bool
    let reason: String?
    
    static let ok = ModerationResult(allowed: true, reason: nil)
}

// MARK: - Content Moderation Utility

final class ContentModerator {
    
    static let shared = ContentModerator()
    
    private init() {}
    
    // MARK: - Leetspeak Normalization
    
    private let leetMap: [Character: Character] = [
        "@": "a", "4": "a",
        "8": "b",
        "(": "c",
        "3": "e",
        "6": "g", "9": "g",
        "#": "h",
        "1": "i", "!": "i",
        "7": "t",
        "0": "o",
        "5": "s", "$": "s",
        "+": "t",
        "2": "z",
    ]
    
    // MARK: - Word Lists
    
    // Slurs and hate speech — always blocked in all contexts
    private let alwaysBlocked: Set<String> = [
        "nigger", "nigga", "niggers", "niggas", "chink", "chinks", "spic", "spics",
        "wetback", "wetbacks", "kike", "kikes", "gook", "gooks", "beaner", "beaners",
        "coon", "coons", "darkie", "darkies", "jigaboo", "raghead", "ragheads",
        "towelhead", "towelheads", "zipperhead",
        "faggot", "faggots", "fag", "fags", "tranny", "trannies",
        "retard", "retards", "retarded",
        "nazi", "nazis", "hitler",
        // Non-English slurs
        "marica", "maricon", "nègre", "enculé",
    ]
    
    // Profanity — blocked in usernames only (not comments/notes)
    private let profanity: Set<String> = [
        "fuck", "fucker", "fuckers", "fucking", "fucked", "motherfucker", "motherfuckers",
        "shit", "shits", "shitty", "bullshit",
        "bitch", "bitches",
        "asshole", "assholes",
        "dick", "dicks",
        "cock", "cocks",
        "pussy", "pussies",
        "cunt", "cunts",
        "whore", "whores", "slut", "sluts",
        "asshole", "assholes", "ass",
        // Non-English profanity
        "puta", "putas", "pendejo", "pendejos", "mierda", "coño",
        "putain", "merde", "salope", "connard",
        "scheiße", "scheisse", "arschloch", "hurensohn", "fotze",
        "cazzo", "stronzo", "puttana", "vaffanculo",
        "caralho", "porra", "buceta",
    ]
    
    // Whitelisted words (Scunthorpe problem prevention)
    private let whitelist: Set<String> = [
        "scunthorpe", "cockburn", "cocktail", "cockatoo", "cockatiel",
        "peacock", "hancock", "dickens", "dickson", "assassin", "assassins",
        "classic", "classics", "bassist", "therapist",
        "shiitake", "shitake", "buttress", "butterscotch",
        "sextant", "essex", "sussex", "middlesex",
        "nigeria", "nigerian", "nigerians", "niger",
        "raccoon", "cocoon", "coonhound",
        "analytic", "analytics", "analysis", "analog", "analogy",
        "hitchcock", "woodcock", "gamecock",
        "pass", "mass", "grass", "brass", "class", "glass",
        "assume", "assault",
        "pass", "mass", "grass", "brass", "class", "glass", "lass",
    ]
    
    // Reserved usernames
    private let reservedUsernames: Set<String> = [
        "admin", "administrator", "playedit", "played_it", "played-it", "playeditapp", "playeditofficial", "playeditappofficial",
        "support", "help", "info", "contact", "team", "staff", "mod", "moderator",
        "system", "official", "root", "superuser", "null", "undefined",
        "api", "bot", "test", "demo", "example", "guest",
        "noreply", "no-reply", "no_reply",
        "abuse", "security", "privacy", "legal", "copyright",
        "everyone", "all", "here", "channel",
        "dan", "tony", "alex", "dwrib"
    ]
    
    // Targeted insults — profanity aimed at people, blocked in all contexts
    private let targetedInsults: Set<String> = [
        // Compound insults
        "shithead", "shitheads",
        "dickhead", "dickheads",
        "asshead",
        "fuckhead", "fuckheads",
        "cockhead",
        "pisshead",
        "dumbass", "dumbasses",
        "jackass", "jackasses",
        "fatass",
        "bitchass",
        "dipshit", "dipshits",
        "fuckface",
        "shitface",
        "asswipe", "asswipes",
        "shitbag", "shitbags",
        "douchebag", "douchebags",
        "scumbag", "scumbags",
        "cumstain",
        "cocksucker", "cocksuckers",
        "motherfucker", "motherfuckers",
        // Standalone words that are insults when aimed at people
        "dick", "dicks",
        "cock", "cocks",
        "bitch", "bitches",
        "asshole", "assholes",
        "ass",
        "cunt", "cunts",
        "pussy", "pussies",
        "whore", "whores",
        "slut", "sluts",
        "twat", "twats",
        "wanker", "wankers",
        "tosser", "tossers",
        "bellend",
        "knob", "knobhead",
        "prick", "pricks",
    ]
    
    // MARK: - Normalization
    
    private func normalize(_ text: String) -> String {
        var result = text.lowercased()
        
        // Remove zero-width characters
        result = result.replacingOccurrences(
            of: "[\\u{200B}-\\u{200D}\\u{2060}\\u{FEFF}]",
            with: "",
            options: .regularExpression
        )
        
        // Apply leetspeak normalization
        result = String(result.map { leetMap[$0] ?? $0 })
        
        // Collapse repeated characters (3+ -> 2)
        result = result.replacingOccurrences(
            of: "(.)\\1{2,}",
            with: "$1$1",
            options: .regularExpression
        )
        
        return result
    }
    
    // MARK: - Word Boundary Matching
    
    private func containsBlockedWord(_ text: String, in blockedWords: Set<String>) -> String? {
        let normalized = normalize(text)
        let originalLower = text.lowercased()
        
        // Find all whitelist positions in the original text
        var whitelistedRanges: [Range<String.Index>] = []
        for word in whitelist {
            var searchRange = originalLower.startIndex..<originalLower.endIndex
            while let range = originalLower.range(of: word, range: searchRange) {
                whitelistedRanges.append(range)
                searchRange = range.upperBound..<originalLower.endIndex
            }
        }
        
        for blocked in blockedWords {
            // Use word boundary regex
            guard let regex = try? NSRegularExpression(
                pattern: "\\b\(NSRegularExpression.escapedPattern(for: blocked))\\b",
                options: .caseInsensitive
            ) else { continue }
            
            let nsString = normalized as NSString
            let matches = regex.matches(in: normalized, range: NSRange(location: 0, length: nsString.length))
            
            for match in matches {
                // Check if this match falls within a whitelisted word
                let matchRange = Range(match.range, in: normalized)!
                let isWhitelisted = whitelistedRanges.contains { whiteRange in
                    // Approximate check: if the match start is within a whitelisted range
                    let matchStartOffset = normalized.distance(from: normalized.startIndex, to: matchRange.lowerBound)
                    let matchEndOffset = normalized.distance(from: normalized.startIndex, to: matchRange.upperBound)
                    let whiteStartOffset = originalLower.distance(from: originalLower.startIndex, to: whiteRange.lowerBound)
                    let whiteEndOffset = originalLower.distance(from: originalLower.startIndex, to: whiteRange.upperBound)
                    return matchStartOffset >= whiteStartOffset && matchEndOffset <= whiteEndOffset
                }
                
                if !isWhitelisted {
                    return blocked
                }
            }
        }
        
        return nil
    }
    
    // MARK: - Username Word Matching (leading boundary only)
    private func containsBlockedInUsername(_ text: String, in blockedWords: Set<String>) -> String? {
        let normalized = normalize(text)
        
        // Check if the entire text is a whitelisted word
        if whitelist.contains(text.lowercased()) {
            return nil
        }
        
        for blocked in blockedWords {
            // Leading word boundary only — catches "shitplayer" but not "lass" matching "ass"
            guard let regex = try? NSRegularExpression(
                pattern: "\\b\(NSRegularExpression.escapedPattern(for: blocked))",
                options: .caseInsensitive
            ) else { continue }
            
            let nsString = normalized as NSString
            let matches = regex.matches(in: normalized, range: NSRange(location: 0, length: nsString.length))
            
            if !matches.isEmpty {
                let isWhitelisted = whitelist.contains { whiteWord in
                    whiteWord.contains(blocked) && normalized.contains(whiteWord)
                }
                if !isWhitelisted {
                    return blocked
                }
            }
        }
        
        return nil
    }
    
    // MARK: - Public API
    
    /// Check if a username is allowed
    func checkUsername(_ username: String) -> ModerationResult {
        let lower = username.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check reserved usernames
        if reservedUsernames.contains(lower) {
            return ModerationResult(
                allowed: false,
                reason: "This username is reserved. Please choose a different one."
            )
        }
        
        // Check slurs (always blocked)
        if let _ = containsBlockedInUsername(username, in: alwaysBlocked) {
            return ModerationResult(
                allowed: false,
                reason: "This username contains inappropriate language. Please choose a different one."
            )
        }
        
        // Check profanity (blocked in usernames)
        if let _ = containsBlockedInUsername(username, in: profanity) {
            return ModerationResult(
                allowed: false,
                reason: "This username contains inappropriate language. Please choose a different one."
            )
        }
        
        return .ok
    }
    
    /// Check if a comment or note is allowed
    func checkText(_ text: String) -> ModerationResult {
        // Block slurs and hate speech
        if let _ = containsBlockedInUsername(text, in: alwaysBlocked) {
            return ModerationResult(
                allowed: false,
                reason: "Your message contains language that isn't allowed. Please revise and try again."
            )
        }
        
        // Block targeted insults (profanity aimed at people)
        if let _ = containsBlockedInUsername(text, in: targetedInsults) {
            return ModerationResult(
                allowed: false,
                reason: "Your message contains language that isn't allowed. Please revise and try again."
            )
        }
        
        return .ok
    }
}

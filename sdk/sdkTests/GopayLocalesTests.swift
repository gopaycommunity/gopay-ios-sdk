//
//  GopayLocalesTests.swift
//  sdkTests
//
//  Tests for the payment card form locale registry and resolver.
//

import Testing
import Foundation
@testable import sdk

// Serialized because the tests mutate GopayLocales' shared custom/default state.
@Suite(.serialized)
struct GopayLocalesTests {

    /// Resets shared registry state so tests don't leak into each other.
    private func reset() {
        GopayLocales.clearCustom()
        GopayLocales.setDefaultLocale(nil)
    }

    @Test func resolve_knownCode_returnsThatLocale() {
        reset()
        #expect(GopayLocales.resolve("de") == GopayLocales.de)
        #expect(GopayLocales.resolve("cs") == GopayLocales.cs)
    }

    @Test func resolve_codeIsCaseAndRegionInsensitive() {
        reset()
        #expect(GopayLocales.resolve("DE") == GopayLocales.de)
        #expect(GopayLocales.resolve("de-DE") == GopayLocales.de)
        #expect(GopayLocales.resolve("de_AT") == GopayLocales.de)
    }

    @Test func resolve_unknownCode_fallsBackToCzech() {
        reset()
        #expect(GopayLocales.resolve("xx") == GopayLocales.cs)
    }

    @Test func resolve_nilPreferred_usesSdkDefaultWhenSet() {
        reset()
        GopayLocales.setDefaultLocale("fr")
        #expect(GopayLocales.resolve(nil) == GopayLocales.fr)
        reset()
    }

    @Test func resolve_explicitPreferred_beatsSdkDefault() {
        reset()
        GopayLocales.setDefaultLocale("fr")
        #expect(GopayLocales.resolve("it") == GopayLocales.it)
        reset()
    }

    @Test func register_customLocale_isResolvable() {
        reset()
        var custom = GopayLocales.en
        custom.panLabel = "Custom PAN"
        GopayLocales.register(custom, for: "xx")
        #expect(GopayLocales.resolve("xx") == custom)
        reset()
    }

    @Test func register_customLocale_overridesBuiltInOfSameCode() {
        reset()
        var overridden = GopayLocales.de
        overridden.panLabel = "Overridden"
        GopayLocales.register(overridden, for: "de")
        #expect(GopayLocales.resolve("de").panLabel == "Overridden")
        reset()
    }

    @Test func registerAll_registersEveryEntry() {
        reset()
        var xx = GopayLocales.en; xx.panLabel = "XX"
        var yy = GopayLocales.en; yy.panLabel = "YY"
        GopayLocales.registerAll(["xx": xx, "yy": yy])
        #expect(GopayLocales.resolve("xx").panLabel == "XX")
        #expect(GopayLocales.resolve("yy").panLabel == "YY")
        reset()
    }

    @Test func clearCustom_removesCustomButKeepsBuiltIns() {
        reset()
        GopayLocales.register(GopayLocales.en, for: "xx")
        GopayLocales.clearCustom()
        #expect(GopayLocales.resolve("xx") == GopayLocales.cs) // custom gone -> fallback
        #expect(GopayLocales.resolve("de") == GopayLocales.de) // built-in intact
    }

    @Test func availableCodes_includesCustomAndBuiltIns() {
        reset()
        GopayLocales.register(GopayLocales.en, for: "xx")
        let codes = GopayLocales.availableCodes()
        #expect(codes.contains("xx"))
        #expect(codes.contains("cs"))
        #expect(codes == codes.sorted())
        reset()
    }

    @Test func builtIn_containsExpectedTwentyLocales() {
        let expected: Set<String> = [
            "bg", "cs", "de", "en", "es", "et", "fr", "hr", "hu", "it",
            "lt", "lv", "nl", "pl", "pt", "ro", "ru", "sk", "sl", "uk"
        ]
        #expect(Set(GopayLocales.builtIn.keys) == expected)
    }

    @Test func builtIn_everyLocaleHasAllFieldsNonEmpty() {
        for (code, s) in GopayLocales.builtIn {
            let fields = [
                s.panLabel, s.panPlaceholder, s.expLabel, s.expPlaceholder,
                s.cvvLabel, s.cvvPlaceholder, s.pay, s.panErrorPattern,
                s.expErrorPattern, s.cvvErrorPattern, s.patternErrorMessage,
                s.requiredErrorMessage
            ]
            for value in fields {
                #expect(!value.trimmingCharacters(in: .whitespaces).isEmpty,
                        "Locale '\(code)' has an empty field")
            }
        }
    }

    @Test func defaultLocaleConstant_hasBuiltInEntry() {
        #expect(GopayLocales.defaultLocale == "cs")
        #expect(GopayLocales.builtIn[GopayLocales.defaultLocale] != nil)
    }
}

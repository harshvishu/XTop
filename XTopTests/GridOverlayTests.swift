import Foundation
import Testing
@testable import XTop

@Suite("GridOffsetsParser")
struct GridOffsetsParserTests {
    @Test func parsesSimpleList() {
        let result = GridOffsetsParser.parse("8, 8, 4, 4")
        #expect((try? result.get()) == [8, 8, 4, 4])
    }

    @Test func toleratesWhitespace() {
        let result = GridOffsetsParser.parse("  8 ,8 ,  4,4  ")
        #expect((try? result.get()) == [8, 8, 4, 4])
    }

    @Test func acceptsSingleValue() {
        let result = GridOffsetsParser.parse("12")
        #expect((try? result.get()) == [12])
    }

    @Test func rejectsEmpty() {
        let result = GridOffsetsParser.parse("   ")
        if case .failure(let error) = result {
            #expect(error == .empty)
        } else {
            Issue.record("expected failure")
        }
    }

    @Test func rejectsTrailingComma() {
        let result = GridOffsetsParser.parse("8, 8,")
        if case .failure(.invalidToken) = result {
            // ok
        } else {
            Issue.record("expected invalidToken failure")
        }
    }

    @Test func rejectsNonNumeric() {
        let result = GridOffsetsParser.parse("8, abc, 4")
        if case .failure(.invalidToken(let token)) = result {
            #expect(token == "abc")
        } else {
            Issue.record("expected invalidToken failure")
        }
    }

    @Test func rejectsZero() {
        let result = GridOffsetsParser.parse("8, 0, 4")
        if case .failure(.nonPositive(let value)) = result {
            #expect(value == 0)
        } else {
            Issue.record("expected nonPositive failure")
        }
    }

    @Test func rejectsNegative() {
        let result = GridOffsetsParser.parse("8, -4, 4")
        if case .failure(.nonPositive(let value)) = result {
            #expect(value == -4)
        } else {
            Issue.record("expected nonPositive failure")
        }
    }

    @Test func formatRoundTrips() {
        let formatted = GridOffsetsParser.format([8, 8, 4, 4])
        #expect(formatted == "8, 8, 4, 4")
    }

    @Test func formatHandlesFractional() {
        let formatted = GridOffsetsParser.format([4.5, 8])
        #expect(formatted == "4.5, 8")
    }
}

@Suite("GridAxisSpec")
struct GridAxisSpecTests {
    @Test func uniformExpandsToFillDimension() {
        let spec = GridAxisSpec(mode: .uniform, uniformSpacing: 8)
        let positions = spec.resolvedLinePositions(filling: 40)
        #expect(positions == [8, 16, 24, 32])
    }

    @Test func uniformReturnsEmptyForZeroDimension() {
        let spec = GridAxisSpec(mode: .uniform, uniformSpacing: 8)
        #expect(spec.resolvedLinePositions(filling: 0).isEmpty)
    }

    @Test func uniformReturnsEmptyForNonPositiveSpacing() {
        let spec = GridAxisSpec(mode: .uniform, uniformSpacing: 0)
        #expect(spec.resolvedLinePositions(filling: 200).isEmpty)
    }

    @Test func customResolvesToCumulativeOffsets() {
        let spec = GridAxisSpec(mode: .custom, customOffsets: [8, 8, 4, 4])
        let positions = spec.resolvedLinePositions(filling: 100)
        #expect(positions == [8, 16, 20, 24])
    }

    @Test func customClipsOverflow() {
        let spec = GridAxisSpec(mode: .custom, customOffsets: [8, 8, 100, 4])
        let positions = spec.resolvedLinePositions(filling: 20)
        // 8 included, 8+8=16 included, 16+100=116 clipped (>= 20), rest discarded
        #expect(positions == [8, 16])
    }

    @Test func customSkipsZeroAndNegativeGaps() {
        let spec = GridAxisSpec(mode: .custom, customOffsets: [8, 0, -4, 4])
        let positions = spec.resolvedLinePositions(filling: 100)
        #expect(positions == [8, 12])
    }
}

@Suite("GridOverlayConfigStore")
struct GridOverlayConfigStoreTests {
    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "xtop.gridStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return (defaults, suiteName)
    }

    @Test func returnsDefaultForUnknownUDID() {
        let (defaults, _) = makeDefaults()
        let store = GridOverlayConfigStore(defaults: defaults, key: "k")
        let config = store.config(forUDID: "missing")
        #expect(config == .default)
        #expect(config.isEnabled == false)
        #expect(config.opacity == GridOverlayConfig.defaultOpacity)
        #expect(config.horizontal.mode == .uniform)
        #expect(config.horizontal.uniformSpacing == 8)
        #expect(config.vertical.uniformSpacing == 8)
    }

    @Test func roundTripsConfig() {
        let (defaults, _) = makeDefaults()
        let store = GridOverlayConfigStore(defaults: defaults, key: "k")
        let config = GridOverlayConfig(
            isEnabled: true,
            opacity: 0.5,
            horizontal: GridAxisSpec(mode: .custom, uniformSpacing: 8, customOffsets: [12, 12]),
            vertical: GridAxisSpec(mode: .custom, uniformSpacing: 8, customOffsets: [8, 8, 4, 4])
        )
        store.setConfig(config, forUDID: "udid-1")

        let reread = GridOverlayConfigStore(defaults: defaults, key: "k")
        #expect(reread.config(forUDID: "udid-1") == config)
    }

    @Test func storesPerUDIDIndependently() {
        let (defaults, _) = makeDefaults()
        let store = GridOverlayConfigStore(defaults: defaults, key: "k")
        let a = GridOverlayConfig(isEnabled: true, opacity: 0.4)
        let b = GridOverlayConfig(isEnabled: false, opacity: 0.7)
        store.setConfig(a, forUDID: "A")
        store.setConfig(b, forUDID: "B")
        #expect(store.config(forUDID: "A") == a)
        #expect(store.config(forUDID: "B") == b)
    }

    @Test func clearReturnsToDefault() {
        let (defaults, _) = makeDefaults()
        let store = GridOverlayConfigStore(defaults: defaults, key: "k")
        store.setConfig(GridOverlayConfig(isEnabled: true), forUDID: "udid-1")
        store.clearConfig(forUDID: "udid-1")
        #expect(store.config(forUDID: "udid-1") == .default)
    }
}

@Suite("SimulatorWindowTracker matching")
struct SimulatorWindowMatcherTests {
    private struct FakeWindow { let title: String? }

    @Test func matchesByDisplayName() {
        let identity = SimulatorIdentity(udid: "U-1", displayName: "iPhone 17 Pro")
        let windows = [
            FakeWindow(title: "iPad Pro (12.9-inch) — iPadOS 18.0"),
            FakeWindow(title: "iPhone 17 Pro — iOS 26.0"),
            FakeWindow(title: "iPhone 17 — iOS 26.0")
        ]
        let match = SimulatorWindowTracker.matchWindow(for: identity, in: windows) { $0.title }
        #expect(match?.title == "iPhone 17 Pro — iOS 26.0")
    }

    @Test func matchIsCaseInsensitive() {
        let identity = SimulatorIdentity(udid: "U-1", displayName: "iPhone 17 Pro")
        let windows = [FakeWindow(title: "IPHONE 17 PRO — iOS 26.0")]
        let match = SimulatorWindowTracker.matchWindow(for: identity, in: windows) { $0.title }
        #expect(match != nil)
    }

    @Test func fallsBackToUDIDSubstring() {
        let identity = SimulatorIdentity(udid: "abc-123", displayName: "iPhone 17 Pro")
        let windows = [
            FakeWindow(title: "Some Window abc-123 details"),
            FakeWindow(title: "Other Window")
        ]
        let match = SimulatorWindowTracker.matchWindow(for: identity, in: windows) { $0.title }
        #expect(match?.title == "Some Window abc-123 details")
    }

    @Test func returnsNilWhenNothingMatches() {
        let identity = SimulatorIdentity(udid: "U-1", displayName: "iPhone 17 Pro")
        let windows = [FakeWindow(title: "iPad Pro — iPadOS 18.0")]
        let match = SimulatorWindowTracker.matchWindow(for: identity, in: windows) { $0.title }
        #expect(match == nil)
    }

    @Test func returnsNilForEmptyList() {
        let identity = SimulatorIdentity(udid: "U-1", displayName: "iPhone 17 Pro")
        let windows: [FakeWindow] = []
        let match = SimulatorWindowTracker.matchWindow(for: identity, in: windows) { $0.title }
        #expect(match == nil)
    }
}

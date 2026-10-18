import Foundation

/// Recognizes "tap a lone modifier twice" (e.g. Shift, Shift) without interfering with normal use.
///
/// A tap counts only when the modifier goes down and up again with no other modifier held, no key
/// pressed and no mouse button pressed in between, and the press is short. Two qualifying taps within
/// the interval fire. Shift-click selection, ⌘C, typing capitals and holding ⌘ all reset the state, so
/// ordinary shortcuts never trigger the radial. Pure logic: fed events, emits matches (unit tested).
public struct ModifierTapRecognizer: Sendable {
    public enum Modifier: String, CaseIterable, Sendable {
        case shift, command, option, control
    }

    public enum Input: Sendable {
        /// Current set of held modifiers (from a flagsChanged event).
        case modifiers(Set<Modifier>, time: TimeInterval)
        /// Any key press (keyDown) — cancels a pending tap.
        case key(time: TimeInterval)
        /// Any mouse button press — cancels a pending tap (e.g. Shift-click).
        case mouse(time: TimeInterval)
    }

    public var watched: Set<Modifier>
    public var doubleTapInterval: TimeInterval
    public var maxHold: TimeInterval

    private var held: Set<Modifier> = []
    private var pressStart: (Modifier, TimeInterval)?
    private var pressContaminated = false
    private var lastTap: (Modifier, TimeInterval)?

    public init(watched: Set<Modifier>, doubleTapInterval: TimeInterval = 0.32, maxHold: TimeInterval = 0.22) {
        self.watched = watched
        self.doubleTapInterval = doubleTapInterval
        self.maxHold = maxHold
    }

    /// Feed an event. Returns the modifier that was double-tapped, if this event completed a double tap.
    public mutating func handle(_ input: Input) -> Modifier? {
        switch input {
        case .key, .mouse:
            pressContaminated = true
            lastTap = nil
            return nil
        case .modifiers(let now, let time):
            defer { held = now }
            let pressed = now.subtracting(held)
            let released = held.subtracting(now)
            if !pressed.isEmpty {
                // A modifier went down. Only a single lone modifier can start a tap.
                if now.count == 1, let m = now.first, watched.contains(m) {
                    pressStart = (m, time)
                    pressContaminated = false
                } else {
                    pressStart = nil
                    pressContaminated = true
                    lastTap = nil
                }
                return nil
            }
            guard !released.isEmpty else { return nil }
            defer { if now.isEmpty { pressContaminated = false } }
            guard now.isEmpty, let (m, start) = pressStart, released == [m], !pressContaminated, time - start <= maxHold else {
                pressStart = nil
                lastTap = nil
                return nil
            }
            pressStart = nil
            if let (prev, prevTime) = lastTap, prev == m, time - prevTime <= doubleTapInterval + maxHold {
                lastTap = nil
                return m
            }
            lastTap = (m, time)
            return nil
        }
    }

    public mutating func reset() {
        held = []
        pressStart = nil
        pressContaminated = false
        lastTap = nil
    }
}

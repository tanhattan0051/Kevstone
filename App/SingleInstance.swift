// SingleInstance.swift — one Keystone per user (design spec E.8).
//
// The event tap is session-scoped, so two running copies would each transform
// every keystroke — producing doubled/garbled output. We take an exclusive
// advisory lock (flock) on a per-user file for the process's lifetime; a second
// instance that can't get the lock knows another copy is already running and
// bows out. This is what prevents "two `swift run` copies fighting over keys".

import Foundation

enum SingleInstance {
    // Held open for the whole process lifetime so the flock persists; the OS
    // releases it automatically when the process exits (even on crash).
    private nonisolated(unsafe) static var lockFD: Int32 = -1

    /// Returns true if this is the only instance (lock acquired). Returns false
    /// if another Keystone already holds the lock.
    @discardableResult
    static func acquire() -> Bool {
        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return true   // can't resolve a home dir → fail open, don't block startup
        }
        let dir = base.appendingPathComponent("com.tanta.keystone", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let lockPath = dir.appendingPathComponent("instance.lock").path

        let fd = open(lockPath, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { return true }              // couldn't open → fail open
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            close(fd)
            return false                                // another instance holds it
        }
        lockFD = fd                                     // keep the fd (and the lock) alive
        return true
    }
}

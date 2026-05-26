import Foundation
import SwiftData

/// The signed-in human using the app. See `User` in CONTEXT.md.
/// Sign in with Apple is required (per ADR 0003); there is no anonymous mode.
/// A single User per install in V1.
@Model
final class User {
    /// Apple's stable `subject` claim from Sign in with Apple. Survives iCloud
    /// re-sign-in and device migration. The canonical identifier for the User.
    var appleUserID: String = ""

    /// Optional display name. Apple provides this only on the first sign-in event;
    /// after that it's our job to remember it.
    var displayName: String?

    /// Optional email (relay or real). Apple provides this only on first sign-in.
    var email: String?

    var createdAt: Date = Date()

    init(appleUserID: String, displayName: String? = nil, email: String? = nil) {
        self.appleUserID = appleUserID
        self.displayName = displayName
        self.email = email
        self.createdAt = Date()
    }
}

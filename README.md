# MTAuthHelper

`MTAuthHelper` is a small iOS Swift package that wraps Firebase Auth, Google Sign-In, and Sign in with Apple behind a single helper API.

It currently provides:

- Google sign-in with `GoogleSignIn`
- Sign in with Apple using system provided button `SignInWithAppleButton`
- Sign in with Apple using customized button with async/await implemented by `ASAuthorizationController + delegate + Continuation`
- Firebase sign-out

The package targets `iOS 15+` and enables Swift strict concurrency checks.

## Requirements

- iOS 15+
- Swift 6.2
- Firebase Auth configured in the host app
- Google Sign-In configured in the host app
- Sign in with Apple capability enabled in the host app

## Installation

Add the package to your app as a local or remote Swift Package dependency using `https://github.com/armstrongcorner/MTAuthHelper`.

Current package dependencies:

- `FirebaseAuth`
- `GoogleSignIn`

## Public API

Main type:

```swift
@MainActor
public final class MTAuthHelper: NSObject
```

Shared instance:

```swift
MTAuthHelper.shared
```

Available methods:

```swift
public func signOut() throws
public func handleGoogleSignIn() async throws -> AuthDataResult?
public func prepareAppleSignIn(with request: ASAuthorizationAppleIDRequest)
public func handleAppleSignIn(with result: Result<ASAuthorization, Error>) async throws -> AuthDataResult?
public func handleAppleSignIn() async throws -> AuthDataResult?
```

## Google Sign-In

Call Google sign-in from the main actor:

```swift
Task { @MainActor in
    do {
        let result = try await MTAuthHelper.shared.handleGoogleSignIn()
        print(result?.user.uid ?? "")
    } catch {
        print(error.localizedDescription)
    }
}
```

`handleGoogleSignIn()`:

- finds the top view controller
- presents the Google sign-in flow
- exchanges Google tokens for a Firebase credential
- signs in with Firebase Auth

## Sign in with Apple

### Option 1: Use `SignInWithAppleButton`

```swift
import AuthenticationServices
import MTAuthHelper

SignInWithAppleButton(.continue) { request in
    MTAuthHelper.shared.prepareAppleSignIn(with: request)
} onCompletion: { result in
    Task { @MainActor in
        do {
            let authResult = try await MTAuthHelper.shared.handleAppleSignIn(with: result)
            print(authResult?.user.uid ?? "")
        } catch {
            print(error.localizedDescription)
        }
    }
}
```

### Option 2: Use a custom button

If you need a fully custom Apple sign-in button, call the helper's async Apple flow:

```swift
Button {
    Task { @MainActor in
        do {
            let result = try await MTAuthHelper.shared.handleAppleSignIn()
            print(result?.user.uid ?? "")
        } catch {
            print(error.localizedDescription)
        }
    }
} label: {
    HStack {
        Image(systemName: "apple.logo")
        Text("Continue with Apple")
    }
}
```

This path uses `ASAuthorizationController + delegate` internally and bridges the callback-based API into `async/await` with a continuation.

## Error Handling

The package throws `MTAuthError`:

```swift
public enum MTAuthError: Error {
    case noTopVC
    case noIdToken
    case appleCredentialNotFound
    case appleSignInError(Error)
    case firebaseAuthError(Error)
    case unknown
}
```

Typical handling:

```swift
do {
    _ = try await MTAuthHelper.shared.handleGoogleSignIn()
} catch let error as MTAuthError {
    print(error)
} catch {
    print(error.localizedDescription)
}
```

## Notes

- `MTAuthHelper` is isolated to the main actor because authentication flows present UI.
- `AuthorizationController` from SwiftUI environment is intentionally not used inside this package. That API is appropriate in SwiftUI views, not in a reusable helper package.
- Apple sign-in nonce generation is handled by `CryptoUtility`.
- Top view controller lookup for Google sign-in is handled by `ViewUtility`.

## Source Layout

```text
Sources/
  MTAuthHelper.swift
  Utilities/
    CryptoUtility.swift
    ViewUtility.swift
```

## Host App Setup


The host app is still responsible for project configuration required by Firebase Auth, Google Sign-In, and Sign in with Apple.

### Firebase Setup

Make sure Firebase is initialized in the host app before calling any authentication APIs from `MTAuthHelper`.

Typical app setup includes:

- adding the Firebase SDK to the app
- adding `GoogleService-Info.plist` to the app target
- configuring Firebase during app launch

### Google Sign-In Setup

To use Google Sign-In, the host app must:

- add `GoogleService-Info.plist` to the app target
- configure the app's URL scheme using the reversed client ID from `GoogleService-Info.plist`

The URL scheme is typically the value of `REVERSED_CLIENT_ID`.

Example:

```text
com.googleusercontent.apps.xxxxxxxxxxxxxxxxxxxxx
```

### Sign in with Apple Setup

To use Sign in with Apple, the host app must enable the required capability.

In Xcode:

1. Open the app target.
2. Go to `Signing & Capabilities`.
3. Add the `Sign in with Apple` capability.
4. Add the `GIDClientID` key pair in Info.plist (generated from adding URL scheme), the value should be the 'CLIENT_ID' value in GoogleService-Info.plist

If your app uses Firebase Auth together with Apple Sign-In, you should also make sure the Apple sign-in provider is enabled in the Firebase Console.

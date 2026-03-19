import FirebaseAuth
import GoogleSignIn
import AuthenticationServices

public enum MTAuthError: Error {
    case noTopVC
    case noIdToken
    case appleCredentialNotFound
    case appleSignInError(Error)
    case firebaseAuthError(Error)
    case unknown
}

@MainActor
public final class MTAuthHelper: NSObject {
    public static let shared = MTAuthHelper()
    private override init() {}
    
    private var currentNonce: String?
    private var appleSignInContinuation: CheckedContinuation<AuthDataResult?, Error>?
    
    package func signIn(credential: AuthCredential) async throws -> AuthDataResult {
        return try await Auth.auth().signIn(with: credential)
    }

    public func signOut() throws {
        try Auth.auth().signOut()
    }
}

// MARK: - Handle Google SSO
extension MTAuthHelper {
    @discardableResult
    public func handleGoogleSignIn() async throws -> AuthDataResult? {
        do {
            // Get the top uiviewcontroller to pop google login sheet.
            guard let topVC = await ViewUtility.shared.topViewController() else {
                throw MTAuthError.noTopVC
            }
            
            // Get the Google login result and create sign in credential with tokens.
            let gidSignInResult = try await GIDSignIn.sharedInstance.signIn(withPresenting: topVC)
            
            guard let idToken = gidSignInResult.user.idToken?.tokenString else {
                throw MTAuthError.noIdToken
            }
            let accessToken = gidSignInResult.user.accessToken.tokenString
            
            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)
            
            // Sign in with Firebase.
            return try await Auth.auth().signIn(with: credential)
        } catch {
            print(error.localizedDescription)
            throw MTAuthError.firebaseAuthError(error)
        }
    }
}

// MARK: - Handle iOS SSO with request and result
/// Example of using iOS SDK provided sign in button
/*
 SignInWithAppleButton(.continue) { request in
     MTAuthHelper.shared.prepareAppleSignIn(with: request)
 } onCompletion: { result in
     Task {
         _ = try? await MTAuthHelper.shared.handleAppleSignIn(with: result)
     }
 }
 */
extension MTAuthHelper {
    public func prepareAppleSignIn(with request: ASAuthorizationAppleIDRequest) {
        let nonce = CryptoUtility.randomNonceString()
        currentNonce = nonce
        request.requestedScopes = [.email, .fullName]
        request.nonce = CryptoUtility.sha256(nonce)
    }
    
    @discardableResult
    public func handleAppleSignIn(with result: Result<ASAuthorization, Error>) async throws -> AuthDataResult? {
        switch result {
        case .success(let auth):
            guard let appleIDCredential = auth.credential as? ASAuthorizationAppleIDCredential else {
                print("Unable to fetch Apple credential related info")
                throw MTAuthError.appleCredentialNotFound
            }
            
            return try await signInWithAppleCredential(appleIDCredential)
        case .failure(let error):
            print("Sign in with Apple failed: \(error.localizedDescription)")
            throw MTAuthError.appleSignInError(error)
        }
    }
    
    private func signInWithAppleCredential(_ appleIDCredential: ASAuthorizationAppleIDCredential) async throws -> AuthDataResult? {
        guard
            let appleIDToken = appleIDCredential.identityToken,
            let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
            throw MTAuthError.appleCredentialNotFound
        }

        // Initialize a Firebase credential, including the user's full name.
        let credential = OAuthProvider.appleCredential(
            withIDToken: idTokenString,
            rawNonce: currentNonce,
            fullName: appleIDCredential.fullName
        )

        // Sign in with Firebase.
        do {
            return try await Auth.auth().signIn(with: credential)
        } catch {
            print(error.localizedDescription)
            throw MTAuthError.firebaseAuthError(error)
        }
    }
}

// MARK: - Handle Apple SSO with AuthorizationController
/// Comment this out because AuthorizationController async way is used for SwiftUI only,
/// otherwise 'import _AuthenticationServices_SwiftUI' could work but it is not a normal way
/*
import _AuthenticationServices_SwiftUI

extension MTAuthHelper {
    public func startAppleSignIn(with authController: AuthorizationController) async throws -> AuthDataResult? {
        // Create and perform Apple auth request
        let result: ASAuthorizationResult
        do {
            let request = ASAuthorizationAppleIDProvider().createRequest()
            MTAuthHelper.shared.prepareAppleSignIn(with: request)
            
            result = try await authController.performRequest(request)
        } catch {
            throw MTAuthError.appleAuthRequestFailed(error)
        }
        
        // Handle the auth result
        switch result {
        case .appleID(let credential):
            return try await signInWithAppleCredential(credential)
        default:
            throw MTAuthError.unknown
        }
    }
}
 */

// MARK: - Handle Apple SSO with ASAuthorizationController + delegate
extension MTAuthHelper: ASAuthorizationControllerDelegate {
    public func handleAppleSignIn() async throws -> AuthDataResult? {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        prepareAppleSignIn(with: request)

        return try await withCheckedThrowingContinuation { continuation in
            appleSignInContinuation = continuation

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.performRequests()
        }
    }
    
    public func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard
            let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let appleIDToken = appleIDCredential.identityToken,
            let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
            appleSignInContinuation?.resume(throwing: MTAuthError.appleCredentialNotFound)
            appleSignInContinuation = nil
            return
        }

        let credential = OAuthProvider.appleCredential(
            withIDToken: idTokenString,
            rawNonce: currentNonce,
            fullName: appleIDCredential.fullName
        )

        Task {
            do {
                let result = try await Auth.auth().signIn(with: credential)
                appleSignInContinuation?.resume(returning: result)
                appleSignInContinuation = nil
            } catch {
                appleSignInContinuation?.resume(throwing: MTAuthError.firebaseAuthError(error))
                appleSignInContinuation = nil
            }
        }
    }
    
    public func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: any Error) {
        appleSignInContinuation?.resume(throwing: MTAuthError.appleSignInError(error))
        appleSignInContinuation = nil
    }
}

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
public final class MTAuthHelper {
    public static let shared = MTAuthHelper()
    private init() {}
    
    private var currentNonce: String?
    
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

// MARK: - Handle iOS SSO
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
            do {
                guard
                    let appleIDCredential = auth.credential as? ASAuthorizationAppleIDCredential,
                    let appleIDToken = appleIDCredential.identityToken,
                    let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
                    
                    print("Unable to fetch Apple credential related info")
                    throw MTAuthError.appleCredentialNotFound
                }
                
                // Initialize a Firebase credential, including the user's full name.
                let credential = OAuthProvider.appleCredential(
                    withIDToken: idTokenString,
                    rawNonce: currentNonce,
                    fullName: appleIDCredential.fullName
                )
                
                // Sign in with Firebase.
                return try await Auth.auth().signIn(with: credential)
            } catch {
                print(error.localizedDescription)
                throw MTAuthError.firebaseAuthError(error)
            }
        case .failure(let error):
            print("Sign in with Apple failed: \(error.localizedDescription)")
            throw MTAuthError.appleSignInError(error)
        }
    }
}

//
//  OAuth.swift
//  PCloudSDKSwift
//
//  Created by Todor Pitekov on 03/01/2017
//  Copyright © 2017 pCloud LTD. All rights reserved.
//

import Foundation

/// Executes UI-specific actions related to the OAuth authorization flow.
public protocol OAuthAuthorizationFlowView {
	/// Presents a web view to the user showing a page at a specific address. The web view should forward navigation actions
	/// and the user attempting to exit the web view to the provided blocks.
	///
	/// - parameter url: The address to open in the web view.
	/// - parameter interceptNavigation: A block to be called when the web view attempts a redirection. The block should
	/// be invoked with the destination address. Returns `true` when the web view should cancel the redirection, and `false` otherwise.
	/// - parameter didCancel: A block to be called when the user attempts to exit the web view by means of a button, gesture, etc.
	func presentWebView(url: URL, interceptNavigation: @escaping (URL) -> Bool, didCancel: @escaping () -> Void)
	
	/// Dismisses the web view presented using
	/// ```
	/// presentWebView(:interceptNavigation:didCancel:)
	/// ```
	func dismissWebView()
}


/// OAuth namespace.
public struct OAuth {
	/// The result of an authorization attempt.
	public enum Result {
		case success(token: String, userId: UInt64)
		case failure(Error)
		case cancel
	}
	
	/// A failed authorization as per RFC 6749.
	public enum Error: String, Swift.Error {
		/// The request is missing a required parameter, includes an invalid parameter value, includes a parameter more than
		/// once, or is otherwise malformed.
		case invalidRequest = "invalid_request"
		
		/// The client is not authorized to request an access token using this method.
		case unauthorizedClient = "unauthorized_client"
		
		/// The resource owner or authorization server denied the request.
		case accessDenied = "access_denied"
		
		/// The authorization server does not support obtaining an access token using this method.
		case unsupportedResponseType = "unsupported_response_type"
		
		/// The requested scope is invalid, unknown, or malformed.
		case invalidScope = "invalid_scope"
		
		/// The authorization server encountered an unexpected condition that prevented it from fulfilling the request.
		case serverError = "server_error"
		
		///  The authorization server is currently unable to handle the request due to a temporary overloading or maintenance
		/// of the server.
		case temporarilyUnavailable = "temporarily_unavailable"
		
		/// Unexpected error.
		case unknown = "unknown"
	}
	
	/// Attempts to authorize.
	///
	/// - parameter view: An object handling UI-specific actions related to the authorization flow.
	/// - parameter appKey: An app key.
	/// - parameter storeToken: A block called with an access token and a user id as the first and second arguments, respectively.
	/// It should store the token in a persistent storage.
	/// - parameter completionToken: A block called when authorization completes.
	public static func performAuthorizationFlow(view: OAuthAuthorizationFlowView,
	                                            appKey: String,
	                                            storeToken: @escaping (String, UInt64) -> Void,
	                                            _ completionBlock: @escaping (Result) -> Void) {
		// Create URL.
		let authorizationUrl = createAuthorizationUrl(appKey: appKey, redirectUrl: createRedirectUrl(appKey: appKey))
		
		// Define callbacks.
		let interceptBlock: (URL) -> Bool = { url in
			if let result = handleRedirectUrl(url, appKey: appKey) {
				// This is an OAuth redirect.
				view.dismissWebView()
				
				if case let .success(token, userId) = result {
					storeToken(token, userId)
				}
				
				completionBlock(result)
				return true
			}
			
			return false
		}
		
		let cancelBlock = {
			view.dismissWebView()
			completionBlock(.cancel)
		}
		
		// Present the web view.
		view.presentWebView(url: authorizationUrl, interceptNavigation: interceptBlock, didCancel: cancelBlock)
	}
	
	/// Fetches the first access token found in the keychain.
	///
	/// - returns: An OAuth access token, or `nil` if there are no access tokens in the keychain.
	public static func getAnyToken() -> String? {
		if let key = Keychain.getAllKeys().first {
			return Keychain.getString(forKey: key)
		}
		
		return nil
	}
	
	/// Fetches an access token for a specific user.
	///
	/// - parameter userId: The unique identifier of a user.
	/// - returns: An OAuth access token, or `nil` if there is no access token for this user in the keychain.
	public static func getToken(forUser userId: UInt64) -> String? {
		return Keychain.getString(forKey: keychainKeyForUser(userId))
	}
	
	/// Updates an access token in the keychain for a user.
	///
	/// - parameter token: An OAuth access token.
	/// - parameter userId: A unique identifier of a user to store `token` against.
	public static func storeToken(_ token: String, forUser userId: UInt64) {
		Keychain.set(token, forKey: keychainKeyForUser(userId))
	}
	
	/// Deletes a token for a user from the keychain.
	///
	/// - parameter userId: A unique identifier of a user to delete the token for.
	public static func deleteToken(forUser userId: UInt64) {
		Keychain.deleteData(forKey: keychainKeyForUser(userId))
	}
	
	/// Deletes all tokens from the keychain.
	public static func deleteAllTokens() {
		for key in Keychain.getAllKeys() {
			Keychain.deleteData(forKey: key)
		}
	}
	
	// Computes keychain key from a user id.
	static func keychainKeyForUser(_ userId: UInt64) -> String {
		return "\(userId)"
	}
	
	// Creates a redirect URL using and app key.
	static func createRedirectUrl(appKey: String) -> String {
		var components = URLComponents()
		components.scheme = "pclsdk-w-\(appKey.lowercased())"
		components.host = "oauth2redirect"
		
		return components.url!.absoluteString
	}
	
	// Creates an authorization URL from an app key for the implicit grant flow.
	static func createAuthorizationUrl(appKey: String, redirectUrl: String) -> URL {
		var components = URLComponents()
		components.scheme = Scheme.https.rawValue
		components.host = "my.pcloud.com"
		components.path = "/oauth2/authorize"
		components.queryItems = [
			URLQueryItem(name: "client_id", value: appKey),
			URLQueryItem(name: "response_type", value: "token"),
			URLQueryItem(name: "redirect_uri", value: redirectUrl)
		]
		
		return components.url!
	}
	
	// Checks if the provided url is a redirect url and if it is, tries to extract a result from its fragment.
	static func handleRedirectUrl(_ url: URL, appKey: String) -> Result? {
		let redirectUrl = URL(string: createRedirectUrl(appKey: appKey))!
		
		guard url.scheme == redirectUrl.scheme && url.host == redirectUrl.host else {
			return nil
		}
		
		return extractResult(from: url)
	}
	
	// Extracts a result from a redirection URL.
	static func extractResult(from url: URL) -> Result {
		// As of the time of writing this (December 2016), this is how the pCloud API manages access denied - it does not send a fragment.
		guard let fragment = url.fragment else {
			return .failure(.accessDenied)
		}
		
		// Convert fragment parameters to key value pairs.
		var parameters: [String: String] = [:]
		
		for pair in fragment.components(separatedBy: "&") {
			let components = pair.components(separatedBy: "=")
			parameters[components[0]] = components[1]
		}
		
		// Handle errors.
		if let errorCode = parameters["error"] {
			if let error = Error(rawValue: errorCode) {
				return .failure(error)
			}
			
			return .failure(.unknown)
		}
		
		// Expect that if there is no error, there must be an access token.
		let token = parameters["access_token"]!
		let userId = parameters["userid"]!
		
		return .success(token: token, userId: UInt64(userId)!)
	}
}

extension OAuth.Result: CustomStringConvertible {
	public var description: String {
		switch self {
		case let .success(token, userId): return "SUCCESS: token=\(token), userid=\(userId)"
		case let .failure(error): return "FAILURE: \(error)"
		case .cancel: return "CANCELLED"
		}
	}
}

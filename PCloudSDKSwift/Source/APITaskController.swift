//
//  APITaskController.swift
//  PCloudSDKSwift
//
//  Created by Todor Pitekov on 03/01/2017
//  Copyright © 2016 pCloud LTD. All rights reserved.
//

import Foundation

/// Dispatches network tasks for pCloud API methods.
public final class APITaskController {
	/// Builds a `CallOperation` from a `Call.Request`.
	public typealias CallDispatcher = (Call.Request) -> CallOperation
	/// Builds an `UploadOperation` from an `Upload.Request`.
	public typealias UploadDispatcher = (Upload.Request) -> UploadOperation
	/// Builds a `DownloadOperation` from a `Download.Request`.
	public typealias DownloadDispatcher = (Download.Request) -> DownloadOperation
	
	fileprivate let authenticator: Authenticator
	fileprivate let hostProvider: HostProvider
	fileprivate let callDispatcher: CallDispatcher
	fileprivate let uploadDispatcher: UploadDispatcher
	fileprivate let downloadDispatcher: DownloadDispatcher
	
	/// Initializes a controller with a host provider, command authenticator and network operation builders.
	///
	/// - parameter hostProvider: Used to derive the endpoint when dispatching a network task.
	/// - parameter authenticator: Used to attach authentication data to methods that require authentication.
	/// - parameter callDispatcher: A block creating a `CallOperation` from a `Call.Request`.
	/// - parameter uploadDispatcher: A block creating an `UploadOperation` from an `Upload.Request`.
	/// - parameter downloadDispatcher: A block creating a `DownloadOperation` from a `Download.Request`.
	public init(hostProvider: HostProvider,
	            authenticator: Authenticator,
	            callDispatcher: @escaping CallDispatcher,
	            uploadDispatcher: @escaping UploadDispatcher,
	            downloadDispatcher: @escaping DownloadDispatcher) {
		self.authenticator = authenticator
		self.hostProvider = hostProvider
		self.callDispatcher = callDispatcher
		self.uploadDispatcher = uploadDispatcher
		self.downloadDispatcher = downloadDispatcher
	}
	
	fileprivate func buildCallRequest(command: Call.Command, hostName: String?, authenticate: Bool) -> Call.Request {
		let host = hostName ?? hostProvider.defaultHostName
		var command = command
		
		if authenticate {
			command.parameters.append(contentsOf: authenticator.authenticationParameters)
		}
		
		return Call.Request(command: command, hostName: host)
	}
	
	fileprivate func buildUploadRequest(command: Call.Command, body: Upload.Request.Body, hostName: String?, authenticate: Bool) -> Upload.Request {
		let host = hostName ?? hostProvider.defaultHostName
		var command = command
		
		if authenticate {
			command.parameters.append(contentsOf: authenticator.authenticationParameters)
		}
		
		return Upload.Request(command: command, body: body, hostName: host)
	}
	
	/// Dispatches and returns a task for a specific pCloud API method.
	///
	/// - parameter method: An object defining input and output for this call.
	/// - parameter hostName: An API host name. When `nil`, the controller will fall back to its host provider.
	/// - returns: A non-running task that can execute the call.
	public func call<T: PCloudAPIMethod>(_ method: T, onHost hostName: String? = nil) -> CallTask<T> {
		let command = method.createCommand()
		let request = buildCallRequest(command: command, hostName: hostName, authenticate: method.requiresAuthentication)
		let operation = callDispatcher(request)
		let responseParser = method.createResponseParser()
		return CallTask(operation: operation, responseParser: responseParser)
	}
	
	/// Dispatches and returns an upload task using a specific API method.
	///
	/// - parameter method: An object defining input and output for this call.
	/// - parameter body: The data to upload.
	/// - parameter hostName: An API host name. When `nil`, the controller will fall back to its host provider.
	/// - returns: A non-running task that can execute the upload.
	public func upload<T: PCloudAPIMethod>(_ method: T, body: Upload.Request.Body, onHost hostName: String? = nil) -> UploadTask<T> {
		let command = method.createCommand()
		let request = buildUploadRequest(command: command, body: body, hostName: hostName, authenticate: method.requiresAuthentication)
		let operation = uploadDispatcher(request)
		let responseParser = method.createResponseParser()
		return UploadTask(operation: operation, responseParser: responseParser)
	}
	
	/// Creates and returns a download task given an address provider and a destination.
	///
	/// - parameter addressProvider: A block obtaining a resource address asynchronously. When the task completes, the completion block passed
	/// as the parameter to this block should be called on the main thread. Referenced strongly by the task.
	/// - parameter operationBuilder: A block creating a download operation from a resource address. Referenced strongly by the task.
	/// - returns: A non-running task that can execute the download.
	public func download(addressProvider: @escaping DownloadTask.AddressProvider, destination: @escaping (URL) -> URL) -> DownloadTask {
		let downloadDispatcher = self.downloadDispatcher
		
		let operationBuilder: (URL) -> DownloadOperation = { address in
			let request = Download.Request(resourceAddress: address, destination: destination)
			return downloadDispatcher(request)
		}
		
		return DownloadTask(addressProvider: addressProvider, operationBuilder: operationBuilder)
	}
}

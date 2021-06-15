//
//  NetworkRouter.swift
//  Avocadough
//
//  Created by Thomas Rademaker on 2/10/19.
//  Copyright © 2019 SparrowTek. All rights reserved.
//

import Foundation

public protocol NetworkRouterDelegate: AnyObject {
    func intercept(_ request: inout URLRequest)
}

public protocol NetworkRouterProtocol: AnyObject {
    associatedtype Endpoint: EndpointType
    var delegate: NetworkRouterDelegate? { get set }
    @available(iOS 15.0, *)
    func execute<T: Decodable>(_ route: Endpoint) async throws -> T
}

public enum NetworkError : Error {
    case encodingFailed
    case missingURL
    case networkError(data: Data?)
    case statusCode
    case noData
}

public typealias HTTPHeaders = [String:String]

public class NetworkRouter<Endpoint: EndpointType>: NetworkRouterProtocol {
    
    public weak var delegate: NetworkRouterDelegate?
    let urlSession: URLSession
    let reachability: Reachability
    let urlSessionTaskDelegate: URLSessionTaskDelegate?
    
    public init(urlSessionDelegate: URLSessionDelegate? = nil, urlSessionTaskDelegate: URLSessionTaskDelegate? = nil) {
        urlSession = URLSession(configuration: URLSessionConfiguration.default, delegate: urlSessionDelegate, delegateQueue: nil)
        self.urlSessionTaskDelegate = urlSessionTaskDelegate
        reachability = Reachability()
        reachability.delegate = self
    }
    
    @available(iOS 15.0, *)
    public func execute<T: Decodable>(_ route: Endpoint) async throws -> T {
        guard var request = try? buildRequest(from: route) else { throw NetworkError.encodingFailed }
        delegate?.intercept(&request)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        NetworkLogger.log(request: request)
        
        let (data, response) = try await urlSession.data(for: request, delegate: urlSessionTaskDelegate)
        guard let httpResponse = response as? HTTPURLResponse else { throw NetworkError.statusCode }
        switch httpResponse.statusCode {
        case 200...299:
            return try decoder.decode(T.self, from: data)
        default:
            throw NetworkError.statusCode
        }
    }
    
    private func buildRequest(from route: Endpoint) throws -> URLRequest {
        
        var request = URLRequest(url: route.baseURL.appendingPathComponent(route.path),
                                 cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
                                 timeoutInterval: 10.0)
        
        request.httpMethod = route.httpMethod.rawValue
        do {
            switch route.task {
            case .request:
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                addAdditionalHeaders(route.headers, request: &request)
            case .requestParameters(let bodyParameters,
                                    let bodyEncoding,
                                    let urlParameters):
                
                addAdditionalHeaders(route.headers, request: &request)
                try configureParameters(bodyParameters: bodyParameters,
                                        bodyEncoding: bodyEncoding,
                                        urlParameters: urlParameters,
                                        request: &request)
            }
            return request
        } catch {
            throw error
        }
    }
    
    private func configureParameters(bodyParameters: Parameters?,
                                     bodyEncoding: ParameterEncoding,
                                     urlParameters: Parameters?,
                                     request: inout URLRequest) throws {
        do {
            try bodyEncoding.encode(urlRequest: &request, bodyParameters: bodyParameters, urlParameters: urlParameters)
        } catch {
            throw error
        }
    }
    
    private func addAdditionalHeaders(_ additionalHeaders: HTTPHeaders?, request: inout URLRequest) {
        guard let headers = additionalHeaders else { return }
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
    }
}

extension NetworkRouter: ReachabilityDelegate {
    func reachabiltyStatusChange(reachabilityStatus status: ReachabiltyStatus) {
        let notificationCenter = NotificationCenter.default
        
        switch status {
        case .notReachable:
            notificationCenter.post(name: .reachabilityNotReachable, object: nil)
        case .unknown:
            notificationCenter.post(name: .reachabilityUnknown, object: nil)
        case .reachableEithernetOrWifi:
            notificationCenter.post(name: .reachabilityReachableEithernetOrWifi, object: nil)
        case .reachableWWAN:
            notificationCenter.post(name: .reachabilityReachableWWAN, object: nil)
        }
    }
}

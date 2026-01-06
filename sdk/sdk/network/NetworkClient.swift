import Foundation

public protocol NetworkClientProtocol {
    var baseURL: String { get }
    func sendRequest(_ request: URLRequest, completion: @escaping (Result<Data, Error>) -> Void)
    func makeURL(path: String) -> URL?
}

public class DefaultNetworkClient: NSObject, NetworkClientProtocol, URLSessionDelegate {
    public let baseURL: String
    private let session: URLSession
    
    public init(baseURL: String, configuration: URLSessionConfiguration = .default) {
        self.baseURL = baseURL
        self.session = URLSession(configuration: configuration, delegate: nil, delegateQueue: nil)
        super.init()
    }
    
    public func makeURL(path: String) -> URL? {
        return URL(string: baseURL + path)
    }
    
    public func sendRequest(_ request: URLRequest, completion: @escaping (Result<Data, Error>) -> Void) {
        var mutableRequest = request
        let userAgent = "GoPay iOS SDK \(GopaySDK.version)"
        mutableRequest.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        
        let task = session.dataTask(with: mutableRequest) { data, response, error in
            if let error = error {
                completion(.failure(error))
            } else if let data = data {
                completion(.success(data))
            } else {
                completion(.failure(GopaySDKErrors.unknownError()))
            }
        }
        task.resume()
    }
    
    // URLSessionDelegate methods for SSL pinning or custom certificate handling can be added here.
} 

public struct ToolManagerErrorPayload: Codable {
    public let code: String
    public let message: String
    public let details: [String: String]?
    
    public init(code: String, message: String, details: [String : String]?) {
        self.code = code
        self.message = message
        self.details = details
    }
}

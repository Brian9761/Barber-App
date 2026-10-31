import Foundation
import IzzyClipzKit

/// Any error as a plain sentence for the owner, with a way forward.
enum ErrorText {
    static func message(for error: Error) -> String {
        if let apiError = error as? APIError { return apiError.userMessage }
        if let described = (error as? LocalizedError)?.errorDescription { return described }
        return "Something went wrong. Try again in a moment."
    }
}

//
//  Auth0Config.swift
//  swamphacks
//
//  Created by Christian Caraballo on 10/17/26.
//


import Foundation

enum Auth0Config {
    private static var plist: [String: Any] {
        guard let url = Bundle.main.url(
            forResource: "Auth0",
            withExtension: "plist"
        ) else {
            print("DEBUG: Auth0.plist was not found in the app bundle.")
            return [:]
        }

        print("DEBUG: Found Auth0.plist at \(url.path)")

        do {
            let data = try Data(contentsOf: url)
            let result = try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            )

            guard let dictionary = result as? [String: Any] else {
                print("DEBUG: Auth0.plist is not a dictionary.")
                return [:]
            }

            print("DEBUG: Keys found: \(dictionary.keys.sorted())")
            return dictionary
        } catch {
            print("DEBUG: Could not read Auth0.plist: \(error)")
            return [:]
        }
    }

    static var clientId: String {
        guard let value = plist["ClientId"] as? String,
              !value.isEmpty else {
            fatalError("Auth0 ClientId is missing or is not a nonempty string.")
        }
        return value
    }

    static var domain: String {
        guard let value = plist["Domain"] as? String,
              !value.isEmpty else {
            fatalError("Auth0 Domain is missing or is not a nonempty string.")
        }
        return value
    }
}

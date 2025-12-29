import Foundation

/// Default configuration templates for SwiftProjectKit
public enum DefaultConfigs {}

// MARK: - Git Ignore

public extension DefaultConfigs {
    static let gitignore = """
    # Swift Package Manager
    .build/
    .swiftpm/
    Package.resolved

    # Xcode
    *.xcodeproj/
    *.xcworkspace/
    xcuserdata/
    *.playground/
    DerivedData/

    # macOS
    .DS_Store
    *.dSYM.zip
    *.dSYM

    # Generated
    *.generated.swift

    # IDE
    .idea/
    .vscode/

    # Testing
    *.xcresult

    # Secrets (never commit these)
    .env
    .env.*
    *.pem
    *.p12
    credentials.json
    secrets.json
    """
}

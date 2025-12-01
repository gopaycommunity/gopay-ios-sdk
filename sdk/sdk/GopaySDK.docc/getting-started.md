# Getting Started with GopaySDK

Learn how to initialize and configure the GopaySDK in your iOS app, including how to select the environment.

## Step 1: Import the SDK

```swift
import GopaySDK
```

## Step 2: Choose the Environment

Select the appropriate environment for your use case:

```swift
let environment: GopayEnvironment = .sandbox // or .development(baseURL: "https://your-dev-url.com"), .production
```

## Step 3: Configure the SDK

Create a configuration object. You can also enable debug logging and provide an error callback if needed:

```swift
let config = GopaySDKConfig(
    environment: environment,
    enableDebugLogging: true, // Optional
    errorCallback: { error in // Optional
        print("GopaySDK Error: \(error)")
    },
)
```

## Step 4: Initialize the SDK

Initialize the SDK with your configuration:

```swift
GopaySDK.shared.initialize(with: config)
```

## Full Example

```swift
import GopaySDK

let config = GopaySDKConfig(
    environment: .sandbox, // or .development(baseURL: "https://your-dev-url.com"), .production
    enableDebugLogging: true,
    errorCallback: { error in
        print("GopaySDK Error: \(error)")
    }
)

GopaySDK.shared.initialize(with: config)
```

---

For more details, see the API reference for [`GopaySDK`](<doc:GopaySDK>), [`GopaySDKConfig`](<doc:GopaySDKConfig>), and [`GopayEnvironment`](<doc:GopayEnvironment>). 
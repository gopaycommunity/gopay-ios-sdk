Pod::Spec.new do |spec|
  spec.name         = "GopaySDK"
  spec.version      = "1.3.0"
  spec.summary      = "Gopay SDK for iOS applications"
  spec.description  = <<-DESC
                   A payment SDK that allows merchants to integrate payment services into their iOS applications.
                   DESC
  spec.homepage     = "https://github.com/gopaycommunity/gopay-ios-sdk"
  spec.readme       = "https://github.com/gopaycommunity/gopay-ios-sdk/blob/master/README.md"
  spec.license      = { :type => "MIT", :file => "LICENSE" }
  spec.author       = { "Gopay" => "support@gopay.com" }
  spec.platform     = :ios, "13.0"
  spec.source       = { :git => "https://github.com/gopaycommunity/gopay-ios-sdk.git", :tag => "#{spec.version}" }
  spec.source_files = "sdk/sdk/**/*.{swift,h,m}"
  spec.swift_version = "5.0"
  spec.static_framework = true
  spec.requires_arc = true
end 
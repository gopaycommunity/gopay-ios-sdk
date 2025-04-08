Pod::Spec.new do |spec|
  spec.name         = "GopaySDK"
  spec.version      = "0.1.0"
  spec.summary      = "A simple payment SDK for iOS applications"
  spec.description  = <<-DESC
                   A payment SDK that allows merchants to integrate payment services into their iOS applications.
                   This is a demonstration version with basic functionality.
                   DESC
  spec.homepage     = "https://github.com/yourusername/GopaySDK"
  spec.license      = { :type => "MIT", :file => "LICENSE" }
  spec.author       = { "Your Name" => "your.email@example.com" }
  spec.platform     = :ios, "13.0"
  spec.source       = { :git => "https://github.com/yourusername/GopaySDK.git", :tag => "#{spec.version}" }
  spec.source_files = "sdk/sdk/**/*.{swift,h,m}"
  spec.swift_version = "5.0"
  spec.static_framework = true
  spec.requires_arc = true
end 
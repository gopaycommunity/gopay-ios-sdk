module.exports = {
    branches: ["master"],
    plugins: [
        "@semantic-release/commit-analyzer",
        ["@semantic-release/npm", { npmPublish: false }],
        [
            "@semantic-release/release-notes-generator",
            {
                // Keep internal Bitbucket URLs out of the release notes and CHANGELOG.md.
                writerOpts: {
                    finalizeContext: (context) => ({ ...context, linkReferences: false, linkCompare: false }),
                },
            },
        ],
        "@semantic-release/changelog",
        ["@semantic-release/exec", { prepareCmd: "./scripts/set-version.sh ${nextRelease.version}" }],
        [
            "@semantic-release/git",
            {
                assets: ["CHANGELOG.md", "package.json", "GopaySDK.podspec", "sdk/sdk/GopaySDK.swift"],
            },
        ],
    ],
    tagFormat: "${version}",
};

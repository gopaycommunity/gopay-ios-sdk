// The transform of conventional-changelog-angular 8.3.1 (src/writer.js), except that "#123" and "@name"
// in a subject stay plain text instead of becoming links to the repository host.
const transform = (commit) => {
    let discard = true;
    const notes = commit.notes.map((note) => {
        discard = false;
        return { ...note, title: "BREAKING CHANGES" };
    });
    let { type } = commit;

    if (commit.type === "feat") {
        type = "Features";
    } else if (commit.type === "fix") {
        type = "Bug Fixes";
    } else if (commit.type === "perf") {
        type = "Performance Improvements";
    } else if (commit.type === "revert" || commit.revert) {
        type = "Reverts";
    } else if (discard) {
        return undefined;
    } else if (commit.type === "docs") {
        type = "Documentation";
    } else if (commit.type === "style") {
        type = "Styles";
    } else if (commit.type === "refactor") {
        type = "Code Refactoring";
    } else if (commit.type === "test") {
        type = "Tests";
    } else if (commit.type === "build") {
        type = "Build System";
    } else if (commit.type === "ci") {
        type = "Continuous Integration";
    }

    const scope = commit.scope === "*" ? "" : commit.scope;
    const shortHash = typeof commit.hash === "string" ? commit.hash.substring(0, 7) : commit.shortHash;
    const { subject } = commit;
    // Like the preset, don't repeat an issue the subject already names as a reference.
    const issues = typeof subject === "string" ? [...subject.matchAll(/#([0-9]+)/g)].map((match) => match[1]) : [];
    const references = commit.references.filter((reference) => !issues.includes(reference.issue));

    return { notes, type, scope, shortHash, subject, references };
};

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
                    transform,
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

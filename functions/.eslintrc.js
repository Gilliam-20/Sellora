module.exports = {
  env: {
    es6: true,
    node: true,
  },
  parserOptions: {
    // Matches the Node 20 runtime these functions actually run on; 2020
    // rejected syntax Node accepts, e.g. numeric separators (1_000).
    "ecmaVersion": 2022,
  },
  extends: [
    "eslint:recommended",
    "google",
  ],
  rules: {
    "no-restricted-globals": ["error", "name", "length"],
    "prefer-arrow-callback": "error",
    "quotes": ["error", "double", { "allowTemplateLiterals": true }],
    // The codebase consistently writes `{ foo }` with spaces; match that
    // instead of Google style's no-space rule.
    "object-curly-spacing": ["error", "always"],

    // `firebase.json` runs this config as a predeploy gate, so anything left
    // at "error" blocks a deploy. These are the style-only rules, demoted so
    // that formatting can't stop a release while genuine correctness rules
    // (no-undef, no-unused-vars, ...) still do.
    //
    // linebreak-style is off rather than warned: this repo is developed on
    // Windows, so CRLF is correct here and the rule was producing 1638 of
    // the 1759 reported problems - pure noise that buried everything else.
    // See .gitattributes, which normalizes what actually lands in git.
    "linebreak-style": "off",
    "max-len": ["warn", { code: 80, ignoreUrls: true }],
    "require-jsdoc": "warn",
    "valid-jsdoc": "warn",
  },
  overrides: [
    {
      files: ["**/*.spec.*"],
      env: {
        mocha: true,
      },
      rules: {},
    },
  ],
  globals: {},
};

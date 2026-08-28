# Releasing Rails Ninja

Releases are published to RubyGems.org from GitHub Actions using trusted
publishing. No long-lived RubyGems API key is stored in GitHub.

Before the first release, create a pending trusted publisher from your
RubyGems.org profile with:

- Gem name: `rails_ninja`
- Repository owner: `fintual-oss`
- Repository name: `rails-ninja`
- Workflow filename: `release.yml`
- GitHub environment: `release`

Also create a `release` environment in the GitHub repository. Environment
protection rules can be used to require approval before publication.

Build and inspect the package locally:

```sh
bundle exec rake build
gem specification pkg/rails_ninja-0.1.0.gem files
```

To publish, update `RailsNinja::VERSION`, merge the change into `main`, then
push a matching tag:

```sh
git tag v0.1.0
git push origin v0.1.0
```

The release workflow verifies the tag, runs the tests, and publishes the gem.
After the first successful release, the pending publisher becomes the trusted
publisher for subsequent releases.

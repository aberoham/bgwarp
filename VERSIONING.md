# bgwarp Versioning Strategy

## Version Format

bgwarp uses a date-based versioning scheme similar to Cloudflare WARP:

```
YYYY.M.BUILD.PATCH
```

### Components

- **YYYY**: Full year (e.g., 2025)
- **M**: Month without zero-padding (e.g., 6 for June, 12 for December)
- **BUILD**: Auto-incrementing build number within the month
- **PATCH**: Patch number for hotfixes (starts at 0)

### Examples

- `2025.6.1.0` - First build in June 2025
- `2025.6.2.0` - Second build in June 2025
- `2025.6.2.1` - Hotfix for the second build
- `2025.7.1.0` - First build in July 2025 (build number resets)

## Why Date-Based Versioning?

1. **Tool Context**: Users can immediately see when the tool was built, which is critical for security-sensitive emergency tools
2. **Clear Timeline**: Easy to determine if a version is current or outdated
3. **Automatic Progression**: No debates about whether a change is major/minor/patch
4. **Upstream Alignment**: Similar to Cloudflare WARP's versioning pattern

## Version Management

### Local Development

Use the `version.sh` script:

```bash
# Show current version
./version.sh current

# Bump build number (e.g., 2025.6.1.0 → 2025.6.2.0)
./version.sh build
./version.sh build --tag  # Also creates git tag

# Bump patch number (e.g., 2025.6.2.0 → 2025.6.2.1)
./version.sh patch
./version.sh patch --tag  # Also creates git tag

# Set custom version
./version.sh custom 2025.6.100.0
./version.sh custom 2025.6.100.0 --tag  # Also creates git tag
```

### GitHub Actions

The release workflow triggers on:

1. **Tag Push**: Push a version tag to trigger a release
   ```bash
   git tag v2025.6.1.0
   git push origin v2025.6.1.0
   ```

2. **Manual Workflow**: Use GitHub Actions UI to trigger a release
   - Choose `build` to increment build number
   - Choose `patch` to increment patch number
   - Choose `custom` to set a specific version

The workflow automatically:
- Builds on both Intel (macos-13) and Apple Silicon (macos-14) runners
- Creates a universal binary using `lipo`
- Generates architecture-specific packages
- Uploads all variants to the GitHub Release

## Release Process

### Automated Release (Recommended)

1. Make your changes and commit
2. Use version script to create a tag:
   ```bash
   ./version.sh build --tag
   git push origin v2025.6.1.0
   ```
3. GitHub Actions will automatically:
   - Build the binary
   - Create the installer package
   - Generate release notes from commits
   - Upload artifacts with checksums
   - Create a GitHub Release

### Manual Release

1. Update version in `build-pkg.sh`
2. Build locally:
   ```bash
   ./build.sh
   ./build-pkg.sh
   ```
3. Create release on GitHub manually

## Version in Code

The version is embedded in the binary at compile time:
- Defined via `-DBGWARP_VERSION` compiler flag
- Accessible via `bgwarp --version` command
- Shows both version and architecture (x86_64 or arm64)

Version sources:
- `build-pkg.sh` - Default version for manual builds
- Git tags - Source of truth for releases
- GitHub Actions - Automatically determines version from tags or inputs


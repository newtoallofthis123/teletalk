project := "Teletalk.xcodeproj"
scheme := "Teletalk"
build_dir := "build"

# Debug build
build:
    xcodebuild -project {{project}} -scheme {{scheme}} -configuration Debug build

# Release build with ad-hoc signing
build-release:
    xcodebuild \
        -project {{project}} \
        -scheme {{scheme}} \
        -configuration Release \
        -derivedDataPath {{build_dir}} \
        CODE_SIGN_IDENTITY="-" \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGNING_ALLOWED=NO \
        build

# Build release and install to /Applications
install: build-release
    cp -R {{build_dir}}/Build/Products/Release/Teletalk.app /Applications/
    @echo "Installed to /Applications/Teletalk.app"

# Clean build artifacts
clean:
    xcodebuild -project {{project}} -scheme {{scheme}} clean
    rm -rf {{build_dir}}

# Format Swift code
format:
    swiftformat .

# Lint Swift code
lint:
    swiftlint

# Check formatting (CI-friendly, no modifications)
format-check:
    swiftformat --lint .

# Check linting (CI-friendly, non-modifying)
lint-check:
    swiftlint

# Open project in Xcode
open:
    open {{project}}

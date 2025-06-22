// Example: How to embed version information in bgwarp binary
// This would be added to bgwarp.m or included as a separate file

// Version can be set at compile time with -D flag:
// clang -DBGWARP_VERSION=\"2025.6.1.0\" ...

#ifndef BGWARP_VERSION
#define BGWARP_VERSION "dev"
#endif

// Add to the beginning of main() or as a separate function:
static void printVersion(void) {
    printf("bgwarp version %s\n", BGWARP_VERSION);
    printf("Emergency WARP disconnect tool for macOS\n");
    printf("Built with: %s\n", __clang_version__);
}

// In main(), add handling for --version flag:
/*
if (argc > 1 && strcmp(argv[1], "--version") == 0) {
    printVersion();
    return 0;
}
*/

// Modified build command in build.sh:
/*
VERSION=$(./version.sh current)
clang -framework Foundation \
      -framework LocalAuthentication \
      -framework Security \
      -framework SystemConfiguration \
      -DBGWARP_VERSION=\"${VERSION}\" \
      -fobjc-arc \
      -O2 \
      ...
*/
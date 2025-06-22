#!/bin/bash
#
# Version management script for bgwarp
# Handles version bumping and tagging following YYYY.M.BUILD.PATCH pattern
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get current date components
YEAR=$(date +%Y)
MONTH=$(date +%-m)  # No zero padding

# Function to get current version from git tags
get_current_version() {
    local last_tag=$(git describe --tags --abbrev=0 2>/dev/null || echo "v${YEAR}.${MONTH}.0.0")
    echo "${last_tag#v}"  # Remove 'v' prefix
}

# Function to parse version components
parse_version() {
    local version=$1
    IFS='.' read -r year month build patch <<< "$version"
    echo "$year $month $build $patch"
}

# Function to bump version
bump_version() {
    local bump_type=$1
    local current_version=$(get_current_version)
    local components=($(parse_version "$current_version"))
    
    local last_year=${components[0]}
    local last_month=${components[1]}
    local last_build=${components[2]}
    local last_patch=${components[3]}
    
    case "$bump_type" in
        build)
            if [[ "$last_year.$last_month" == "$YEAR.$MONTH" ]]; then
                echo "${YEAR}.${MONTH}.$((last_build + 1)).0"
            else
                echo "${YEAR}.${MONTH}.1.0"
            fi
            ;;
        patch)
            if [[ "$last_year.$last_month" == "$YEAR.$MONTH" ]]; then
                echo "${YEAR}.${MONTH}.${last_build}.$((last_patch + 1))"
            else
                echo "${YEAR}.${MONTH}.1.0"
            fi
            ;;
        *)
            echo "Invalid bump type: $bump_type" >&2
            return 1
            ;;
    esac
}

# Function to update version in files
update_version_in_files() {
    local new_version=$1
    
    # Update build-pkg.sh
    if [ -f "build-pkg.sh" ]; then
        sed -i '' "s/VERSION=\"[^\"]*\"/VERSION=\"${new_version}\"/" build-pkg.sh
        echo -e "${GREEN}✓${NC} Updated version in build-pkg.sh"
    fi
    
    # Could add more files here in the future
}

# Function to create git tag
create_tag() {
    local version=$1
    local tag="v${version}"
    
    echo -e "${BLUE}Creating tag: ${tag}${NC}"
    
    # Create annotated tag
    git tag -a "$tag" -m "Release ${version}

$(git log --oneline --no-merges $(git describe --tags --abbrev=0 2>/dev/null || echo "")..HEAD | sed 's/^/- /')"
    
    echo -e "${GREEN}✓${NC} Tag created: ${tag}"
    
    # Ask user if they want to push the tag
    echo ""
    echo -ne "${YELLOW}Push tag to origin? [Y/n] ${NC}"
    read -r response
    response=${response:-Y}  # Default to Y if empty
    
    if [[ "$response" =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}Pushing tag to origin...${NC}"
        if git push origin "$tag"; then
            echo -e "${GREEN}✓${NC} Tag pushed successfully!"
            echo ""
            echo -e "${GREEN}Release workflow will start automatically on GitHub${NC}"
        else
            echo -e "${RED}✗${NC} Failed to push tag"
            echo -e "${YELLOW}You can push manually with: git push origin ${tag}${NC}"
        fi
    else
        echo -e "${YELLOW}Tag not pushed. To push later, run:${NC}"
        echo "  git push origin ${tag}"
    fi
}

# Main script logic
main() {
    echo -e "${BLUE}bgwarp Version Management${NC}"
    echo ""
    
    # Check if we're in a git repository
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo -e "${RED}Error: Not in a git repository${NC}"
        exit 1
    fi
    
    # Get current version
    current_version=$(get_current_version)
    echo -e "Current version: ${YELLOW}${current_version}${NC}"
    echo ""
    
    # Handle command line arguments
    case "${1:-}" in
        current)
            echo "$current_version"
            ;;
        build)
            new_version=$(bump_version build)
            echo -e "New version: ${GREEN}${new_version}${NC}"
            
            if [[ "${2:-}" == "--tag" ]]; then
                update_version_in_files "$new_version"
                create_tag "$new_version"
            else
                echo ""
                echo "To create a tag, run: $0 build --tag"
            fi
            ;;
        patch)
            new_version=$(bump_version patch)
            echo -e "New version: ${GREEN}${new_version}${NC}"
            
            if [[ "${2:-}" == "--tag" ]]; then
                update_version_in_files "$new_version"
                create_tag "$new_version"
            else
                echo ""
                echo "To create a tag, run: $0 patch --tag"
            fi
            ;;
        custom)
            if [ -z "${2:-}" ]; then
                echo -e "${RED}Error: Custom version required${NC}"
                echo "Usage: $0 custom YYYY.M.BUILD.PATCH"
                exit 1
            fi
            
            new_version=$2
            echo -e "New version: ${GREEN}${new_version}${NC}"
            
            if [[ "${3:-}" == "--tag" ]]; then
                update_version_in_files "$new_version"
                create_tag "$new_version"
            else
                echo ""
                echo "To create a tag, run: $0 custom $new_version --tag"
            fi
            ;;
        *)
            echo "Usage: $0 {current|build|patch|custom} [--tag]"
            echo ""
            echo "Commands:"
            echo "  current          Show current version"
            echo "  build [--tag]    Bump build number (YYYY.M.BUILD.0)"
            echo "  patch [--tag]    Bump patch number (YYYY.M.BUILD.PATCH)"
            echo "  custom VERSION [--tag]  Set custom version"
            echo ""
            echo "Options:"
            echo "  --tag    Create git tag and update version in files"
            echo ""
            echo "Version format: YYYY.M.BUILD.PATCH"
            echo "Example: 2025.6.100.0"
            ;;
    esac
}

main "$@"
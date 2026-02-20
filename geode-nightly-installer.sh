#!/usr/bin/env bash

TEMP_DIR=$(mktemp -d)

# Colors
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

while getopts v OPTS; do
    case ${OPTS} in
        v) VERBOSE=1 ;;
    esac
done

verbose_log() {
    if [ ! -z "$1" ] && [ ! -z "$VERBOSE" ]; then
        echo -e "[VERBOSE]: $1"
    fi
}

check_dependencies() {
    if ! [ -x "$(command -v unzip)" ]; then
        echo -e "${RED}Error${NC}: unzip is not installed." >&2
        exit 1
    fi
    if ! [ -x "$(command -v curl)" ]; then
        echo -e "${RED}Error${NC}: curl is not installed." >&2
        exit 1
    fi
    if ! [ -x "$(command -v jq)" ]; then
        if [ -x "$(command -v python)" ]; then py_cmd=python;
        elif [ -x "$(command -v python3)" ]; then py_cmd=python3;
        else echo -e "${RED}Error${NC}: neither jq nor python are installed" >&2; exit 1; fi
    fi
}

is_valid_gd_path() {
    if [ -z "$1" ] || [ ! -d "$1" ] || [ ! -f "$1/libcocos2d.dll" ]; then
        LAST_VALID_GD_PATH_ERR="Path does not contain Geometry Dash or is invalid."
        return 1
    fi
    return 0
}

find_gd_installation() {
    verbose_log "Searching for Geometry Dash..."
    local DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
    for GD_IDX in "$DATA_HOME/Steam" "$HOME/Steam" "$HOME/.var/app/com.valvesoftware.Steam/data/Steam" "$HOME/snap/steam/common/.steam/steam"; do
        local PATH_TEST="$GD_IDX/steamapps/common/Geometry Dash"
        verbose_log "- Testing path: $PATH_TEST"
        if is_valid_gd_path "$PATH_TEST"; then
            GD_PATH="$PATH_TEST"
            return 0
        fi
    done
    return 1
}

confirm() {
    while read -n1 -r -p "$(echo -e $1) [Y/n]: " < /dev/tty; do
        case $REPLY in
            y|Y|"") return 0 ;;
            n|N) echo ""; return 1 ;;
        esac
    done
}

ask_gd_path() {
    while read -p "Enter the path where Geometry Dash is located: " POTENTIAL_PATH < /dev/tty; do
        POTENTIAL_PATH=${POTENTIAL_PATH%"/GeometryDash.exe"}
        if is_valid_gd_path "$POTENTIAL_PATH"; then
            if confirm "Do you want to install to ${YELLOW}$POTENTIAL_PATH${NC}?"; then
                GD_PATH="$POTENTIAL_PATH"
                break
            fi
        else
            echo -e "${RED}$LAST_VALID_GD_PATH_ERR${NC}"
        fi
    done
}

install() {
    if [ -z "$GD_PATH" ] || [ -z "$DOWNLOAD_URL" ]; then
        echo -e "${RED}Error:${NC} Missing installation data." >&2
        exit 1
    fi

    echo -e "Downloading from: ${BLUE}$DOWNLOAD_URL${NC}"
    # Using -f to ensure curl fails if the URL is a 404
    if ! curl -L -f -o "$TEMP_DIR/geode.zip" "$DOWNLOAD_URL"; then
        echo -e "${RED}Error:${NC} Failed to download the file. The URL might be invalid." >&2
        exit 1
    fi

    echo "Unzipping..."
    if ! unzip -qq "$TEMP_DIR/geode.zip" -d "$TEMP_DIR/geode"; then
        echo -e "${RED}Error:${NC} Failed to unzip Geode. The download may be corrupted." >&2
        exit 1
    fi

    echo "Installing..."
    mv "$TEMP_DIR"/geode/* "$GD_PATH"
}

check_dependencies
echo "--- Fetching Latest Development Release ---"

# Get release JSON from GitHub API
GITHUB_JSON="$(curl -s 'https://api.github.com/repos/geode-sdk/geode/releases')"

# Extract TAG and DOWNLOAD_URL for the windows asset
if [ -x "$(command -v jq)" ]; then
    TAG=$(echo "$GITHUB_JSON" | jq -r '[.[] | select(.prerelease == true)][0].tag_name')
    DOWNLOAD_URL=$(echo "$GITHUB_JSON" | jq -r '[.[] | select(.prerelease == true)][0].assets[] | select(.name | contains("win.zip")) | .browser_download_url')
else
    # Fallback to Python if jq is missing
    TAG=$(echo "$GITHUB_JSON" | $py_cmd -c 'import json,sys; d=json.load(sys.stdin); dev=[r for r in d if r["prerelease"]][0]; print(dev["tag_name"])')
    DOWNLOAD_URL=$(echo "$GITHUB_JSON" | $py_cmd -c 'import json,sys; d=json.load(sys.stdin); dev=[r for r in d if r["prerelease"]][0]; print([a["browser_download_url"] for a in dev["assets"] if "win.zip" in a["name"]][0])')
fi

if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" == "null" ]; then
    echo -e "${RED}Error:${NC} Could not find a Windows asset in the latest development release."
    exit 1
fi

echo -e "Detected version: ${YELLOW}$TAG${NC}"

if ! find_gd_installation; then
    echo -e "Could not find Geometry Dash in common paths."
    ask_gd_path
else
    echo -e "Geometry Dash found at: ${YELLOW}$GD_PATH${NC}"
    if ! confirm "Proceed with development installation?"; then
        ask_gd_path
    fi
fi

install

echo -e "\n${BLUE}Geode Development Release installed successfully!${NC}"
echo -e "Steam Launch Options: ${YELLOW}WINEDLLOVERRIDES=\"xinput1_4=n,b\" %command%${NC}"

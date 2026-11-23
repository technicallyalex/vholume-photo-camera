#!/bin/sh
set -eu
destination="${1:-$(dirname -- "$0")/../../platforms/linux/Proton/Native}"
mkdir -p "$destination"
destination="$(cd "$destination" && pwd)"
cd "$(dirname -- "$0")"
mkdir -p "$destination"
dotnet publish NativeDng.csproj -c Release -r linux-x64 --self-contained true -o "$destination"
sdk_root="$(dirname "$(readlink -f "$(command -v dotnet)")")"
cp "$sdk_root/LICENSE.txt" "$destination/DOTNET-LICENSE.txt"
cp "$sdk_root/ThirdPartyNotices.txt" "$destination/DOTNET-THIRD-PARTY-NOTICES.txt"
chmod 755 "$destination/PhotoCameraDng"
"$destination/PhotoCameraDng" --version

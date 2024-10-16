#!/bin/bash

# This bash script is used to update the vscode version requirement in the package.json file of a VSIX extension.
# It starts by storing the current working directory in a variable _PWD.
# Then it loops over all VSIX files in the ./bin directory that match the pattern GitHub.copilot*.vsix.
# For each VSIX file, it generates a unique UUID and creates a temporary directory with this UUID.
# It then unzips the VSIX file into this temporary directory and removes the original VSIX file.
# It uses sed to replace the vscode version requirement in the package.json file of the extension with a new requirement (>=1.80.0).
# The updated extension files are then zipped back into a VSIX file with the original name and placed back in the ./bin directory.
# The script then changes back to the original working directory and removes the temporary directory.
# This process is repeated for all matching VSIX files in the ./bin directory.
_PWD=$(pwd)
for EXTENSION in $(ls ./bin/GitHub.copilot*.vsix); do
    UUID=$(uuidgen)
    mkdir -p ./tmp/$UUID
    cd ./tmp/$UUID
    unzip ../../bin/$(basename $EXTENSION)
    rm ../../bin/$(basename $EXTENSION)
    sed -ibak 's/\"vscode\"[[:space:]]*:[[:space:]]*\"\^1\.[0-9]*\.[0-9]*\(-[0-9A-Za-z-]*\)*\"/\"vscode\":\">=1\.80\.0\"/g' extension/package.json
    rm -f extension/package.jsonbak*
    zip -r ../../bin/$(basename $EXTENSION) *
    cd $_PWD
    rm -rf ./tmp/$UUID
done


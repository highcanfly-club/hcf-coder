#!/bin/bash
_PWD=$(pwd)
for EXTENSION in $(ls ./bin/GitHub.copilot*.vsix); do
    UUID=$(uuidgen)
    mkdir -p ./tmp/$UUID
    cd ./tmp/$UUID
    unzip ../../bin/$(basename $EXTENSION)
    rm ../../bin/$(basename $EXTENSION)
    sed -ibak 's/\"vscode\":\"\^1\.[0-9]*\.[0-9]*\"/\"vscode\":\">=1\.80\.0\"/g' extension/package.json
    sed -ibak2 's/\"vscode\": \"\^1\.[0-9]*\.[0-9]*\"/\"vscode\": \">=1\.80\.0\"/g' extension/package.json
    rm -f extension/package.jsonbak*
    zip -r ../../bin/$(basename $EXTENSION) *
    cd $_PWD
    rm -rf ./tmp/$UUID
done


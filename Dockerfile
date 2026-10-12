FROM golang:trixie AS entangle-builder
RUN git clone --depth 1 https://github.com/sctg-development/entangle.git && \
    cd entangle && \
    go build -o /app/entangle

FROM astral/uv:trixie AS mistral-builder
ENV PATH="/root/.cargo/bin:${PATH}"
RUN apt-get update && apt-get install -y --no-install-recommends curl && \
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y && \
    . "$HOME/.cargo/env" && \
    git clone --depth 1 https://github.com/sctg-development/mistral-vibe.git && \
    cd mistral-vibe && \
    uv build --wheel
FROM codercom/code-server:4.141.0-noble AS coder
USER 0

RUN /usr/lib/code-server/bin/code-server -v | sed -ne 's/.*\([0-9]\.[0-9]*\.[0-9A-Za-z-]*\)$/\1/p' > /usr/lib/code-server/engine_version.txt

FROM ubuntu:noble AS downloader
ARG VSIXHARVESTER_VERSION="0.2.12"
RUN apt-get update && apt-get install -y curl uuid-runtime zip
COPY --from=sctg/clinepool-download /usr/local/bin/clinepool-download /usr/bin/clinepool-download
COPY extensions.json /extensions.json
RUN  if [ $(dpkg --print-architecture) = "amd64" ] ; then \
            curl -fsSL https://github.com/sctg-development/vsixHarvester/releases/download/${VSIXHARVESTER_VERSION}/vsixHarvester_ubuntu-24.04_amd64_${VSIXHARVESTER_VERSION} -o vsixHarvester ; \
      else \
            curl -fsSL https://github.com/sctg-development/vsixHarvester/releases/download/${VSIXHARVESTER_VERSION}/vsixHarvester_ubuntu-24.04_arm64_${VSIXHARVESTER_VERSION} -o vsixHarvester ; \
      fi
COPY --from=coder /usr/lib/code-server/engine_version.txt /engine_version.txt
RUN chmod +x vsixHarvester \
      && ./vsixHarvester --verbose -i /extensions.json -e $(cat /engine_version.txt)
RUN /usr/bin/clinepool-download -v --vsix --out-file /extensions/clinepool-extensions.vsix
COPY --from=sctg/kilocode-download /usr/local/bin/kilocode-download /usr/bin/kilocode-download
RUN /usr/bin/kilocode-download -v --vsix --out-file /extensions/kilocode-extensions.vsix
RUN /usr/bin/kilocode-download -v --cli --out-file /usr/bin/kilo
COPY --from=entangle-builder /app/entangle /usr/bin/entangle
RUN mkdir -p extensions/amd64 \
      && mkdir -p extensions/arm64 \
      && find ./extensions -name "*@linux-x64.vsix" | xargs -I '{}' mv '{}' ./extensions/amd64/ \
      && find ./extensions -name "*@linux-arm64.vsix" | xargs -I '{}' mv '{}' ./extensions/arm64/
# universalize Copilot
COPY scripts/change-vsix-requirements.sh /change-vsix-requirements.sh
RUN chmod +x /change-vsix-requirements.sh \
      && /change-vsix-requirements.sh /extensions/MS-CEINTL.vscode-language-pack-fr*.vsix \
      && /change-vsix-requirements.sh /extensions/GitHub.copilot*.vsix \
      && /change-vsix-requirements.sh /extensions/amd64/ms-toolsai.jupyter*.vsix \
      && /change-vsix-requirements.sh /extensions/arm64/ms-toolsai.jupyter*.vsix 

FROM highcanfly/devserver-prebuild:latest
USER 0
ARG NODE_MAJOR="24"
ARG DEBIAN_FRONTEND=noninteractive
ARG TZ=Etc/UTC
ARG GOVERSION="1.27.2"
ENV ENTRYPOINTD=/entrypoint.d
ENV BASEDIR=/home/coder
ENV HOME=$BASEDIR
WORKDIR ${BASEDIR}

COPY --from=coder /usr/lib/code-server /usr/lib/code-server
COPY --from=coder /usr/bin/code-server /usr/bin/code-server
COPY --from=coder /usr/bin/entrypoint.sh /usr/bin/entrypoint.sh
ARG EXTENSIONS_DIR=/opt/code-server/extensions
ENV EXTENSIONS_DIR=${EXTENSIONS_DIR}
# jq is used by start.sh and hcf-layout to merge JSON settings
RUN command -v jq >/dev/null || (apt-get update && apt-get install -y --no-install-recommends jq && rm -rf /var/lib/apt/lists/*)
RUN mkdir -p ${BASEDIR}/workdir \
      && mkdir -p ${BASEDIR}/.local \
      && mkdir -p ${BASEDIR}/.config \
      && mkdir -p ${BASEDIR}/.ssh \
      && mkdir -p ${EXTENSIONS_DIR} \
      && mkdir -p /usr/share/img

# Extensions live in the image (not on the PVC): a new image brings new extension versions.
COPY --from=downloader /extensions /ext
RUN   if [ $(dpkg --print-architecture) = "amd64" ] ; then \
            for file in /ext/amd64/*.vsix; do \
                code-server --extensions-dir ${EXTENSIONS_DIR} --install-extension $file; \
            done; \
      else \
            for file in /ext/arm64/*.vsix; do \
                code-server --extensions-dir ${EXTENSIONS_DIR} --install-extension $file; \
            done; \
      fi
RUN for FILE in /ext/*.vsix; do \
        code-server --extensions-dir ${EXTENSIONS_DIR} --install-extension $FILE; \
    done
# languagepacks.json is rebuilt for the installed fr pack (real path and version) and copied
# into the user-data-dir at each start by start.sh
COPY languagepacks.json /ext/languagepacks.json
RUN FRDIR=$(ls -d ${EXTENSIONS_DIR}/ms-ceintl.vscode-language-pack-fr-* | head -n1) \
      && FRVER=${FRDIR##*-} \
      && jq --arg dir "$FRDIR" --arg ver "$FRVER" \
           '.fr.extensions[0].version = $ver | .fr.translations |= with_entries(.value |= sub("^.*/translations/"; $dir + "/translations/"))' \
           /ext/languagepacks.json > /usr/share/languagepacks.json \
      && rm -rf /ext
# Defaults and layout profiles (see scripts/start.sh and scripts/hcf-layout)
COPY config /usr/share/hcf-coder/config
COPY scripts/hcf-layout /usr/bin/hcf-layout
# start.sh is also baked in the prebuild image: copy it here so a change never needs a prebuild rebuild
COPY scripts/start.sh /usr/bin/start.sh
RUN chmod +x /usr/bin/hcf-layout /usr/bin/start.sh

RUN git config --global user.email "hcf@coder" \
      && git config --global user.name "hcf coder"
# Only toolchains stay in /vscode (symlinked by start.sh). .local and .config are real
# directories on the PVC, so code-server, Kilo, Cline and Claude state survives restarts.
RUN mkdir -p /vscode
RUN mv ${BASEDIR}/.cargo /vscode/
RUN rm -f ${BASEDIR}/.bash_history
RUN rm -f ${BASEDIR}/.bashrc
RUN mv ${BASEDIR}/.profile /vscode/
RUN mv ${BASEDIR}/.gitconfig /vscode/
RUN mv ${BASEDIR}/.rustup /vscode/
RUN mv ${BASEDIR}/go /vscode/
COPY --from=downloader /vsixHarvester /usr/bin/vsixHarvester
COPY --from=downloader /change-vsix-requirements.sh /usr/bin/change-vsix-requirements.sh
COPY --from=downloader /extensions.json /vsixHarvester.json
COPY --from=ismogroup/busybox:1.37.0-php-8.3-apache /busybox-1.37.0/_install/bin/busybox /bin/busybox
COPY --from=astral/uv:trixie /usr/local/bin/uv /usr/local/bin/uv
COPY --from=downloader /usr/bin/kilo /usr/bin/kilo
COPY --from=downloader /usr/bin/entangle /usr/bin/entangle
COPY --from=mistral-builder /mistral-vibe/dist/*.whl /tmp/mistral/
RUN uv pip install --system /tmp/mistral/*.whl && rm -rf /tmp/mistral
COPY --from=ghcr.io/getsops/sops:v3.13.3 /usr/local/bin/sops /usr/local/bin/sops
ARG HELM_VERSION="v4.3.0"
RUN ARCH=$(dpkg --print-architecture) && \
    if [ "$ARCH" = "amd64" ]; then HELM_ARCH="amd64"; else HELM_ARCH="arm64"; fi && \
    curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-${HELM_ARCH}.tar.gz" | tar -xz -C /tmp && \
    mv /tmp/linux-${HELM_ARCH}/helm /usr/bin/helm && \
    chmod +x /usr/bin/helm
RUN  /bin/busybox --install -s
USER 0
EXPOSE 8080
ENTRYPOINT [ "/usr/bin/start.sh" ]

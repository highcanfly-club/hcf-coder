FROM bitnami/oauth2-proxy:7-debian-11 as oauth2

FROM golang:1.21-alpine  as gobuilder
WORKDIR /app
COPY secret2sshkey/* ./
RUN go mod tidy
RUN go build -o secret2sshkey -ldflags="-s -w" main.go
ENTRYPOINT ["tail", "-f", "/dev/null"]

FROM highcanfly/llvm4msvc AS llvm4msvc

FROM highcanfly/llvm4msvc-x86 AS llvm4msvc-x86

FROM codercom/code-server:latest as coder

FROM ubuntu:latest

USER 0
ARG NODE_MAJOR="18"
ARG DEBIAN_FRONTEND=noninteractive
ARG TZ=Etc/UTC
ARG GOVERSION="1.21.1"
ENV ENTRYPOINTD=/entrypoint.d
ENV BASEDIR=/home/coder
RUN apt-get update && apt-get install -y ca-certificates curl gnupg sshfs php-cli build-essential dnsutils iputils-ping lld llvm clang git cmake vim sudo dumb-init\
      && mkdir -p /etc/apt/keyrings \
      && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
      && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_MAJOR.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list \
      && apt-get update \
      && apt-get install nodejs -y
RUN curl -fsSL https://go.dev/dl/go${GOVERSION}.linux-$(dpkg --print-architecture).tar.gz | tar -xvz && mv go /usr/local/ \
      && sed -ibak 's/:\/usr\/bin:/:\/usr\/bin:\/usr\/local\/go\/bin:/g' /etc/profile \
      && curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash - \ 
      && curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/$(dpkg --print-architecture)/kubectl" \
      && chmod +x kubectl && mv kubectl /usr/local/bin/kubectl
COPY --from=coder /usr/lib/code-server /usr/lib/code-server
COPY --from=coder /usr/bin/code-server /usr/bin/code-server
COPY --from=coder /usr/bin/entrypoint.sh /usr/bin/entrypoint.sh
RUN mkdir -p ${BASEDIR}/workdir \
      && mkdir -p {BASEDIR}/.local \
      && mkdir -p {BASEDIR}/.config \  
      && mkdir -p /root/.ssh \
      && mkdir -p /usr/share/img \
      && npm install -g node-gyp argon2
COPY --from=oauth2 /opt/bitnami/oauth2-proxy/bin/oauth2-proxy /bin/oauth2-proxy
COPY --from=gobuilder /app/secret2sshkey /usr/bin/secret2sshkey
COPY scripts/start.sh /usr/bin/start.sh
COPY scripts/golang.env /usr/local/go/bin/golang.env
COPY scripts/msvc.env /usr/local/bin/msvc.env
COPY scripts/msvc-x86.env /usr/local/bin/msvc-x86.env
RUN chmod ugo+x /usr/bin/start.sh \
      && chmod ugo+x /usr/local/go/bin/golang.env \
      && chmod ugo+x /usr/local/bin/msvc.env \
      && chmod ugo+x /usr/local/bin/msvc-x86.env \
      && echo ". /usr/local/go/bin/golang.env" >> /etc/profile \
      && echo ". /usr/local/bin/msvc.env" >> /etc/profile
COPY hcf.png /usr/share/img/hcf.png
COPY bin /ext
# WORKAROUND argon2 binary on ARM64
RUN cd /usr/lib/code-server \
      && rm -rf node_modules/argon2 \
      && npm install -g node-gyp \
      && npm install argon2 argon2-cli \
      && echo -n "password" | npx argon2-cli -d -e
RUN code-server --install-extension redhat.vscode-yaml \
      && code-server --install-extension esbenp.prettier-vscode \
      && code-server --install-extension rust-lang.rust \
      && code-server --install-extension bierner.markdown-preview-github-styles \
      && code-server --install-extension franneck94.vscode-c-cpp-dev-extension-pack \
      && code-server --install-extension franneck94.vscode-typescript-extension-pack \
      && code-server --install-extension devsense.phptools-vscode \
      && code-server --install-extension lokalise.i18n-ally \
      && code-server --install-extension Vue.volar \
      && code-server --install-extension ms-kubernetes-tools.vscode-kubernetes-tools
RUN   if [ $(dpkg --print-architecture) = "amd64" ] ; then \
            code-server --install-extension ext/ms-vscode.cpptools@linux-x64.vsix; \
      else \
            code-server --install-extension ext/ms-vscode.cpptools@linux-arm64.vsix; \
      fi \
      && code-server --install-extension ext/yaml.vsix \
      && code-server --install-extension ext/go.vsix \
      && code-server --install-extension ext/ms-vscode.vscode-typescript-next.vsix \
      && code-server --install-extension ext/ms-vscode.cpptools-themes.vsix \
      && code-server --install-extension ext/ms-vscode.cmake-tools.vsix \
      && code-server --install-extension ext/vscode-language-pack-fr.vsix \
      && mkdir -p /root/.local/share/code-server \
      && cat ext/languagepacks.json > /root/.local/share/code-server/languagepacks.json \
      && rm -rf ext \
      && mv ${BASEDIR}/.local ${BASEDIR}/.config /root/ || true
RUN mkdir -p /root/.local/share/code-server/User/globalStorage && \
      mkdir -p /root/.local/share/code-server/User && echo '{"locale":"fr"}' | tee /root/.local/share/code-server/User/locale.json && \
      mkdir -p /root/.local/share/code-server/User && echo '{"locale":"fr"}' | tee /root/.local/share/code-server/User/argv.json && \
      mkdir -p ${BASEDIR}/.vscode && echo '{"workbench.colorTheme": "Visual Studio Dark"}' | tee ${BASEDIR}/.vscode/settings.json
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y \
      && /root/.cargo/bin/rustup target add x86_64-pc-windows-msvc \
      && /root/.cargo/bin/rustup target add x86_64-unknown-linux-gnu \
      && /root/.cargo/bin/rustup target add aarch64-unknown-linux-gnu
RUN ln -svf /usr/bin/clang-14 /usr/bin/clang-cl \
      && ln -svf /usr/bin/ld.lld-14 /usr/bin/lld-link
COPY --from=llvm4msvc-x86 /usr/share/msvc /usr/share/msvc
COPY --from=llvm4msvc /usr/share/msvc /usr/share/msvc
ENV CC_x86_64_pc_windows_msvc="clang-cl" \
    CXX_x86_64_pc_windows_msvc="clang-cl" \
    AR_x86_64_pc_windows_msvc="llvm-lib" \
    CL_FLAGS="-Wno-unused-command-line-argument -fuse-ld=lld-link /usr/share/msvc/crt/include /usr/share/msvc/sdk/include/ucrt /usr/share/msvc/sdk/include/um /usr/share/msvc/sdk/include/shared" \
    CARGO_TARGET_X86_64_PC_WINDOWS_MSVC_LINKER="lld-link" \
    CARGO_TARGET_X86_64_PC_WINDOWS_MSVC_RUSTFLAGS="-Lnative=/usr/share/msvc/crt/lib/x86_64 -Lnative=/usr/share/msvc/sdk/lib/um/x86_64 -Lnative=/usr/share/msvc/sdk/lib/ucrt/x86_64"
ENV CFLAGS_x86_64_pc_windows_msvc="$CL_FLAGS" \
    CXXFLAGS_x86_64_pc_windows_msvc="$CL_FLAGS"
ENV CS_DISABLE_GETTING_STARTED_OVERRIDE=1
RUN apt-get clean autoclean \
      && apt-get autoremove --yes \
      && rm -rf /var/lib/{apt,dpkg,cache,log}/
USER 0
EXPOSE 8080
ENTRYPOINT [ "/usr/bin/start.sh" ]

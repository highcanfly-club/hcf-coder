FROM bitnami/oauth2-proxy:7-debian-11 as oauth2

FROM highcanfly/secret2sshkey:latest  as secret2sshkey

FROM highcanfly/llvm4msvc:latest AS llvm4msvc

FROM highcanfly/llvm4msvc-x86:latest AS llvm4msvc-x86

FROM codercom/code-server:latest as coder

FROM ubuntu:latest

USER 0
ARG NODE_MAJOR="20"
ARG DEBIAN_FRONTEND=noninteractive
ARG TZ=Etc/UTC
ARG GOVERSION="1.21.5"
ENV ENTRYPOINTD=/entrypoint.d
ENV BASEDIR=/home/coder
ENV HOME=$BASEDIR
WORKDIR ${BASEDIR}
RUN mkdir -p ${BASEDIR} && sed -ibak 's/:\/root:/:\/home\/coder:/g' /etc/passwd 
RUN apt-get update && apt-get install -y ca-certificates curl gnupg sshfs php-cli build-essential dnsutils iputils-ping lld llvm clang git cmake vim sudo dumb-init python3-pip\
      && mkdir -p /etc/apt/keyrings \
      && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
      && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_MAJOR.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list \
      && apt-get update \
      && apt-get install nodejs -y
RUN curl -fsSL https://go.dev/dl/go${GOVERSION}.linux-$(dpkg --print-architecture).tar.gz | tar -xz && mv go /usr/local/ \
      && sed -ibak 's/:\/usr\/bin:/:\/usr\/bin:\/usr\/local\/go\/bin:/g' /etc/profile \
      && curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash - \ 
      && curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/$(dpkg --print-architecture)/kubectl" \
      && chmod +x kubectl && mv kubectl /usr/local/bin/kubectl
RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/trusted.gpg.d/docker.gpg \
      && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/trusted.gpg.d/docker.gpg] https://download.docker.com/linux/ubuntu jammy stable" | tee /etc/apt/sources.list.d/docker.list \
      && apt-get update \
      && apt-get install -y docker-ce docker-ce-cli containerd.io
COPY --from=coder /usr/lib/code-server /usr/lib/code-server
COPY --from=coder /usr/bin/code-server /usr/bin/code-server
COPY --from=coder /usr/bin/entrypoint.sh /usr/bin/entrypoint.sh
RUN mkdir -p ${BASEDIR}/workdir \
      && mkdir -p ${BASEDIR}/.local \
      && mkdir -p ${BASEDIR}/.config \  
      && mkdir -p ${BASEDIR}/.ssh \
      && mkdir -p /usr/share/img 
COPY --from=oauth2 /opt/bitnami/oauth2-proxy/bin/oauth2-proxy /bin/oauth2-proxy
COPY --from=secret2sshkey /app/secret2sshkey /usr/bin/secret2sshkey
COPY scripts/start.sh /usr/bin/start.sh
COPY scripts/golang.env /usr/local/go/bin/golang.env
COPY scripts/msvc.env /usr/local/bin/msvc.env
COPY scripts/msvc-x86.env /usr/local/bin/msvc-x86.env
COPY scripts/getKubeConfig /usr/local/bin/getKubeConfig
RUN chmod ugo+x /usr/bin/start.sh \
      && chmod ugo+x /usr/local/go/bin/golang.env \
      && chmod ugo+x /usr/local/bin/msvc.env \
      && chmod ugo+x /usr/local/bin/msvc-x86.env \
      && echo ". /usr/local/go/bin/golang.env" >> /etc/profile \
      && echo ". /usr/local/bin/msvc.env" >> /etc/profile
COPY hcf.png /usr/share/img/hcf.png
COPY bin /ext 
RUN   if [ $(dpkg --print-architecture) = "amd64" ] ; then \
            code-server --install-extension /ext/ms-vscode.cpptools@linux-x64.vsix \
            && code-server --install-extension /ext/rust-analyzer-linux-x64.vsix ; \
      else \
            code-server --install-extension /ext/ms-vscode.cpptools@linux-arm64.vsix \
            && code-server --install-extension /ext/rust-analyzer-linux-arm64.vsix ; \
      fi \
      && code-server --install-extension /ext/yaml.vsix \
      && code-server --install-extension /ext/go.vsix \
      && code-server --install-extension /ext/ms-vscode.vscode-typescript-next.vsix \
      && code-server --install-extension /ext/ms-vscode.cpptools-themes.vsix \
      && code-server --install-extension /ext/ms-vscode.cmake-tools.vsix \
      && code-server --install-extension /ext/vscode-kubernetes-tools.vsix \
      && code-server --install-extension /ext/vscode-tailwindcss.vsix \
      && code-server --install-extension /ext/Lokalise.i18n-ally.vsix \
      && code-server --install-extension /ext/markdown-preview-enhanced.vsix \
      && code-server --install-extension /ext/Vue.volar.vsix \
      && code-server --install-extension /ext/MS-vsliveshare.vsliveshare.vsix \
      && code-server --install-extension /ext/ms-python.python.vsix \
      && code-server --install-extension /ext/vscode-language-pack-fr.vsix \
      && mkdir -p  ${BASEDIR}/.local/share/code-server \
      && cat /ext/languagepacks.json >  ${BASEDIR}/.local/share/code-server/languagepacks.json \
      && rm -rf /ext 
RUN mkdir -p  ${BASEDIR}/.local/share/code-server/User/globalStorage && \
      mkdir -p  ${BASEDIR}/.local/share/code-server/User && echo '{"locale":"fr"}' | tee  ${BASEDIR}/.local/share/code-server/User/locale.json && \
      mkdir -p  ${BASEDIR}/.local/share/code-server/User && echo '{"locale":"fr"}' | tee  ${BASEDIR}/.local/share/code-server/User/argv.json && \
      mkdir -p ${BASEDIR}/.vscode && echo '{"workbench.colorTheme": "Visual Studio Dark"}' | tee ${BASEDIR}/.vscode/settings.json
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y \
      && ${BASEDIR}/.cargo/bin/rustup target add x86_64-pc-windows-msvc \
      && ${BASEDIR}/.cargo/bin/rustup target add x86_64-unknown-linux-gnu \
      && ${BASEDIR}/.cargo/bin/rustup target add aarch64-unknown-linux-gnu
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
RUN   curl https://get.okteto.com -sSfL | sh
RUN /usr/bin/bash -c 'source /usr/local/go/bin/golang.env && /usr/local/go/bin/go install -v golang.org/x/tools/gopls@latest'
RUN apt dist-upgrade -y && apt-get clean autoclean \
      && apt-get autoremove --yes \
      && rm -rf /var/lib/{apt,dpkg,cache,log}/
RUN cd /usr/lib/llvm-14/bin/ && ln -svf clang clang-cl
RUN git config --global user.email "hcf@coder" \
      && git config --global user.name "hcf coder"
RUN mkdir -p /vscode 
RUN mv ${BASEDIR}/.local /vscode/  
RUN mv ${BASEDIR}/.cargo /vscode/  
RUN rm -f ${BASEDIR}/.bash_history
RUN rm -f ${BASEDIR}/.bashrc 
RUN mv ${BASEDIR}/.profile /vscode/  
RUN mv ${BASEDIR}/.gitconfig /vscode/ 
RUN mv ${BASEDIR}/.config /vscode/  
RUN mv ${BASEDIR}/.rustup /vscode/ 
RUN mv ${BASEDIR}/go /vscode/ 
USER 0
EXPOSE 8080
ENTRYPOINT [ "/usr/bin/start.sh" ]

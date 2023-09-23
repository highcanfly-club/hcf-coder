FROM bitnami/oauth2-proxy:7-debian-11 as oauth2
USER 0

FROM golang:1.21-alpine  as gobuilder
WORKDIR /app
COPY secret2sshkey/* ./
RUN go mod tidy
RUN go build -o secret2sshkey -ldflags="-s -w" main.go
ENTRYPOINT ["tail", "-f", "/dev/null"]

FROM highcanfly/llvm4msvc AS llvm4msvc

FROM codercom/code-server:latest
ENV NODE_MAJOR 18
RUN sudo apt-get update && sudo apt-get install -y ca-certificates curl gnupg && sudo mkdir -p /etc/apt/keyrings &&\
      curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg &&\
      echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_MAJOR.x nodistro main" | sudo tee /etc/apt/sources.list.d/nodesource.list &&\
      sudo apt-get update && sudo apt-get install nodejs -y
RUN curl -fsSL https://go.dev/dl/go1.21.0.linux-$(dpkg --print-architecture).tar.gz | tar -xvz && sudo mv go /usr/local/ \
      && sudo sed -ibak 's/:\/usr\/bin:/:\/usr\/bin:\/usr\/local\/go\/bin:/g' /etc/profile
RUN curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | sudo -E bash - 
RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/$(dpkg --print-architecture)/kubectl" && chmod +x kubectl && sudo mv kubectl /usr/local/bin/kubectl
RUN sudo mkdir -p /var/lib/apt/lists/partial \
  && sudo apt-get update \
  && sudo apt dist-upgrade -y \
  && sudo apt-get install -y \
  sshfs php-cli build-essential dnsutils iputils-ping lld llvm clang
RUN sudo mkdir -p /home/coder/workdir && sudo mkdir -p /root/.ssh && sudo mkdir -p /usr/share/img
COPY --from=oauth2 /opt/bitnami/oauth2-proxy/bin/oauth2-proxy /bin/oauth2-proxy
COPY --from=gobuilder /app/secret2sshkey /usr/bin/secret2sshkey
COPY scripts/start.sh /usr/bin/start.sh
RUN sudo chmod ugo+x /usr/bin/start.sh
COPY hcf.png /usr/share/img/hcf.png
RUN code-server --install-extension redhat.vscode-yaml
RUN code-server --install-extension esbenp.prettier-vscode
RUN code-server --install-extension golang.Go
RUN code-server --install-extension bierner.markdown-preview-github-styles
RUN code-server --install-extension franneck94.vscode-c-cpp-dev-extension-pack
RUN code-server --install-extension franneck94.vscode-typescript-extension-pack
RUN code-server --install-extension devsense.phptools-vscode
RUN code-server --install-extension lokalise.i18n-ally
RUN code-server --install-extension Vue.volar
# RUN code-server --install-extension ms-kubernetes-tools.vscode-kubernetes-tools
RUN code-server --install-extension MS-CEINTL.vscode-language-pack-fr
RUN sudo mv /home/coder/.local /home/coder/.config /root/
RUN sudo mkdir -p /root/.local/share/code-server/User/globalStorage && \
      sudo mkdir -p /root/.local/share/code-server/User && echo '{"locale":"fr"}' | sudo tee /root/.local/share/code-server/User/locale.json && \
      sudo mkdir -p /root/.local/share/code-server/User && echo '{"locale":"fr"}' | sudo tee /root/.local/share/code-server/User/argv.json && \
      sudo mkdir -p /home/coder/.vscode && echo '{"workbench.colorTheme": "Visual Studio Dark"}' | sudo tee /home/coder/.vscode/settings.json
COPY --from=llvm4msvc /usr/share/msvc /usr/share/msvc
USER 0
EXPOSE 8080
ENTRYPOINT [ "/usr/bin/start.sh" ]

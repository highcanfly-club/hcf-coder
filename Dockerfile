FROM bitnami/oauth2-proxy:7-debian-11 as oauth2
USER 0

FROM golang:1.20-alpine  as gobuilder
WORKDIR /app
COPY secret2sshkey/* ./
RUN go mod tidy
RUN go build -o secret2sshkey -ldflags="-s -w" main.go
ENTRYPOINT ["tail", "-f", "/dev/null"]

FROM codercom/code-server:latest
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash - &&\
      sudo apt-get install -y nodejs
RUN curl -fsSL https://go.dev/dl/go1.20.2.linux-$(dpkg --print-architecture).tar.gz | tar -xvz && sudo mv go /usr/local/ \
      && sudo sed -ibak 's/:\/usr\/bin:/:\/usr\/bin:\/usr\/local\/go\/bin:/g' /etc/profile
RUN sudo mkdir -p /var/lib/apt/lists/partial \
  && sudo apt-get update \
  && sudo apt-get install -y \
  sshfs php-cli
RUN sudo mkdir -p /home/coder/workdir && sudo mkdir -p /root/.ssh && sudo mkdir -p /usr/share/img
COPY --from=oauth2 /opt/bitnami/oauth2-proxy/bin/oauth2-proxy /bin/oauth2-proxy
COPY --from=gobuilder /app/secret2sshkey /usr/bin/secret2sshkey
COPY scripts/start.sh /usr/bin/start.sh
COPY hcf.png /usr/share/img/hcf.png
RUN sudo chmod ugo+x /usr/bin/start.sh
USER 0
EXPOSE 8080
ENTRYPOINT [ "/usr/bin/start.sh" ]

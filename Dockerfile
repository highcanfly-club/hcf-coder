FROM golang:1.20-alpine  as gobuilder
WORKDIR /app
COPY secret2sshkey/* ./
RUN go mod tidy
RUN go build -o secret2sshkey -ldflags="-s -w" main.go
ENTRYPOINT ["tail", "-f", "/dev/null"]

FROM codercom/code-server:latest
RUN sudo mkdir -p /var/lib/apt/lists/partial \
  && sudo apt-get update \
  && sudo apt-get install -y \
  sshfs
RUN sudo mkdir -p /home/coder/workdir && sudo mkdir -p /root/.ssh
COPY --from=gobuilder /app/secret2sshkey /usr/bin/secret2sshkey
COPY scripts/start.sh /usr/bin/start.sh
RUN sudo chmod ugo+x /usr/bin/start.sh
USER 0
EXPOSE 8080
ENTRYPOINT [ "/usr/bin/start.sh" ]

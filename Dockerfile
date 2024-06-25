FROM codercom/code-server:latest as coder

FROM highcanfly/devserver-prebuild:latest
USER 0
ARG NODE_MAJOR="20"
ARG DEBIAN_FRONTEND=noninteractive
ARG TZ=Etc/UTC
ARG GOVERSION="1.22.4"
ENV ENTRYPOINTD=/entrypoint.d
ENV BASEDIR=/home/coder
ENV HOME=$BASEDIR
WORKDIR ${BASEDIR}

COPY --from=coder /usr/lib/code-server /usr/lib/code-server
COPY --from=coder /usr/bin/code-server /usr/bin/code-server
COPY --from=coder /usr/bin/entrypoint.sh /usr/bin/entrypoint.sh
RUN mkdir -p ${BASEDIR}/workdir \
      && mkdir -p ${BASEDIR}/.local \
      && mkdir -p ${BASEDIR}/.config \  
      && mkdir -p ${BASEDIR}/.ssh \
      && mkdir -p /usr/share/img 

COPY bin /ext 
RUN   if [ $(dpkg --print-architecture) = "amd64" ] ; then \
            for file in /ext/amd64/*.vsix; do \
                code-server --install-extension $file; \
            done; \
      else \
            for file in /ext/arm64/*.vsix; do \
                code-server --install-extension $file; \
            done; \
      fi
RUN for FILE in /ext/*.vsix; do \
        code-server --install-extension $FILE; \
    done
RUN mkdir -p  ${BASEDIR}/.local/share/code-server \
      && cat /ext/languagepacks.json >  ${BASEDIR}/.local/share/code-server/languagepacks.json \
      && rm -rf /ext 
RUN mkdir -p  ${BASEDIR}/.local/share/code-server/User/globalStorage && \
      mkdir -p  ${BASEDIR}/.local/share/code-server/User && echo '{"locale":"fr"}' | tee  ${BASEDIR}/.local/share/code-server/User/locale.json && \
      mkdir -p  ${BASEDIR}/.local/share/code-server/User && echo '{"locale":"fr"}' | tee  ${BASEDIR}/.local/share/code-server/User/argv.json && \
      mkdir -p ${BASEDIR}/.vscode && echo '{"workbench.colorTheme": "Visual Studio Dark"}' | tee ${BASEDIR}/.vscode/settings.json

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

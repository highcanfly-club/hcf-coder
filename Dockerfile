FROM codercom/code-server:4.99.3-noble AS coder
USER 0
#RUN /usr/lib/code-server/bin/code-server -v || true
RUN /usr/lib/code-server/bin/code-server -v | sed -ne 's/.*\([0-9]\.[0-9]*\.[0-9A-Za-z-]*\)$/\1/p' > /usr/lib/code-server/engine_version.txt

FROM ubuntu:noble AS downloader
ARG VSIXHARVESTER_VERSION="0.2.6"
ARG SWISH_VERSION="1.0.7"
RUN apt-get update && apt-get install -y curl uuid-runtime zip
COPY extensions.json /extensions.json
RUN  if [ $(dpkg --print-architecture) = "amd64" ] ; then \
            curl -fsSL https://github.com/sctg-development/vsixHarvester/releases/download/${VSIXHARVESTER_VERSION}/vsixHarvester_linux_amd64_static_${VSIXHARVESTER_VERSION} -o vsixHarvester ; \
            curl -fsSL https://github.com/sctg-development/Swish/releases/download/${SWISH_VERSION}/swish_linux_amd64_static_${SWISH_VERSION} -o swish ; \
      else \
            curl -fsSL https://github.com/sctg-development/vsixHarvester/releases/download/${VSIXHARVESTER_VERSION}/vsixHarvester_linux_arm64_static_${VSIXHARVESTER_VERSION} -o vsixHarvester ; \
            curl -fsSL https://github.com/sctg-development/Swish/releases/download/${SWISH_VERSION}/swish_linux_arm64_static_${SWISH_VERSION} -o swish ; \
      fi
COPY --from=coder /usr/lib/code-server/engine_version.txt /engine_version.txt
RUN chmod +x vsixHarvester \
      && chmod +x swish \
      && ./vsixHarvester --verbose -i /extensions.json -e $(cat /engine_version.txt)
RUN mkdir -p extensions/amd64 \
      && mkdir -p extensions/arm64 \
      && find ./extensions -name "*@linux-x64.vsix" | xargs -I '{}' mv '{}' ./extensions/amd64/ \
      && find ./extensions -name "*@linux-arm64.vsix" | xargs -I '{}' mv '{}' ./extensions/arm64/
# universalize Copilot
COPY scripts/change-vsix-requirements.sh /change-vsix-requirements.sh
RUN chmod +x /change-vsix-requirements.sh \
      && /change-vsix-requirements.sh /extensions/MS-CEINTL.vscode-language-pack-fr*.vsix \
      && /change-vsix-requirements.sh /extensions/GitHub.copilot*.vsix \
      && /change-vsix-requirements.sh /extensions/GitHub.copilot-chat*.vsix \
      && /change-vsix-requirements.sh /extensions/amd64/ms-toolsai.jupyter*.vsix \
      && /change-vsix-requirements.sh /extensions/arm64/ms-toolsai.jupyter*.vsix 

FROM highcanfly/devserver-prebuild:latest
USER 0
ARG NODE_MAJOR="20"
ARG DEBIAN_FRONTEND=noninteractive
ARG TZ=Etc/UTC
ARG GOVERSION="1.24.1"
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

COPY --from=downloader /extensions /ext
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
COPY languagepacks.json /ext/languagepacks.json
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
COPY --from=downloader /swish /usr/bin/swish
COPY --from=downloader /vsixHarvester /usr/bin/vsixHarvester
COPY --from=downloader /change-vsix-requirements.sh /usr/bin/change-vsix-requirements.sh
COPY --from=downloader /extensions.json /vsixHarvester.json
COPY --from=ismogroup/busybox:1.37.0-php-8.3-apache /busybox-1.37.0/_install/bin/busybox /bin/busybox
RUN  /bin/busybox --install -s
USER 0
EXPOSE 8080
ENTRYPOINT [ "/usr/bin/start.sh" ]
